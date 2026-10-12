import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_clip/main.dart';
import 'package:lan_clip/src/controller.dart';
import 'package:lan_clip/src/core/models.dart';
import 'package:lan_clip/src/core/network.dart';
import 'package:lan_clip/src/core/store.dart';
import 'protocol_test.dart' show tinyPng;

class FakeApi extends ApiClient {
  bool fail = false;
  DiscoveredPeer? pairingCandidate;
  @override
  Future<Peer> pair(
    DiscoveredPeer candidate,
    String code,
    String clientId,
    String clientName,
  ) async {
    pairingCandidate = candidate;
    throw const ClipException('测试连接终止');
  }

  List<ClipPayload> payloads = [];
  @override
  Future<DeliveryResult> send(
    Peer peer,
    String clientId,
    ClipPayload payload,
  ) async {
    payloads.add(payload);
    return DeliveryResult(
      peer.id,
      peer.name,
      !fail,
      fail ? '剪贴板暂时不可用，请重试' : null,
    );
  }
}

class PreviewController extends ClipController {
  PreviewController({super.sender, required super.store, super.api});
  @override
  bool get online => true;
}

void main() {
  setUpAll(() async {
    // Use an installed CJK font only in local visual captures; do not redistribute it.
    final font = File('/System/Library/Fonts/Supplemental/Arial Unicode.ttf');
    if (font.existsSync()) {
      final loader = FontLoader('Roboto')
        ..addFont(font.readAsBytes().then((b) => ByteData.sublistView(b)));
      await loader.load();
      await (FontLoader('Ahem')
            ..addFont(font.readAsBytes().then((b) => ByteData.sublistView(b))))
          .load();
      final icons = File(
        '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      );
      if (icons.existsSync()) {
        await (FontLoader('MaterialIcons')..addFont(
              icons.readAsBytes().then((b) => ByteData.sublistView(b)),
            ))
            .load();
      }
    }
  });
  late PreviewController controller;
  late FakeApi api;
  setUp(() {
    final store = AppStore(Directory('unused'))
      ..id = 'phone-test'
      ..name = 'Android 手机';
    store.peers = [
      Peer(
        id: 'mac',
        name: 'MacBook',
        platform: 'macos',
        host: '127.0.0.1',
        port: 1,
        fingerprint: '',
        token: '',
      )..online = true,
      Peer(
        id: 'win',
        name: 'Windows 电脑',
        platform: 'windows',
        host: '127.0.0.1',
        port: 1,
        fingerprint: '',
        token: '',
      )..online = true,
    ];
    api = FakeApi();
    controller = PreviewController(sender: true, store: store, api: api)
      ..ready = true;
  });
  tearDown(() => controller.dispose());

  Future<void> render(
    WidgetTester tester, {
    Size size = const Size(390, 693),
    double scale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: LanClipApp(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'text dialog starts blank, never reads clipboard, sends exact user input to both computers',
    (tester) async {
      var reads = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.getData') reads++;
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await render(tester);
      await tester.tap(find.text('发送文字'));
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, '');
      expect(reads, 0);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '发送'))
            .onPressed,
        isNull,
      );
      await tester.enterText(find.byType(TextField), '手动输入\n原样保留  ');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, '发送'));
      await tester.pumpAndSettle();
      expect(api.payloads, hasLength(2));
      expect(api.payloads.every((p) => p.text == '手动输入\n原样保留  '), true);
      expect(find.byType(AlertDialog), findsNothing);
      expect(reads, 0);
    },
  );

  testWidgets('failed delivery retains input and retry reuses the message ID', (
    tester,
  ) async {
    api.fail = true;
    await render(tester);
    await tester.tap(find.text('发送文字'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '失败也不能丢失');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '发送'));
    await tester.pumpAndSettle();
    final messageId = api.payloads.first.id;
    expect(controller.peers.every((p) => p.online), true);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '失败也不能丢失',
    );
    expect(find.text('重试'), findsOneWidget);
    api.fail = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(api.payloads.every((p) => p.id == messageId), true);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('narrow phone and large type remain usable', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await render(tester, size: const Size(320, 640));
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('发送文字'));
    await tester.tap(find.text('发送文字'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '多行\n内容');
    expect(tester.takeException(), isNull);
    expect(find.text('取消'), findsOneWidget);
  });

  testWidgets(
    'a single discovered computer is selected without a separate tap',
    (tester) async {
      controller.discovery.candidates['new-pc'] = const DiscoveredPeer(
        id: 'new-pc',
        name: '书房电脑',
        platform: 'windows',
        host: '192.168.0.12',
        port: 45877,
      );
      await render(tester);
      await tester.tap(find.text('添加'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '123456-ABCD-EF12-3456');
      await tester.tap(find.widgetWithText(FilledButton, '连接'));
      await tester.pumpAndSettle();
      expect(api.pairingCandidate?.id, 'new-pc');
      expect(api.pairingCandidate?.host, '192.168.0.12');
      expect(find.text('请选择一台电脑，或使用 IP 添加'), findsNothing);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets('capture Android homepage and blank editor', (tester) async {
    controller.peers.last.online = false;
    await render(tester, size: const Size(390, 780));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../work/verification/android-home.png'),
    );
    await tester.tap(find.text('发送文字'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../work/verification/android-dialog.png'),
    );
  }, skip: !const bool.fromEnvironment('CAPTURE_UI'));

  testWidgets(
    'first-run phone guides pairing instead of offering disabled send actions',
    (tester) async {
      controller.store.peers.clear();
      await render(tester);
      expect(find.text('先连接一台电脑'), findsOneWidget);
      expect(find.text('发送文字'), findsNothing);
      await tester.tap(find.text('添加电脑'));
      await tester.pumpAndSettle();
      expect(find.text('正在查找电脑…'), findsOneWidget);
      expect(find.text('电脑 IP'), findsNothing);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));
    },
  );

  testWidgets(
    'desktop pairing finishes into persistent phone status, including after receipt and disconnect',
    (tester) async {
      final store = controller.store;
      controller.dispose();
      controller = PreviewController(sender: false, store: store)..ready = true;
      await render(tester, size: const Size(760, 540));
      expect(find.text('连接你的手机'), findsOneWidget);
      expect(find.text('在线'), findsNothing);
      await tester.tap(find.text('开始配对'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      final phone = TrustedPhone(id: 'phone', name: '我的手机', token: 'test-token')
        ..lastSeen = DateTime.now();
      store.phones.add(phone);
      controller.changed();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('开始配对'), findsNothing);
      expect(find.text('我的手机'), findsOneWidget);
      expect(find.text('在线'), findsOneWidget);
      controller.latest = ReceivedClip(
        ClipPayload.text('状态区域不会被收到的内容替代'),
        '我的手机',
      );
      controller.changed();
      await tester.pumpAndSettle();
      expect(find.text('已配对手机'), findsOneWidget);
      expect(find.text('状态区域不会被收到的内容替代'), findsOneWidget);
      phone.lastSeen = DateTime.now().subtract(const Duration(seconds: 16));
      controller.changed();
      await tester.pumpAndSettle();
      expect(find.text('离线'), findsOneWidget);
      expect(find.text('在线'), findsNothing);
      expect(find.text('我的手机'), findsOneWidget);
      expect(find.text('连接你的手机'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'desktop small window accommodates long device names and large text',
    (tester) async {
      final store = controller.store;
      store.phones.add(
        TrustedPhone(
          id: 'phone',
          name: '这是一个非常长的安卓设备名称用于检查小窗口显示',
          token: 'test',
        ),
      );
      controller.dispose();
      controller = PreviewController(sender: false, store: store)..ready = true;
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await render(tester, size: const Size(500, 360));
      expect(tester.takeException(), isNull);
      expect(find.text('已配对手机'), findsOneWidget);
    },
  );

  testWidgets('capture first-run phone and desktop', (tester) async {
    controller.store.peers.clear();
    await render(tester, size: const Size(390, 780));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../work/verification/android-first-run.png'),
    );
    final store = controller.store;
    store.name = '我的 Mac';
    controller.dispose();
    controller = PreviewController(sender: false, store: store)..ready = true;
    await render(tester, size: const Size(760, 540));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../work/verification/desktop-first-run.png'),
    );
  }, skip: !const bool.fromEnvironment('CAPTURE_UI'));

  testWidgets('capture desktop text and image previews', (tester) async {
    final store = controller.store;
    store.name = '我的 Mac';
    store.phones.add(
      TrustedPhone(id: 'phone', name: '我的手机', token: 'test')
        ..lastSeen = DateTime.now(),
    );
    controller.dispose();
    controller = PreviewController(sender: false, store: store)
      ..ready = true
      ..latest = ReceivedClip(
        ClipPayload.text('会议地点改到二楼，记得带上电脑。'),
        'Android 手机',
      );
    await render(tester, size: const Size(760, 540));
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../work/verification/desktop-text.png'),
    );
    store.phones.single.lastSeen = DateTime.now().subtract(
      const Duration(seconds: 16),
    );
    controller.changed();
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../work/verification/desktop-offline.png'),
    );
    controller.latest = ReceivedClip(ClipPayload.image(tinyPng), 'Android 手机');
    controller.changed();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }, skip: !const bool.fromEnvironment('CAPTURE_UI'));
}
