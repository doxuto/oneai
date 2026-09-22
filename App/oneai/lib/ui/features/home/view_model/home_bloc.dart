import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:codebase_ai/domain/models/minute_model.dart';
import 'package:codebase_ai/domain/models/tag_model.dart';
import 'package:codebase_ai/domain/use_cases/minute_usecase.dart';
import 'package:codebase_ai/domain/use_cases/tag_usecase.dart';
import 'package:codebase_ai/utils/loading_manager.dart';
import 'package:codebase_ai/utils/result.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:logging/logging.dart';

part 'home_bloc.freezed.dart';

// Loading operations enum
enum HomeOperation { loadMinutes, loadTags, createTag, updateMinuteName, updateMinuteIcon, deleteMinuteItem, deleteTag }

// Events
@freezed
sealed class HomeEvent with _$HomeEvent {
  const factory HomeEvent.onInit() = OnInitEvent;
  const factory HomeEvent.loadMinuteItems({required bool isRefresh, required bool isLoadMore}) = LoadMinuteItemsEvent;
  const factory HomeEvent.createTag({required String name}) = CreateTagEvent;
  const factory HomeEvent.updateMinuteName({required String id, required String newName}) = UpdateMinuteNameEvent;
  const factory HomeEvent.updateMinuteIcon({required String id, required String iconAsset}) = UpdateMinuteIconEvent;
  const factory HomeEvent.deleteMinuteItem({required String id}) = DeleteMinuteItemEvent;
  const factory HomeEvent.loadTags() = LoadTagsEvent;
  const factory HomeEvent.selectTags({required List<String> tagIds}) = SelectTagsEvent;
  const factory HomeEvent.deleteTag({required String tagId}) = DeleteTagEvent;
}

// State
@freezed
sealed class HomeState with _$HomeState {
  const factory HomeState({
    @Default(false) bool isLoading,
    String? errorMessage,
    @Default([]) List<Minute> minutes,
    @Default([]) List<Tag> tags,
    @Default([]) List<String> selectedTagIds,
    @Default(false) bool isLoadingMore,
  }) = _HomeState;
}

// Bloc
class HomeBloc extends Bloc<HomeEvent, HomeState> {
  final TagUseCase _tagUseCase;
  final MinuteUseCase _minuteUseCase;
  final _log = Logger('HomeBloc');
  final LoadingManager<HomeOperation> _loadingManager = LoadingManager<HomeOperation>();

  HomeBloc({required TagUseCase tagUseCase, required MinuteUseCase minuteUseCase})
    : _tagUseCase = tagUseCase,
      _minuteUseCase = minuteUseCase,
      super(const HomeState()) {
    on<OnInitEvent>(_onInit);
    on<LoadMinuteItemsEvent>(_onLoadMinuteItems);
    on<UpdateMinuteNameEvent>(_onUpdateMinuteName);
    on<UpdateMinuteIconEvent>(_onUpdateMinuteIcon);
    on<DeleteMinuteItemEvent>(_onDeleteMinuteItem);
    on<LoadTagsEvent>(_onLoadTags);
    on<CreateTagEvent>(_onCreateTag);
    on<SelectTagsEvent>(_onSelectTags);
    on<DeleteTagEvent>(_onDeleteTag);
  }

  Future<void> _onInit(OnInitEvent event, Emitter<HomeState> emit) async {
    add(const HomeEvent.loadMinuteItems(isRefresh: true, isLoadMore: false));
    add(const HomeEvent.loadTags());
    await emit.forEach(
      _minuteUseCase.minutesStream,
      onData: (minutes) => state.copyWith(minutes: minutes, isLoading: _loadingManager.isLoading),
      onError:
          (error, stackTrace) => state.copyWith(isLoading: _loadingManager.isLoading, errorMessage: error.toString()),
    );
  }

  Future<void> _onLoadMinuteItems(LoadMinuteItemsEvent event, Emitter<HomeState> emit) async {
    Function()? completeOperation;
    if (event.isLoadMore) {
      emit(state.copyWith(isLoadingMore: true));
    } else {
      completeOperation = _loadingManager.startOperation(HomeOperation.loadMinutes);
      emit(state.copyWith(isLoading: _loadingManager.isLoading));
    }

    final result = await _minuteUseCase.loadMinutes(isRefresh: event.isRefresh, isLoadMore: event.isLoadMore);

    completeOperation?.call();
    switch (result) {
      case Ok():
        emit(state.copyWith(isLoading: _loadingManager.isLoading, isLoadingMore: false));
      case Error(error: final error):
        emit(
          state.copyWith(isLoading: _loadingManager.isLoading, isLoadingMore: false, errorMessage: error.toString()),
        );
    }
  }

  Future<void> _onCreateTag(CreateTagEvent event, Emitter<HomeState> emit) async {
    final completeOperation = _loadingManager.startOperation(HomeOperation.createTag);
    emit(state.copyWith(isLoading: _loadingManager.isLoading));
    final result = await _tagUseCase.createTag(event.name);
    completeOperation();
    switch (result) {
      case Ok():
        _log.info('Tag created successfully: ${event.name}');
        emit(state.copyWith(isLoading: _loadingManager.isLoading));
      case Error(error: final error):
        emit(state.copyWith(isLoading: _loadingManager.isLoading, errorMessage: error.toString()));
    }
  }

  Future<void> _onUpdateMinuteName(UpdateMinuteNameEvent event, Emitter<HomeState> emit) async {
    final completeOperation = _loadingManager.startOperation(HomeOperation.updateMinuteName);
    emit(state.copyWith(isLoading: _loadingManager.isLoading));
    final result = await _minuteUseCase.updateMinuteById(event.id, title: event.newName);
    completeOperation();
    if (result is Ok) {
      _log.info('Minute name updated successfully');
      emit(state.copyWith(isLoading: _loadingManager.isLoading));
    } else if (result is Error) {
      emit(state.copyWith(isLoading: _loadingManager.isLoading, errorMessage: result.error.toString()));
    }
  }

  Future<void> _onUpdateMinuteIcon(UpdateMinuteIconEvent event, Emitter<HomeState> emit) async {
    final completeOperation = _loadingManager.startOperation(HomeOperation.updateMinuteIcon);
    emit(state.copyWith(isLoading: _loadingManager.isLoading));
    final result = await _minuteUseCase.updateMinuteById(event.id, iconAsset: event.iconAsset);
    completeOperation();
    if (result is Ok) {
      _log.info('Minute icon updated successfully');
      emit(state.copyWith(isLoading: _loadingManager.isLoading));
    } else if (result is Error) {
      emit(state.copyWith(isLoading: _loadingManager.isLoading, errorMessage: result.error.toString()));
    }
  }

  Future<void> _onDeleteMinuteItem(DeleteMinuteItemEvent event, Emitter<HomeState> emit) async {
    final completeOperation = _loadingManager.startOperation(HomeOperation.deleteMinuteItem);
    emit(state.copyWith(isLoading: _loadingManager.isLoading));
    final result = await _minuteUseCase.deleteMinuteById(event.id);
    completeOperation();
    if (result is Ok) {
      _log.info('Minute item deleted successfully');
      emit(state.copyWith(isLoading: _loadingManager.isLoading));
    } else if (result is Error) {
      emit(state.copyWith(isLoading: _loadingManager.isLoading, errorMessage: result.error.toString()));
    }
  }

  Future<void> _onLoadTags(LoadTagsEvent event, Emitter<HomeState> emit) async {
    final completeOperation = _loadingManager.startOperation(HomeOperation.loadTags);
    emit(state.copyWith(isLoading: _loadingManager.isLoading));
    final result = await _tagUseCase.getAllTags();
    completeOperation();
    switch (result) {
      case Ok(value: final tags):
        emit(state.copyWith(tags: tags, isLoading: _loadingManager.isLoading));
      case Error(error: final error):
        emit(state.copyWith(isLoading: _loadingManager.isLoading, errorMessage: error.toString()));
    }
    await emit.forEach(
      _tagUseCase.tagsStream,
      onData: (tags) => state.copyWith(tags: tags, isLoading: _loadingManager.isLoading),
      onError:
          (error, stackTrace) => state.copyWith(isLoading: _loadingManager.isLoading, errorMessage: error.toString()),
    );
  }

  Future<void> _onDeleteTag(DeleteTagEvent event, Emitter<HomeState> emit) async {
    final completeOperation = _loadingManager.startOperation(HomeOperation.deleteTag);
    emit(state.copyWith(isLoading: _loadingManager.isLoading));
    final result = await _tagUseCase.deleteTag(event.tagId);
    completeOperation();
    if (result is Ok) {
      _log.info('Tag deleted successfully');
      emit(state.copyWith(isLoading: _loadingManager.isLoading));
    } else if (result is Error) {
      emit(state.copyWith(isLoading: _loadingManager.isLoading, errorMessage: result.error.toString()));
    }
  }

  Future<void> _onSelectTags(SelectTagsEvent event, Emitter<HomeState> emit) async {
    emit(state.copyWith(selectedTagIds: event.tagIds));
  }
}
