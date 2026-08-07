import 'package:flutter/material.dart';

/// Floating toast-style SnackBar for short feedback.
void showAppToast(
  BuildContext context,
  String message, {
  bool error = false,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger.clearSnackBars();
  final scheme = Theme.of(context).colorScheme;
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        message,
        style: TextStyle(
          color: error ? scheme.onError : Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(18, 0, 18, 28),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      duration: const Duration(seconds: 3),
      backgroundColor: error ? scheme.error : const Color(0xFF1F2A24),
    ),
  );
}
