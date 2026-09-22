import 'package:bloc/bloc.dart';
import 'package:codebase_ai/data/repositories/auth_repository.dart';
import 'settings_event.dart';
import 'settings_state.dart';

class SettingsBloc extends Bloc<SettingsEvent, SettingsState> {
  final AuthRepository authRepository;

  SettingsBloc({required this.authRepository}) : super(const SettingsState.initial()) {
    on<SettingsEvent>((event, emit) async {
      if (event is DeleteAccountEvent) {
        emit(const SettingsState.loading());
        try {
          await authRepository.deleteAccount();
          emit(const SettingsState.deleteAccountSuccess());
        } catch (e) {
          emit(SettingsState.error(e.toString()));
        }
      }
    });
  }
}
