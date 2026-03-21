// ============================================================
// Constantes globales de la aplicación
// ============================================================

/// ID de usuario hardcodeado para el MVP (sin autenticación real).
/// En una app de producción esto vendría de un sistema de auth (Firebase, Auth0, etc.)
const kHardcodedUserId = '00000000-0000-0000-0000-000000000001';

/// Host del servidor gRPC.
///
/// Se puede sobreescribir en tiempo de compilación:
///   flutter run --dart-define=GRPC_HOST=10.0.2.2
///
/// Por qué dos hosts distintos:
///   - iOS Simulator: el simulador corre como proceso nativo en tu Mac,
///     por lo que 'localhost' apunta directamente a tu máquina.
///   - Android Emulator: la VM tiene su propia red virtual. '10.0.2.2'
///     es la dirección especial que apunta al host (tu Mac/PC).
const kGrpcHost = String.fromEnvironment(
  'GRPC_HOST',
  defaultValue: 'localhost',
);

/// Puerto donde escucha el backend Go.
const kGrpcPort = 50051;
