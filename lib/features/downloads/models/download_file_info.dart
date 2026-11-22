class DownloadFileInfo {
  final String fileName;
  final int? fileSize;
  final String fileType;
  final bool supportsResume;
  final String protocol;
  final bool isDirectDownload;
  final String directDownloadReason;
  final String? contentType;

  const DownloadFileInfo({
    required this.fileName,
    required this.fileSize,
    required this.fileType,
    required this.supportsResume,
    this.protocol = 'HTTPS',
    this.isDirectDownload = true,
    this.directDownloadReason = 'Direct download link',
    this.contentType,
  });

  String get formattedSize {
    if (fileSize == null) return 'Unknown';

    if (fileSize! < 1024) {
      return '$fileSize B';
    }

    if (fileSize! < 1024 * 1024) {
      return '${(fileSize! / 1024).toStringAsFixed(2)} KB';
    }

    if (fileSize! < 1024 * 1024 * 1024) {
      return '${(fileSize! / (1024 * 1024)).toStringAsFixed(2)} MB';
    }

    return '${(fileSize! / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
