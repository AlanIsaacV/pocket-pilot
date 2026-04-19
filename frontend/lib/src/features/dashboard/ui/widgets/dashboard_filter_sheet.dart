import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/core/theme/app_theme.dart';
import 'package:pocket_pilot/src/features/accounts/data/account_local_store.dart';
import 'package:pocket_pilot/src/features/accounts/domain/account.dart';
import 'package:pocket_pilot/src/features/dashboard/ui/dashboard_filter_view_model.dart';
import 'package:pocket_pilot/src/features/dashboard/ui/widgets/temporal_page_view.dart';

class DashboardFilterSheet extends StatelessWidget {
  const DashboardFilterSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.12,
      minChildSize: 0.12,
      maxChildSize: 0.55,
      snap: true,
      snapSizes: const [0.12, 0.55],
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: cs.surfaceContainer,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(16),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 8,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: AppTheme.radiusFull,
                  ),
                ),
              ),
              const TemporalPageView(),
              const _ScopeFilters(),
            ],
          ),
        );
      },
    );
  }
}

class _ScopeFilters extends StatefulWidget {
  const _ScopeFilters();

  @override
  State<_ScopeFilters> createState() => _ScopeFiltersState();
}

class _ScopeFiltersState extends State<_ScopeFilters> {
  List<AccountModel> _accounts = const [];
  List<String> _currencies = const [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadAccounts();
  }

  Future<void> _loadAccounts() async {
    try {
      final db = context.read<DatabaseHelper>();
      final store = AccountLocalStore(db: db);
      final accounts = (await store.getAccounts())
          .where((a) => a.type != 'contact')
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      final currencies = accounts.map((a) => a.currencyCode).toSet().toList()
        ..sort();
      if (!mounted) return;
      setState(() {
        _accounts = accounts;
        _currencies = currencies;
        _loaded = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loaded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final filterVM = context.watch<DashboardFilterViewModel>();

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Filtros',
                  style: GoogleFonts.ibmPlexSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
              ),
              if (filterVM.hasFilters)
                TextButton(
                  onPressed: filterVM.clearAll,
                  child: const Text('Limpiar'),
                ),
            ],
          ),
          if (_loaded && _currencies.length > 1) ...[
            const SizedBox(height: 12),
            Text(
              'Moneda',
              style: GoogleFonts.ibmPlexSans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: _currencies.map((cc) {
                final selected = filterVM.currencyCode == cc;
                return ChoiceChip(
                  label: Text(cc),
                  selected: selected,
                  onSelected: (_) {
                    filterVM.setCurrencyCode(selected ? null : cc);
                  },
                );
              }).toList(),
            ),
          ],
          if (_loaded && _accounts.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'Cuentas',
              style: GoogleFonts.ibmPlexSans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: _accounts.map((a) {
                final selected = filterVM.accountIds.contains(a.id);
                return FilterChip(
                  label: Text(a.name),
                  selected: selected,
                  onSelected: (_) => filterVM.toggleAccountId(a.id),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }
}
