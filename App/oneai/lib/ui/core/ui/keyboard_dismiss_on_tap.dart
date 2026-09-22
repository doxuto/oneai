import 'package:flutter/material.dart';

class KeyboardDismissOnTap extends StatelessWidget {
  final Widget child;

  const KeyboardDismissOnTap({super.key, required this.child});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () {
      // Hide the keyboard
      final currentFocus = FocusScope.of(context);
      if (!currentFocus.hasPrimaryFocus && currentFocus.focusedChild != null) {
        currentFocus.unfocus();
      }
    },
    behavior: HitTestBehavior.translucent,
    child: child,
  );
}
