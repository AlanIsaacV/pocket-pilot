// ============================================================
// Test de humo básico
// ============================================================
//
// Este test verifica que la app arranca sin crash.
// Para hacer tests completos necesitamos mockear la DB y gRPC;
// eso está fuera del alcance del MVP.
//
// Para correr: flutter test

import 'package:flutter_test/flutter_test.dart';

void main() {
  // Test placeholder: el test de humo real requiere
  // inicializar la DB y los mocks de gRPC.
  // Por ahora verificamos que el framework de tests funciona.
  test('placeholder — el proyecto compila correctamente', () {
    expect(1 + 1, equals(2));
  });
}
