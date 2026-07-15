// features/statistics/ui/tag_list_screen.dart
//
// Listado de todos los tags con actividad neta de gasto en la ventana
// actual del DashboardFilterViewModel. Tap → TagHistoryScreen.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/core/theme/app_colors.dart';
import 'package:pocket_pilot/src/core/theme/app_theme.dart';
import 'package:pocket_pilot/src/features/dashboard/ui/dashboard_filter_view_model.dart';
import 'package:pocket_pilot/src/features/dashboard/ui/widgets/dashboard_filter_sheet.dart';
import 'package:pocket_pilot/src/features/statistics/data/statistics_repository.dart';
import 'package:pocket_pilot/src/features/statistics/domain/tag_summary_dto.dart';

class TagListScreen extends StatefulWidget {
  const TagListScreen({super.key});

  @override
  State<TagListScreen> createState() => _TagListScreenState();
}

class _TagListScreenState extends State<TagListScreen> {
  List<TagSummaryDTO>? _tags;
  bool _loading = true;
  String? _error;

  DashboardFilterViewModel? _filterVM;
  String? _lastFrom;
  String? _lastTo;
  String? _lastCurrency;
  Set<String> _lastAccountIds = const {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final vm = context.read<DashboardFilterViewModel>();
    if (!identical(vm, _filterVM)) {
      _filterVM?.removeListener(_onFilterChanged);
      _filterVM = vm;
      _filterVM!.addListener(_onFilterChanged);
    }
  }

  @override
  void dispose() {
    _filterVM?.removeListener(_onFilterChanged);
    super.dispose();
  }

  void _onFilterChanged() {
    final vm = _filterVM!;
    final (from, to) = vm.resolvedDateRange;
    final currency = vm.currencyCode;
    final accountIds = vm.accountIds;
    if (from == _lastFrom &&
        to == _lastTo &&
        currency == _lastCurrency &&
        _setEquals(accountIds, _lastAccountIds)) {
      return;
    }
    _load();
  }

  static bool _setEquals(Set<String> a, Set<String> b) {
    if (a.length != b.length) return false;
    for (final item in a) {
      if (!b.contains(item)) return false;
    }
    return true;
  }

  Future<void> _load() async {
    final repo = context.read<StatisticsRepository>();
    final vm = context.read<DashboardFilterViewModel>();
    final (from, to) = vm.resolvedDateRange;
    final accountIds = vm.accountIds.isNotEmpty ? vm.accountIds : null;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await repo.listTagsWithTotals(
        from: from,
        to: to,
        accountIds: accountIds,
        currencyCode: vm.currencyCode,
      );
      if (!mounted) return;
      setState(() {
        _tags = data;
        _loading = false;
        _lastFrom = from;
        _lastTo = to;
        _lastCurrency = vm.currencyCode;
        _lastAccountIds = Set.of(vm.accountIds);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tags')),
      body: Stack(
        children: [
          _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? _ErrorView(message: _error!, onRetry: _load)
                  : _List(tags: _tags ?? const []),
          const DashboardFilterSheet(),
        ],
      ),
    );
  }
}

class _List extends StatelessWidget {
  final List<TagSummaryDTO> tags;

  const _List({required this.tags});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (tags.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Sin etiquetas con gasto en el periodo',
            style: GoogleFonts.ibmPlexSans(
              fontSize: 13,
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 160),
      itemCount: tags.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) => _TagTile(tag: tags[i]),
    );
  }
}

class _TagTile extends StatelessWidget {
  final TagSummaryDTO tag;

  const _TagTile({required this.tag});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final palette = AppColors.categoryPresets;
    final color = palette[tag.tagName.hashCode.abs() % palette.length];

    return InkWell(
      borderRadius: AppTheme.radiusMedium,
      onTap: () => context.push(
        '/dashboard/statistics/tags/${Uri.encodeComponent(tag.tagName)}'
        '?currency=${tag.currencyCode}',
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: cs.surfaceContainer,
          borderRadius: AppTheme.radiusMedium,
          border: Border.all(color: cs.surfaceContainerHigh, width: 1),
        ),
        child: Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: color,
                borderRadius: const BorderRadius.all(Radius.circular(3)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                tag.tagName,
                style: GoogleFonts.ibmPlexSans(
                  fontSize: 14,
                  color: cs.onSurface,
                ),
              ),
            ),
            Text(
              _fmt(tag.totalCents, tag.currencyCode),
              style: GoogleFonts.ibmPlexSans(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 18, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  static String _fmt(int cents, String currency) {
    final sign = cents < 0 ? '-' : '';
    final abs = cents.abs();
    final whole = abs ~/ 100;
    final frac = abs % 100;
    final buf = StringBuffer();
    final s = whole.toString();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    final fracStr = frac == 0 ? '' : '.${frac.toString().padLeft(2, '0')}';
    return '$sign$currency \$${buf.toString()}$fracStr';
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Reintentar')),
          ],
        ),
      ),
    );
  }
}
