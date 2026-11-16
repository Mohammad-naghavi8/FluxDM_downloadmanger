import 'dart:io';

import 'package:dio/dio.dart';

class DownloadService {
  final Dio _dio = Dio();

  Future<void> downloadFile({
    required String url,
    required String savePath,
    required void Function(int received, int total) onProgress,
    CancelToken? cancelToken,
  }) async {
    final uri = Uri.tryParse(url);

    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      throw ArgumentError('Invalid download URL');
    }

    final file = File(savePath);

    await file.parent.create(recursive: true);

    await _dio.download(
      url,
      savePath,
      cancelToken: cancelToken,
      deleteOnError: false,
      onReceiveProgress: (received, total) {
        onProgress(received, total);
      },
    );
  }

  Future<int> getDownloadedBytes(String savePath) async {
    final file = File(savePath);

    if (!await file.exists()) {
      return 0;
    }

    return await file.length();
  }

  Future<bool> supportsResume(String url) async {
    try {
      final response = await _dio.head(
        url,
        options: Options(
          followRedirects: true,
          validateStatus: (status) =>
              status != null && status >= 200 && status < 400,
        ),
      );

      final acceptRanges = response.headers.value('accept-ranges');

      return acceptRanges?.toLowerCase() == 'bytes';
    } catch (_) {
      return false;
    }
  }

  Future<void> resumeDownload({
    required String url,
    required String savePath,
    required int downloadedBytes,
    required void Function(int received, int total) onProgress,
    CancelToken? cancelToken,
  }) async {
    final file = File(savePath);

    final response = await _dio.get<ResponseBody>(
      url,
      options: Options(
        responseType: ResponseType.stream,
        headers: {'Range': 'bytes=$downloadedBytes-'},
        validateStatus: (status) => status == 206,
      ),
      cancelToken: cancelToken,
    );

    final contentRange = response.headers.value('content-range');

    if (contentRange == null ||
        !contentRange.startsWith('bytes $downloadedBytes-')) {
      throw Exception('Server returned an invalid Content-Range');
    }

    final total = int.tryParse(contentRange.split('/').last);

    if (total == null) {
      throw Exception('Could not determine file size');
    }

    final sink = file.openWrite(mode: FileMode.append);

    var received = downloadedBytes;

    try {
      await for (final chunk in response.data!.stream) {
        sink.add(chunk);
        received += chunk.length;
        onProgress(received, total);
      }

      await sink.flush();
    } finally {
      await sink.close();
    }
  }
}
