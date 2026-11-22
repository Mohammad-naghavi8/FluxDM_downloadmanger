import 'dart:io';

import 'package:download_manager/core/theme/app_colors.dart';
import 'package:download_manager/features/downloads/services/browser_bridge_service.dart';
import 'package:material_ui/material_ui.dart';

class BrowserIntegrationDialog extends StatelessWidget {
  final BrowserBridgeService bridgeService;

  const BrowserIntegrationDialog({super.key, required this.bridgeService});

  String _extensionDirectoryPath() {
    final cwd = Directory.current.path;
    return '$cwd${Platform.pathSeparator}browser_extension';
  }

  Future<void> _openExtensionFolder(BuildContext context) async {
    final extDir = Directory(_extensionDirectoryPath());
    if (!await extDir.exists()) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Extension folder not found at ${extDir.path}'),
        ),
      );
      return;
    }

    if (Platform.isWindows) {
      await Process.run('explorer.exe', [extDir.path]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final running = bridgeService.isRunning;
    final extPath = _extensionDirectoryPath();

    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Row(
        children: [
          Icon(Icons.language_rounded, color: AppColors.accent, size: 20),
          SizedBox(width: 8),
          Text('Browser Integration', style: TextStyle(fontSize: 16)),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: running ? AppColors.accent : Colors.redAccent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          running
                              ? 'Browser Bridge Active'
                              : 'Browser Bridge Offline',
                          style: TextStyle(
                            color: running
                                ? AppColors.accent
                                : Colors.redAccent,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Local endpoint: ${bridgeService.endpointUrl}',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Supported Link Sources & Protocols',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
            ),
            const SizedBox(height: 6),
            const Text(
              '• Protocols: HTTP, HTTPS, and FTP\n'
              '• Automatic clipboard detection & direct file link check\n'
              '• Chrome / Edge / Brave extension (Manifest V3)',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'How to connect your browser:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
            ),
            const SizedBox(height: 6),
            const Text(
              '1. Open chrome://extensions (or edge://extensions)\n'
              '2. Enable "Developer mode"\n'
              '3. Click "Load unpacked" and select the browser_extension folder',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AppColors.border),
              ),
              child: Text(
                extPath,
                style: const TextStyle(fontSize: 11),
              ),
            ),
          ],
        ),
      ),
      actions: [
        OutlinedButton.icon(
          onPressed: () => _openExtensionFolder(context),
          icon: const Icon(Icons.folder_open_rounded, size: 16),
          label: const Text('Open Extension Folder'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
