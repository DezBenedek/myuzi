import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../widgets/user_avatar.dart';
import '../../widgets/widgets.dart';

class GroupDraft {
  const GroupDraft({required this.name, required this.memberIds});
  final String name;
  final List<String> memberIds;
}

class CreateGroupSheet extends StatefulWidget {
  const CreateGroupSheet({super.key, required this.people});

  final List<FamilyMember> people;

  @override
  State<CreateGroupSheet> createState() => _CreateGroupSheetState();
}

class _CreateGroupSheetState extends State<CreateGroupSheet> {
  final _name = TextEditingController();
  final _search = TextEditingController();
  final _selected = <String>{};

  @override
  void dispose() {
    _name.dispose();
    _search.dispose();
    super.dispose();
  }

  void _submit() {
    FocusScope.of(context).unfocus();
    Navigator.pop(
      context,
      GroupDraft(
        name: _name.text.trim(),
        memberIds: _selected.toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.text.trim().toLowerCase();
    final filtered = q.isEmpty
        ? widget.people
        : widget.people
            .where(
              (p) =>
                  p.name.toLowerCase().contains(q) ||
                  p.email.toLowerCase().contains(q),
            )
            .toList();
    final height = MediaQuery.sizeOf(context).height * 0.88;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    return SizedBox(
      height: height,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 4, 20, 16 + bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Új csoport', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(hintText: 'Csoport neve'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _search,
              decoration: const InputDecoration(
                hintText: 'Keresés név vagy email alapján',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            Text(
              _selected.isEmpty
                  ? 'Válassz tagokat'
                  : '${_selected.length} tag kiválasztva',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 6),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        'Nincs találat',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    )
                  : ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final p = filtered[i];
                        final on = _selected.contains(p.id);
                        return CheckboxListTile(
                          value: on,
                          contentPadding: EdgeInsets.zero,
                          secondary: UserAvatar(
                            name: p.name,
                            avatarUrl: p.avatarUrl,
                            userId: p.id,
                            radius: 20,
                          ),
                          title: Text(p.name),
                          subtitle: Text(p.email),
                          onChanged: (v) {
                            setState(() {
                              if (v == true) {
                                _selected.add(p.id);
                              } else {
                                _selected.remove(p.id);
                              }
                            });
                          },
                        );
                      },
                    ),
            ),
            const SizedBox(height: 8),
            BigButton(
              label: 'Kész',
              icon: Icons.check,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}
