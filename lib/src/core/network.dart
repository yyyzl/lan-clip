import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'identity.dart';
import 'models.dart';

Future<Map<String, dynamic>> readJson(
  Stream<List<int>> stream,
  int limit,
) async {
  final bytes = BytesBuilder(copy: false);
  await for (final chunk in stream.timeout(const Duration(seconds: 25))) {
    if (bytes.length + chunk.length > limit) {
      throw const ClipException('内容过大');
    }
    bytes.add(chunk);
  }
  return jsonDecode(utf8.decode(bytes.takeBytes())) as Map<String, dynamic>;
}

class ApiClient {
  /// Every TLS connection is pinned, including the initial pairing handshake.
  Future<Map<String, dynamic>> call({
    required String host,
    required int port,
    required String fingerprint,
    required String path,
    String? token,
    String? clientId,
    Map<String, dynamic>? body,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (!RegExp(r'^([0-9a-fA-F]{12}|[0-9a-fA-F]{64})$').hasMatch(fingerprint)) {
      throw const ClipException('电脑身份记录无效，请重新添加电脑');
    }
    final client = HttpClient(context: SecurityContext(withTrustedRoots: false))
      ..connectionTimeout = const Duration(seconds: 4)
      ..findProxy = ((_) => 'DIRECT')
      ..badCertificateCallback = (certificate, _, _) => certificateFingerprint(
        certificate.der,
      ).startsWith(fingerprint.toLowerCase());
    try {
      return await (() async {
        final request = await client.openUrl(
          body == null ? 'GET' : 'POST',
          Uri(scheme: 'https', host: host, port: port, path: path),
        );
        request.followRedirects = false;
        if (token != null) {
          request.headers.set('authorization', 'Bearer $token');
        }
        if (clientId != null) {
          request.headers.set('x-lan-clip-device', clientId);
        }
        if (body != null) {
          request.headers.contentType = ContentType.json;
          request.add(utf8.encode(jsonEncode(body)));
        }
        final response = await request.close();
        final result = await readJson(response, 8192);
        if (response.statusCode != 200) {
          throw ClipException(result['error'] as String? ?? '电脑未能接收');
        }
        return result;
      })().timeout(timeout);
    } on HandshakeException {
      throw const ClipException('配对码不匹配，或电脑身份已更改');
    } on SocketException {
      throw const ClipException('无法连接电脑，请检查网络和电脑防火墙');
    } on TimeoutException {
      throw const ClipException('电脑响应超时，请检查连接后重试');
    } finally {
      client.close(force: true);
    }
  }

  Future<Peer> pair(
    DiscoveredPeer candidate,
    String code,
    String clientId,
    String clientName,
  ) async {
    final cleaned = code.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
    if (!RegExp(r'^\d{6}[0-9A-F]{12}$').hasMatch(cleaned)) {
      throw const ClipException('请输入电脑显示的完整配对码');
    }
    final fingerprintPrefix = cleaned.substring(6);
    final data = await call(
      host: candidate.host,
      port: candidate.port,
      fingerprint: fingerprintPrefix,
      path: '/v1/pair',
      body: {
        'pin': cleaned.substring(0, 6),
        'id': clientId,
        'name': clientName,
      },
    );
    final fingerprint = data['fingerprint'] as String;
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(fingerprint) ||
        !fingerprint.startsWith(fingerprintPrefix.toLowerCase()) ||
        (candidate.id.isNotEmpty && candidate.id != data['id'])) {
      throw const ClipException('电脑身份不匹配，请重新添加');
    }
    return Peer(
      id: data['id'] as String,
      name: data['name'] as String,
      platform: data['platform'] as String,
      host: candidate.host,
      port: candidate.port,
      fingerprint: fingerprint,
      token: data['token'] as String,
    )..online = true;
  }

  Future<void> ping(Peer peer, String clientId) async {
    final data = await call(
      host: peer.host,
      port: peer.port,
      fingerprint: peer.fingerprint,
      path: '/v1/ping',
      token: peer.token,
      clientId: clientId,
      timeout: const Duration(seconds: 5),
    );
    if (data['id'] != peer.id) throw const ClipException('电脑身份不匹配');
    final name = data['name'];
    if (name is String && name.trim().isNotEmpty && name.length <= 40) {
      peer.name = name.trim();
    }
  }

  Future<DeliveryResult> send(
    Peer peer,
    String clientId,
    ClipPayload payload,
  ) async {
    try {
      payload.validate();
      final response = await call(
        host: peer.host,
        port: peer.port,
        fingerprint: peer.fingerprint,
        path: '/v1/clip',
        token: peer.token,
        clientId: clientId,
        body: payload.toJson(),
      );
      if (response['id'] != payload.id || response['written'] != true) {
        throw const ClipException('电脑尚未确认剪贴板写入');
      }
      return DeliveryResult(peer.id, peer.name, true);
    } catch (error) {
      return DeliveryResult(
        peer.id,
        peer.name,
        false,
        error is ClipException ? error.message : '发送失败，请重试',
      );
    }
  }
}
