import 'package:download_manager/core/localization/app_strings.dart';
import 'package:download_manager/core/theme/app_colors.dart';
import 'package:download_manager/features/torrents/models/torrent_models.dart';
import 'package:download_manager/features/torrents/services/rss_feed_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';

class RssFeedsDialog extends StatefulWidget {
  final RssAndTorrentStorageService storage;
  final void Function(RssArticle article)? onDownloadArticle;

  const RssFeedsDialog({
    super.key,
    required this.storage,
    this.onDownloadArticle,
  });

  @override
  State<RssFeedsDialog> createState() => _RssFeedsDialogState();
}

class _RssFeedsDialogState extends State<RssFeedsDialog> {
  int _selectedTab = 0; // 0 = Feeds, 1 = Download rules

  final TextEditingController _feedAddressController = TextEditingController();
  final TextEditingController _intervalController = TextEditingController(
    text: '30',
  );

  // Rule editor controllers
  final TextEditingController _ruleNameController = TextEditingController();
  final TextEditingController _mustContainController = TextEditingController();
  final TextEditingController _mustNotContainController =
      TextEditingController();
  final TextEditingController _episodesController = TextEditingController();
  final TextEditingController _saveToController = TextEditingController();

  List<RssFeedEntry> _feeds = [];
  List<RssDownloadRule> _rules = [];
  String? _selectedFeedId;
  int? _selectedArticleIndex;
  String? _selectedRuleId;
  bool _isRefreshing = false;
  String _statusText = "Type a feed's address above and click Add feed.";

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _feedAddressController.dispose();
    _intervalController.dispose();
    _ruleNameController.dispose();
    _mustContainController.dispose();
    _mustNotContainController.dispose();
    _episodesController.dispose();
    _saveToController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    final feeds = await widget.storage.loadFeeds();
    final rules = await widget.storage.loadRules();
    final interval = await widget.storage.loadCheckIntervalMinutes();
    if (!mounted) return;
    setState(() {
      _feeds = feeds;
      _rules = rules;
      _intervalController.text = '$interval';
      if (_feeds.isNotEmpty) {
        _selectedFeedId = _feeds.first.id;
      }
      if (_rules.isNotEmpty) {
        _selectRule(_rules.first);
      }
    });
  }

  RssFeedEntry? get _selectedFeed {
    for (final f in _feeds) {
      if (f.id == _selectedFeedId) return f;
    }
    return null;
  }

  RssDownloadRule? get _selectedRule {
    for (final r in _rules) {
      if (r.id == _selectedRuleId) return r;
    }
    return null;
  }

  List<RssArticle> get _allLoadedArticles {
    final all = <RssArticle>[];
    for (final f in _feeds) {
      all.addAll(f.articles);
    }
    return all;
  }

  Future<void> _addFeed() async {
    final url = _feedAddressController.text.trim();
    if (url.isEmpty) return;

    final feed = RssFeedEntry(
      id: 'feed_${DateTime.now().microsecondsSinceEpoch}',
      url: url,
      title: Uri.tryParse(url)?.host ?? url,
    );

    setState(() {
      _feeds.add(feed);
      _selectedFeedId = feed.id;
      _selectedArticleIndex = null;
      _feedAddressController.clear();
      _statusText = 'Fetching ${feed.url}...';
    });

    await widget.storage.saveFeeds(_feeds);
    await _refreshFeed(feed);
  }

  Future<void> _refreshFeed(RssFeedEntry feed) async {
    setState(() {
      _isRefreshing = true;
      _statusText = 'Refreshing ${feed.title}...';
    });

    try {
      final result = await widget.storage.fetchFeed(feed);
      if (!mounted) return;
      setState(() {
        feed.title = result.title;
        feed.articles = result.articles;
        feed.lastError = null;
        _isRefreshing = false;
        _statusText =
            'Loaded ${result.articles.length} article${result.articles.length == 1 ? '' : 's'} from ${feed.title}.';
      });
      await widget.storage.saveFeeds(_feeds);
    } catch (err) {
      if (!mounted) return;
      setState(() {
        feed.lastError = err.toString();
        _isRefreshing = false;
        _statusText = 'Could not load feed: $err';
      });
    }
  }

  Future<void> _removeSelectedFeed() async {
    final feed = _selectedFeed;
    if (feed == null) return;
    setState(() {
      _feeds.removeWhere((f) => f.id == feed.id);
      _selectedFeedId = _feeds.isNotEmpty ? _feeds.first.id : null;
      _selectedArticleIndex = null;
      _statusText = _feeds.isEmpty
          ? "Type a feed's address above and click Add feed."
          : 'Removed feed.';
    });
    await widget.storage.saveFeeds(_feeds);
  }

  void _selectRule(RssDownloadRule rule) {
    _selectedRuleId = rule.id;
    _ruleNameController.text = rule.name;
    _mustContainController.text = rule.mustContain;
    _mustNotContainController.text = rule.mustNotContain;
    _episodesController.text = rule.episodes;
    _saveToController.text = rule.saveTo;
  }

  void _addNewRule() {
    final rule = RssDownloadRule(
      id: 'rule_${DateTime.now().microsecondsSinceEpoch}',
      name: 'New rule',
    );
    setState(() {
      _rules.add(rule);
      _selectRule(rule);
    });
    widget.storage.saveRules(_rules);
  }

  void _deleteSelectedRule() {
    final rule = _selectedRule;
    if (rule == null) return;
    setState(() {
      _rules.removeWhere((r) => r.id == rule.id);
      if (_rules.isNotEmpty) {
        _selectRule(_rules.first);
      } else {
        _selectedRuleId = null;
      }
    });
    widget.storage.saveRules(_rules);
  }

  void _syncSelectedRuleFromFields() {
    final rule = _selectedRule;
    if (rule == null) return;
    setState(() {
      rule.name = _ruleNameController.text;
      rule.mustContain = _mustContainController.text;
      rule.mustNotContain = _mustNotContainController.text;
      rule.episodes = _episodesController.text;
      rule.saveTo = _saveToController.text;
    });
    widget.storage.saveRules(_rules);
  }

  Future<void> _pickRuleSaveFolder() async {
    final result = await FilePicker.pickDirectory();
    if (!mounted || result == null || result.path.isEmpty) return;
    _saveToController.text = result.path;
    _syncSelectedRuleFromFields();
  }

  void _saveInterval() {
    final parsed = int.tryParse(_intervalController.text.trim());
    if (parsed != null && parsed >= 1) {
      widget.storage.saveCheckIntervalMinutes(parsed);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: Container(
        width: 720,
        height: 515,
        decoration: BoxDecoration(
          color: const Color(0xFF232323),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: const Color(0xFF3A3A3A)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x99000000),
              blurRadius: 24,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          children: [
            _buildTitleBar(),
            _buildTabsBar(),
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF2B2B2B),
                  border: Border.all(color: const Color(0xFF3F3F3F)),
                ),
                child: _selectedTab == 0
                    ? _buildFeedsTab()
                    : _buildDownloadRulesTab(),
              ),
            ),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildTitleBar() {
    return Container(
      height: 30,
      padding: const EdgeInsets.only(left: 10, right: 6),
      decoration: const BoxDecoration(
        color: Color(0xFF141414),
        border: Border(bottom: BorderSide(color: Color(0xFF333333))),
      ),
      child: Row(
        children: [
          const Icon(Icons.rss_feed_rounded, size: 15, color: AppColors.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              AppStrings.instance.t('RSS feeds'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          InkWell(
            onTap: () {
              _saveInterval();
              Navigator.of(context).pop();
            },
            borderRadius: BorderRadius.circular(3),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.close, size: 15, color: Color(0xFFCCCCCC)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabsBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
      child: Row(
        children: [
          _tabItem('Feeds', index: 0),
          const SizedBox(width: 2),
          _tabItem('Download rules', index: 1),
        ],
      ),
    );
  }

  Widget _tabItem(String label, {required int index}) {
    final active = _selectedTab == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedTab = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF2B2B2B) : const Color(0xFF1E1E1E),
          border: Border(
            top: BorderSide(
              color: active ? AppColors.accent : const Color(0xFF3A3A3A),
              width: active ? 1.5 : 1,
            ),
            left: const BorderSide(color: Color(0xFF3A3A3A)),
            right: const BorderSide(color: Color(0xFF3A3A3A)),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : const Color(0xFFB0B0B0),
            fontSize: 12,
            fontWeight: active ? FontWeight.w500 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildFeedsTab() {
    final feed = _selectedFeed;
    final articles = feed?.articles ?? const <RssArticle>[];
    final selectedArticle =
        (_selectedArticleIndex != null &&
            _selectedArticleIndex! >= 0 &&
            _selectedArticleIndex! < articles.length)
        ? articles[_selectedArticleIndex!]
        : null;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              const SizedBox(
                width: 96,
                child: Text(
                  'Feed address:',
                  style: TextStyle(color: Color(0xFFE0E0E0), fontSize: 12),
                ),
              ),
              Expanded(
                child: _inputField(
                  controller: _feedAddressController,
                  onSubmitted: (_) => _addFeed(),
                ),
              ),
              const SizedBox(width: 8),
              _btn(
                'Add feed',
                width: 96,
                onPressed: _addFeed,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: Row(
              children: [
                // Left pane: feeds list
                SizedBox(
                  width: 215,
                  child: Column(
                    children: [
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E1E1E),
                            border: Border.all(color: const Color(0xFF3D3D3D)),
                          ),
                          child: ListView.builder(
                            itemCount: _feeds.length,
                            itemBuilder: (context, idx) {
                              final item = _feeds[idx];
                              final selected = item.id == _selectedFeedId;
                              return InkWell(
                                onTap: () => setState(() {
                                  _selectedFeedId = item.id;
                                  _selectedArticleIndex = null;
                                }),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 6,
                                  ),
                                  color: selected
                                      ? const Color(0xFF383838)
                                      : Colors.transparent,
                                  child: Text(
                                    item.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: selected
                                          ? Colors.white
                                          : const Color(0xFFD0D0D0),
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: _btn(
                              _isRefreshing ? '...' : 'Refresh',
                              onPressed: (feed != null && !_isRefreshing)
                                  ? () => _refreshFeed(feed)
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: _btn(
                              'Remove',
                              onPressed: feed != null
                                  ? _removeSelectedFeed
                                  : null,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                // Right pane: articles list
                Expanded(
                  child: Column(
                    children: [
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E1E1E),
                            border: Border.all(color: const Color(0xFF3D3D3D)),
                          ),
                          child: ListView.separated(
                            itemCount: articles.length,
                            separatorBuilder: (_, _) => const Divider(
                              height: 1,
                              color: Color(0xFF2B2B2B),
                            ),
                            itemBuilder: (context, idx) {
                              final art = articles[idx];
                              final selected = _selectedArticleIndex == idx;
                              return InkWell(
                                onTap: () => setState(
                                  () => _selectedArticleIndex = idx,
                                ),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 6,
                                  ),
                                  color: selected
                                      ? const Color(0xFF383838)
                                      : Colors.transparent,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        art.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: selected
                                              ? Colors.white
                                              : const Color(0xFFE0E0E0),
                                          fontSize: 12,
                                        ),
                                      ),
                                      if (art.pubDate.isNotEmpty)
                                        Text(
                                          art.pubDate,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Color(0xFF8E8E8E),
                                            fontSize: 10.5,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _statusText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFFB8B8B8),
                                fontSize: 11.5,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _btn(
                            'Download...',
                            width: 96,
                            onPressed: selectedArticle != null
                                ? () {
                                    widget.onDownloadArticle?.call(
                                      selectedArticle,
                                    );
                                  }
                                : null,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDownloadRulesTab() {
    final selectedRule = _selectedRule;
    final matchingArticles = selectedRule == null
        ? const <RssArticle>[]
        : _allLoadedArticles
              .where((art) => selectedRule.matchesArticle(art))
              .toList(growable: false);

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Left pane: rules list
          SizedBox(
            width: 195,
            child: Column(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1E1E),
                      border: Border.all(color: const Color(0xFF3D3D3D)),
                    ),
                    child: ListView.builder(
                      itemCount: _rules.length,
                      itemBuilder: (context, idx) {
                        final rule = _rules[idx];
                        final selected = rule.id == _selectedRuleId;
                        return InkWell(
                          onTap: () => setState(() => _selectRule(rule)),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                            color: selected
                                ? const Color(0xFF3A3A3A)
                                : Colors.transparent,
                            child: Text(
                              rule.name.trim().isEmpty
                                  ? 'New rule'
                                  : rule.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: selected
                                    ? Colors.white
                                    : const Color(0xFFD0D0D0),
                                fontSize: 12,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _btn('New rule', onPressed: _addNewRule),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _btn(
                        'Delete',
                        onPressed: selectedRule != null
                            ? _deleteSelectedRule
                            : null,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          // Right pane: rule editor or empty message
          Expanded(
            child: selectedRule == null
                ? const Align(
                    alignment: Alignment.topLeft,
                    child: Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text(
                        'A rule adds the new articles whose titles it matches, as they come.',
                        style: TextStyle(
                          color: Color(0xFFC8C8C8),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  )
                : SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _checkRow(
                          value: selectedRule.enabled,
                          label: 'Use this rule',
                          onChanged: (v) {
                            setState(() => selectedRule.enabled = v);
                            widget.storage.saveRules(_rules);
                          },
                        ),
                        const SizedBox(height: 8),
                        _ruleFieldRow(
                          'Name:',
                          _inputField(
                            controller: _ruleNameController,
                            onChanged: (_) => _syncSelectedRuleFromFields(),
                          ),
                        ),
                        const SizedBox(height: 6),
                        _ruleFieldRow(
                          'Must contain:',
                          _inputField(
                            controller: _mustContainController,
                            onChanged: (_) => _syncSelectedRuleFromFields(),
                          ),
                        ),
                        const SizedBox(height: 6),
                        _ruleFieldRow(
                          'Must not contain:',
                          _inputField(
                            controller: _mustNotContainController,
                            onChanged: (_) => _syncSelectedRuleFromFields(),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Padding(
                          padding: const EdgeInsets.only(left: 128),
                          child: _checkRow(
                            value: selectedRule.useRegex,
                            label: 'Regular expressions',
                            onChanged: (v) {
                              setState(() => selectedRule.useRegex = v);
                              widget.storage.saveRules(_rules);
                            },
                          ),
                        ),
                        const SizedBox(height: 6),
                        _ruleFieldRow(
                          'Episodes:',
                          _inputField(
                            controller: _episodesController,
                            onChanged: (_) => _syncSelectedRuleFromFields(),
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.only(left: 128, top: 4),
                          child: Text(
                            'Words: all of them; | between alternatives; * and ?. Episodes:\n1x2;1x5-8;2x1-. Each episode once.',
                            style: TextStyle(
                              color: Color(0xFF9C9C9C),
                              fontSize: 11,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        _ruleFieldRow(
                          'Save to:',
                          Row(
                            children: [
                              Expanded(
                                child: _inputField(
                                  controller: _saveToController,
                                  hint: "(the Torrents category's folder)",
                                  onChanged: (_) =>
                                      _syncSelectedRuleFromFields(),
                                ),
                              ),
                              const SizedBox(width: 6),
                              _btn(
                                '...',
                                width: 28,
                                onPressed: _pickRuleSaveFolder,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        Padding(
                          padding: const EdgeInsets.only(left: 128),
                          child: _checkRow(
                            value: selectedRule.addWithoutStarting,
                            label: 'Add them without starting them',
                            onChanged: (v) {
                              setState(
                                () => selectedRule.addWithoutStarting = v,
                              );
                              widget.storage.saveRules(_rules);
                            },
                          ),
                        ),
                        const SizedBox(height: 8),
                        _ruleFieldRow(
                          'Feeds:',
                          Container(
                            height: 46,
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E1E1E),
                              border: Border.all(
                                color: const Color(0xFF3D3D3D),
                              ),
                            ),
                            child: _feeds.isEmpty
                                ? const SizedBox.shrink()
                                : ListView.builder(
                                    itemCount: _feeds.length,
                                    itemBuilder: (context, idx) {
                                      final feed = _feeds[idx];
                                      final checked = selectedRule.feedIds
                                          .contains(feed.id);
                                      return InkWell(
                                        onTap: () {
                                          setState(() {
                                            if (checked) {
                                              selectedRule.feedIds.remove(
                                                feed.id,
                                              );
                                            } else {
                                              selectedRule.feedIds.add(feed.id);
                                            }
                                          });
                                          widget.storage.saveRules(_rules);
                                        },
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(
                                                checked
                                                    ? Icons.check_box
                                                    : Icons
                                                          .check_box_outline_blank,
                                                size: 14,
                                                color: checked
                                                    ? AppColors.accent
                                                    : const Color(0xFF777777),
                                              ),
                                              const SizedBox(width: 6),
                                              Expanded(
                                                child: Text(
                                                  feed.title,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    color: Color(0xFFD8D8D8),
                                                    fontSize: 11.5,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                          ),
                          alignTop: true,
                        ),
                        const Padding(
                          padding: EdgeInsets.only(left: 128, top: 3),
                          child: Text(
                            'None ticked: every feed.',
                            style: TextStyle(
                              color: Color(0xFF9C9C9C),
                              fontSize: 11,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Matches ${matchingArticles.length} articles now (it adds new ones only):',
                          style: const TextStyle(
                            color: Color(0xFFD8D8D8),
                            fontSize: 11.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          height: 48,
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E1E1E),
                            border: Border.all(color: const Color(0xFF3D3D3D)),
                          ),
                          child: ListView.builder(
                            itemCount: matchingArticles.length,
                            itemBuilder: (context, idx) => Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              child: Text(
                                matchingArticles[idx].title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFFD8D8D8),
                                  fontSize: 11.5,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Row(
        children: [
          if (_selectedTab == 0) ...[
            const Text(
              'Check feeds every',
              style: TextStyle(color: Color(0xFFE0E0E0), fontSize: 12),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 44,
              child: _inputField(
                controller: _intervalController,
                textAlign: TextAlign.right,
                onChanged: (_) => _saveInterval(),
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'minutes',
              style: TextStyle(color: Color(0xFFE0E0E0), fontSize: 12),
            ),
          ],
          const Spacer(),
          _btn(
            'Close',
            width: 82,
            onPressed: () {
              _saveInterval();
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }

  Widget _ruleFieldRow(String label, Widget field, {bool alignTop = false}) {
    return Row(
      crossAxisAlignment: alignTop
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 128,
          child: Padding(
            padding: EdgeInsets.only(top: alignTop ? 4 : 0),
            child: Text(
              label,
              style: const TextStyle(color: Color(0xFFE0E0E0), fontSize: 12),
            ),
          ),
        ),
        Expanded(child: field),
      ],
    );
  }

  Widget _checkRow({
    required bool value,
    required String label,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 18,
          height: 18,
          child: Checkbox(
            value: value,
            activeColor: AppColors.accent,
            checkColor: Colors.black,
            side: const BorderSide(color: Color(0xFF666666)),
            onChanged: (v) => onChanged(v ?? false),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: GestureDetector(
            onTap: () => onChanged(!value),
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFFE0E0E0), fontSize: 12),
            ),
          ),
        ),
      ],
    );
  }

  Widget _inputField({
    required TextEditingController controller,
    String? hint,
    TextAlign textAlign = TextAlign.start,
    ValueChanged<String>? onChanged,
    ValueChanged<String>? onSubmitted,
  }) {
    return SizedBox(
      height: 25,
      child: TextField(
        controller: controller,
        textAlign: textAlign,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        style: const TextStyle(color: Colors.white, fontSize: 12),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Color(0xFF888888), fontSize: 11.5),
          filled: true,
          fillColor: const Color(0xFF1A1A1A),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 7,
            vertical: 5,
          ),
          enabledBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(2)),
            borderSide: BorderSide(color: Color(0xFF454545)),
          ),
          focusedBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(2)),
            borderSide: BorderSide(color: AppColors.accent, width: 1.2),
          ),
        ),
      ),
    );
  }

  Widget _btn(String label, {VoidCallback? onPressed, double? width}) {
    final enabled = onPressed != null;
    return SizedBox(
      width: width,
      height: 26,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          backgroundColor: enabled
              ? const Color(0xFF333333)
              : const Color(0xFF272727),
          foregroundColor: enabled ? Colors.white : const Color(0xFF707070),
          side: BorderSide(
            color: enabled
                ? const Color(0xFF4E4E4E)
                : const Color(0xFF3B3B3B),
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
          textStyle: const TextStyle(fontSize: 12),
        ),
        child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}
