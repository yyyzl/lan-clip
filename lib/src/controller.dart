import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'core/discovery.dart';
import 'core/identity.dart';
import 'core/models.dart';
import 'core/network.dart';
import 'core/receiver.dart';
import 'core/store.dart';
import 'platform/native_bridge.dart';

class ClipController extends ChangeNotifier {
  ClipController({bool? sender, AppStore? store, ApiClient? api})
    : isSender = sender ?? Platform.isAndroid,
      _store = store,
      api = api ?? ApiClient();
  final bool isSender;
  final ApiClient api;
  AppStore? _store;
  AppStore get store => _store!;
  final discovery = Discovery();
  Receiver? receiver;
  Timer? _timer;
  bool _disposed = false;
  bool _refreshing = false;
  bool ready = false;
  bool busy = false;
  String? error;
  String? discoveryError;
  ReceivedClip? latest;
  List<DeliveryResult> results = [];
  List<String> addresses = [];
  List<Peer> get peers => _store?.peers ?? [];
  List<TrustedPhone> get phones => _store?.phones ?? [];
  List<DiscoveredPeer> get candidates => discovery.candidates.values
      .where((c) => !peers.any((p) => p.id == c.id))
      .toList();
  bool get online => isSender
      ? peers.any((p) => p.online)
      : (receiver?.running ?? false) && addresses.isNotEmpty;
  String get deviceName => _store?.name ?? '';
  String? get pairingCode => receiver?.pairingCode;

  void changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> initialize() async {
    try {
      if (_store == null) {
        final base = Directory(await NativeBridge.supportDirectory());
        _store = AppStore(Directory('${base.path}/lan-clip'));
      }
      await store.load();
      if (isSender) {
        try {
          await discovery.browse();
          discovery.onChanged = changed;
          discovery.search(knownHosts: peers.map((p) => p.host).toList());
        } catch (_) {
          discoveryError = '自动发现不可用，可以通过电脑 IP 添加';
        }
        await refresh();
        _timer = Timer.periodic(
          const Duration(seconds: 4),
          (_) => unawaited(refresh()),
        );
      } else {
        final identity = await ServerIdentity.load(store.directory);
        receiver = Receiver(
          store: store,
          identity: identity,
          writeClipboard: NativeBridge.write,
          onChanged: changed,
          onReceived: (value) {
            latest = value;
            changed();
          },
        );
        await receiver!.start();
        try {
          await discovery.advertise(
            id: store.id,
            name: () => store.name,
            platform: Platform.operatingSystem,
            port: receiver!.port,
          );
        } catch (_) {
          discoveryError = '自动发现不可用，手机可通过电脑 IP 添加';
        }
        addresses = await _localAddresses();
        _timer = Timer.periodic(const Duration(seconds: 5), (_) async {
          addresses = await _localAddresses();
          changed();
        });
      }
      ready = true;
    } catch (e) {
      error = e is SocketException ? '接收端口无法打开，请确认没有重复运行轻贴，再重试' : '启动失败：$e';
    }
    changed();
  }

  Future<List<String>> _localAddresses() async {
    try {
      return (await NetworkInterface.list(type: InternetAddressType.IPv4))
          .expand((i) => i.addresses)
          .where((a) {
            final bytes = a.rawAddress;
            // Exclude link-local and local proxy benchmark interfaces.
            return !a.isLoopback &&
                !(bytes[0] == 169 && bytes[1] == 254) &&
                !(bytes[0] == 198 && (bytes[1] == 18 || bytes[1] == 19));
          })
          .map((a) => a.address)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> refresh() async {
    if (_refreshing || _store == null || !isSender) return;
    _refreshing = true;
    try {
      discovery.broadcastAddresses = await NativeBridge.broadcastAddresses();
      discovery.search(knownHosts: peers.map((p) => p.host).toList());
      var detailsChanged = false;
      await Future.wait(
        List<Peer>.of(peers).map((peer) async {
          final found = discovery.candidates[peer.id];
          final hosts = <String>{if (found != null) found.host, peer.host};
          var connected = false;
          for (final host in hosts) {
            final port = found != null && host == found.host
                ? found.port
                : peer.port;
            final attempt = Peer(
              id: peer.id,
              name: peer.name,
              platform: peer.platform,
              host: host,
              port: port,
              fingerprint: peer.fingerprint,
              token: peer.token,
            );
            try {
              await api.ping(attempt, store.id);
              detailsChanged |=
                  peer.host != host ||
                  peer.port != port ||
                  peer.name != attempt.name;
              peer.name = attempt.name;
              peer.host = host;
              peer.port = port;
              connected = true;
              break;
            } catch (_) {}
          }
          peer.online = connected;
        }),
      );
      if (detailsChanged) await store.save();
    } catch (_) {
      discoveryError = '设备地址未能保存，下次打开时会重新查找';
    } finally {
      _refreshing = false;
      changed();
    }
  }

  Future<void> pair(DiscoveredPeer candidate, String code) async {
    final peer = await api.pair(candidate, code, store.id, store.name);
    final previous = List<Peer>.of(store.peers);
    store.peers.removeWhere((p) => p.id == peer.id);
    store.peers.add(peer);
    try {
      await store.save();
    } catch (_) {
      store.peers = previous;
      rethrow;
    }
    changed();
  }

  Future<void> removePeer(String id) async {
    final previous = List<Peer>.of(store.peers);
    store.peers.removeWhere((p) => p.id == id);
    try {
      await store.save();
    } catch (_) {
      store.peers = previous;
      rethrow;
    }
    changed();
  }

  Future<void> removePhone(String id) async {
    final previous = List<TrustedPhone>.of(store.phones);
    store.phones.removeWhere((p) => p.id == id);
    try {
      await store.save();
    } catch (_) {
      store.phones = previous;
      rethrow;
    }
    changed();
  }

  Future<void> rename(String name) async {
    if (name.trim().isEmpty || name.trim().length > 40) {
      throw const ClipException('设备名称需要 1–40 个字');
    }
    final old = store.name;
    store.name = name.trim();
    try {
      await store.save();
    } catch (_) {
      store.name = old;
      rethrow;
    }
    changed();
  }

  void openPairing() {
    receiver?.openPairing();
  }

  void closePairing() {
    receiver?.closePairing();
  }

  Future<List<DeliveryResult>> sendText(String text) =>
      send(ClipPayload.text(text));
  Future<List<DeliveryResult>> sendImage(Uint8List png) =>
      send(ClipPayload.image(png));
  Future<List<DeliveryResult>> send(ClipPayload payload) async {
    if (busy) throw const ClipException('请等待当前发送完成');
    payload.validate();
    if (peers.isEmpty) throw const ClipException('请先添加一台电脑');
    busy = true;
    results = [];
    changed();
    try {
      // Try every paired computer even when its last heartbeat was stale.
      // Each future completes independently, so an offline PC cannot delay the other write.
      final targets = List<Peer>.of(peers);
      await Future.wait(
        targets.map((peer) async {
          final result = await api.send(peer, store.id, payload);
          // A clipboard error does not imply that the computer is disconnected.
          // Heartbeats determine offline state; a successful send confirms online.
          if (result.success) peer.online = true;
          results = [...results, result];
          changed();
        }),
      );
      return List.unmodifiable(results);
    } finally {
      busy = false;
      changed();
    }
  }

  Future<void> restart() async {
    _timer?.cancel();
    discovery.close();
    await receiver?.stop();
    error = null;
    discoveryError = null;
    ready = false;
    changed();
    await initialize();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    discovery.close();
    unawaited(receiver?.stop() ?? Future.value());
    super.dispose();
  }
}
