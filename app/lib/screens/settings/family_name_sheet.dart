import 'package:flutter/material.dart';

import '../../widgets/widgets.dart';

class FamilyNameSheet extends StatefulWidget {
  const FamilyNameSheet({super.key, required this.initialName});

  final String initialName;

  @override
  State<FamilyNameSheet> createState() => _FamilyNameSheetState();
}

class _FamilyNameSheetState extends State<FamilyNameSheet> {
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
