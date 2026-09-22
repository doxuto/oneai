import 'dart:async';
import 'package:bloc/bloc.dart';
import 'package:codebase_ai/domain/models/minute_model.dart';
import 'package:codebase_ai/domain/models/tag_model.dart';
import 'package:codebase_ai/domain/use_cases/minute_usecase.dart';
import 'package:codebase_ai/domain/use_cases/tag_usecase.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:codebase_ai/utils/result.dart';

part 'minute_item_bloc.freezed.dart';

@freezed
sealed class MinuteItemEvent with _$MinuteItemEvent {
  const factory MinuteItemEvent.loadTags() = _LoadTags;
  const factory MinuteItemEvent.toggleTag(String tagId) = _ToggleTag;
  const factory MinuteItemEvent.saveTags() = _SaveTags;
}

@freezed
sealed class MinuteItemState with _$MinuteItemState {
  const factory MinuteItemState({
    @Default(false) bool isLoading,
    String? errorMessage,
    @Default([]) List<Tag> tags,
    @Default([]) List<String> selectedTagIds,
  }) = _MinuteItemState;
}

class MinuteItemBloc extends Bloc<MinuteItemEvent, MinuteItemState> {
  final TagUseCase tagUseCase;
  final MinuteUseCase minuteUseCase;
  final Minute minute;
  StreamSubscription<List<Tag>>? _tagSub;

  MinuteItemBloc({required this.tagUseCase, required this.minuteUseCase, required this.minute})
    : super(MinuteItemState(selectedTagIds: List<String>.from(minute.tags ?? []))) {
    on<_LoadTags>(_onLoadTags);
    on<_ToggleTag>(_onToggleTag);
    on<_SaveTags>(_onSaveTags);
  }

  Future<void> _onLoadTags(_LoadTags event, Emitter<MinuteItemState> emit) async {
    emit(state.copyWith(isLoading: true, errorMessage: null));
    final result = await tagUseCase.getAllTags();
    switch (result) {
      case Ok(value: final tags):
        emit(state.copyWith(isLoading: false, tags: tags));
      case Error(error: final error):
        emit(state.copyWith(isLoading: false, errorMessage: error.toString()));
    }
    await emit.forEach(
      tagUseCase.tagsStream,
      onData: (tags) => state.copyWith(tags: tags, isLoading: false),
      onError: (error, stackTrace) => state.copyWith(isLoading: false, errorMessage: error.toString()),
    );
  }

  void _onToggleTag(_ToggleTag event, Emitter<MinuteItemState> emit) {
    final selected = List<String>.from(state.selectedTagIds);
    if (selected.contains(event.tagId)) {
      selected.remove(event.tagId);
    } else {
      selected.add(event.tagId);
    }
    emit(state.copyWith(selectedTagIds: selected));
  }

  Future<void> _onSaveTags(_SaveTags event, Emitter<MinuteItemState> emit) async {
    final original = List<String>.from(minute.tags ?? []);
    final selected = state.selectedTagIds;
    if (!_listEquals(original, selected)) {
      emit(state.copyWith(isLoading: true));
      final result = await minuteUseCase.updateMinuteById(minute.id, tags: selected);
      switch (result) {
        case Ok():
          emit(state.copyWith(isLoading: false));
        case Error(error: final error):
          emit(state.copyWith(isLoading: false, errorMessage: error.toString()));
      }
    }
  }

  bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    final aSorted = List<String>.from(a)..sort();
    final bSorted = List<String>.from(b)..sort();
    for (int i = 0; i < aSorted.length; i++) {
      if (aSorted[i] != bSorted[i]) return false;
    }
    return true;
  }

  @override
  Future<void> close() {
    _tagSub?.cancel();
    return super.close();
  }
}
