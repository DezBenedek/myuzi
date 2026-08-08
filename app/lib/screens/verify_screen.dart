import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/providers.dart';
import '../services/api_client.dart';
import '../widgets/widgets.dart';

class VerifyScreen extends ConsumerStatefulWidget {
  const VerifyScreen({super.key});

  @override
  ConsumerState<VerifyScreen> createState() => _VerifyScreenState();
}

class _VerifyScreenState extends ConsumerState<VerifyScreen> {
  final _code = TextEditingController();
  final _name = TextEditingController();
  bool _busy = false;
  bool _askName = false;
  bool _resendBusy = false;
  String? _error;
  String? _info;
  int _resendIn = 30;
  Timer? _resendTimer;

  @override
  void initState() {
    super.initState();
    _startResendCooldown();
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _code.dispose();
    _name.dispose();
    super.dispose();
  }

  void _startResendCooldown([int seconds = 30]) {
    _resendTimer?.cancel();
    setState(() => _resendIn = seconds);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_resendIn <= 1) {
        t.cancel();
        setState(() => _resendIn = 0);
      } else {
        setState(() => _resendIn -= 1);
      }
    });
  }

  Future<void> _resend() async {
    if (_resendBusy || _resendIn > 0 || _askName) return;
    setState(() {
      _resendBusy = true;
      _error = null;
      _info = null;
    });
    try {
      await ref.read(authProvider.notifier).resendLoginCode();
      if (!mounted) return;
      setState(() => _info = 'Új kódot küldtünk.');
      _startResendCooldown(30);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
      if (e.statusCode == 429) _startResendCooldown(30);
    } catch (_) {
      if (mounted) setState(() => _error = 'Nem sikerült új kódot küldeni');
    } finally {
      if (mounted) setState(() => _resendBusy = false);
    }
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      await ref.read(authProvider.notifier).verify(
            _code.text.trim(),
            name: _askName ? _name.text.trim() : null,
          );
      if (mounted) context.go('/');
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.needsName && !_askName) {
        setState(() {
          _askName = true;
          _error = null;
        });
      } else {
        setState(() => _error = e.message);
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Sikertelen belépés');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final t = Theme.of(context);
    final canResend = !_askName && _resendIn == 0 && !_resendBusy && !_busy;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (_askName) {
              setState(() => _askName = false);
            } else {
              context.go('/login');
            }
          },
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 24),
          children: [
            Text(
              _askName ? 'Becenév' : 'Írd be a kódot',
              style: t.textTheme.displayLarge?.copyWith(fontSize: 34),
            ),
            const SizedBox(height: 8),
            Text(
              _askName
                  ? 'A kód rendben. Add meg, hogyan szólítsunk.'
                  : 'Elküldtük ide: ${auth.pendingEmail ?? ''}',
              style: t.textTheme.bodyLarge,
            ),
            const SizedBox(height: 28),
            if (!_askName)
              TextField(
                controller: _code,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                autofocus: true,
                style: t.textTheme.displayLarge?.copyWith(letterSpacing: 10, fontSize: 36),
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                decoration: const InputDecoration(hintText: '••••••'),
                onSubmitted: (_) => _submit(),
              )
            else
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                autofocus: true,
                decoration: const InputDecoration(hintText: 'Pl. Anna'),
                onSubmitted: (_) => _submit(),
              ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: t.colorScheme.error, fontWeight: FontWeight.w700)),
            ],
            if (_info != null) ...[
              const SizedBox(height: 12),
              Text(_info!, style: TextStyle(color: t.colorScheme.primary, fontWeight: FontWeight.w700)),
            ],
            const SizedBox(height: 24),
            BigButton(
              label: _busy
                  ? 'Ellenőrzés…'
                  : _askName
                      ? 'Belépek'
                      : 'Tovább',
              icon: Icons.check_circle_outline,
              onPressed: _busy ? null : _submit,
            ),
            if (!_askName) ...[
              const SizedBox(height: 16),
              TextButton(
                onPressed: canResend ? _resend : null,
                child: Text(
                  _resendBusy
                      ? 'Küldés…'
                      : _resendIn > 0
                          ? 'Új kód $_resendIn mp múlva'
                          : 'Új kód küldése',
                  style: t.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
