import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../providers/connectivity_provider.dart';
import '../../providers/providers.dart';
import '../../services/api_client.dart';
import '../../services/local_cache.dart';
import '../../services/toast.dart';
import '../../widgets/user_avatar.dart';
import '../../widgets/widgets.dart';
import 'profile_edit_sheet.dart';

class SettingsProfileSection extends ConsumerStatefulWidget {
  const SettingsProfileSection({super.key});

  @override
  ConsumerState<SettingsProfileSection> createState() =>
      _SettingsProfileSectionState();
}

class _SettingsProfileSectionState
    extends ConsumerState<SettingsProfileSection> {
  bool _avatarBusy = false;

  Future<void> _editProfile() async {
    final user = ref.read(authProvider).user;
    if (user == null) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => ProfileEditSheet(
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
      if (!mounted) return;
      showAppToast(context, 'Nincs internet', error: true);
      return;
    }
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 768,
      maxHeight: 768,
      imageQuality: 75,
    );
    if (file == null) return;
    if (!mounted) return;

    setState(() => _avatarBusy = true);
    try {
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty || bytes.length > 1024 * 1024) {
        if (mounted) showAppToast(context, 'A kép legfeljebb 1 MB lehet', error: true);
        return;
      }
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
    } catch (_) {
      if (mounted) showAppToast(context, 'Profilkép mentése sikertelen', error: true);
    } finally {
      if (mounted) setState(() => _avatarBusy = false);
    }
  }

  Future<void> _removeAvatar() async {
    if (!ref.read(connectivityProvider)) {
      if (!mounted) return;
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
    } catch (_) {
      if (mounted) showAppToast(context, 'Profilkép törlése sikertelen', error: true);
    } finally {
      if (mounted) setState(() => _avatarBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    final t = Theme.of(context);

    return SoftCard(
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
    );
  }
}
