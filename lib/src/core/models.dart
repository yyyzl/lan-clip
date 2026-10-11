import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

const protocolVersion = 1;
const discoveryPort = 45876;
const receiverPort = 45877;
const maxTextBytes = 1024 * 1024;
const maxImageBytes = 20 * 1024 * 1024;
const maxWireBytes = maxImageBytes * 4 ~/ 3 + 8192;

String randomId([int length = 24]) {
  final random = Random.secure();
  return base64UrlEncode(
    List.generate(length, (_) => random.nextInt(256)),
  ).replaceAll('=', '');
}

class ClipException implements Exception {
  const ClipException(this.message);
  final String message;
  @override
  String toString() => message;
}

class Peer {
  Peer({
    required this.id,
    required this.name,
    required this.platform,
    required this.host,
    required this.port,
    required this.fingerprint,
    required this.token,
  });
  final String id;
  String name;
  final String platform;
  String host;
  int port;
  final String fingerprint;
  final String token;
  bool online = false;
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'platform': platform,
    'host': host,
    'port': port,
    'fingerprint': fingerprint,
    'token': token,
  };
  factory Peer.fromJson(Map<String, dynamic> j) => Peer(
    id: j['id'] as String,
    name: j['name'] as String,
    platform: j['platform'] as String,
    host: j['host'] as String,
    port: j['port'] as int,
    fingerprint: j['fingerprint'] as String,
    token: j['token'] as String,
  );
}

class TrustedPhone {
  TrustedPhone({required this.id, required this.name, required this.token});
  final String id;
  final String name;
  final String token;
  DateTime? lastSeen;
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'token': token};
  factory TrustedPhone.fromJson(Map<String, dynamic> j) => TrustedPhone(
    id: j['id'] as String,
    name: j['name'] as String,
    token: j['token'] as String,
  );
}

class DiscoveredPeer {
  const DiscoveredPeer({
    required this.id,
    required this.name,
    required this.platform,
    required this.host,
    required this.port,
  });
  final String id, name, platform, host;
  final int port;
}

class ClipPayload {
  ClipPayload.text(String value, {String? id})
    : id = id ?? randomId(),
      kind = 'text',
      text = value,
      png = null;
  ClipPayload.image(Uint8List value, {String? id})
    : id = id ?? randomId(),
      kind = 'image',
      text = null,
      png = value;
  final String id;
  final String kind;
  final String? text;
  final Uint8List? png;
  bool get isImage => kind == 'image';
  void validate() {
    if (id.isEmpty || id.length > 128) {
      throw const ClipException('消息编号无效');
    }
    if (!isImage) {
      if (text == null || text!.trim().isEmpty) {
        throw const ClipException('请输入要发送的文字');
      }
      if (utf8.encode(text!).length > maxTextBytes) {
        throw const ClipException('文字不能超过 1 MB');
      }
    } else {
      final data = png!;
      const signature = [137, 80, 78, 71, 13, 10, 26, 10];
      if (data.length < 24 ||
          data.length > maxImageBytes ||
          !List.generate(8, (i) => data[i] == signature[i]).every((v) => v)) {
        throw const ClipException('图片无效，或超过 20 MB');
      }
      final header = ByteData.sublistView(data);
      final width = header.getUint32(16);
      final height = header.getUint32(20);
      if (width == 0 || height == 0 || width * height > 24000000) {
        throw const ClipException('图片不能超过 2400 万像素');
      }
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind,
    if (isImage) 'data': base64Encode(png!) else 'text': text,
  };
  factory ClipPayload.fromJson(Map<String, dynamic> j) {
    final kind = j['kind'];
    final id = j['id'] as String;
    final ClipPayload result;
    if (kind == 'text') {
      result = ClipPayload.text(j['text'] as String, id: id);
    } else if (kind == 'image') {
      result = ClipPayload.image(base64Decode(j['data'] as String), id: id);
    } else {
      throw const ClipException('不支持的内容类型');
    }
    result.validate();
    return result;
  }
}

class ReceivedClip {
  ReceivedClip(this.payload, this.sender, {DateTime? at})
    : at = at ?? DateTime.now();
  final ClipPayload payload;
  final String sender;
  final DateTime at;
}

class DeliveryResult {
  const DeliveryResult(this.peerId, this.name, this.success, [this.error]);
  final String peerId, name;
  final bool success;
  final String? error;
}
