import 'package:download_manager/app/app.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Cap Flutter's image cache (default is 100 MB) to keep RAM footprint lower.
  PaintingBinding.instance.imageCache
    ..maximumSize = 20
    ..maximumSizeBytes = 8 << 20;
  runApp(const DownloadManagerApp());
}
