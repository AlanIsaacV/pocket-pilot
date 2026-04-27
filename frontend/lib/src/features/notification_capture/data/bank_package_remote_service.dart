import 'package:grpc/grpc.dart';
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart';

import 'package:pocket_pilot/src/core/grpc/grpc_client.dart';
import 'package:pocket_pilot/src/generated/pocket_pilot/v1/bank_package_service.pbgrpc.dart';
import 'package:pocket_pilot/src/generated/pocket_pilot/v1/common.pb.dart';

/// Cliente gRPC para `bank_packages`. Pull-only para la lista (catálogo
/// global); push-only para `submitPackageSuggestion` (sugerencia anónima).
class BankPackageRemoteService {
  late final BankPackageServiceClient _client;

  BankPackageRemoteService() {
    _client = BankPackageServiceClient(
      GrpcClient.channel,
      interceptors: GrpcClient.interceptors,
    );
  }

  Future<ListBankPackagesResponse> listBankPackages({
    DateTime? updatedSince,
    String? pageToken,
    int pageSize = 100,
  }) async {
    try {
      final request = ListBankPackagesRequest(
        page: PageRequest(pageSize: pageSize, pageToken: pageToken ?? ''),
      );
      if (updatedSince != null) {
        request.updatedSince = Timestamp.fromDateTime(updatedSince.toUtc());
      }
      return await _client.listBankPackages(request);
    } on GrpcError catch (e) {
      throw Exception('gRPC listBankPackages error: ${e.message}');
    }
  }

  /// Envía una sugerencia anónima. Fire-and-forget: si falla, el cliente
  /// no reintenta automáticamente — es un nice-to-have, no bloquea la UX.
  Future<void> submitPackageSuggestion({
    required String packageName,
    required String proposedLabel,
    String? proposedBankId,
  }) async {
    try {
      await _client.submitPackageSuggestion(
        SubmitPackageSuggestionRequest(
          packageName: packageName,
          proposedLabel: proposedLabel,
          proposedBankId: proposedBankId ?? '',
        ),
      );
    } on GrpcError catch (e) {
      // Silencioso: el caller decide si quiere logear. La sugerencia es
      // best-effort — cualquier failure se traga sin afectar la UI.
      throw Exception('gRPC submitPackageSuggestion error: ${e.message}');
    }
  }
}
