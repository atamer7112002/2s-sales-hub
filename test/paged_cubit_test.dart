import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:task_2s_egypt/core/network/paged_cubit.dart';

void main() {
  test('late responses cannot replace a newer search', () async {
    final old = Completer<PageResult<int>>();
    final cubit = PagedCubit<int>(
      (query, offset) => query == 'new'
          ? Future.value(const PageResult([2], false))
          : old.future,
    );
    final first = cubit.load();
    cubit.query = 'new';
    await cubit.load(reset: true);
    old.complete(const PageResult([1], false));
    await first;
    expect(cubit.state.items, [2]);
    await cubit.close();
  });
  test('page failure retains previous rows and can be retried', () async {
    var fail = false;
    final cubit = PagedCubit<int>((query, offset) async {
      if (fail) {
        throw Exception('offline');
      }
      return PageResult([offset + 1], true);
    });
    await cubit.load();
    fail = true;
    await cubit.load();
    expect(cubit.state.items, [1]);
    expect(cubit.state.error, isNotNull);
    fail = false;
    await cubit.load();
    expect(cubit.state.items, [1, 2]);
    await cubit.close();
  });
}
