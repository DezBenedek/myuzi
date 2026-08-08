import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../services/api_client.dart';
import '../../services/toast.dart';
import '../../widgets/user_avatar.dart';

Future<void> showNearbyPeopleSheet(
  BuildContext context,
  WidgetRef ref,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _NearbyPeopleSheet(),
  );
}

class _NearbyPeopleSheet extends ConsumerStatefulWidget {
  const _NearbyPeopleSheet();

  @override
  ConsumerState<_NearbyPeopleSheet> createState() => _NearbyPeopleSheetState();
}

class _NearbyPeopleSheetState extends ConsumerState<_NearbyPeopleSheet> {
  final _search = TextEditingController();
  Timer? _debounce;
  List<NearbyPerson> _familyPeople = const [];
  List<NearbyPerson> _contactPeople = const [];
  List<NearbyRequest> _requests = const [];
  bool _loading = true;
  bool _contactsLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _search.addListener(_onSearchChanged);
    unawaited(_load());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search
      ..removeListener(_onSearchChanged)
      ..dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 280), () {
      unawaited(_loadFamilyPeople());
    });
  }

  Future<void> _load() async {
    try {
      await Future.wait([_loadFamilyPeople(), _loadRequests()]);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadFamilyPeople() async {
    try {
      final people = await ref.read(apiProvider).nearbyPeople(
            query: _search.text.trim(),
          );
      if (mounted) setState(() => _familyPeople = people);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _loadRequests() async {
    try {
      final requests = await ref.read(apiProvider).nearbyRequests();
      if (mounted) {
        setState(() => _requests = requests);
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _matchContacts() async {
    if (_contactsLoading) return;
    setState(() {
      _contactsLoading = true;
      _error = null;
    });
    try {
      final permission = await FlutterContacts.permissions.request(
        PermissionType.read,
      );
      if (permission != PermissionStatus.granted &&
          permission != PermissionStatus.limited) {
        if (mounted) {
          showAppToast(
            context,
            'A névjegyekhez engedély szükséges.',
            error: true,
          );
        }
        return;
      }
      final contacts = await FlutterContacts.getAll(
        properties: {ContactProperty.email},
      );
      final emails = contacts
          .expand((contact) => contact.emails)
          .map((email) => email.address.trim().toLowerCase())
          .where((email) => email.contains('@'))
          .toSet()
          .toList();
      final people = await ref.read(apiProvider).matchContactEmails(emails);
      if (mounted) setState(() => _contactPeople = people);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'A névjegyek betöltése sikertelen.');
    } finally {
      if (mounted) setState(() => _contactsLoading = false);
    }
  }

  Future<void> _openOrRequest(NearbyPerson person) async {
    final isFamilyPerson = _familyPeople.any((item) => item.id == person.id);
    try {
      if (isFamilyPerson) {
        final conversationId = await ref.read(apiProvider).openDirect(person.id);
        if (!mounted) return;
        Navigator.pop(context);
        context.push('/chat/$conversationId');
      } else {
        await ref.read(apiProvider).requestNearbyConnection(person.id);
        if (mounted) {
          showAppToast(context, 'Kapcsolatkérés elküldve');
          await _loadRequests();
        }
      }
    } on ApiException catch (e) {
      if (mounted) showAppToast(context, e.message, error: true);
    }
  }

  Future<void> _acceptRequest(NearbyRequest request) async {
    try {
      await ref.read(apiProvider).acceptNearbyRequest(request.id);
      await _loadRequests();
      if (mounted) showAppToast(context, 'Kapcsolat elfogadva');
    } on ApiException catch (e) {
      if (mounted) showAppToast(context, e.message, error: true);
    }
  }

  Widget _personTile(NearbyPerson person, {required bool contactMatch}) {
    final t = Theme.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: UserAvatar(
        name: person.name,
        avatarUrl: person.avatarUrl,
        userId: person.id,
        radius: 22,
      ),
      title: Text(person.name),
      subtitle: Text(
        contactMatch
            ? '${person.email} · Névjegyzékből'
            : '${person.familyName ?? "Ismerős család"} · ${person.email}',
      ),
      trailing: IconButton(
        tooltip: contactMatch ? 'Kapcsolatfelkérés' : 'Üzenet',
        icon: Icon(
          contactMatch ? Icons.person_add_alt_1 : Icons.chat_bubble_outline,
          color: t.colorScheme.primary,
        ),
        onPressed: () => _openOrRequest(person),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          4,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: _loading
            ? const SizedBox(
                height: 240,
                child: Center(child: CircularProgressIndicator()),
              )
            : SizedBox(
                height: MediaQuery.sizeOf(context).height * .82,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Közeli ismerősök', style: t.textTheme.headlineMedium),
                    const SizedBox(height: 8),
                    Text(
                      'Az összekapcsolt családok tagjai itt azonnal elérhetők. A névjegyzékből csak engedélyezett felhasználókat ajánlunk.',
                      style: t.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _search,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        labelText: 'Keresés név vagy email alapján',
                      ),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _contactsLoading ? null : _matchContacts,
                      icon: const Icon(Icons.contacts_outlined),
                      label: Text(
                        _contactsLoading
                            ? 'Névjegyek betöltése…'
                            : 'Névjegyek ajánlásai',
                      ),
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          _error!,
                          style: TextStyle(color: t.colorScheme.error),
                        ),
                      ),
                    if (_requests.any((request) => request.incoming)) ...[
                      const SizedBox(height: 16),
                      Text('Beérkező kérések', style: t.textTheme.titleLarge),
                      ..._requests
                          .where((request) => request.incoming)
                          .map(
                            (request) => ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: UserAvatar(
                                name: request.user.name,
                                avatarUrl: request.user.avatarUrl,
                                userId: request.user.id,
                                radius: 20,
                              ),
                              title: Text(request.user.name),
                              subtitle: const Text('Kapcsolatfelkérés'),
                              trailing: IconButton(
                                tooltip: 'Elfogadás',
                                icon: const Icon(Icons.check_circle_outline),
                                onPressed: () => _acceptRequest(request),
                              ),
                            ),
                          ),
                    ],
                    const SizedBox(height: 12),
                    Expanded(
                      child: ListView(
                        children: [
                          if (_familyPeople.isNotEmpty) ...[
                            Text(
                              'Ismerős családok tagjai',
                              style: t.textTheme.titleLarge,
                            ),
                            ..._familyPeople.map(
                              (person) => _personTile(
                                person,
                                contactMatch: false,
                              ),
                            ),
                          ],
                          if (_contactPeople.isNotEmpty) ...[
                            const SizedBox(height: 14),
                            Text(
                              'Névjegyzékből ajánlott',
                              style: t.textTheme.titleLarge,
                            ),
                            ..._contactPeople.map(
                              (person) => _personTile(
                                person,
                                contactMatch: true,
                              ),
                            ),
                          ],
                          if (_familyPeople.isEmpty && _contactPeople.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 28),
                              child: Text('Nincs találat.'),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
