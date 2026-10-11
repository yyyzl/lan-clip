import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:basic_utils/basic_utils.dart';
import 'package:crypto/crypto.dart';

String certificateFingerprint(List<int> der) => sha256.convert(der).toString();
String pemFingerprint(String pem) => certificateFingerprint(
  base64Decode(pem.replaceAll(RegExp(r'-----[^-]+-----|\s'), '')),
);

class ServerIdentity {
  ServerIdentity(this.certificate, this.privateKey);
  final String certificate, privateKey;
  String get fingerprint => pemFingerprint(certificate);
  SecurityContext get context => SecurityContext(withTrustedRoots: false)
    ..useCertificateChainBytes(utf8.encode(certificate))
    ..usePrivateKeyBytes(utf8.encode(privateKey));

  static Future<ServerIdentity> load(Directory directory) async {
    final cert = File('${directory.path}/identity.pem');
    final key = File('${directory.path}/identity-key.pem');
    if (await cert.exists() && await key.exists()) {
      return ServerIdentity(
        await cert.readAsString(),
        await key.readAsString(),
      );
    }
    final identity = await Isolate.run(generate);
    await key.writeAsString(identity.privateKey, flush: true);
    if (!Platform.isWindows) await Process.run('chmod', ['600', key.path]);
    await cert.writeAsString(identity.certificate, flush: true);
    return identity;
  }

  static ServerIdentity generate() {
    final pair = CryptoUtils.generateRSAKeyPair(keySize: 2048);
    final privateKey = pair.privateKey as RSAPrivateKey;
    final publicKey = pair.publicKey as RSAPublicKey;
    final csr = X509Utils.generateRsaCsrPem(
      {'CN': 'Lan Clip'},
      privateKey,
      publicKey,
    );
    final certificate = X509Utils.generateSelfSignedCertificate(
      privateKey,
      csr,
      3650,
    );
    return ServerIdentity(
      certificate,
      CryptoUtils.encodeRSAPrivateKeyToPem(privateKey),
    );
  }
}
