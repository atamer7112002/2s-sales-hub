import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

class PageResult<T> {
  const PageResult(this.items, this.hasMore, {this.offline = false});
  final List<T> items;
  final bool hasMore, offline;
}

class PageState<T> {
  const PageState({
    this.items = const [],
    this.loading = false,
    this.hasMore = true,
    this.offline = false,
    this.error,
  });
  final List<T> items;
  final bool loading, hasMore, offline;
  final String? error;
}

class PagedCubit<T> extends Cubit<PageState<T>> {
  PagedCubit(this.fetch) : super(PageState<T>());
  final Future<PageResult<T>> Function(String query, int offset) fetch;
  String query = '';
  int _generation = 0;
  Timer? _debounce;
  void search(String value) {
    query = value;
    _generation++;
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 350),
      () => load(reset: true),
    );
  }

  Future<void> load({bool reset = false}) async {
    if (state.loading && !reset) {
      return;
    }
    final generation = ++_generation;
    final previous = reset ? <T>[] : state.items;
    emit(PageState(items: previous, loading: true, offline: state.offline));
    try {
      final result = await fetch(query, previous.length);
      if (isClosed || generation != _generation) {
        return;
      }
      emit(
        PageState(
          items: List.unmodifiable([...previous, ...result.items]),
          hasMore: result.hasMore,
          offline: result.offline,
        ),
      );
    } catch (e) {
      if (!isClosed && generation == _generation) {
        emit(
          PageState(
            items: previous,
            error: e.toString(),
            offline: state.offline,
          ),
        );
      }
    }
  }

  void replaceItems(List<T> items) {
    if (isClosed) return;
    emit(
      PageState(
        items: List.unmodifiable(items),
        loading: state.loading,
        hasMore: state.hasMore,
        offline: state.offline,
        error: state.error,
      ),
    );
  }

  @override
  Future<void> close() {
    _debounce?.cancel();
    return super.close();
  }
}
