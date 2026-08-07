import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/providers.dart';
import '../services/api_client.dart';
import '../widgets/widgets.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _familyName = TextEditingController();
  final _inviteToken = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _familyName.dispose();
    _inviteToken.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(apiProvider).createFamily(_familyName.text.trim());
      ref.invalidate(familyProvider);
      if (mounted) context.go('/');
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _accept() async {
    var token = _inviteToken.text.trim();
    if (token.contains('/invite/')) {
      token = token.split('/invite/').last.split('?').first;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(apiProvider).acceptInvite(token);
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
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 36, 22, 24),
          children: [
            Text('Család', style: t.textTheme.displayLarge),
            const SizedBox(height: 8),
            Text(
              'Hozz létre új családot, vagy fogadj el egy meghívót.',
              style: t.textTheme.bodyLarge,
            ),
            const SizedBox(height: 28),
            SoftCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Új család', style: t.textTheme.titleLarge),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _familyName,
                    decoration: const InputDecoration(hintText: 'Család neve'),
                  ),
                  const SizedBox(height: 12),
                  BigButton(
                    label: 'Létrehozom',
                    icon: Icons.home_outlined,
                    onPressed: _busy ? null : _create,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SoftCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Meghívó', style: t.textTheme.titleLarge),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _inviteToken,
                    decoration: const InputDecoration(
                      hintText: 'Link vagy kód',
                    ),
                  ),
                  const SizedBox(height: 12),
                  BigButton(
                    label: 'Csatlakozom',
                    icon: Icons.group_add_outlined,
                    outlined: true,
                    onPressed: _busy ? null : _accept,
                  ),
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: TextStyle(color: t.colorScheme.error, fontWeight: FontWeight.w700)),
            ],
          ],
        ),
      ),
    );
  }
}
