import 'dart:async';

import 'package:codebase_ai/data/repositories/oneai_repository.dart';
import 'package:codebase_ai/domain/models/tag_model.dart';
import 'package:codebase_ai/utils/result.dart';

class TagUseCase {
  final OneAiRepository _repository;
  final StreamController<List<Tag>> _tagsController = StreamController.broadcast();
  List<Tag> _tagsCache = [];

  TagUseCase(this._repository);

  Stream<List<Tag>> get tagsStream async* {
    if (_tagsCache.isNotEmpty) {
      yield List<Tag>.from(_tagsCache);
    }
    yield* _tagsController.stream;
  }

  Future<Result<Tag>> createTag(String name) async {
    final result = await _repository.createTag(name);
    if (result is Ok) {
      await getAllTags();
    }
    return result;
  }

  Future<Result<Tag>> updateTag(String tagId, String name) async {
    final result = await _repository.updateTag(tagId, name);
    if (result is Ok) {
      await getAllTags();
    }
    return result;
  }

  Future<Result<void>> deleteTag(String tagId) async {
    final result = await _repository.deleteTag(tagId);
    if (result is Ok) {
      await getAllTags();
    }
    return result;
  }

  Future<Result<List<Tag>>> getAllTags() async {
    final result = await _repository.getAllTags();
    if (result is Ok<List<Tag>>) {
      _tagsCache = result.value;
      _tagsController.add(_tagsCache);
    }
    return result;
  }

  void dispose() {
    _tagsController.close();
  }
}
