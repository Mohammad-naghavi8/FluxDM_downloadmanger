class DirectDownloadCheck {
  final bool isDirect;
  final String reason;

  const DirectDownloadCheck({required this.isDirect, required this.reason});
}

class DownloadLinkHelper {
  static const Set<String> supportedSchemes = {'http', 'https', 'ftp'};

  static const Set<String> _directFileExtensions = {
    // Archives
    'zip', 'rar', '7z', 'tar', 'gz', 'bz2', 'xz', 'tgz', 'iso', 'img', 'cab',
    // Programs / Installers
    'exe', 'msi', 'msix', 'appx', 'apk', 'aab', 'dmg', 'pkg', 'deb', 'rpm',
    'appimage', 'jar', 'bin', 'run',
    // Video
    'mp4', 'mkv', 'avi', 'mov', 'wmv', 'webm', 'flv', 'm4v', 'ts', '3gp',
    // Audio
    'mp3', 'wav', 'flac', 'aac', 'ogg', 'm4a', 'opus', 'wma',
    // Documents
    'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'odt', 'ods', 'rtf',
    'txt', 'csv', 'epub', 'mobi',
    // Images
    'jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'svg', 'tiff', 'ico', 'psd',
    // Misc
    'torrent', 'dat', 'pak', 'vpk', 'rom', 'nsp', 'xci',
  };

  static final RegExp _urlExtractPattern = RegExp(
    r'(?:https?|ftp)://[^\s<>"{}|\\^`\[\]]+',
    caseSensitive: false,
  );

  static bool isSupportedUri(Uri? uri) {
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) return false;
    return supportedSchemes.contains(uri.scheme.toLowerCase()) &&
        uri.host.isNotEmpty;
  }

  static bool isSupportedUrl(String url) {
    return isSupportedUri(Uri.tryParse(url.trim()));
  }

  static String? extractSupportedUrl(String rawText) {
    final trimmed = rawText.trim();
    if (trimmed.isEmpty) return null;

    if (isSupportedUrl(trimmed)) {
      return trimmed;
    }

    final match = _urlExtractPattern.firstMatch(trimmed);
    if (match == null) return null;

    var candidate = match.group(0)!;
    while (candidate.isNotEmpty &&
        '.,;:)>\'"'.contains(candidate[candidate.length - 1])) {
      candidate = candidate.substring(0, candidate.length - 1);
    }

    return isSupportedUrl(candidate) ? candidate : null;
  }

  static String protocolLabel(Uri uri) => uri.scheme.toUpperCase();

  static bool isLikelyDirectDownloadUrl(Uri uri) {
    if (!isSupportedUri(uri)) return false;
    final scheme = uri.scheme.toLowerCase();

    if (scheme == 'ftp') {
      return uri.pathSegments.any((segment) => segment.isNotEmpty);
    }

    if (uri.pathSegments.isNotEmpty) {
      final last = Uri.decodeComponent(uri.pathSegments.last).toLowerCase();
      if (last.contains('.')) {
        final ext = last.split('.').last;
        if (_directFileExtensions.contains(ext) ||
            RegExp(r'^part\d+$').hasMatch(ext) ||
            RegExp(r'^r\d{2}$').hasMatch(ext) ||
            RegExp(r'^\d{3}$').hasMatch(ext)) {
          return true;
        }
      }
    }

    final queryLower = uri.query.toLowerCase();
    if (queryLower.contains('download=1') ||
        queryLower.contains('download=true') ||
        queryLower.contains('attachment') ||
        queryLower.contains('export=download')) {
      return true;
    }

    return false;
  }

  static DirectDownloadCheck evaluateDirectDownload({
    required Uri uri,
    String? contentType,
    String? contentDisposition,
  }) {
    if (uri.scheme.toLowerCase() == 'ftp') {
      return const DirectDownloadCheck(
        isDirect: true,
        reason: 'Direct FTP file link',
      );
    }

    if (contentDisposition != null &&
        contentDisposition.toLowerCase().contains('attachment')) {
      return const DirectDownloadCheck(
        isDirect: true,
        reason: 'Direct download (server attachment)',
      );
    }

    final mime = contentType?.split(';').first.trim().toLowerCase() ?? '';
    if (mime.isNotEmpty) {
      if (mime == 'text/html' || mime == 'application/xhtml+xml') {
        return const DirectDownloadCheck(
          isDirect: false,
          reason: 'Web page (HTML), not a direct file link',
        );
      }

      if (mime == 'application/octet-stream' ||
          mime.startsWith('video/') ||
          mime.startsWith('audio/') ||
          mime.startsWith('image/') ||
          mime.contains('zip') ||
          mime.contains('rar') ||
          mime.contains('compressed') ||
          mime.contains('archive') ||
          mime.contains('pdf') ||
          mime.contains('msdownload') ||
          mime.contains('android.package')) {
        return const DirectDownloadCheck(
          isDirect: true,
          reason: 'Direct download link',
        );
      }
    }

    if (isLikelyDirectDownloadUrl(uri)) {
      return const DirectDownloadCheck(
        isDirect: true,
        reason: 'Direct download link',
      );
    }

    return const DirectDownloadCheck(
      isDirect: false,
      reason: 'Could not confirm direct file link',
    );
  }
}
