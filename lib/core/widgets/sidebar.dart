import 'package:download_manager/core/theme/app_colors.dart';
import 'package:material_ui/material_ui.dart';

class DownloadSidebar extends StatelessWidget {
  final List<String> categories;
  final String selectedCategory;
  final int queuedCount;
  final ValueChanged<String> onSelectCategory;

  const DownloadSidebar({
    super.key,
    required this.categories,
    required this.selectedCategory,
    required this.queuedCount,
    required this.onSelectCategory,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 224,
      color: AppColors.sidebar,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Text(
              'LIBRARY',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: categories.length,
              itemBuilder: (context, index) {
                final category = categories[index];
                final selected = selectedCategory == category;

                return Material(
                  color: Colors.transparent,
                  child: ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                    minLeadingWidth: 20,
                    horizontalTitleGap: 12,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                    selected: selected,
                    selectedTileColor: AppColors.accentDark,
                    leading: Icon(
                      _categoryIcon(category),
                      size: 17,
                      color: selected
                          ? AppColors.accent
                          : AppColors.textSecondary,
                    ),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            category,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: selected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: selected
                                  ? AppColors.accent
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ),
                        if (category == 'Queues' && queuedCount > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.accentDark,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '$queuedCount',
                              style: const TextStyle(
                                color: AppColors.accent,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                    onTap: () => onSelectCategory(category),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  IconData _categoryIcon(String category) {
    return switch (category) {
      'All Downloads' => Icons.download_rounded,
      'Compressed' => Icons.folder_zip_outlined,
      'Documents' => Icons.description_outlined,
      'Music' => Icons.music_note_outlined,
      'Program' => Icons.apps,
      'Video' => Icons.video_library_outlined,
      'Unfinished' => Icons.downloading_outlined,
      'Finished' => Icons.check_circle_outline,
      'Queues' => Icons.playlist_play,
      _ => Icons.folder_outlined,
    };
  }
}
