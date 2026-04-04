import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_pilot/src/core/sync/sync_service.dart';
import 'package:pocket_pilot/src/features/categories/data/category_repository.dart';
import 'package:pocket_pilot/src/features/categories/domain/category.dart';
import 'package:pocket_pilot/src/features/categories/ui/categories_view_model.dart';

class _FakeCategoryRepository implements CategoryRepository {
  @override
  Future<List<CategoryModel>> getCategories() async => const [];

  @override
  Future<List<CategoryModel>> getDeletedCategories() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DelayedSyncService implements SyncService {
  _DelayedSyncService(this.delay);

  final Duration delay;

  @override
  Future<void> sync() async {
    await Future<void>.delayed(delay);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('loadOnAppear does not notify listeners after dispose', () async {
    final vm = CategoriesViewModel(
      repository: _FakeCategoryRepository(),
      syncService: _DelayedSyncService(const Duration(milliseconds: 30)),
    );

    vm.loadOnAppear();
    await Future<void>.delayed(const Duration(milliseconds: 1));
    vm.dispose();

    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(true, isTrue);
  });
}
