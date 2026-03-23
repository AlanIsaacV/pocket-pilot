import 'package:grpc/grpc.dart';
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart';

import 'package:pocket_pilot/src/generated/pocket_pilot/v1/tags_service.pbgrpc.dart';
import 'package:pocket_pilot/src/core/grpc/auth_interceptor.dart';
import 'package:pocket_pilot/src/core/grpc/grpc_client.dart';

class TagRemoteService {
  late final TagServiceClient _client;

  TagRemoteService() {
    _client = TagServiceClient(
      GrpcClient.channel,
      interceptors: [const AuthInterceptor()],
    );
  }

  Future<ListTagsResponse> listTags({DateTime? updatedSince}) async {
    try {
      final request = ListTagsRequest();
      if (updatedSince != null) {
        request.updatedSince = Timestamp.fromDateTime(updatedSince.toUtc());
      }
      return await _client.listTags(request);
    } on GrpcError catch (e) {
      throw Exception('gRPC listTags error: ${e.message}');
    }
  }

  Future<UpsertTagResponse> upsertTag(Map<String, dynamic> map) async {
    try {
      final now = DateTime.now().toUtc();
      final tag = Tag(
        id: map['id'] as String,
        name: map['name'] as String,
        createdAt: Timestamp.fromDateTime(
            map['created_at'] != null
                ? DateTime.parse(map['created_at'] as String).toUtc()
                : now),
        updatedAt: Timestamp.fromDateTime(
            map['updated_at'] != null
                ? DateTime.parse(map['updated_at'] as String).toUtc()
                : now),
      );
      return await _client.upsertTag(UpsertTagRequest(tag: tag));
    } on GrpcError catch (e) {
      throw Exception('gRPC upsertTag error: ${e.message}');
    }
  }

  Future<void> deleteTag({
    required String id,
    required DateTime deletedAt,
  }) async {
    try {
      await _client.deleteTag(
        DeleteTagRequest(
          id: id,
          deletedAt: Timestamp.fromDateTime(deletedAt.toUtc()),
        ),
      );
    } on GrpcError catch (e) {
      throw Exception('gRPC deleteTag error: ${e.message}');
    }
  }
}
