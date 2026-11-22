import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:download_manager/features/downloads/services/go_engine_client.dart';
import 'package:download_manager/features/downloads/services/go_engine_process.dart';
import 'package:download_manager/features/torrents/models/torrent_models.dart';

class TorrentParser {
  static bool isMagnetLink(String input) {
    return input.trim().toLowerCase().startsWith('magnet:?');
  }

  static Future<TorrentMetadata> parse(String input) async {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Please paste a magnet link or choose a .torrent file.');
    }

    if (GoEngineProcess.instance.isRunning) {
      try {
        return await GoEngineClient().parseTorrent(trimmed);
      } catch (_) {}
    }

    if (isMagnetLink(trimmed)) {
      return parseMagnet(trimmed);
    }

    final file = File(trimmed);
    if (!await file.exists()) {
      throw FormatException('Torrent file not found: $trimmed');
    }

    final bytes = await file.readAsBytes();
    return parseTorrentBytes(bytes, sourcePath: trimmed);
  }

  static TorrentMetadata parseMagnet(String magnetUri) {
    final uri = Uri.tryParse(magnetUri);
    if (uri == null || uri.scheme.toLowerCase() != 'magnet') {
      throw const FormatException('Invalid magnet link.');
    }

    final params = uri.queryParametersAll;
    String? infoHash;
    final xtList = params['xt'] ?? const [];
    for (final xt in xtList) {
      final lower = xt.toLowerCase();
      if (lower.startsWith('urn:btih:')) {
        infoHash = xt.substring('urn:btih:'.length);
        break;
      }
      if (lower.startsWith('urn:btmh:')) {
        infoHash = xt.substring('urn:btmh:'.length);
        break;
      }
    }

    if (infoHash == null || infoHash.isEmpty) {
      throw const FormatException('Magnet link is missing a valid info hash (xt=urn:btih:...).');
    }

    final displayName = (params['dn']?.isNotEmpty ?? false)
        ? params['dn']!.first.trim()
        : 'Torrent_$infoHash';
    final trackers = params['tr'] ?? const [];
    final exactLength = int.tryParse(params['xl']?.firstOrNull ?? '') ?? 0;

    return TorrentMetadata(
      source: magnetUri,
      name: displayName,
      infoHash: infoHash,
      trackers: trackers,
      isMagnet: true,
      files: [
        TorrentFileItem(
          name: displayName,
          relativePath: displayName,
          sizeBytes: exactLength,
          selected: true,
        ),
      ],
    );
  }

  static TorrentMetadata parseTorrentBytes(
    Uint8List bytes, {
    required String sourcePath,
  }) {
    final decoder = _BencodeDecoder(bytes);
    final root = decoder.decode();
    if (root is! Map<String, dynamic>) {
      throw const FormatException('Invalid .torrent file structure.');
    }

    final info = root['info'];
    if (info is! Map<String, dynamic>) {
      throw const FormatException('Missing "info" dictionary in .torrent file.');
    }

    final torrentName = _decodeString(info['name']) ??
        sourcePath.split(Platform.pathSeparator).last;

    final trackers = <String>[];
    final announce = _decodeString(root['announce']);
    if (announce != null && announce.isNotEmpty) {
      trackers.add(announce);
    }
    final announceList = root['announce-list'];
    if (announceList is List) {
      for (final tier in announceList) {
        if (tier is List) {
          for (final item in tier) {
            final url = _decodeString(item);
            if (url != null && url.isNotEmpty && !trackers.contains(url)) {
              trackers.add(url);
            }
          }
        }
      }
    }

    final files = <TorrentFileItem>[];
    final rawFiles = info['files'];
    if (rawFiles is List && rawFiles.isNotEmpty) {
      for (final entry in rawFiles) {
        if (entry is! Map<String, dynamic>) continue;
        final length = entry['length'] is int ? entry['length'] as int : 0;
        final rawPath = entry['path'];
        final segments = <String>[];
        if (rawPath is List) {
          for (final seg in rawPath) {
            final s = _decodeString(seg);
            if (s != null && s.isNotEmpty) segments.add(s);
          }
        }
        final relPath = segments.isNotEmpty ? segments.join('/') : torrentName;
        files.add(
          TorrentFileItem(
            name: segments.isNotEmpty ? segments.last : torrentName,
            relativePath: relPath,
            sizeBytes: length,
            selected: true,
          ),
        );
      }
    } else {
      final length = info['length'] is int ? info['length'] as int : 0;
      files.add(
        TorrentFileItem(
          name: torrentName,
          relativePath: torrentName,
          sizeBytes: length,
          selected: true,
        ),
      );
    }

    return TorrentMetadata(
      source: sourcePath,
      name: torrentName,
      trackers: trackers,
      files: files,
      isMagnet: false,
    );
  }

  static String? _decodeString(dynamic value) {
    if (value is String) return value;
    if (value is Uint8List) {
      try {
        return utf8.decode(value, allowMalformed: true);
      } catch (_) {
        return String.fromCharCodes(value);
      }
    }
    return null;
  }
}

class _BencodeDecoder {
  final Uint8List _data;
  int _pos = 0;

  _BencodeDecoder(this._data);

  dynamic decode() {
    if (_pos >= _data.length) {
      throw const FormatException('Unexpected end of bencode data');
    }
    final b = _data[_pos];
    if (b == 0x69) {
      // 'i' -> integer
      return _decodeInt();
    }
    if (b == 0x6C) {
      // 'l' -> list
      return _decodeList();
    }
    if (b == 0x64) {
      // 'd' -> dictionary
      return _decodeDict();
    }
    if (b >= 0x30 && b <= 0x39) {
      // '0'-'9' -> byte string
      return _decodeBytes();
    }
    throw FormatException('Invalid bencode token at offset $_pos');
  }

  int _decodeInt() {
    _pos++; // skip 'i'
    final start = _pos;
    while (_pos < _data.length && _data[_pos] != 0x65) {
      _pos++;
    }
    if (_pos >= _data.length) {
      throw const FormatException('Unterminated bencode integer');
    }
    final raw = ascii.decode(_data.sublist(start, _pos));
    _pos++; // skip 'e'
    return int.parse(raw);
  }

  Uint8List _decodeBytes() {
    final start = _pos;
    while (_pos < _data.length && _data[_pos] != 0x3A) {
      _pos++;
    }
    if (_pos >= _data.length) {
      throw const FormatException('Unterminated bencode string length');
    }
    final length = int.parse(ascii.decode(_data.sublist(start, _pos)));
    _pos++; // skip ':'
    if (_pos + length > _data.length) {
      throw const FormatException('Bencode byte string exceeds buffer');
    }
    final slice = _data.sublist(_pos, _pos + length);
    _pos += length;
    return slice;
  }

  List<dynamic> _decodeList() {
    _pos++; // skip 'l'
    final result = <dynamic>[];
    while (_pos < _data.length && _data[_pos] != 0x65) {
      result.add(decode());
    }
    if (_pos >= _data.length) {
      throw const FormatException('Unterminated bencode list');
    }
    _pos++; // skip 'e'
    return result;
  }

  Map<String, dynamic> _decodeDict() {
    _pos++; // skip 'd'
    final map = <String, dynamic>{};
    while (_pos < _data.length && _data[_pos] != 0x65) {
      final keyBytes = _decodeBytes();
      final key = utf8.decode(keyBytes, allowMalformed: true);
      final value = decode();
      map[key] = value;
    }
    if (_pos >= _data.length) {
      throw const FormatException('Unterminated bencode dictionary');
    }
    _pos++; // skip 'e'
    return map;
  }
}
