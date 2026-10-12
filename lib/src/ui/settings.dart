import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../controller.dart';
import '../core/models.dart';
import 'theme.dart';

String userError(Object error) =>
    error is ClipException ? error.message : '操作失败，请重试';

class AddComputerDialog extends StatefulWidget {
  const AddComputerDialog({super.key, required this.controller});
  final ClipController controller;
  @override
  State<AddComputerDialog> createState() => _AddComputerDialogState();
}

class _AddComputerDialogState extends State<AddComputerDialog> {
  final _host = TextEditingController();
  final _code = TextEditingController();
  DiscoveredPeer? _selected;
  bool _manual = false;
  bool _searchTimedOut = false;
  Timer? _searchTimer;

  DiscoveredPeer? get _candidate {
    final candidates = widget.controller.candidates;
    if (_selected != null) {
      for (final candidate in candidates) {
        if (candidate.id == _selected!.id) return candidate;
      }
    }
    return candidates.length == 1 ? candidates.single : null;
  }

  void _search() {
    _searchTimer?.cancel();
    _searchTimedOut = false;
    widget.controller.discovery.search();
    _searchTimer = Timer(const Duration(seconds: 8), () {
      if (mounted) setState(() => _searchTimedOut = true);
    });
  }

  bool _working = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _host.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _pair() async {
    setState(() {
      _error = null;
      _working = true;
    });
    try {
      DiscoveredPeer? candidate = _candidate;
      if (_manual) {
        final ip = InternetAddress.tryParse(_host.text.trim());
        if (ip == null ||
            ip.type != InternetAddressType.IPv4 ||
            ip.isMulticast) {
          throw const ClipException('请输入电脑显示的 IPv4 地址');
        }
        candidate = DiscoveredPeer(
          id: '',
          name: '',
          platform: '',
          host: ip.address,
          port: receiverPort,
        );
      }
      if (candidate == null) throw const ClipException('请选择一台电脑，或使用 IP 添加');
      await widget.controller.pair(candidate, _code.text);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = userError(e));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) => PopScope(
      canPop: !_working,
      child: AlertDialog(
        title: const Text('添加电脑'),
        content: SizedBox(
          width: 360,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('在电脑上点「开始配对」或「添加手机」，然后输入完整配对码。'),
                const SizedBox(height: 16),
                if (!_manual) ...[
                  if (widget.controller.candidates.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        _searchTimedOut ? '未发现电脑，请确认电脑端已打开' : '正在查找电脑…',
                        style: TextStyle(color: secondaryColor),
                      ),
                    ),
                  ...widget.controller.candidates.map(
                    (p) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      selected: _candidate?.id == p.id,
                      leading: Icon(
                        _candidate?.id == p.id
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                      ),
                      onTap: _working
                          ? null
                          : () => setState(() => _selected = p),
                      title: Text(p.name),
                      subtitle: Text(p.host),
                    ),
                  ),
                  if (_searchTimedOut && widget.controller.candidates.isEmpty)
                    TextButton(
                      onPressed: _working ? null : () => setState(_search),
                      child: const Text('重新查找'),
                    ),
                  TextButton(
                    onPressed: _working
                        ? null
                        : () => setState(() => _manual = true),
                    child: const Text('使用 IP 添加'),
                  ),
                ] else ...[
                  TextField(
                    controller: _host,
                    enabled: !_working,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '电脑 IP',
                      hintText: '192.168.1.8',
                    ),
                  ),
                  TextButton(
                    onPressed: _working
                        ? null
                        : () => setState(() {
                            _manual = false;
                            _search();
                          }),
                    child: const Text('返回自动查找'),
                  ),
                ],
                const SizedBox(height: 8),
                TextField(
                  controller: _code,
                  enabled: !_working,
                  autocorrect: false,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: '配对码',
                    hintText: '123456-ABCD-EF12-3456',
                  ),
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
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _working ? null : () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(80, 48)),
            onPressed: _working ? null : _pair,
            child: Text(_working ? '连接中' : '连接'),
          ),
        ],
      ),
    ),
  );
}

class PairingDialog extends StatefulWidget {
  const PairingDialog({super.key, required this.controller});
  final ClipController controller;
  @override
  State<PairingDialog> createState() => _PairingDialogState();
}

class _PairingDialogState extends State<PairingDialog> {
  Timer? _timer;
  Set<String> _initialTokens = {};
  bool _closing = false;

  void _finishWhenPaired() {
    if (_closing || !mounted) return;
    if (widget.controller.phones.any(
      (p) => p.online && !_initialTokens.contains(p.token),
    )) {
      _closing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context);
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _initialTokens = widget.controller.phones.map((p) => p.token).toSet();
    widget.controller.addListener(_finishWhenPaired);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_closing) widget.controller.openPairing();
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.controller.removeListener(_finishWhenPaired);
    // Avoid notifying another dialog during its parent's build/dispose phase.
    scheduleMicrotask(widget.controller.closePairing);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      final code = c.pairingCode;
      final paired = c.phones.any((p) => !_initialTokens.contains(p.token));
      final seconds =
          c.receiver?.pairingExpires?.difference(DateTime.now()).inSeconds ?? 0;
      return AlertDialog(
        title: const Text('添加手机'),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (code != null) ...[
                  const Text('在手机上点「添加电脑」，选择这台电脑。'),
                  const SizedBox(height: 20),
                  Text(
                    c.deviceName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  SelectableText(
                    code,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      letterSpacing: .5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${seconds < 0 ? 0 : seconds} 秒后过期',
                    style: const TextStyle(color: secondaryColor),
                  ),
                  const SizedBox(height: 20),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('找不到电脑？', style: TextStyle(fontSize: 14)),
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: SelectableText(
                          c.addresses.isEmpty
                              ? '尚未连接网络'
                              : '使用 IP 添加：${c.addresses.join(' / ')}',
                          style: const TextStyle(
                            fontSize: 14,
                            color: secondaryColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  Text(paired ? '手机已添加' : '配对码已失效'),
                  if (!paired)
                    TextButton(
                      onPressed: c.openPairing,
                      child: const Text('重新生成'),
                    ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('完成'),
          ),
        ],
      );
    },
  );
}

class SettingsDialog extends StatefulWidget {
  const SettingsDialog({super.key, required this.controller});
  final ClipController controller;
  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  late final TextEditingController _name;
  String? _error;
  bool _saving = false;
  bool _saved = false;
  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.controller.deviceName);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _rename() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.controller.rename(_name.text);
      if (mounted) setState(() => _saved = true);
    } catch (e) {
      if (mounted) setState(() => _error = userError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _remove(String id, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('移除 $name？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      if (widget.controller.isSender) {
        await widget.controller.removePeer(id);
      } else {
        await widget.controller.removePhone(id);
      }
    } catch (e) {
      if (mounted) setState(() => _error = userError(e));
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      return AlertDialog(
        title: const Text('设置'),
        content: SizedBox(
          width: 380,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _name,
                  onChanged: (_) => setState(() => _saved = false),
                  maxLength: 40,
                  decoration: const InputDecoration(labelText: '设备名称'),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _saving ? null : _rename,
                    child: Text(
                      _saving
                          ? '保存中'
                          : _saved
                          ? '已保存'
                          : '保存名称',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  '已配对设备',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                if (c.isSender && c.peers.isEmpty ||
                    !c.isSender && c.phones.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      '暂无设备',
                      style: TextStyle(color: secondaryColor),
                    ),
                  ),
                if (c.isSender)
                  ...c.peers.map(
                    (p) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(p.name),
                      subtitle: Text(p.host),
                      trailing: IconButton(
                        tooltip: '移除 ${p.name}',
                        onPressed: () => _remove(p.id, p.name),
                        icon: const Icon(Icons.link_off),
                      ),
                    ),
                  ),
                if (!c.isSender) ...[
                  ...c.phones.map(
                    (p) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(p.name),
                      subtitle: OnlineStatus(c.online && p.online),
                      trailing: IconButton(
                        tooltip: '移除 ${p.name}',
                        onPressed: () => _remove(p.id, p.name),
                        icon: const Icon(Icons.link_off),
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => PairingDialog(controller: c),
                    ),
                    icon: const Icon(Icons.add),
                    label: const Text('添加手机'),
                  ),
                  if (c.addresses.isNotEmpty)
                    SelectableText(
                      c.addresses.join('\n'),
                      style: const TextStyle(
                        color: secondaryColor,
                        fontSize: 13,
                      ),
                    ),
                ],
                if (c.discoveryError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(c.discoveryError!),
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
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('完成'),
          ),
        ],
      );
    },
  );
}
