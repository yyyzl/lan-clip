import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../controller.dart';
import '../core/models.dart';
import '../platform/native_bridge.dart';
import 'settings.dart';
import 'theme.dart';

class ClipHome extends StatefulWidget {
  const ClipHome({super.key, required this.controller});
  final ClipController controller;
  @override
  State<ClipHome> createState() => _ClipHomeState();
}

class _ClipHomeState extends State<ClipHome> with WidgetsBindingObserver {
  ClipController get c => widget.controller;
  bool _pickingImage = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (c.isSender && Platform.isAndroid) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _recoverImage());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && c.isSender) {
      unawaited(c.refresh());
    }
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  void _settings() => showDialog<void>(
    context: context,
    builder: (_) => SettingsDialog(controller: c),
  );

  Future<void> _recoverImage() async {
    try {
      final response = await ImagePicker().retrieveLostData();
      if (response.files?.isNotEmpty ?? false) {
        await _previewImage(response.files!.first);
      } else if (response.exception != null) {
        _message('未能恢复所选图片，请重新选择');
      }
    } catch (_) {
      /* A fresh install normally has no lost activity result. */
    }
  }

  Future<void> _pickImage() async {
    if (_pickingImage) return;
    setState(() => _pickingImage = true);
    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        requestFullMetadata: false,
      );
      if (image != null && mounted) await _previewImage(image);
    } catch (e) {
      _message(e is ClipException ? e.message : '无法打开相册，请检查权限后重试');
    } finally {
      if (mounted) setState(() => _pickingImage = false);
    }
  }

  Future<void> _previewImage(XFile file) async {
    if (await file.length() > maxImageBytes) {
      throw const ClipException('图片不能超过 20 MB');
    }
    final png = await normalizeImage(await file.readAsBytes());
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => ComposeDialog(controller: c, image: png),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: c,
    builder: (context, _) {
      if (!c.ready) {
        return Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: c.error == null
                  ? const CircularProgressIndicator()
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Brand(),
                        const SizedBox(height: 24),
                        Text(c.error!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: c.restart,
                          child: const Text('重试'),
                        ),
                      ],
                    ),
            ),
          ),
        );
      }
      return Scaffold(
        body: SafeArea(
          child: c.isSender ? _sender(context) : _receiver(context),
        ),
      );
    },
  );

  Widget _sender(BuildContext context) => RefreshIndicator(
    onRefresh: c.refresh,
    child: ListView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Brand(),
            IconButton(
              onPressed: _settings,
              tooltip: '设置',
              icon: const Icon(Icons.settings_outlined, size: 27),
            ),
          ],
        ),
        const SizedBox(height: 30),
        Text('发到电脑', style: Theme.of(context).textTheme.headlineLarge),
        const SizedBox(height: 26),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('设备', style: Theme.of(context).textTheme.titleLarge),
            TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => AddComputerDialog(controller: c),
              ),
              child: const Text('添加'),
            ),
          ],
        ),
        if (c.peers.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              '还没有添加电脑',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: secondaryColor),
            ),
          ),
        ...c.peers.indexed.expand(
          (entry) => [
            if (entry.$1 > 0) const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 17),
              child: Row(
                children: [
                  Icon(
                    entry.$2.platform == 'macos'
                        ? Icons.laptop_mac
                        : Icons.desktop_windows_outlined,
                    size: 28,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      entry.$2.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  OnlineStatus(entry.$2.online),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),
        FilledButton.icon(
          onPressed: c.busy || c.peers.isEmpty
              ? null
              : () => showDialog<void>(
                  context: context,
                  builder: (_) => ComposeDialog(controller: c),
                ),
          icon: const Icon(Icons.notes_outlined),
          label: const Text('发送文字'),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: c.busy || _pickingImage || c.peers.isEmpty
              ? null
              : _pickImage,
          icon: _pickingImage
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.image_outlined),
          label: Text(_pickingImage ? '正在读取图片' : '发送图片'),
        ),
        if (c.results.isNotEmpty) ...[
          const SizedBox(height: 20),
          DeliveryList(results: c.results),
        ],
      ],
    ),
  );

  Widget _receiver(BuildContext context) {
    final clip = c.latest;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          child: Row(
            children: [
              const Brand(small: true),
              const Spacer(),
              OnlineStatus(c.online),
              const SizedBox(width: 16),
              IconButton(
                onPressed: _settings,
                tooltip: '设置',
                icon: const Icon(Icons.settings_outlined),
              ),
            ],
          ),
        ),
        const Divider(),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding: EdgeInsets.all(constraints.maxWidth < 550 ? 24 : 36),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (clip == null) ...[
                    const SizedBox(height: 20),
                    Icon(
                      c.online ? Icons.wifi_rounded : Icons.wifi_off_rounded,
                      color: accentColor,
                      size: 36,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '等待接收',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 22),
                    FilledButton.icon(
                      onPressed: () => showDialog<void>(
                        context: context,
                        builder: (_) => PairingDialog(controller: c),
                      ),
                      icon: const Icon(Icons.add),
                      label: const Text('添加手机'),
                    ),
                  ] else ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: Icon(
                            Icons.check_circle,
                            size: 38,
                            color: accentColor,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '已写入剪贴板',
                                style: Theme.of(
                                  context,
                                ).textTheme.headlineMedium,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '来自 ${clip.sender} · ${_time(clip.at)}',
                                style: const TextStyle(
                                  fontSize: 15,
                                  color: secondaryColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (constraints.maxWidth >= 580) ...[
                          const SizedBox(width: 20),
                          _KeyCap(Platform.isMacOS ? '⌘' : 'Ctrl'),
                          const SizedBox(width: 8),
                          const _KeyCap('V'),
                        ],
                      ],
                    ),
                    const SizedBox(height: 30),
                    AnimatedSwitcher(
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 180),
                      child: Container(
                        key: ValueKey(clip.payload.id),
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: sageColor,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  clip.payload.isImage
                                      ? Icons.image_outlined
                                      : Icons.content_paste,
                                  size: 27,
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  clip.payload.isImage ? '图片' : '文字',
                                  style: const TextStyle(
                                    fontSize: 17,
                                    color: secondaryColor,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            if (clip.payload.isImage)
                              Center(
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxHeight: (constraints.maxHeight - 260)
                                        .clamp(90, 400),
                                  ),
                                  child: Image.memory(
                                    clip.payload.png!,
                                    fit: BoxFit.contain,
                                    semanticLabel: '收到的图片',
                                    errorBuilder: (_, _, _) =>
                                        const Text('无法预览图片'),
                                  ),
                                ),
                              )
                            else
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                  minHeight: 50,
                                  maxHeight: 250,
                                ),
                                child: SingleChildScrollView(
                                  child: SelectableText(
                                    clip.payload.text!,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      height: 1.6,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _time(DateTime at) => DateTime.now().difference(at).inMinutes < 1
      ? '刚刚'
      : '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
}

class _KeyCap extends StatelessWidget {
  const _KeyCap(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    decoration: BoxDecoration(
      border: Border.all(color: lineColor, width: 2),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(label, style: const TextStyle(fontSize: 24)),
  );
}

class DeliveryList extends StatelessWidget {
  const DeliveryList({super.key, required this.results});
  final List<DeliveryResult> results;
  @override
  Widget build(BuildContext context) => Column(
    children: results
        .map(
          (r) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  r.success ? Icons.check_circle_outline : Icons.error_outline,
                  color: r.success
                      ? accentColor
                      : Theme.of(context).colorScheme.error,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${r.name}：${r.success ? '已发送' : r.error}',
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
        )
        .toList(),
  );
}

class ComposeDialog extends StatefulWidget {
  const ComposeDialog({super.key, required this.controller, this.image});
  final ClipController controller;
  final Uint8List? image;
  @override
  State<ComposeDialog> createState() => _ComposeDialogState();
}

class _ComposeDialogState extends State<ComposeDialog> {
  final _text = TextEditingController();
  ClipPayload? _pending;
  List<DeliveryResult> _results = [];
  bool _sending = false;
  String? _error;
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() {
      _sending = true;
      _error = null;
    });
    // Preserve id when retrying unchanged content, avoiding duplicate clipboard writes.
    final payload = _pending ??= widget.image == null
        ? ClipPayload.text(_text.text)
        : ClipPayload.image(widget.image!);
    try {
      final result = await widget.controller.send(payload);
      if (!mounted) return;
      if (result.every((r) => r.success)) {
        Navigator.pop(context);
        return;
      }
      setState(() => _results = result);
    } catch (e) {
      if (mounted) {
        setState(() => _error = e is ClipException ? e.message : '发送失败，请重试');
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_sending,
    child: AlertDialog(
      title: Text(widget.image == null ? '发送文字' : '发送图片'),
      content: SizedBox(
        width: 320,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.image == null)
                TextField(
                  controller: _text,
                  minLines: 4,
                  maxLines: 7,
                  readOnly: _sending,
                  autofocus: false,
                  keyboardType: TextInputType.multiline,
                  decoration: const InputDecoration(hintText: '输入文字'),
                  onChanged: (_) => setState(() {
                    _pending = null;
                    _results = [];
                  }),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 300),
                  child: Image.memory(widget.image!, fit: BoxFit.contain),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (_results.isNotEmpty) ...[
                const SizedBox(height: 12),
                DeliveryList(results: _results),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(80, 48)),
          onPressed:
              _sending || (widget.image == null && _text.text.trim().isEmpty)
              ? null
              : _send,
          child: Text(
            _sending
                ? '发送中'
                : _results.isNotEmpty
                ? '重试'
                : '发送',
          ),
        ),
      ],
    ),
  );
}
