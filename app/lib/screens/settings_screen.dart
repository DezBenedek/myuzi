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
import '../providers/theme_provider.dart';
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
  bool _openingWeb = false;
  bool _avatarBusy = false;

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

  Future<void> _avatarActions() async {
    final user = ref.read(authProvider).user;
    if (user == null || _avatarBusy) return;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final t = Theme.of(ctx);
        final hasAvatar = user.avatarUrl != null;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: Text(hasAvatar ? 'Profilkép cseréje' : 'Profilkép beállítása'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickAvatar();
                  },
                ),
                if (hasAvatar)
                  ListTile(
                    leading: Icon(Icons.delete_outline, color: t.colorScheme.error),
                    title: Text(
                      'Profilkép törlése',
                      style: TextStyle(color: t.colorScheme.error),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      _removeAvatar();
                    },
                  ),
              ],
            ),
          ),
        );
      },
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

  Future<void> _inviteDrawer() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _InviteSheet(
        onCreate: (email) async {
          final url = await ref.read(apiProvider).createInvite(
                email: email.isEmpty ? null : email,
              );
          await Clipboard.setData(ClipboardData(text: url));
          return url;
        },
      ),
    );
  }

  Future<void> _confirmLogout() async {
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
                Text('Kijelentkezés', style: t.textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(
                  'Biztosan kijelentkezel?',
                  style: t.textTheme.bodyLarge,
                ),
                const SizedBox(height: 16),
                BigButton(
                  label: 'Kijelentkezés',
                  icon: Icons.logout,
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
    if (ok != true || !mounted) return;
    await ref.read(authProvider.notifier).logout();
    if (mounted) context.go('/login');
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

    final name = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _FamilyNameSheet(initialName: fam.name),
    );
    if (name == null || name.length < 2) return;

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
                Text(
                  leaving ? 'Kilépés a családból' : 'Tag eltávolítása',
                  style: t.textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  leaving
                      ? 'Biztosan kilépsz a(z) ${fam.name} családból?'
                      : 'Eltávolítod ${member.name}-t a családból?',
                  style: t.textTheme.bodyLarge,
                ),
                const SizedBox(height: 16),
                BigButton(
                  label: leaving ? 'Kilépek' : 'Eltávolít',
                  icon: leaving ? Icons.logout : Icons.person_remove_outlined,
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
    final dark = ref.watch(themeModeProvider) == ThemeMode.dark;
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
                  onTap: _avatarBusy ? null : _avatarActions,
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
              title: Text('Sötét téma', style: t.textTheme.titleLarge),
              value: dark,
              onChanged: (v) => ref.read(themeModeProvider.notifier).setDark(v),
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
                Row(
                  children: [
                    Expanded(
                      child: Text('Családtagok', style: t.textTheme.titleLarge),
                    ),
                    if (fam != null)
                      IconButton(
                        tooltip: 'Meghívó',
                        onPressed: _inviteDrawer,
                        icon: Icon(Icons.add, color: t.colorScheme.primary),
                      ),
                  ],
                ),
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
                Text(
                  fam == null
                      ? 'Előfizetés'
                      : fam.isPaid
                          ? 'Csomagmódosítás'
                          : 'Előfizetés',
                  style: t.textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  fam == null ? 'Nincs család' : fam.planSummary,
                  style: t.textTheme.bodyMedium,
                ),
                const SizedBox(height: 10),
                BigButton(
                  label: _openingWeb
                      ? 'Megnyitás…'
                      : fam == null
                          ? 'Fiókkezelő'
                          : fam.isPaid
                              ? 'Csomagmódosítás'
                              : 'Előfizetés',
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
            onPressed: _confirmLogout,
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
            onPressed: _busy
                ? null
                : () {
                    FocusScope.of(context).unfocus();
                    _save();
                  },
          ),
        ],
      ),
    );
  }
}

class _InviteSheet extends StatefulWidget {
  const _InviteSheet({required this.onCreate});

  final Future<String> Function(String email) onCreate;

  @override
  State<_InviteSheet> createState() => _InviteSheetState();
}

class _InviteSheetState extends State<_InviteSheet> {
  final _email = TextEditingController();
  String? _inviteUrl;
  var _busy = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      final url = await widget.onCreate(_email.text.trim());
      if (!mounted) return;
      setState(() {
        _inviteUrl = url;
        _busy = false;
      });
      showAppToast(context, 'Meghívó kész (vágólapra másolva)');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showAppToast(context, e.message, error: true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      showAppToast(context, 'Meghívó sikertelen', error: true);
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
          Text('Meghívó', style: t.textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            'Opcionális email — ha megadod, elküldjük a meghívót.',
            style: t.textTheme.bodyMedium,
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'email@pelda.hu (opcionális)'),
          ),
          if (_inviteUrl != null) ...[
            const SizedBox(height: 12),
            SelectableText(_inviteUrl!, style: t.textTheme.bodyMedium),
          ],
          const SizedBox(height: 16),
          BigButton(
            label: _busy ? 'Készítés…' : 'Meghívó készítése',
            icon: Icons.link,
            onPressed: _busy ? null : _submit,
          ),
        ],
      ),
    );
  }
}

class _FamilyNameSheet extends StatefulWidget {
  const _FamilyNameSheet({required this.initialName});

  final String initialName;

  @override
  State<_FamilyNameSheet> createState() => _FamilyNameSheetState();
}

class _FamilyNameSheetState extends State<_FamilyNameSheet> {
  late final TextEditingController _name;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 8, 20, 20 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Család neve', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 14),
          TextField(
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(hintText: 'Család neve'),
          ),
          const SizedBox(height: 16),
          BigButton(
            label: 'Mentés',
            icon: Icons.check,
            onPressed: () {
              FocusScope.of(context).unfocus();
              Navigator.pop(context, _name.text.trim());
            },
          ),
        ],
      ),
    );
  }
}
