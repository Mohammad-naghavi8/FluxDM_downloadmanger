class DownloadFileInfo {
  final String fileName;
  final int? fileSize;
  final String fileType;
  final bool supportsResume;

  const DownloadFileInfo({
    required this.fileName,
    required this.fileSize,
    required this.fileType,
    required this.supportsResume,
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
