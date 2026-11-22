import 'package:download_manager/core/localization/app_strings.dart';
import 'package:download_manager/core/theme/app_colors.dart';
import 'package:download_manager/features/torrents/models/torrent_models.dart';
import 'package:material_ui/material_ui.dart';

class TorrentSettingsDialog extends StatefulWidget {
  final TorrentSettings initialSettings;

  const TorrentSettingsDialog({super.key, required this.initialSettings});

  @override
  State<TorrentSettingsDialog> createState() => _TorrentSettingsDialogState();
}

class _TorrentSettingsDialogState extends State<TorrentSettingsDialog> {
  late bool _keepSharing;
  late bool _stopAtRatio;
  late bool _stopAfterMinutes;
  late bool _registerAssoc;
  late bool _acceptIncoming;
  late bool _mapUpnp;
  late bool _enableDht;
  late bool _enableLpd;
  late bool _useProxy;
  late bool _stopWhenIdle;
  late bool _limitUpload;

  late final TextEditingController _ratioController;
  late final TextEditingController _minutesController;
  late final TextEditingController _portController;
  late final TextEditingController _uploadLimitController;
  late final TextEditingController _blocklistController;

  @override
  void initState() {
    super.initState();
    final s = widget.initialSettings;
    _keepSharing = s.keepSharingAfterFinish;
    _stopAtRatio = s.stopAtShareRatio;
    _stopAfterMinutes = s.stopAfterMinutesEnabled;
    _registerAssoc = s.registerFileAssociation;
    _acceptIncoming = s.acceptIncomingConnections;
    _mapUpnp = s.mapPortUpnp;
    _enableDht = s.enableDht;
    _enableLpd = s.enableLocalPeerDiscovery;
    _useProxy = s.useProxy;
    _stopWhenIdle = s.stopEngineWhenIdle;
    _limitUpload = s.limitUploadEnabled;

    _ratioController = TextEditingController(
      text: s.shareRatio.toStringAsFixed(2),
    );
    _minutesController = TextEditingController(text: '${s.stopAfterMinutes}');
    _portController = TextEditingController(
      text: s.listeningPort != null ? '${s.listeningPort}' : '',
    );
    _uploadLimitController = TextEditingController(
      text: '${s.limitUploadKBps}',
    );
    _blocklistController = TextEditingController(text: s.blocklistUrl);
  }

  @override
  void dispose() {
    _ratioController.dispose();
    _minutesController.dispose();
    _portController.dispose();
    _uploadLimitController.dispose();
    _blocklistController.dispose();
    super.dispose();
  }

  void _saveAndClose() {
    final ratio = double.tryParse(_ratioController.text.trim()) ?? 2.0;
    final minutes = int.tryParse(_minutesController.text.trim()) ?? 1440;
    final port = int.tryParse(_portController.text.trim());
    final uploadLimit = int.tryParse(_uploadLimitController.text.trim()) ?? 100;

    Navigator.of(context).pop(
      TorrentSettings(
        keepSharingAfterFinish: _keepSharing,
        stopAtShareRatio: _stopAtRatio,
        shareRatio: ratio.clamp(0.1, 100.0),
        stopAfterMinutesEnabled: _stopAfterMinutes,
        stopAfterMinutes: minutes.clamp(1, 525600),
        registerFileAssociation: _registerAssoc,
        acceptIncomingConnections: _acceptIncoming,
        listeningPort: (port != null && port > 0 && port <= 65535)
            ? port
            : null,
        mapPortUpnp: _mapUpnp,
        enableDht: _enableDht,
        enableLocalPeerDiscovery: _enableLpd,
        useProxy: _useProxy,
        stopEngineWhenIdle: _stopWhenIdle,
        limitUploadEnabled: _limitUpload,
        limitUploadKBps: uploadLimit.clamp(1, 1024 * 1024),
        blocklistUrl: _blocklistController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: Container(
        width: 520,
        decoration: BoxDecoration(
          color: const Color(0xFF232323),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: const Color(0xFF3A3A3A)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x99000000),
              blurRadius: 24,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildTitleBar(),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                  _checkItem(
                    value: _keepSharing,
                    label: 'Keep sharing torrents after they finish',
                    onChanged: (v) => setState(() => _keepSharing = v),
                  ),
                  _helperText('Off: a finished torrent stops, like any download.'),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.only(left: 20),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _checkItem(
                                value: _stopAtRatio,
                                label: 'Stop sharing at a share ratio of',
                                enabled: _keepSharing,
                                onChanged: (v) =>
                                    setState(() => _stopAtRatio = v),
                              ),
                            ),
                            SizedBox(
                              width: 68,
                              child: _numField(
                                controller: _ratioController,
                                enabled: _keepSharing && _stopAtRatio,
                              ),
                            ),
                            const SizedBox(width: 56),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: _checkItem(
                                value: _stopAfterMinutes,
                                label: 'Stop sharing after sharing for',
                                enabled: _keepSharing,
                                onChanged: (v) =>
                                    setState(() => _stopAfterMinutes = v),
                              ),
                            ),
                            SizedBox(
                              width: 68,
                              child: _numField(
                                controller: _minutesController,
                                enabled: _keepSharing && _stopAfterMinutes,
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 48,
                              child: Text(
                                'minutes',
                                style: TextStyle(
                                  color: _keepSharing
                                      ? const Color(0xFFD0D0D0)
                                      : const Color(0xFF7A7A7A),
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  _checkItem(
                    value: _registerAssoc,
                    label:
                        'Open magnet links and .torrent files with FluxDM',
                    onChanged: (v) => setState(() => _registerAssoc = v),
                  ),
                  _helperText(
                    'For your Windows account only. Another app chosen in "Open with" stays first.',
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Divider(height: 1, color: Color(0xFF3D3D3D)),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: _checkItem(
                          value: _acceptIncoming,
                          label: 'Accept incoming connections',
                          enabled: !_useProxy,
                          onChanged: (v) =>
                              setState(() => _acceptIncoming = v),
                        ),
                      ),
                      const Text(
                        'Port:',
                        style: TextStyle(
                          color: Color(0xFFD8D8D8),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 72,
                        child: _numField(
                          controller: _portController,
                          enabled: !_useProxy && _acceptIncoming,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.only(left: 20),
                    child: _checkItem(
                      value: _mapUpnp,
                      label: 'Map the port on the router (UPnP)',
                      enabled: !_useProxy && _acceptIncoming,
                      onChanged: (v) => setState(() => _mapUpnp = v),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _checkItem(
                    value: _enableDht,
                    label: 'Find peers through the DHT',
                    enabled: !_useProxy,
                    onChanged: (v) => setState(() => _enableDht = v),
                  ),
                  const SizedBox(height: 8),
                  _checkItem(
                    value: _enableLpd,
                    label: 'Find peers on the local network',
                    enabled: !_useProxy,
                    onChanged: (v) => setState(() => _enableLpd = v),
                  ),
                  _helperText(
                    'It tells the computers on your network which torrents you have.',
                  ),
                  const SizedBox(height: 8),
                  _checkItem(
                    value: _useProxy,
                    label: 'Use the proxy (Options → Proxy / Socks, SOCKS5)',
                    onChanged: (v) => setState(() => _useProxy = v),
                  ),
                  _helperText(
                    'With it, incoming connections, the DHT and local peers are off.',
                  ),
                  const SizedBox(height: 8),
                  _checkItem(
                    value: _stopWhenIdle,
                    label:
                        'Stop the torrent engine when no torrent is running',
                    onChanged: (v) => setState(() => _stopWhenIdle = v),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _checkItem(
                          value: _limitUpload,
                          label: 'Limit uploading for all torrents to',
                          onChanged: (v) => setState(() => _limitUpload = v),
                        ),
                      ),
                      SizedBox(
                        width: 68,
                        child: _numField(
                          controller: _uploadLimitController,
                          enabled: _limitUpload,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'KBytes/sec',
                        style: TextStyle(
                          color: Color(0xFFD0D0D0),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Block the addresses in this list (P2P or eMule format):',
                    style: TextStyle(color: Color(0xFFE0E0E0), fontSize: 12),
                  ),
                  const SizedBox(height: 5),
                  SizedBox(
                    height: 26,
                    child: TextField(
                      controller: _blocklistController,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      decoration: const InputDecoration(
                        filled: true,
                        fillColor: Color(0xFF1A1A1A),
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(2)),
                          borderSide: BorderSide(color: Color(0xFF444444)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(2)),
                          borderSide: BorderSide(
                            color: AppColors.accent,
                            width: 1.2,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 5),
                  const Text(
                    'Fetched again every 7 days. Changes apply when no torrent is running.',
                    style: TextStyle(color: Color(0xFF9A9A9A), fontSize: 11),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      SizedBox(
                        width: 82,
                        height: 27,
                        child: OutlinedButton(
                          onPressed: _saveAndClose,
                          style: OutlinedButton.styleFrom(
                            backgroundColor: const Color(0xFF243B31),
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: AppColors.accent),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(3),
                            ),
                            textStyle: const TextStyle(fontSize: 12),
                          ),
                          child: Text(AppStrings.instance.t('OK')),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 82,
                        height: 27,
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: OutlinedButton.styleFrom(
                            backgroundColor: const Color(0xFF303030),
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Color(0xFF4E4E4E)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(3),
                            ),
                            textStyle: const TextStyle(fontSize: 12),
                          ),
                          child: Text(AppStrings.instance.t('Cancel')),
                        ),
                      ),
                    ],
                  ),
                ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTitleBar() {
    return Container(
      height: 30,
      padding: const EdgeInsets.only(left: 10, right: 6),
      decoration: const BoxDecoration(
        color: Color(0xFF141414),
        border: Border(bottom: BorderSide(color: Color(0xFF333333))),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.tune_rounded,
            size: 15,
            color: AppColors.accent,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              AppStrings.instance.t('Torrent settings'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          InkWell(
            onTap: () => Navigator.of(context).pop(),
            borderRadius: BorderRadius.circular(3),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.close, size: 15, color: Color(0xFFCCCCCC)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _checkItem({
    required bool value,
    required String label,
    required ValueChanged<bool> onChanged,
    bool enabled = true,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 18,
          height: 18,
          child: Checkbox(
            value: value,
            activeColor: enabled ? AppColors.accent : const Color(0xFF555555),
            checkColor: Colors.black,
            side: BorderSide(
              color: enabled
                  ? const Color(0xFF6E6E6E)
                  : const Color(0xFF444444),
            ),
            onChanged: enabled ? (v) => onChanged(v ?? false) : null,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: GestureDetector(
            onTap: enabled ? () => onChanged(!value) : null,
            child: Text(
              label,
              style: TextStyle(
                color: enabled
                    ? const Color(0xFFE6E6E6)
                    : const Color(0xFF777777),
                fontSize: 12,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _helperText(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 26, top: 3),
      child: Text(
        text,
        style: const TextStyle(color: Color(0xFF9A9A9A), fontSize: 11.2),
      ),
    );
  }

  Widget _numField({
    required TextEditingController controller,
    bool enabled = true,
  }) {
    return SizedBox(
      height: 24,
      child: TextField(
        controller: controller,
        enabled: enabled,
        textAlign: TextAlign.right,
        style: TextStyle(
          color: enabled ? Colors.white : const Color(0xFF707070),
          fontSize: 12,
        ),
        decoration: InputDecoration(
          filled: true,
          fillColor: enabled
              ? const Color(0xFF1A1A1A)
              : const Color(0xFF202020),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 6,
            vertical: 4,
          ),
          disabledBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(2)),
            borderSide: BorderSide(color: Color(0xFF333333)),
          ),
          enabledBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(2)),
            borderSide: BorderSide(color: Color(0xFF454545)),
          ),
          focusedBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(2)),
            borderSide: BorderSide(color: AppColors.accent, width: 1.2),
          ),
        ),
      ),
    );
  }
}
