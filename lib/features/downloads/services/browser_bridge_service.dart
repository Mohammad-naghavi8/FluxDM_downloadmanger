import 'dart:convert';
import 'dart:io';

import 'package:download_manager/features/downloads/utils/download_link_helper.dart';

class BrowserCapturedLink {
  final String url;
  final String? fileName;
  final bool autoStart;

  const BrowserCapturedLink({
    required this.url,
    this.fileName,
    this.autoStart = false,
  });
}

class BrowserBridgeService {
  static const int defaultPort = 45821;

  HttpServer? _server;
  int? _boundPort;

  bool get isRunning => _server != null;
  int get port => _boundPort ?? defaultPort;
  String get endpointUrl => 'http://127.0.0.1:$port/add-download';

  Future<bool> start({
    required void Function(BrowserCapturedLink link) onLinkReceived,
    int port = defaultPort,
  }) async {
    if (_server != null) return true;

    try {
      final server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        port,
        shared: true,
      );
      _server = server;
      _boundPort = server.port;

      server.listen((HttpRequest request) async {
        _applyCorsHeaders(request.response);

        if (request.method == 'OPTIONS') {
          request.response.statusCode = HttpStatus.noContent;
          await request.response.close();
          return;
        }

        if (request.method == 'GET' && request.uri.path == '/health') {
          request.response.statusCode = HttpStatus.ok;
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'ok': true,
              'app': 'Download Manager',
              'port': _boundPort,
            }),
          );
          await request.response.close();
          return;
        }

        if (request.method == 'POST' && request.uri.path == '/add-download') {
          try {
            final body = await utf8.decoder.bind(request).join();
            final data = jsonDecode(body) as Map<String, dynamic>;
            final rawUrl = (data['url'] as String?)?.trim() ?? '';
            final extracted = DownloadLinkHelper.extractSupportedUrl(rawUrl);

            if (extracted == null) {
              request.response.statusCode = HttpStatus.badRequest;
              request.response.headers.contentType = ContentType.json;
              request.response.write(
                jsonEncode({
                  'ok': false,
                  'error': 'Unsupported or invalid download URL',
                }),
              );
              await request.response.close();
              return;
            }

            final link = BrowserCapturedLink(
              url: extracted,
              fileName: (data['fileName'] as String?)?.trim(),
              autoStart: data['autoStart'] == true,
            );

            onLinkReceived(link);

            request.response.statusCode = HttpStatus.ok;
            request.response.headers.contentType = ContentType.json;
            request.response.write(
              jsonEncode({'ok': true, 'receivedUrl': extracted}),
            );
            await request.response.close();
          } catch (error) {
            request.response.statusCode = HttpStatus.badRequest;
            request.response.headers.contentType = ContentType.json;
            request.response.write(
              jsonEncode({'ok': false, 'error': 'Invalid JSON payload'}),
            );
            await request.response.close();
          }
          return;
        }

        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      });

      return true;
    } catch (_) {
      return false;
    }
  }

  void _applyCorsHeaders(HttpResponse response) {
    response.headers.set('Access-Control-Allow-Origin', '*');
    response.headers.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    response.headers.set('Access-Control-Allow-Headers', 'Content-Type');
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    _boundPort = null;
    if (server != null) {
      await server.close(force: true);
    }
  }
}
