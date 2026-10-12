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

  void _addComputer() => showDialog<void>(
    context: context,
    builder: (_) => AddComputerDialog(controller: c),
  );

  void _addPhone() => showDialog<void>(
    context: context,
    builder: (_) => PairingDialog(controller: c),
  );

  void _help() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('连接手机和电脑'),
      content: const SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Text(
            '1. 手机和电脑连接同一个 Wi-Fi，打开轻贴。\n\n'
            '2. 电脑点击「开始配对」或「添加手机」。\n\n'
            '3. 手机点击「添加电脑」，选择电脑并输入完整配对码。\n\n'
            '找不到电脑时可以重新查找，或在添加页面使用电脑显示的 IP。',
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('知道了'),
        ),
      ],
    ),
  );

  Widget _header({bool desktop = false}) => Padding(
    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
    child: Row(
      children: [
        Brand(small: desktop),
        if (desktop && c.phones.isNotEmpty) ...[
          const SizedBox(width: 18),
          Expanded(
            child: Text(
              c.deviceName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: secondaryColor),
            ),
          ),
        ] else
          const Spacer(),
        IconButton(
          onPressed: _settings,
          tooltip: '设置',
          icon: const Icon(Icons.settings_outlined),
        ),
      ],
    ),
  );

  Widget _guide({required bool sender}) => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: constraints.maxHeight),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 414),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ConnectionMark(large: sender),
                  const SizedBox(height: 20),
                  Text(
                    sender ? '先连接一台电脑' : '连接你的手机',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    sender ? '在电脑上打开轻贴，点击「开始配对」' : '打开手机轻贴，添加这台电脑',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 14, color: secondaryColor),
                  ),
                  const SizedBox(height: 24),
                  if (!sender) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: lineColor),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Platform.isMacOS
                                ? Icons.laptop_mac
                                : Icons.desktop_windows_outlined,
                            size: 32,
                            color: accentColor,
                          ),
                          const SizedBox(width: 18),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  c.deviceName,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                const Text(
                                  '此电脑',
                                  style: TextStyle(
                                    color: secondaryColor,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: sender ? _addComputer : _addPhone,
                      child: Text(sender ? '添加电脑' : '开始配对'),
                    ),
                  ),
                  const SizedBox(height: 4),
                  TextButton(
                    onPressed: _help,
                    child: Text(sender ? '找不到电脑？' : '如何连接'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _sender(BuildContext context) => Column(
    children: [
      _header(),
      Expanded(
        child: c.peers.isEmpty
            ? _guide(sender: true)
            : RefreshIndicator(
                onRefresh: c.refresh,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(24, 18, 24, 28),
                  children: [
                    _SectionHeading(
                      '我的电脑',
                      action: '添加',
                      onPressed: _addComputer,
                    ),
                    const SizedBox(height: 4),
                    ...c.peers.map(
                      (peer) => Column(
                        children: [
                          _DeviceRow(
                            name: peer.name,
                            online: peer.online,
                            icon: peer.platform == 'macos'
                                ? Icons.laptop_mac
                                : Icons.desktop_windows_outlined,
                            mobile: true,
                            onTap: _settings,
                          ),
                          const Divider(),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                    FilledButton.icon(
                      onPressed: c.busy
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
                      onPressed: c.busy || _pickingImage ? null : _pickImage,
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
              ),
      ),
    ],
  );

  Widget _receiver(BuildContext context) => Column(
    children: [
      _header(desktop: true),
      const Divider(),
      if (!c.online)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            children: [
              const Icon(Icons.wifi_off, size: 18, color: secondaryColor),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('尚未连接网络', style: TextStyle(color: secondaryColor)),
              ),
              TextButton(onPressed: c.restart, child: const Text('重试')),
            ],
          ),
        ),
      Expanded(
        child: c.phones.isEmpty
            ? _guide(sender: false)
            : LayoutBuilder(
                builder: (context, constraints) => Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: constraints.maxWidth < 550 ? 20 : 28,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Keep the connected devices visible while the received content scrolls.
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: constraints.maxHeight * .48,
                        ),
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.only(top: 8, bottom: 18),
                          child: Column(
                            children: [
                              _SectionHeading(
                                '已配对手机',
                                action: '添加手机',
                                onPressed: _addPhone,
                              ),
                              const SizedBox(height: 6),
                              ...c.phones.map(
                                (phone) => Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      border: Border.all(color: lineColor),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: _DeviceRow(
                                      name: phone.name,
                                      online: c.online && phone.online,
                                      icon: Icons.smartphone_outlined,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const Divider(),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child: _received(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    ],
  );

  Widget _received(BuildContext context) {
    final clip = c.latest;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('最近收到', style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            if (clip != null)
              Text(
                _time(clip.at),
                style: const TextStyle(fontSize: 13, color: secondaryColor),
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (clip == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Row(
              children: [
                Icon(Icons.inbox_outlined, size: 22, color: secondaryColor),
                SizedBox(width: 12),
                Text(
                  '等待手机发送内容',
                  style: TextStyle(color: secondaryColor, fontSize: 14),
                ),
              ],
            ),
          )
        else
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: lineColor),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      clip.payload.isImage
                          ? Icons.image_outlined
                          : Icons.description_outlined,
                      size: 22,
                      color: secondaryColor,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      clip.payload.isImage ? '图片' : '文字',
                      style: const TextStyle(
                        color: secondaryColor,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '来自 ${clip.sender}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: secondaryColor,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (clip.payload.isImage)
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 280),
                      child: Image.memory(
                        clip.payload.png!,
                        fit: BoxFit.contain,
                        semanticLabel: '收到的图片',
                        errorBuilder: (_, _, _) => const Text('无法预览图片'),
                      ),
                    ),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 220),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        clip.payload.text!,
                        style: const TextStyle(fontSize: 16, height: 1.6),
                      ),
                    ),
                  ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    const Icon(
                      Icons.check_circle,
                      size: 20,
                      color: accentColor,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        '已写入剪贴板',
                        style: TextStyle(fontSize: 14, color: accentColor),
                      ),
                    ),
                    const SizedBox(width: 12),
                    _KeyCap(
                      Theme.of(context).platform == TargetPlatform.macOS
                          ? '⌘'
                          : 'Ctrl',
                    ),
                    const SizedBox(width: 6),
                    const _KeyCap('V'),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }

  String _time(DateTime at) => DateTime.now().difference(at).inMinutes < 1
      ? '刚刚'
      : '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading(
    this.title, {
    required this.action,
    required this.onPressed,
  });
  final String title, action;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(title, style: Theme.of(context).textTheme.titleMedium),
      ),
      TextButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.add, size: 19),
        label: Text(action),
      ),
    ],
  );
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({
    required this.name,
    required this.online,
    required this.icon,
    this.mobile = false,
    this.onTap,
  });
  final String name;
  final bool online, mobile;
  final IconData icon;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(12),
    child: Padding(
      padding: EdgeInsets.symmetric(
        horizontal: mobile ? 0 : 18,
        vertical: mobile ? 18 : 14,
      ),
      child: Row(
        children: [
          Container(
            width: mobile ? 44 : 52,
            height: 52,
            decoration: mobile
                ? null
                : BoxDecoration(
                    color: sageColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
            child: Icon(icon, size: 30, color: mobile ? inkColor : accentColor),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                if (mobile)
                  OnlineStatus(online)
                else
                  const Text(
                    'Android',
                    style: TextStyle(fontSize: 14, color: secondaryColor),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (mobile)
            const Icon(Icons.chevron_right, size: 22, color: secondaryColor)
          else
            OnlineStatus(online),
        ],
      ),
    ),
  );
}

class _ConnectionMark extends StatelessWidget {
  const _ConnectionMark({this.large = false});
  final bool large;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      padding: EdgeInsets.all(large ? 20 : 18),
      decoration: const BoxDecoration(color: sageColor, shape: BoxShape.circle),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.smartphone_outlined,
            size: large ? 56 : 34,
            color: accentColor,
          ),
          const SizedBox(width: 8),
          const Icon(Icons.more_horiz, size: 24, color: accentColor),
          const SizedBox(width: 8),
          Icon(Icons.laptop_mac, size: large ? 70 : 44, color: accentColor),
        ],
      ),
    ),
  );
}

class _KeyCap extends StatelessWidget {
  const _KeyCap(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      border: Border.all(color: lineColor),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      label,
      style: const TextStyle(fontSize: 12, color: secondaryColor),
    ),
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
