import 'package:pocket_pilot/src/features/accounts/data/account_local_store.dart';
import 'package:pocket_pilot/src/features/categories/data/category_local_store.dart';
import 'package:pocket_pilot/src/features/goals/data/goal_local_store.dart';
import 'package:pocket_pilot/src/features/transaction_templates/data/transaction_template_local_store.dart';
import 'package:pocket_pilot/src/features/transaction_templates/domain/transaction_template.dart';
import 'package:pocket_pilot/src/features/user_preferences/data/user_preference_local_store.dart';

class AIContextBuilder {
  final AccountLocalStore _accounts;
  final CategoryLocalStore _categories;
  final TransactionTemplateLocalStore _templates;
  final GoalLocalStore _goals;
  final UserPreferenceLocalStore _prefs;

  AIContextBuilder({
    required AccountLocalStore accounts,
    required CategoryLocalStore categories,
    required TransactionTemplateLocalStore templates,
    required GoalLocalStore goals,
    required UserPreferenceLocalStore prefs,
  }) : _accounts = accounts,
       _categories = categories,
       _templates = templates,
       _goals = goals,
       _prefs = prefs;

  Future<String> buildSystemPrompt() async {
    final lang = await _getLanguage();
    final now = DateTime.now();
    final dateStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    final buf = StringBuffer();

    buf.writeln(
      'Eres un asistente financiero personal. Responde siempre en $lang.',
    );
    buf.writeln(
      'Eres conciso y directo. Tus respuestas seran leidas en voz alta por TTS,',
    );
    buf.writeln(
      'asi que usa oraciones cortas y naturales. No uses markdown, listas, ni formato.',
    );
    buf.writeln();
    buf.writeln('== Reglas para usar herramientas ==');
    buf.writeln(
      'Usa UNICAMENTE los IDs exactos listados abajo (cuentas, categorias, metas). Nunca inventes IDs.',
    );
    buf.writeln(
      'Si el usuario no menciona la cuenta, usa la cuenta que mejor corresponda segun el contexto. Si hay ambiguedad, pregunta.',
    );
    buf.writeln(
      'NUNCA uses monto 0 ni valores placeholder. Si el usuario no dice el monto, preguntale antes de crear la transaccion.',
    );
    buf.writeln(
      'Confirma los datos antes de ejecutar una herramienta si algo no queda claro.',
    );
    buf.writeln();
    buf.writeln('Hoy es: $dateStr');

    final accounts = await _accounts.getAccounts();
    if (accounts.isNotEmpty) {
      buf.writeln();
      buf.writeln('== Cuentas del usuario ==');
      for (final a in accounts) {
        buf.writeln(
          'ID: ${a.id} | Nombre: ${a.name} | Tipo: ${a.type} | Moneda: ${a.currencyCode}',
        );
      }
    }

    final categories = await _categories.getCategories();
    if (categories.isNotEmpty) {
      buf.writeln();
      buf.writeln('== Categorias disponibles ==');
      for (final c in categories) {
        buf.writeln('ID: ${c.id} | Nombre: ${c.name} | Tipo: ${c.type}');
      }
    }

    final templateRows = await _templates.queryRows();
    if (templateRows.isNotEmpty) {
      buf.writeln();
      buf.writeln('== Plantillas rapidas ==');
      for (final row in templateRows) {
        final t = TransactionTemplateModel.fromMap(row);
        final amountStr = t.amountCents != null
            ? '\$${(t.amountCents! / 100).toStringAsFixed(0)} ${t.currencyCode}'
            : 'monto variable';
        buf.writeln(
          'ID: ${t.id} | Nombre: ${t.name} | Cuenta: ${t.accountId} | Monto: $amountStr',
        );
      }
    }

    final goalRows = await _goals.queryRows();
    if (goalRows.isNotEmpty) {
      buf.writeln();
      buf.writeln('== Metas de ahorro ==');
      for (final row in goalRows) {
        final name = row['name'] as String;
        final target = row['target_amount_cents'] as int;
        final currency = row['currency_code'] as String;
        final targetDate = row['target_date'] as String?;
        buf.write('ID: ${row['id']} | Nombre: $name');
        buf.write(
          ' | Objetivo: \$${(target / 100).toStringAsFixed(0)} $currency',
        );
        if (targetDate != null) {
          buf.write(' | Fecha limite: $targetDate');
        }
        buf.writeln();
      }
    }

    return buf.toString();
  }

  Future<String> _getLanguage() async {
    final pref = await _prefs.getByKey('app.language');
    return pref?.prefValue ?? 'espanol';
  }
}
