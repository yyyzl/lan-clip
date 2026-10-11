import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import '../core/models.dart';

class NativeBridge {
  static const channel = MethodChannel('lan_clip/native');
  static Future<void> write(ClipPayload payload) async {
    if (payload.isImage) {
      await channel.invokeMethod<void>('writeImage', payload.png);
    } else {
      await Clipboard.setData(ClipboardData(text: payload.text!));
    }
  }

  static Future<String> supportDirectory() async =>
      (await channel.invokeMethod<String>('supportDirectory'))!;
  static Future<List<String>> broadcastAddresses() async {
    if (!Platform.isAndroid) return [];
    try {
      return await channel.invokeListMethod<String>('broadcastAddresses') ?? [];
    } on PlatformException {
      return [];
    } on MissingPluginException {
      return [];
    }
  }

  static Future<void> hide() => channel.invokeMethod<void>('hide');
  static Future<void> quit() => channel.invokeMethod<void>('quit');
}

/// Decode before allocating full pixels; preserve resolution and transparency.
Future<Uint8List> normalizeImage(Uint8List bytes) async {
  if (bytes.length > maxImageBytes) throw const ClipException('图片不能超过 20 MB');
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  ui.Image? image;
  try {
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    if (descriptor.width * descriptor.height > 24000000) {
      throw const ClipException('图片不能超过 2400 万像素');
    }
    codec = await descriptor.instantiateCodec();
    image = (await codec.getNextFrame()).image;
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null || data.lengthInBytes > maxImageBytes) {
      throw const ClipException('图片转换后超过 20 MB，请换一张较小的图片');
    }
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } on ClipException {
    rethrow;
  } catch (_) {
    throw const ClipException('无法读取这张图片，请选择 JPG、PNG 或 WebP 图片');
  } finally {
    image?.dispose();
    codec?.dispose();
    descriptor?.dispose();
    buffer.dispose();
  }
}
