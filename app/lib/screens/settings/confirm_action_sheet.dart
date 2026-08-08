import 'package:flutter/material.dart';

import '../../widgets/widgets.dart';

Future<bool> showConfirmActionSheet(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
  required IconData confirmIcon,
}) async {
  final ok = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      final t = Theme.of(ctx);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: t.textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(body, style: t.textTheme.bodyLarge),
              const SizedBox(height: 16),
              BigButton(
                label: confirmLabel,
                icon: confirmIcon,
                danger: true,
                onPressed: () => Navigator.pop(ctx, true),
              ),
              const SizedBox(height: 8),
              BigButton(
                label: 'Mégse',
                icon: Icons.close,
                outlined: true,
                onPressed: () => Navigator.pop(ctx, false),
              ),
            ],
          ),
        ),
      );
    },
  );
  return ok == true;
}
