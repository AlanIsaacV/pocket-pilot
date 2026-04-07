import 'package:grpc/grpc.dart';
import 'package:pocket_pilot/src/core/constants/constants.dart';

class GrpcClient {
  GrpcClient._();

  static ClientChannel? _channel;
  static List<ClientInterceptor> _interceptors = [];

  static void init({List<ClientInterceptor> interceptors = const []}) {
    _interceptors = interceptors;
  }

  static ClientChannel get channel {
    _channel ??= ClientChannel(
      kGrpcHost,
      port: kGrpcPort,
      options: const ChannelOptions(
        credentials: ChannelCredentials.insecure(),
      ),
    );
    return _channel!;
  }

  static List<ClientInterceptor> get interceptors => _interceptors;

  static Future<void> dispose() async {
    await _channel?.shutdown();
    _channel = null;
  }
}
