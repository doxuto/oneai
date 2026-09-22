import 'package:flutter/material.dart';

double getDialogWidth(BuildContext context) {
  final double screenWidth = MediaQuery.of(context).size.width;
  if (screenWidth < 600) {
    return screenWidth * 0.9; // For smaller screens, use 90%
  } else if (screenWidth < 1200) {
    return screenWidth * 0.8; // For medium screens, use 80%
  } else {
    return screenWidth * 0.6; // For larger screens, use 60%
  }
}
