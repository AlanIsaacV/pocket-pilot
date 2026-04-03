// frontend/lib/src/features/transactions/ui/widgets/filter_sheet.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/core/theme/app_theme.dart';
import 'package:pocket_pilot/src/features/accounts/data/account_local_store.dart';
import 'package:pocket_pilot/src/features/accounts/domain/account.dart';
import 'package:pocket_pilot/src/features/categories/data/category_local_store.dart';
import 'package:pocket_pilot/src/features/categories/domain/category.dart';
import 'package:pocket_pilot/src/features/transactions/data/transaction_local_store.dart';
import 'package:pocket_pilot/src/features/transactions/ui/widgets/advanced_filters.dart';
import 'package:pocket_pilot/src/features/transactions/ui/widgets/temporal_page_view.dart';

class FilterSheet extends StatefulWidget {
  const FilterSheet({super.key});

  @override
  State<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<FilterSheet> {
  List<AccountModel> _accounts = [];
  List<CategoryModel> _topCategories = [];
  List<String> _currencies = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadFilterData();
  }

  Future<void> _loadFilterData() async {
    final db = context.read<DatabaseHelper>();
    final accountStore = AccountLocalStore(db: db);
    final categoryStore = CategoryLocalStore(db: db);
    final txnStore = TransactionLocalStore(db: db);

    final accounts = (await accountStore.getAccounts())
        .where((a) => a.type != 'contact')
        .toList();
    final topIds = await txnStore.queryTopCategoryIds();
    final allCategories = await categoryStore.getCategories();

    // Resolve top categories in order, keeping only existing ones
    final topCategories = <CategoryModel>[];
    for (final id in topIds) {
      final cat = allCategories.where((c) => c.id == id).firstOrNull;
      if (cat != null) topCategories.add(cat);
    }

    // Distinct currencies from accounts
    final currencies = accounts.map((a) => a.currencyCode).toSet().toList()
      ..sort();

    if (mounted) {
      setState(() {
        _accounts = accounts;
        _topCategories = topCategories;
        _currencies = currencies;
        _loaded = true;
      });
    }
  }

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
              // Drag handle
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
              // Temporal filters (always visible)
              const TemporalPageView(),
              // Advanced filters (visible when expanded)
              if (_loaded)
                AdvancedFilters(
                  accounts: _accounts,
                  topCategories: _topCategories,
                  currencies: _currencies,
                ),
            ],
          ),
        );
      },
    );
  }
}
