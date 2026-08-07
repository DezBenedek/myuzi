import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/providers.dart';
import '../services/api_client.dart';
import '../widgets/widgets.dart';

class InviteScreen extends ConsumerStatefulWidget {
  const InviteScreen({super.key, required this.token});

  final String token;

  @override
  ConsumerState<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends ConsumerState<InviteScreen> {
  String? _familyName;
  String? _error;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await ref.read(apiProvider).getInvite(widget.token);
      final invite = data['invite'] as Map<String, dynamic>;
      setState(() {
        _familyName = invite['familyName'] as String?;
        _loading = false;
      });
    } on ApiException catch (e) {
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  Future<void> _accept() async {
    final auth = ref.read(authProvider);
    if (!auth.isLoggedIn) {
      context.go('/login');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).acceptInvite(widget.token);
      ref.invalidate(familyProvider);
      if (mounted) context.go('/');
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('MyÜzi', style: t.textTheme.displayLarge),
                    const SizedBox(height: 12),
                    Text(
                      _familyName == null
                          ? (_error ?? 'Érvénytelen meghívó')
                          : 'Meghívót kaptál a(z) $_familyName családba.',
                      style: t.textTheme.bodyLarge,
                    ),
                    const Spacer(),
                    if (_familyName != null)
                      BigButton(
                        label: _busy ? 'Csatlakozás…' : 'Csatlakozom',
                        icon: Icons.group_add,
                        onPressed: _busy ? null : _accept,
                      ),
                    const SizedBox(height: 10),
                    BigButton(
                      label: 'Vissza',
                      outlined: true,
                      onPressed: () => context.go('/'),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
