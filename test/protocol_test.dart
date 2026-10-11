import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_clip/src/core/discovery.dart';
import 'package:lan_clip/src/core/identity.dart';
import 'package:lan_clip/src/core/models.dart';
import 'package:lan_clip/src/core/network.dart';
import 'package:lan_clip/src/core/receiver.dart';
import 'package:lan_clip/src/core/store.dart';

final tinyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

void main() {
  late Directory temp;
  late ServerIdentity identity;
  late AppStore store;
  late Receiver server;
  final api = ApiClient();
  final written = <ClipPayload>[];
  var failWrite = false;
  Completer<void>? barrier;

  setUpAll(() async {
    identity = ServerIdentity.generate();
  });
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('lan-clip-test-');
    store = AppStore(temp);
    await store.load();
    written.clear();
    failWrite = false;
    barrier = null;
    server = Receiver(
      store: store,
      identity: identity,
      platform: 'macos',
      writeClipboard: (p) async {
        if (barrier != null) await barrier!.future;
        if (failWrite) throw StateError('clipboard busy');
        written.add(p);
      },
    );
    await server.start(address: InternetAddress.loopbackIPv4, port: 0);
  });
  tearDown(() async {
    await server.stop();
    await temp.delete(recursive: true);
  });

  Future<Peer> pair() async {
    server.openPairing();
    return api.pair(
      DiscoveredPeer(
        id: store.id,
        name: store.name,
        platform: 'macos',
        host: '127.0.0.1',
        port: server.port,
      ),
      server.pairingCode!,
      'phone-1',
      '我的手机',
    );
  }

  test(
    'pair over pinned TLS, persist token, write exact Unicode text',
    () async {
      final peer = await pair();
      expect(server.pairingOpen, false);
      expect(peer.fingerprint, identity.fingerprint);
      final reloaded = AppStore(temp);
      await reloaded.load();
      expect(reloaded.phones.single.token, peer.token);
      const text = '第一行\n🙂 中文 é\t末尾空格  ';
      expect(
        (await api.send(peer, 'phone-1', ClipPayload.text(text))).success,
        true,
      );
      expect(written.single.text, text);
    },
  );

  test('verified heartbeat updates a renamed computer', () async {
    final peer = await pair();
    store.name = '书房 Mac';
    await api.ping(peer, 'phone-1');
    expect(peer.name, '书房 Mac');
  });

  test('image payload arrives as PNG bytes, not a path or URL', () async {
    final peer = await pair();
    final result = await api.send(peer, 'phone-1', ClipPayload.image(tinyPng));
    expect(result.success, true);
    expect(written.single.png, orderedEquals(tinyPng));
  });

  test(
    'success waits for actual write; duplicate request writes only once',
    () async {
      final peer = await pair();
      barrier = Completer<void>();
      final payload = ClipPayload.text('等待写入');
      var acknowledged = false;
      final first = api.send(peer, 'phone-1', payload).then((r) {
        acknowledged = true;
        return r;
      });
      final second = api.send(peer, 'phone-1', payload);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(acknowledged, false);
      expect(written, isEmpty);
      barrier!.complete();
      expect((await first).success, true);
      expect((await second).success, true);
      expect(written, hasLength(1));
    },
  );

  test(
    'native clipboard failure is reported and same payload may be retried',
    () async {
      final peer = await pair();
      final payload = ClipPayload.text('重试');
      failWrite = true;
      final result = await api.send(peer, 'phone-1', payload);
      expect(result.success, false);
      expect(result.error, contains('剪贴板'));
      failWrite = false;
      expect((await api.send(peer, 'phone-1', payload)).success, true);
      expect(written, hasLength(1));
    },
  );

  test(
    'unpaired, revoked or forged device cannot overwrite clipboard',
    () async {
      final peer = await pair();
      expect(
        (await api.send(
          peer,
          'different-phone',
          ClipPayload.text('forged'),
        )).success,
        false,
      );
      store.phones.clear();
      expect(
        (await api.send(peer, 'phone-1', ClipPayload.text('revoked'))).success,
        false,
      );
      expect(written, isEmpty);
    },
  );

  test(
    'certificate mismatch is rejected before pairing or clipboard write',
    () async {
      final peer = await pair();
      final wrong = Peer(
        id: peer.id,
        name: peer.name,
        platform: peer.platform,
        host: peer.host,
        port: peer.port,
        fingerprint: '0' * 64,
        token: peer.token,
      );
      expect(
        (await api.send(wrong, 'phone-1', ClipPayload.text('no'))).success,
        false,
      );
      expect(written, isEmpty);
    },
  );

  test('pairing requires a live window and a correct private PIN', () async {
    final candidate = DiscoveredPeer(
      id: store.id,
      name: store.name,
      platform: 'macos',
      host: '127.0.0.1',
      port: server.port,
    );
    server.openPairing();
    final realCode = server.pairingCode!;
    final wrongPin = realCode.startsWith('000000') ? '111111' : '000000';
    final wrongCode = '$wrongPin${realCode.substring(6)}';
    for (var i = 0; i < 5; i++) {
      await expectLater(
        api.pair(candidate, wrongCode, 'bad', '陌生手机'),
        throwsA(isA<ClipException>()),
      );
    }
    expect(server.pairingOpen, false);
    await expectLater(
      api.pair(candidate, realCode, 'phone', '手机'),
      throwsA(isA<ClipException>()),
    );
    expect(store.phones, isEmpty);
  });

  test(
    'empty or malformed saved fingerprints never disable certificate validation',
    () async {
      for (final fingerprint in ['', 'bad', 'a' * 63]) {
        await expectLater(
          api.call(
            host: '127.0.0.1',
            port: server.port,
            fingerprint: fingerprint,
            path: '/v1/ping',
          ),
          throwsA(isA<ClipException>()),
        );
      }
      expect(written, isEmpty);
    },
  );

  test(
    'malformed content, oversized text and huge image dimensions are rejected',
    () {
      expect(
        () => ClipPayload.text('  \n').validate(),
        throwsA(isA<ClipException>()),
      );
      expect(
        () => ClipPayload.text('a' * (maxTextBytes + 1)).validate(),
        throwsA(isA<ClipException>()),
      );
      expect(
        () => ClipPayload.image(Uint8List(40)).validate(),
        throwsA(isA<ClipException>()),
      );
      final huge = Uint8List.fromList(tinyPng);
      ByteData.sublistView(huge).setUint32(16, 100000000);
      expect(
        () => ClipPayload.image(huge).validate(),
        throwsA(isA<ClipException>()),
      );
    },
  );

  test(
    'UDP discovery advertises only metadata and can find a receiver',
    () async {
      final reserve = await RawDatagramSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final port = reserve.port;
      reserve.close();
      final advertiser = Discovery();
      final browser = Discovery();
      addTearDown(() {
        advertiser.close();
        browser.close();
      });
      await advertiser.advertise(
        id: store.id,
        name: () => '测试电脑',
        platform: 'windows',
        port: server.port,
        udpPort: port,
      );
      await browser.browse();
      final found = Completer<void>();
      browser.onChanged = () {
        if (!found.isCompleted) found.complete();
      };
      browser.broadcastAddresses = ['127.0.0.1'];
      browser.search(port: port);
      await found.future.timeout(const Duration(seconds: 2));
      expect(browser.candidates[store.id]?.name, '测试电脑');
      expect(browser.candidates[store.id]?.port, server.port);
    },
  );

  test(
    'two receivers accept independently when another computer is unreachable',
    () async {
      final first = await pair();
      final secondDir = await Directory.systemTemp.createTemp(
        'lan-clip-second-',
      );
      final secondStore = AppStore(secondDir);
      await secondStore.load();
      final secondWrites = <ClipPayload>[];
      final second = Receiver(
        store: secondStore,
        identity: identity,
        platform: 'windows',
        writeClipboard: (p) async {
          secondWrites.add(p);
        },
      );
      await second.start(address: InternetAddress.loopbackIPv4, port: 0);
      addTearDown(() async {
        await second.stop();
        await secondDir.delete(recursive: true);
      });
      second.openPairing();
      final other = await api.pair(
        DiscoveredPeer(
          id: secondStore.id,
          name: 'PC',
          platform: 'windows',
          host: '127.0.0.1',
          port: second.port,
        ),
        second.pairingCode!,
        'phone-1',
        '我的手机',
      );
      final offline = Peer(
        id: 'offline',
        name: 'Offline',
        platform: 'windows',
        host: '127.0.0.1',
        port: 1,
        fingerprint: identity.fingerprint,
        token: first.token,
      );
      final payload = ClipPayload.text('同时发送');
      final results = await Future.wait(
        [first, other, offline].map((p) => api.send(p, 'phone-1', payload)),
      );
      expect(results.map((r) => r.success), [true, true, false]);
      expect(written.single.text, '同时发送');
      expect(secondWrites.single.text, '同时发送');
    },
  );
}
