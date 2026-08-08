import 'package:flutter/material.dart';

import '../../widgets/widgets.dart';

class EmailContactSheet extends StatefulWidget {
  const EmailContactSheet({super.key});

  @override
  State<EmailContactSheet> createState() => _EmailContactSheetState();
}

class _EmailContactSheetState extends State<EmailContactSheet> {
  final _email = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  void _submit() {
    FocusScope.of(context).unfocus();
    Navigator.pop(context, _email.text.trim());
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
          Text('Email / kapcsolat', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 14),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'valaki@email.hu'),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 16),
          BigButton(
            label: 'Tovább',
            icon: Icons.send,
            onPressed: _submit,
          ),
        ],
      ),
    );
  }
}
