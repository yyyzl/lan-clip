import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'identity.dart';
import 'models.dart';
import 'network.dart';
import 'store.dart';

typedef ClipboardWriter = Future<void> Function(ClipPayload payload);

class Receiver {
  Receiver({
    required this.store,
    required this.identity,
    required this.writeClipboard,
    this.onReceived,
    this.onChanged,
    String? platform,
  }) : platform = platform ?? Platform.operatingSystem;
  final AppStore store;
  final ServerIdentity identity;
  final ClipboardWriter writeClipboard;
  final void Function(ReceivedClip)? onReceived;
  final void Function()? onChanged;
  final String platform;
  HttpServer? _server;
  String? _pin;
  DateTime? pairingExpires;
  Timer? _pairingTimer;
  int _pairingAttempts = 0;
  int _activeRequests = 0;
  final Map<String, Future<void>> _receipts = {};
  Future<void> _writeQueue = Future.value();
  int get port => _server?.port ?? receiverPort;
  bool get running => _server != null;
  bool get pairingOpen =>
      _pin != null &&
      pairingExpires != null &&
      DateTime.now().isBefore(pairingExpires!);
  String? get pairingCode {
    if (!pairingOpen) return null;
    final f = identity.fingerprint.substring(0, 12).toUpperCase();
    return '$_pin-${f.substring(0, 4)}-${f.substring(4, 8)}-${f.substring(8, 12)}';
  }

  void openPairing() {
    _pin = Random.secure().nextInt(1000000).toString().padLeft(6, '0');
    pairingExpires = DateTime.now().add(const Duration(minutes: 2));
    _pairingAttempts = 0;
    _pairingTimer?.cancel();
    _pairingTimer = Timer(const Duration(minutes: 2), closePairing);
    onChanged?.call();
  }

  void closePairing() {
    _pin = null;
    pairingExpires = null;
    _pairingTimer?.cancel();
    onChanged?.call();
  }

  Future<void> start({
    InternetAddress? address,
    int port = receiverPort,
  }) async {
    _server = await HttpServer.bindSecure(
      address ?? InternetAddress.anyIPv4,
      port,
      identity.context,
      shared: false,
    );
    _server!.idleTimeout = const Duration(seconds: 10);
    _server!.listen((request) {
      unawaited(_handle(request));
    });
    onChanged?.call();
  }

  Future<void> stop() async {
    closePairing();
    final server = _server;
    _server = null;
    await server?.close(force: true);
  }

  Future<void> _handle(HttpRequest request) async {
    _activeRequests++;
    try {
      if (_activeRequests > 8) {
        await _reply(request, 429, {'error': '电脑正忙，请稍后重试'});
        return;
      }
      if (request.uri.path == '/v1/pair' && request.method == 'POST') {
        await _pair(request);
        return;
      }
      final id = request.headers.value('x-lan-clip-device');
      final authorization = request.headers.value('authorization') ?? '';
      TrustedPhone? phone;
      for (final p in store.phones) {
        if (p.id == id && _equal(authorization, 'Bearer ${p.token}')) phone = p;
      }
      if (phone == null) {
        await _reply(request, 401, {'error': '配对已失效，请重新添加电脑'});
        return;
      }
      phone.lastSeen = DateTime.now();
      if (request.uri.path == '/v1/ping' && request.method == 'GET') {
        await _reply(request, 200, {'id': store.id, 'name': store.name});
        return;
      }
      if (request.uri.path != '/v1/clip' || request.method != 'POST') {
        await _reply(request, 404, {'error': '不支持的请求'});
        return;
      }
      if (request.contentLength > maxWireBytes) {
        await _reply(request, 413, {'error': '图片不能超过 20 MB'});
        return;
      }
      final payload = ClipPayload.fromJson(
        await readJson(request, maxWireBytes),
      );
      final receipt = '${phone.id}:${payload.id}';
      // Repeated requests wait for the same native write. Never acknowledge first.
      if (!_receipts.containsKey(receipt)) {
        final senderName = phone.name;
        final write = _writeQueue.then((_) async {
          await writeClipboard(payload);
          onReceived?.call(ReceivedClip(payload, senderName));
        });
        _receipts[receipt] = write;
        _writeQueue = write.catchError((Object _) {});
      }
      try {
        await _receipts[receipt];
      } catch (_) {
        _receipts.remove(receipt);
        await _reply(request, 503, {'error': '电脑剪贴板暂时不可用，请重试'});
        return;
      }
      while (_receipts.length > 128) {
        _receipts.remove(_receipts.keys.first);
      }
      await _reply(request, 200, {'id': payload.id, 'written': true});
    } on ClipException catch (error) {
      await _reply(request, 400, {'error': error.message});
    } on FormatException {
      await _reply(request, 400, {'error': '内容格式无效'});
    } on TimeoutException {
      await _reply(request, 408, {'error': '接收超时，请重试'});
    } catch (_) {
      await _reply(request, 400, {'error': '无法处理内容，请重试'});
    } finally {
      _activeRequests--;
    }
  }

  Future<void> _pair(HttpRequest request) async {
    if (!pairingOpen) {
      await _reply(request, 403, {'error': '请在电脑上打开「添加手机」'});
      return;
    }
    final data = await readJson(request, 2048);
    final pin = data['pin'];
    if (pin is! String || !_equal(pin, _pin!)) {
      _pairingAttempts++;
      if (_pairingAttempts >= 5) closePairing();
      await _reply(request, 403, {'error': '配对码错误或已过期'});
      return;
    }
    final id = data['id'];
    final name = data['name'];
    if (id is! String ||
        id.isEmpty ||
        id.length > 128 ||
        name is! String ||
        name.trim().isEmpty ||
        name.length > 80) {
      throw const ClipException('设备名称无效');
    }
    // Consume the window before awaiting disk I/O to prevent concurrent claims.
    closePairing();
    final phone = TrustedPhone(id: id, name: name, token: randomId(32));
    final oldPhones = List<TrustedPhone>.of(store.phones);
    store.phones.removeWhere((p) => p.id == id);
    store.phones.add(phone);
    try {
      await store.save();
    } catch (_) {
      store.phones = oldPhones;
      rethrow;
    }
    onChanged?.call();
    await _reply(request, 200, {
      'id': store.id,
      'name': store.name,
      'platform': platform,
      'fingerprint': identity.fingerprint,
      'token': phone.token,
    });
  }

  static bool _equal(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  Future<void> _reply(
    HttpRequest request,
    int status,
    Map<String, dynamic> body,
  ) async {
    try {
      request.response.statusCode = status;
      request.response.headers.contentType = ContentType.json;
      request.response.headers.set('cache-control', 'no-store');
      request.response.persistentConnection = false;
      request.response.write(jsonEncode(body));
      await request.response.close();
    } catch (_) {
      /* Peer may disconnect while a clipboard write completes. */
    }
  }
}
