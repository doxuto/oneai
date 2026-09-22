import 'dart:async';

import 'package:codebase_ai/config/constants.dart';
import 'package:codebase_ai/data/repositories/oneai_repository.dart';
import 'package:codebase_ai/domain/models/oneai_user_model.dart';
import 'package:codebase_ai/utils/result.dart';
import 'package:logging/logging.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

class CreditUseCase {
  final OneAiRepository _repository;
  final Logger _log = Logger('CreditUseCase');

  CreditUseCase(this._repository);

  int? _creditCache;
  final StreamController<int> _creditController = StreamController<int>.broadcast();

  int get credit => _creditCache ?? 0;

  Stream<int> get creditStream async* {
    if (_creditCache != null) {
      yield _creditCache!;
    }
    yield* _creditController.stream;
  }

  Future<int> getUserCredit() async {
    _log.info('Fetching user credit...');
    final info = await Purchases.getCustomerInfo();
    final isPremium = info.entitlements.active.containsKey(Constants.entitlementId);
    _log.fine('Is premium: $isPremium');
    if (isPremium) {
      _creditCache = 888;
      _log.info('User is premium. Setting credit cache to 888.');
    } else {
      final result = await _repository.getUserInfo();
      _log.fine('Result of getUserInfo: $result');
      if (result is Ok<OneAiUser>) {
        _creditCache = result.value.credit;
        _log.info('User credit from repository: $_creditCache');
      } else {
        _log.warning('Failed to fetch user info or user is not Ok. Result: $result');
      }
    }
    _log.info('Returning user credit: ${_creditCache ?? 0}');
    final result = _creditCache ?? 0;
    _creditController.add(result);
    return result;
  }

  void dispose() {
    _creditController.close();
  }
}
