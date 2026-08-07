import 'package:flutter/material.dart';

class BigButton extends StatelessWidget {
  const BigButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.outlined = false,
    this.danger = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool outlined;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final child = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, size: Theme.of(context).iconTheme.size),
          const SizedBox(width: 10),
        ],
        Flexible(child: Text(label, textAlign: TextAlign.center)),
      ],
    );

    if (outlined) {
      return OutlinedButton(
        onPressed: onPressed,
        style: danger
            ? OutlinedButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error)
            : null,
        child: child,
      );
    }

    return FilledButton(
      onPressed: onPressed,
      style: danger
          ? FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error)
          : null,
      child: child,
    );
  }
}

class SoftCard extends StatelessWidget {
  const SoftCard({super.key, required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final vision = MediaQuery.textScalerOf(context).scale(1) > 1.1;
    return Material(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: vision ? Colors.black : const Color(0xFFD7E4DC),
          width: vision ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: child,
        ),
      ),
    );
  }
}
