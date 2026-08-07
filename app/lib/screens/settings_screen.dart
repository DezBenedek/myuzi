import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/models.dart';
import '../providers/connectivity_provider.dart';
import '../providers/providers.dart';
import '../services/api_client.dart';
import '../services/local_cache.dart';
import '../services/toast.dart';
import '../widgets/user_avatar.dart';
import '../widgets/widgets.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  String? _inviteUrl;
  final _inviteEmail = TextEditingController();
  bool _openingWeb = false;
  bool _avatarBusy = false;

  @override
  void dispose() {
    _inviteEmail.dispose();
    super.dispose();
  }

  Future<void> _invite() async {
    if (!ref.read(connectivityProvider)) {
      showAppToast(context, 'Nincs internet', error: true);
      return;
    }
    try {
      final url = await ref.read(apiProvider).createInvite(
            email: _inviteEmail.text.trim().isEmpty ? null : _inviteEmail.text.trim(),
          );
      setState(() => _inviteUrl = url);
      await Clipboard.setData(ClipboardData(text: url));
      if (mounted) showAppToast(context, 'Meghívó kész (vágólapra másolva)');
    } on ApiException catch (e) {
      if (mounted) showAppToast(context, e.message, error: true);
    }
  }

  Future<void> _openWebAccount() async {
    final online = await ref.read(connectivityProvider.notifier).checkNow();
    if (!online) {
      if (mounted) {
        showAppToast(context, 'Nincs internet — a fiókkezelő online kell', error: true);
      }
      return;
    }
    setState(() => _openingWeb = true);
    try {
      final url = await ref.read(apiProvider).createWebAccountLink();
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } on ApiException catch (e) {
      if (mounted) showAppToast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _openingWeb = false);
    }
  }

  Future<void> _editProfile() async {
    final user = ref.read(authProvider).user;
    if (user == null) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _ProfileEditSheet(
        initialName: user.name,
        initialEmail: user.email,
        onSave: (name, email) async {
          await ref.read(authProvider.notifier).updateProfile(
                name: name,
                email: email,
              );
        },
      ),
    );
  }

  Future<void> _pickAvatar() async {
    if (!ref.read(connectivityProvider)) {
      showAppToast(context, 'Nincs internet', error: true);
      return;
    }
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (file == null) return;

    setState(() => _avatarBusy = true);
    try {
      final bytes = await file.readAsBytes();
      final mime = file.mimeType ??
          (file.path.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg');
      final user = await ref.read(apiProvider).uploadAvatar(
            bytes: bytes,
            contentType: mime,
          );
      await LocalCache.putAvatarBytes(user.id, bytes);
      await ref.read(authProvider.notifier).setAvatar(user);
      if (mounted) showAppToast(context, 'Profilkép mentve');
    } on ApiException catch (e) {
      if (mounted) showAppToast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _avatarBusy = false);
    }
  }

  Future<void> _removeAvatar() async {
    if (!ref.read(connectivityProvider)) {
      showAppToast(context, 'Nincs internet', error: true);
      return;
    }
    final me = ref.read(authProvider).user;
    if (me == null || me.avatarUrl == null) return;

    setState(() => _avatarBusy = true);
    try {
      final user = await ref.read(apiProvider).deleteAvatar();
      await LocalCache.clearAvatar(user.id);
      await ref.read(authProvider.notifier).setAvatar(user);
      if (mounted) showAppToast(context, 'Profilkép törölve');
    } on ApiException catch (e) {
      if (mounted) showAppToast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _avatarBusy = false);
    }
  }

  Future<void> _editFamilyName() async {
    final fam = ref.read(familyProvider).asData?.value.family;
    final me = ref.read(authProvider).user;
    if (fam == null || me == null) return;
    if (fam.ownerId != me.id) {
      showAppToast(context, 'Csak a tulajdonos módosíthatja a család nevét', error: true);
      return;
    }
    if (!ref.read(connectivityProvider)) {
      showAppToast(context, 'Nincs internet', error: true);
      return;
    }

    final ctrl = TextEditingController(text: fam.name);
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final bottom = MediaQuery.viewInsetsOf(ctx).bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 8, 20, 20 + bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Család neve', style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 14),
              TextField(
                controller: ctrl,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(hintText: 'Család neve'),
              ),
              const SizedBox(height: 16),
              BigButton(
                label: 'Mentés',
                icon: Icons.check,
                onPressed: () => Navigator.pop(ctx, true),
              ),
            ],
          ),
        );
      },
    );
    final name = ctrl.text.trim();
    WidgetsBinding.instance.addPostFrameCallback((_) => ctrl.dispose());
    if (ok != true || name.length < 2) return;

    try {
      await ref.read(apiProvider).renameFamily(familyId: fam.id, name: name);
      ref.invalidate(familyProvider);
      if (mounted) showAppToast(context, 'Családnév mentve');
    } on ApiException catch (e) {
      if (mounted) showAppToast(context, e.message, error: true);
    }
  }

  Future<void> _removeMember(FamilyMember member) async {
    final fam = ref.read(familyProvider).asData?.value.family;
    final me = ref.read(authProvider).user;
    if (fam == null || me == null) return;

    final leaving = member.id == me.id;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(leaving ? 'Kilépés a családból' : 'Tag eltávolítása'),
        content: Text(
          leaving
              ? 'Biztosan kilépsz a(z) ${fam.name} családból?'
              : 'Eltávolítod ${member.name}-t a családból?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Mégse')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(leaving ? 'Kilépek' : 'Eltávolít'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await ref.read(apiProvider).removeFamilyMember(
            familyId: fam.id,
            userId: member.id,
          );
      ref.invalidate(familyProvider);
      unawaited(ref.read(homeNotifierProvider.notifier).refresh(silent: true));
      if (mounted) {
        showAppToast(
          context,
          leaving ? 'Kiléptél a családból' : '${member.name} eltávolítva',
        );
      }
    } on ApiException catch (e) {
      if (mounted) showAppToast(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final family = ref.watch(familyProvider);
    final t = Theme.of(context);
    final vision = auth.user?.visionAssist ?? false;
    final fam = family.asData?.value.family;
    final members = family.asData?.value.members ?? const <FamilyMember>[];
    final me = auth.user?.id;
    final isOwner = fam?.ownerId == me;
    final user = auth.user;

    return Scaffold(
      appBar: AppBar(title: const Text('Beállítások')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          SoftCard(
            child: Row(
              children: [
                GestureDetector(
                  onTap: _avatarBusy ? null : _pickAvatar,
                  onLongPress: user?.avatarUrl != null && !_avatarBusy
                      ? _removeAvatar
                      : null,
                  child: Stack(
                    children: [
                      UserAvatar(
                        name: user?.name ?? '?',
                        avatarUrl: user?.avatarUrl,
                        userId: user?.id,
                        radius: 32,
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: t.colorScheme.primary,
                            shape: BoxShape.circle,
                          ),
                          child: _avatarBusy
                              ? const SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(
                                  Icons.camera_alt,
                                  size: 12,
                                  color: Colors.white,
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: InkWell(
                    onTap: _editProfile,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(user?.name ?? '', style: t.textTheme.titleLarge),
                        Text(user?.email ?? '', style: t.textTheme.bodyMedium),
                        const SizedBox(height: 4),
                        Text(
                          'Profilkép: koppints · törlés: hosszan',
                          style: t.textTheme.labelMedium?.copyWith(
                            color: t.colorScheme.onSurface.withValues(alpha: 0.55),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Szerkesztés',
                  onPressed: _editProfile,
                  icon: Icon(Icons.edit_outlined, color: t.colorScheme.primary),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SoftCard(
            onTap: fam == null ? null : _editFamilyName,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Család neve', style: t.textTheme.titleLarge),
                      const SizedBox(height: 4),
                      Text(
                        fam?.name ?? 'Nincs család',
                        style: t.textTheme.bodyLarge,
                      ),
                      if (fam != null && !isOwner)
                        Text(
                          'Csak a tulajdonos módosíthatja',
                          style: t.textTheme.bodyMedium,
                        ),
                    ],
                  ),
                ),
                if (isOwner)
                  Icon(Icons.edit_outlined, color: t.colorScheme.primary),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SoftCard(
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Látássérült segítség', style: t.textTheme.titleLarge),
              value: vision,
              onChanged: (v) => ref.read(authProvider.notifier).setVisionAssist(v),
            ),
          ),
          const SizedBox(height: 12),
          SoftCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Családtagok', style: t.textTheme.titleLarge),
                const SizedBox(height: 8),
                if (members.isEmpty)
                  Text('Nincs család', style: t.textTheme.bodyMedium)
                else
                  ...members.map((m) {
                    final isMe = m.id == me;
                    final canRemove = isOwner && !isMe && m.role != 'owner';
                    final canLeave = !isOwner && isMe;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: UserAvatar(
                        name: m.name,
                        avatarUrl: m.avatarUrl,
                        userId: m.id,
                        radius: 20,
                      ),
                      title: Text(
                        isMe ? '${m.name} (te)' : m.name,
                        style: t.textTheme.titleMedium,
                      ),
                      subtitle: Text(
                        m.role == 'owner' ? 'Tulajdonos · ${m.email}' : m.email,
                        style: t.textTheme.bodyMedium,
                      ),
                      trailing: canRemove || canLeave
                          ? IconButton(
                              tooltip: canLeave ? 'Kilépés' : 'Eltávolítás',
                              icon: Icon(
                                canLeave ? Icons.logout : Icons.person_remove_outlined,
                                color: t.colorScheme.error,
                              ),
                              onPressed: () => _removeMember(m),
                            )
                          : null,
                    );
                  }),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SoftCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Meghívó', style: t.textTheme.titleLarge),
                const SizedBox(height: 8),
                TextField(
                  controller: _inviteEmail,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(hintText: 'Email (opcionális)'),
                ),
                const SizedBox(height: 10),
                BigButton(
                  label: 'Meghívó',
                  icon: Icons.link,
                  onPressed: _invite,
                ),
                if (_inviteUrl != null) ...[
                  const SizedBox(height: 10),
                  SelectableText(_inviteUrl!, style: t.textTheme.bodyMedium),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          SoftCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Előfizetés', style: t.textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(
                  fam == null ? 'Nincs család' : fam.planSummary,
                  style: t.textTheme.bodyMedium,
                ),
                const SizedBox(height: 10),
                BigButton(
                  label: _openingWeb ? 'Megnyitás…' : 'Fiókkezelő',
                  icon: Icons.open_in_browser,
                  outlined: true,
                  onPressed: _openingWeb ? null : _openWebAccount,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          BigButton(
            label: 'Kijelentkezés',
            icon: Icons.logout,
            outlined: true,
            danger: true,
            onPressed: () async {
              await ref.read(authProvider.notifier).logout();
              if (context.mounted) context.go('/login');
            },
          ),
        ],
      ),
    );
  }
}

class _ProfileEditSheet extends StatefulWidget {
  const _ProfileEditSheet({
    required this.initialName,
    required this.initialEmail,
    required this.onSave,
  });

  final String initialName;
  final String initialEmail;
  final Future<void> Function(String name, String email) onSave;

  @override
  State<_ProfileEditSheet> createState() => _ProfileEditSheetState();
}

class _ProfileEditSheetState extends State<_ProfileEditSheet> {
  late final TextEditingController _name;
  late final TextEditingController _email;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initialName);
    _email = TextEditingController(text: widget.initialEmail);
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSave(_name.text.trim(), _email.text.trim());
      if (mounted) Navigator.pop(context);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _busy = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Mentés sikertelen';
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final t = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 8, 20, 20 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Profil', style: t.textTheme.titleLarge),
          const SizedBox(height: 14),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Név'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: TextStyle(color: t.colorScheme.error)),
          ],
          const SizedBox(height: 16),
          BigButton(
            label: _busy ? 'Mentés…' : 'Mentés',
            icon: Icons.check,
            onPressed: _busy ? null : _save,
          ),
        ],
      ),
    );
  }
}
