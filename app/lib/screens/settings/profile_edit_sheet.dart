import 'package:flutter/material.dart';

import '../../services/api_client.dart';
import '../../widgets/widgets.dart';

class ProfileEditSheet extends StatefulWidget {
  const ProfileEditSheet({
    super.key,
    required this.initialName,
    required this.initialEmail,
    required this.onSave,
  });

  final String initialName;
  final String initialEmail;
  final Future<void> Function(String name, String email) onSave;

  @override
  State<ProfileEditSheet> createState() => _ProfileEditSheetState();
}

class _ProfileEditSheetState extends State<ProfileEditSheet> {
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
