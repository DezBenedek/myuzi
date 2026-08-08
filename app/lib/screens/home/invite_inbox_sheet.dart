import 'package:flutter/material.dart';

import '../../widgets/widgets.dart';

/// Prompt for a pending family invite. Returns `true` if the user wants to open it.
Future<bool?> showInviteInboxSheet(
  BuildContext context, {
  required String familyName,
  required String from,
  required bool needsLeave,
  String? currentFamilyName,
}) {
  return showModalBottomSheet<bool>(
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
              Text('Családi meghívó', style: t.textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                '$from meghívott a(z) $familyName családba.',
                style: t.textTheme.bodyLarge,
              ),
              if (needsLeave) ...[
                const SizedBox(height: 8),
                Text(
                  'Ehhez ki kell lépned a(z) ${currentFamilyName ?? "jelenlegi"} családból.',
                  style: TextStyle(color: t.colorScheme.error),
                ),
              ],
              const SizedBox(height: 16),
              BigButton(
                label: 'Megnézem',
                icon: Icons.mail_outline,
                onPressed: () => Navigator.pop(ctx, true),
              ),
              const SizedBox(height: 8),
              BigButton(
                label: 'Később',
                outlined: true,
                onPressed: () => Navigator.pop(ctx, false),
              ),
            ],
          ),
        ),
      );
    },
  );
}
