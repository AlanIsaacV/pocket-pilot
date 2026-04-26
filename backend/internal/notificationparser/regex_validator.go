package notificationparser

import (
	"errors"
	"regexp"
	"strings"
)

// MaxRegexLength es el largo máximo aceptado para un regex propuesto por el
// LLM. Regex largos suelen ser sobre-específicos y/o esconden patrones
// catastróficos; truncar antes de compilar reduce riesgo y costo.
const MaxRegexLength = 200

// ErrRegex* son los errores de validación. Se exponen para los tests y para
// que el handler distinga la causa al loggear.
var (
	ErrRegexEmpty            = errors.New("regex is empty")
	ErrRegexTooLong          = errors.New("regex exceeds max length")
	ErrRegexPythonNamedGroup = errors.New("regex uses Python (?P<...>) syntax; ECMAScript (?<...>) is required")
	ErrRegexBackreference    = errors.New("regex contains a backreference")
	ErrRegexNestedQuantifier = errors.New("regex contains a nested quantifier (ReDoS risk)")
	ErrRegexCompile          = errors.New("regex failed to compile")
)

// nestedQuantifierPatterns: subexpresiones obviamente catastróficas. La lista
// no es exhaustiva — cubre los casos más comunes que generan regex propuestos
// por LLMs: grupos con quantifier interno seguidos de quantifier externo.
var nestedQuantifierPatterns = []string{
	"(.+)+", "(.+)*", "(.+)?",
	"(.*)+", "(.*)*", "(.*)?",
	"(\\w+)+", "(\\w+)*",
	"(\\d+)+", "(\\d+)*",
	"(\\s+)+", "(\\s+)*",
}

// backreferenceRegex detecta \1..\9. Compilado una vez al cargar el paquete.
// RE2 no soporta backreferences en runtime, así que aunque el regex compilara
// al promoverse a producción, en Dart RegExp las backreferences SÍ están
// disponibles vía ECMAScript y son un vector ReDoS clásico. Las rechazamos.
var backreferenceRegex = regexp.MustCompile(`\\[1-9]`)

// ValidateRegex aplica reglas conservadoras antes de aceptar el regex
// propuesto por el LLM. NO es equivalente a una validación Dart completa
// (Dart soporta features que Go RE2 rechaza); el objetivo es descartar
// candidatos obviamente peligrosos o malformados sin permitir que entren a
// `candidate_parsers`. La validación final ocurre cuando el admin promueve
// el candidato a un parser global y los tests del engine corren con Dart.
func ValidateRegex(re string) error {
	re = strings.TrimSpace(re)
	if re == "" {
		return ErrRegexEmpty
	}
	if len(re) > MaxRegexLength {
		return ErrRegexTooLong
	}
	if strings.Contains(re, "(?P<") {
		return ErrRegexPythonNamedGroup
	}
	if backreferenceRegex.MatchString(re) {
		return ErrRegexBackreference
	}
	for _, p := range nestedQuantifierPatterns {
		if strings.Contains(re, p) {
			return ErrRegexNestedQuantifier
		}
	}
	// Compilar con Go RE2 atrapa errores de sintaxis comunes (paréntesis
	// desbalanceados, escapes inválidos). RE2 NO acepta named groups
	// ECMAScript `(?<name>...)`; los traducimos al equivalente Go
	// `(?P<name>...)` SOLO para la prueba de compilación, sin tocar el
	// regex que se persiste — la string original es la que llega a Dart.
	probe := convertECMAToGoNamed(re)
	if _, err := regexp.Compile(probe); err != nil {
		return errors.Join(ErrRegexCompile, err)
	}
	return nil
}

// convertECMAToGoNamed transforma `(?<name>...)` → `(?P<name>...)` para que
// `regexp.Compile` (RE2) acepte el regex en la prueba de compilación.
// Reemplazo simple a nivel de string: solo aplica cuando el `?` va seguido
// de `<` y un identificador. No intenta rescatar regex que también tengan
// backreferences o lookaround — esos ya fueron rechazados antes.
func convertECMAToGoNamed(re string) string {
	return strings.ReplaceAll(re, "(?<", "(?P<")
}
