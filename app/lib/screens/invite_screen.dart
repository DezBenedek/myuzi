import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/providers.dart';
import '../services/api_client.dart';
import '../services/toast.dart';
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
  bool _needsLeave = false;
  String? _currentFamilyName;

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

  Future<void> _accept({bool confirmLeave = false}) async {
    final auth = ref.read(authProvider);
    if (!auth.isLoggedIn) {
      context.go('/login');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(apiProvider).acceptInvite(
            widget.token,
            confirmLeave: confirmLeave,
          );
      ref.invalidate(familyProvider);
      if (mounted) {
        showAppToast(context, 'Csatlakoztál a családhoz');
        context.go('/');
      }
    } on ApiException catch (e) {
      if (e.needsLeaveConfirmation) {
        setState(() {
          _needsLeave = true;
          _currentFamilyName = e.currentFamilyName;
          _error = e.message;
          _busy = false;
        });
        return;
      }
      setState(() {
        _error = e.message;
        _busy = false;
      });
    } catch (_) {
      setState(() {
        _error = 'Csatlakozás sikertelen';
        _busy = false;
      });
    }
  }

  Future<void> _confirmLeaveAndJoin() async {
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
                Text('Kilépés a jelenlegi családból?', style: t.textTheme.titleLarge),
                const SizedBox(height: 10),
                Text(
                  'A(z) ${_currentFamilyName ?? "jelenlegi"} családból kilépsz, '
                  'és csatlakozol a(z) ${_familyName ?? "új"} családhoz. '
                  'Ez nem vonható vissza könnyen.',
                  style: t.textTheme.bodyLarge,
                ),
                const SizedBox(height: 16),
                BigButton(
                  label: 'Kilépek és csatlakozom',
                  icon: Icons.logout,
                  danger: true,
                  onPressed: () => Navigator.pop(ctx, true),
                ),
                const SizedBox(height: 8),
                BigButton(
                  label: 'Mégse',
                  outlined: true,
                  onPressed: () => Navigator.pop(ctx, false),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (ok == true) await _accept(confirmLeave: true);
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
                    if (_error != null && _familyName != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!, style: TextStyle(color: t.colorScheme.error)),
                    ],
                    const Spacer(),
                    if (_familyName != null)
                      BigButton(
                        label: _busy
                            ? 'Csatlakozás…'
                            : _needsLeave
                                ? 'Kilépek és csatlakozom'
                                : 'Csatlakozom',
                        icon: _needsLeave ? Icons.logout : Icons.group_add,
                        danger: _needsLeave,
                        onPressed: _busy
                            ? null
                            : (_needsLeave ? _confirmLeaveAndJoin : () => _accept()),
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
