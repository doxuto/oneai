import 'dart:io';

import 'package:codebase_ai/config/assets.dart';
import 'package:codebase_ai/data/services/shared_preferences_service.dart';
import 'package:codebase_ai/domain/bloc/auth/auth_bloc.dart';
import 'package:codebase_ai/domain/bloc/auth/auth_event.dart';
import 'package:codebase_ai/domain/bloc/auth/auth_state.dart';
import 'package:codebase_ai/ui/core/localization/localization_extension.dart';
import 'package:codebase_ai/ui/core/themes/dimens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:codebase_ai/config/constants.dart';
import 'package:codebase_ai/utils/result.dart';

/// Login page that allows users to authenticate using Google or Apple
class LoginPage extends StatefulWidget {
  /// Creates a new login page
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  String? _previousLoginMethod;
  final SharedPreferencesService _preferencesService = SharedPreferencesService();
  String? _loadingButton; // Constants.loginMethodGoogle, Constants.loginMethodApple, or null

  @override
  void initState() {
    super.initState();
    _loadPreviousLoginMethod();
  }

  Future<void> _loadPreviousLoginMethod() async {
    final result = await _preferencesService.getLoginMethod();
    return switch (result) {
      Ok(:final value) when value != null => setState(() {
        _previousLoginMethod = value;
      }),
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BlocConsumer<AuthBloc, AuthState>(
        listener: (context, state) {
          if (state is ErrorAuthState) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(state.message)));
            setState(() {
              _loadingButton = null;
            });
          } else if (state is! LoadingAuthState) {
            setState(() {
              _loadingButton = null;
            });
          }
        },
        builder: (context, state) {
          final isLoading = state is LoadingAuthState;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Spacer(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SvgPicture.asset(Assets.circularComplicationIcon, width: 50, height: 50),
                      gapW12,
                      Text(context.loc.oneAi, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  gapH12,
                  RichText(
                    textAlign: TextAlign.center,
                    text: TextSpan(
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 24, color: Colors.black),
                      children: [
                        TextSpan(text: context.loc.instantNotesFromAudio),
                        TextSpan(text: context.loc.doneWithAi, style: TextStyle(color: const Color(0xFF0767F8))),
                      ],
                    ),
                  ),
                  const Spacer(),
                  // Sign-in Buttons
                  _buildGoogleSignInButton(
                    context: context,
                    isLoading: _loadingButton == Constants.loginMethodGoogle && isLoading,
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      setState(() {
                        _loadingButton = Constants.loginMethodGoogle;
                      });
                      context.read<AuthBloc>().add(const AuthEvent.signInWithGoogle());
                    },
                  ),
                  if (Platform.isIOS) ...[
                    gapH12,
                    _buildAppleSignInButton(
                      context: context,
                      isLoading: _loadingButton == Constants.loginMethodApple && isLoading,
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        setState(() {
                          _loadingButton = Constants.loginMethodApple;
                        });
                        context.read<AuthBloc>().add(const AuthEvent.signInWithApple());
                      },
                    ),
                    gapH12,
                    if (_previousLoginMethod != null)
                      Text(
                        '(${_previousLoginMethod == Constants.loginMethodGoogle
                            ? 'Previously signed in with Google'
                            : _previousLoginMethod == Constants.loginMethodApple
                            ? 'Previously signed in with Apple'
                            : ''})',
                        style: const TextStyle(fontSize: 12, color: Colors.black, fontWeight: FontWeight.w400),
                      ),
                    gapH24,
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildGoogleSignInButton({
    required BuildContext context,
    required bool isLoading,
    required VoidCallback onPressed,
  }) {
    return OutlinedButton(
      onPressed: isLoading ? null : onPressed,
      style: OutlinedButton.styleFrom(
        backgroundColor: Colors.white,
        side: const BorderSide(color: Colors.black),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        padding: const EdgeInsets.symmetric(vertical: 14.0),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SvgPicture.asset(Assets.googleIcon, width: 17, height: 17),
          gapW4,
          Text(
            context.loc.signInWithGoogle,
            style: const TextStyle(fontSize: 16, color: Colors.black, fontWeight: FontWeight.w600),
          ),
          if (isLoading) ...[
            gapW8,
            const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          ],
        ],
      ),
    );
  }

  Widget _buildAppleSignInButton({
    required BuildContext context,
    required bool isLoading,
    required VoidCallback onPressed,
  }) {
    return ElevatedButton(
      onPressed: isLoading ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        padding: const EdgeInsets.symmetric(vertical: 14.0),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SvgPicture.asset(Assets.appleIcon, width: 17, height: 17),
          gapW4,
          Text(context.loc.signInWithApple, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          if (isLoading) ...[
            gapW8,
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
          ],
        ],
      ),
    );
  }
}
