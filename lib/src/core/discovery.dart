import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'models.dart';

const _query = 'LAN_CLIP_DISCOVER_V1';

class Discovery {
  RawDatagramSocket? _socket;
  final Map<String, DiscoveredPeer> candidates = {};
  void Function()? onChanged;
  // Android provides real interface broadcast addresses, including non-/24 Wi-Fi.
  // Limited broadcast alone can follow a VPN/default route and miss the LAN.
  List<String> broadcastAddresses = [];

  Future<void> advertise({
    required String id,
    required String Function() name,
    required String platform,
    required int port,
    int udpPort = discoveryPort,
  }) async {
    _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, udpPort);
    _socket!.listen((event) {
      if (event != RawSocketEvent.read) return;
      Datagram? packet;
      while ((packet = _socket?.receive()) != null) {
        final p = packet!;
        if (p.data.length > 64 ||
            utf8.decode(p.data, allowMalformed: true) != _query) {
          continue;
        }
        final response = utf8.encode(
          jsonEncode({
            'v': protocolVersion,
            'id': id,
            'name': name(),
            'platform': platform,
            'port': port,
          }),
        );
        try {
          _socket?.send(response, p.address, p.port);
        } catch (_) {}
      }
    }, onError: (Object _) {});
  }

  Future<void> browse() async {
    _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    _socket!.broadcastEnabled = true;
    _socket!.listen((event) {
      if (event != RawSocketEvent.read) return;
      Datagram? packet;
      while ((packet = _socket?.receive()) != null) {
        final p = packet!;
        if (p.data.length > 2048) continue;
        try {
          final j = jsonDecode(utf8.decode(p.data)) as Map<String, dynamic>;
          final port = j['port'];
          final id = j['id'];
          if (j['v'] != protocolVersion ||
              id is! String ||
              id.length > 128 ||
              port is! int ||
              port < 1 ||
              port > 65535 ||
              j['name'] is! String ||
              (j['name'] as String).length > 80 ||
              !['macos', 'windows'].contains(j['platform'])) {
            continue;
          }
          candidates[id] = DiscoveredPeer(
            id: id,
            name: j['name'] as String,
            platform: j['platform'] as String,
            host: p.address.address,
            port: port,
          );
          // Discovery is only a hint; online status requires pinned HTTPS.
          if (candidates.length > 64) candidates.remove(candidates.keys.first);
          onChanged?.call();
        } catch (_) {}
      }
    }, onError: (Object _) {});
  }

  void search({List<String> knownHosts = const [], int port = discoveryPort}) {
    for (final host in {
      '255.255.255.255',
      ...broadcastAddresses,
      ...knownHosts,
    }) {
      try {
        _socket?.send(utf8.encode(_query), InternetAddress(host), port);
      } catch (_) {}
    }
  }

  void close() {
    _socket?.close();
    _socket = null;
  }
}
