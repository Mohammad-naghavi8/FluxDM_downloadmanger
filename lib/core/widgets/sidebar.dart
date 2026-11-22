import 'package:download_manager/core/localization/app_strings.dart';
import 'package:download_manager/core/theme/app_theme_controller.dart';
import 'package:material_ui/material_ui.dart';

class _TreeNodeSpec {
  final String key;
  final String label;
  final String iconType;
  final List<_TreeNodeSpec> children;

  const _TreeNodeSpec({
    required this.key,
    required this.label,
    required this.iconType,
    this.children = const [],
  });
}

class DownloadSidebar extends StatefulWidget {
  final List<String> categories;
  final String selectedCategory;
  final int queuedCount;
  final int Function(String categoryKey)? categoryCount;
  final ValueChanged<String> onSelectCategory;
  final VoidCallback? onClose;

  const DownloadSidebar({
    super.key,
    required this.categories,
    required this.selectedCategory,
    required this.queuedCount,
    required this.onSelectCategory,
    this.categoryCount,
    this.onClose,
  });

  @override
  State<DownloadSidebar> createState() => _DownloadSidebarState();
}

class _DownloadSidebarState extends State<DownloadSidebar> {
  static const List<String> _mediaSubCategories = [
    'Compressed',
    'Documents',
    'Music',
    'Programs',
    'Video',
    'Torrents',
  ];

  final Map<String, bool> _expanded = {
    'All Downloads': true,
    'Unfinished': false,
    'Finished': false,
    'Queues': false,
  };

  String? _hoveredKey;

  List<_TreeNodeSpec> _buildTree() {
    List<_TreeNodeSpec> subNodes(String? prefix) {
      return _mediaSubCategories
          .map(
            (name) => _TreeNodeSpec(
              key: prefix == null ? name : '$prefix::$name',
              label: name,
              iconType: name,
            ),
          )
          .toList(growable: false);
    }

    return [
      _TreeNodeSpec(
        key: 'All Downloads',
        label: 'All Downloads',
        iconType: 'All Downloads',
        children: subNodes(null),
      ),
      _TreeNodeSpec(
        key: 'Unfinished',
        label: 'Unfinished',
        iconType: 'Unfinished',
        children: subNodes('Unfinished'),
      ),
      _TreeNodeSpec(
        key: 'Finished',
        label: 'Finished',
        iconType: 'Finished',
        children: subNodes('Finished'),
      ),
      const _TreeNodeSpec(
        key: 'Queues',
        label: 'Queues',
        iconType: 'Queues',
        children: [
          _TreeNodeSpec(
            key: 'Queues::Main Download Queue',
            label: 'Main Queue',
            iconType: 'QueueItem',
          ),
          _TreeNodeSpec(
            key: 'Queues::Scheduled',
            label: 'Scheduled',
            iconType: 'Scheduled',
          ),
        ],
      ),
    ];
  }

  int _countFor(String key) {
    if (widget.categoryCount != null) {
      return widget.categoryCount!(key);
    }
    if (key == 'Queues') {
      return widget.queuedCount;
    }
    return 0;
  }

  void _toggleExpanded(String key) {
    setState(() {
      _expanded[key] = !(_expanded[key] ?? false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final tree = _buildTree();
    final palette = AppThemeController.instance.palette;
    final isDark = palette.brightness == Brightness.dark;

    return Container(
      width: 214,
      decoration: BoxDecoration(
        color: palette.sidebar,
        border: Border(
          right: BorderSide(color: palette.border, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(palette, isDark),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 4),
              children: [
                for (final root in tree) ...[
                  _buildParentRow(root),
                  if (_expanded[root.key] ?? false)
                    for (int i = 0; i < root.children.length; i++)
                      _buildChildRow(
                        root.children[i],
                        isLast: i == root.children.length - 1,
                      ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(FluxThemePalette palette, bool isDark) {
    final s = AppStrings.instance;
    return Container(
      height: 26,
      padding: const EdgeInsets.only(left: 8, right: 4),
      decoration: BoxDecoration(
        color: palette.menuBar,
        border: Border(
          bottom: BorderSide(color: palette.border, width: 1),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              s.t('Categories'),
              style: TextStyle(
                color: isDark ? const Color(0xFFE8E8E8) : const Color(0xFF111827),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (widget.onClose != null)
            InkWell(
              onTap: widget.onClose,
              borderRadius: BorderRadius.circular(3),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(
                  Icons.close,
                  size: 14,
                  color: isDark ? const Color(0xFFD8D8D8) : const Color(0xFF374151),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildParentRow(_TreeNodeSpec node) {
    final isExpanded = _expanded[node.key] ?? false;
    final isSelected = widget.selectedCategory == node.key;
    final isHovered = _hoveredKey == node.key;
    final count = _countFor(node.key);

    return MouseRegion(
      onEnter: (_) => setState(() => _hoveredKey = node.key),
      onExit: (_) {
        if (_hoveredKey == node.key) {
          setState(() => _hoveredKey = null);
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onSelectCategory(node.key),
        onDoubleTap: () => _toggleExpanded(node.key),
        child: SizedBox(
          height: 24,
          child: Row(
            children: [
              const SizedBox(width: 4),
              InkWell(
                onTap: () => _toggleExpanded(node.key),
                borderRadius: BorderRadius.circular(2),
                child: SizedBox(
                  width: 18,
                  height: 24,
                  child: Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_down
                        : Icons.keyboard_arrow_right,
                    size: 15,
                    color: const Color(0xFFD0D0D0),
                  ),
                ),
              ),
              SizedBox(
                width: 8,
                height: 24,
                child: CustomPaint(
                  painter: _HorizontalDotPainter(),
                ),
              ),
              _IdmTreeIcon(type: node.iconType),
              const SizedBox(width: 5),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 1.5,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFF3E3E3E)
                        : isHovered
                        ? const Color(0xFF2A2A2A)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(2),
                    border: isSelected
                        ? Border.all(
                            color: AppThemeController.instance.palette.accent
                                .withValues(alpha: 0.55),
                            width: 0.7,
                          )
                        : null,
                  ),
                  child: Text(
                    AppStrings.instance.t(node.label),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isSelected
                          ? Colors.white
                          : const Color(0xFFE2E2E2),
                      fontSize: 12.5,
                      fontWeight: isSelected
                          ? FontWeight.w500
                          : FontWeight.normal,
                    ),
                  ),
                ),
              ),
              if (count > 0) ...[
                const SizedBox(width: 4),
                Text(
                  '($count)',
                  style: const TextStyle(
                    color: Color(0xFF9E9E9E),
                    fontSize: 12,
                  ),
                ),
              ],
              const SizedBox(width: 6),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChildRow(_TreeNodeSpec node, {required bool isLast}) {
    final isSelected = widget.selectedCategory == node.key;
    final isHovered = _hoveredKey == node.key;
    final count = _countFor(node.key);

    return MouseRegion(
      onEnter: (_) => setState(() => _hoveredKey = node.key),
      onExit: (_) {
        if (_hoveredKey == node.key) {
          setState(() => _hoveredKey = null);
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onSelectCategory(node.key),
        child: SizedBox(
          height: 24,
          child: Row(
            children: [
              const SizedBox(width: 30),
              SizedBox(
                width: 24,
                height: 24,
                child: CustomPaint(
                  painter: _TreeBranchPainter(isLast: isLast),
                ),
              ),
              _IdmTreeIcon(type: node.iconType),
              const SizedBox(width: 6),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 1.5,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFF3E3E3E)
                        : isHovered
                        ? const Color(0xFF2A2A2A)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(2),
                    border: isSelected
                        ? Border.all(
                            color: AppThemeController.instance.palette.accent
                                .withValues(alpha: 0.55),
                            width: 0.7,
                          )
                        : null,
                  ),
                  child: Text(
                    AppStrings.instance.t(node.label),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isSelected
                          ? Colors.white
                          : const Color(0xFFE2E2E2),
                      fontSize: 12.5,
                      fontWeight: isSelected
                          ? FontWeight.w500
                          : FontWeight.normal,
                    ),
                  ),
                ),
              ),
              if (count > 0) ...[
                const SizedBox(width: 4),
                Text(
                  '($count)',
                  style: const TextStyle(
                    color: Color(0xFF9E9E9E),
                    fontSize: 12,
                  ),
                ),
              ],
              const SizedBox(width: 6),
            ],
          ),
        ),
      ),
    );
  }
}

class _HorizontalDotPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF6A6A6A)
      ..strokeWidth = 1;
    final y = size.height / 2;
    for (double x = 1; x < size.width; x += 3) {
      canvas.drawRect(Rect.fromLTWH(x, y, 1, 1), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _TreeBranchPainter extends CustomPainter {
  final bool isLast;

  const _TreeBranchPainter({required this.isLast});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF6A6A6A)
      ..strokeWidth = 1;

    const trunkX = 8.0;
    final midY = size.height / 2;
    final maxY = isLast ? midY + 1 : size.height;

    for (double y = 0; y < maxY; y += 3) {
      canvas.drawRect(Rect.fromLTWH(trunkX, y, 1, 1), paint);
    }
    for (double x = trunkX + 2; x < size.width; x += 3) {
      canvas.drawRect(Rect.fromLTWH(x, midY, 1, 1), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _TreeBranchPainter oldDelegate) =>
      oldDelegate.isLast != isLast;
}

class _IdmTreeIcon extends StatelessWidget {
  final String type;

  const _IdmTreeIcon({required this.type});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 18,
      height: 18,
      child: Center(child: _buildGlyph()),
    );
  }

  Widget _buildGlyph() {
    switch (type) {
      case 'All Downloads':
        return const Icon(
          Icons.folder_rounded,
          size: 17,
          color: Color(0xFFE8BE47),
        );
      case 'Compressed':
        return const Icon(
          Icons.folder_zip_rounded,
          size: 16,
          color: Color(0xFFDCDCDC),
        );
      case 'Documents':
        return const Icon(
          Icons.insert_drive_file_rounded,
          size: 16,
          color: Color(0xFFF0F0F0),
        );
      case 'Music':
        return const Icon(
          Icons.music_note_rounded,
          size: 17,
          color: Color(0xFFB8B8B8),
        );
      case 'Programs':
        return Container(
          width: 15,
          height: 13,
          decoration: BoxDecoration(
            color: const Color(0xFFF2F2F2),
            borderRadius: BorderRadius.circular(1.5),
            border: Border.all(color: const Color(0xFF6F8FAF), width: 0.8),
          ),
          child: Column(
            children: [
              Container(
                height: 3.5,
                color: const Color(0xFF3E84D6),
              ),
            ],
          ),
        );
      case 'Video':
        return const Icon(
          Icons.movie_outlined,
          size: 16,
          color: Color(0xFF7FD1AE),
        );
      case 'Torrents':
        return _folderWithBadge(
          badgeIcon: Icons.link_rounded,
          badgeColor: const Color(0xFFD8D8D8),
          badgeBg: const Color(0xFF3B3B3B),
        );
      case 'Unfinished':
        return _folderWithBadge(
          badgeIcon: Icons.arrow_forward_rounded,
          badgeColor: const Color(0xFF00D58A),
          badgeBg: const Color(0xFF1A1A1A),
        );
      case 'Finished':
        return _folderWithBadge(
          badgeIcon: Icons.check_rounded,
          badgeColor: const Color(0xFF00D58A),
          badgeBg: const Color(0xFF1A1A1A),
        );
      case 'Queues':
        return _folderWithBadge(
          badgeIcon: Icons.layers_rounded,
          badgeColor: const Color(0xFFE6E6E6),
          badgeBg: const Color(0xFF2C2C2C),
        );
      case 'QueueItem':
        return const Icon(
          Icons.playlist_play_rounded,
          size: 16,
          color: Color(0xFF9AC6FF),
        );
      case 'Scheduled':
        return const Icon(
          Icons.schedule_rounded,
          size: 15,
          color: Color(0xFF00D58A),
        );
      default:
        return const Icon(
          Icons.folder_outlined,
          size: 16,
          color: Color(0xFFE8BE47),
        );
    }
  }

  Widget _folderWithBadge({
    required IconData badgeIcon,
    required Color badgeColor,
    required Color badgeBg,
  }) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        const Icon(
          Icons.folder_rounded,
          size: 17,
          color: Color(0xFFE8BE47),
        ),
        Positioned(
          right: -1,
          bottom: -1,
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: badgeBg,
              borderRadius: BorderRadius.circular(2),
            ),
            child: Icon(
              badgeIcon,
              size: 9,
              color: badgeColor,
            ),
          ),
        ),
      ],
    );
  }
}
