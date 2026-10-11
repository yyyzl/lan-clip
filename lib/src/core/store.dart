import 'dart:convert';
import 'dart:io';
import 'models.dart';

/// No clipboard content is persisted. Tokens and TLS keys stay in the OS profile.
class AppStore {
  AppStore(this.directory);
  final Directory directory;
  late String id;
  String name = '';
  List<Peer> peers = [];
  List<TrustedPhone> phones = [];
  Future<void> _pendingWrite = Future.value();
  File get file => File('${directory.path}/settings.json');

  Future<void> load() async {
    await directory.create(recursive: true);
    if (!Platform.isWindows) {
      await Process.run('chmod', ['700', directory.path]);
    }
    if (await file.exists()) {
      final j = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      id = j['id'] as String;
      name = j['name'] as String? ?? '';
      peers = (j['peers'] as List? ?? [])
          .map((e) => Peer.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      phones = (j['phones'] as List? ?? [])
          .map(
            (e) => TrustedPhone.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList();
    } else {
      id = randomId();
      name = Platform.isAndroid ? 'Android 手机' : Platform.localHostname;
      await save();
    }
  }

  Future<void> save() {
    final json = jsonEncode({
      'id': id,
      'name': name,
      'peers': peers.map((p) => p.toJson()).toList(),
      'phones': phones.map((p) => p.toJson()).toList(),
    });
    final operation = _pendingWrite.then((_) async {
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(json, flush: true);
      if (!Platform.isWindows) await Process.run('chmod', ['600', temp.path]);
      await temp.rename(file.path);
    });
    _pendingWrite = operation.catchError((Object _) {});
    return operation;
  }
}
