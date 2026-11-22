import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DownloadPathService {
  static const String _defaultFolderName = 'Download Manager';
  static const String _pathKey = 'download_directory';

  static const Map<String, String> categories = {
    'Programs': 'Programs',
    'Videos': 'Videos',
    'Music': 'Music',
    'Documents': 'Documents',
    'Images': 'Images',
    'Compressed': 'Compressed',
    'Others': 'Others',
  };

  String getCategoryForFile(String fileName) {
    final extension = fileName.split('.').last.toLowerCase();

    const programs = {'exe', 'msi', 'msix', 'appx', 'apk'};
    const videos = {'mp4', 'mkv', 'avi', 'mov', 'wmv', 'webm'};
    const music = {'mp3', 'wav', 'flac', 'aac', 'ogg', 'm4a'};
    const documents = {
      'pdf',
      'doc',
      'docx',
      'txt',
      'xls',
      'xlsx',
      'ppt',
      'pptx',
    };
    const images = {'jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'};
    const compressed = {'zip', 'rar', '7z', 'tar', 'gz'};

    if (programs.contains(extension)) return 'Programs';
    if (videos.contains(extension)) return 'Videos';
    if (music.contains(extension)) return 'Music';
    if (documents.contains(extension)) return 'Documents';
    if (images.contains(extension)) return 'Images';
    if (compressed.contains(extension)) return 'Compressed';

    return 'Others';
  }

  Future<String> getDefaultPath() async {
    final home =
        Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];

    if (home == null || home.isEmpty) {
      throw Exception('Could not determine user home directory');
    }

    return '$home${Platform.pathSeparator}Downloads'
        '${Platform.pathSeparator}$_defaultFolderName';
  }

  Future<String> getSavedPath() async {
    final prefs = await SharedPreferences.getInstance();

    final savedPath = prefs.getString(_pathKey);

    if (savedPath != null && savedPath.isNotEmpty) {
      return savedPath;
    }

    final defaultPath = await getDefaultPath();
    await prefs.setString(_pathKey, defaultPath);

    return defaultPath;
  }

  Future<bool> chooseDirectory() async {
    final result = await FilePicker.pickDirectory();

    if (result == null) {
      return false;
    }

    final selectedPath = result.path;

    if (selectedPath.isEmpty) {
      return false;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pathKey, selectedPath);

    return true;
  }

  Future<String> getCategoryPath(String category) async {
    final basePath = await getSavedPath();

    final folderName = categories[category] ?? 'Others';

    final directory = Directory(
      '$basePath${Platform.pathSeparator}$folderName',
    );

    await directory.create(recursive: true);

    return directory.path;
  }

  Future<String> getFilePath({
    required String fileName,
    required String category,
  }) async {
    final directoryPath = await getCategoryPath(category);

    return '$directoryPath${Platform.pathSeparator}$fileName';
  }
}
