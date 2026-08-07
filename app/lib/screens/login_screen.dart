import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/providers.dart';
import '../services/api_client.dart';
import '../widgets/widgets.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController();
  bool _vision = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authProvider.notifier).startLogin(
            email: _email.text,
            visionAssist: _vision,
          );
      if (mounted) context.go('/verify');
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Nem sikerült elküldeni a kódot');
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
            Text('MyÜzi', style: t.textTheme.displayLarge),
            const SizedBox(height: 8),
            Text(
              'Email + kód.',
              style: t.textTheme.bodyLarge,
            ),
            const SizedBox(height: 28),
            Text('Email', style: t.textTheme.titleLarge),
            const SizedBox(height: 8),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration: const InputDecoration(hintText: 'te@email.hu'),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 18),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Látássérült segítség', style: t.textTheme.titleLarge),
              subtitle: Text(
                'Nagyobb betűk, erősebb kontraszt, vastagabb gombok',
                style: t.textTheme.bodyMedium,
              ),
              value: _vision,
              onChanged: (v) => setState(() => _vision = v),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: t.colorScheme.error, fontWeight: FontWeight.w700)),
            ],
            const SizedBox(height: 24),
            BigButton(
              label: _busy ? 'Küldés…' : 'Kód küldése',
              icon: Icons.mail_outline,
              onPressed: _busy ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }
}
