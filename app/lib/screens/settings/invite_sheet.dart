import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../services/api_client.dart';
import '../../services/toast.dart';
import '../../widgets/widgets.dart';

class InviteSheet extends StatefulWidget {
  const InviteSheet({super.key, required this.onCreate});

  final Future<String> Function(String email) onCreate;

  @override
  State<InviteSheet> createState() => _InviteSheetState();
}

class _InviteSheetState extends State<InviteSheet> {
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
    final email = _email.text.trim();
    if (!email.contains('@')) {
      showAppToast(context, 'Érvényes email kell', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final url = await widget.onCreate(email);
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
            'Add meg a meghívott email címét — a meghívó csak ehhez a címhez kötődik.',
            style: t.textTheme.bodyMedium,
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'email@pelda.hu'),
          ),
          if (_inviteUrl != null) ...[
            const SizedBox(height: 12),
            Text(
              'A meghívott ezt a QR-kódot is beolvashatja.',
              style: t.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
              ),
              child: QrImageView(
                data: _inviteUrl!,
                size: (MediaQuery.sizeOf(context).width - 110).clamp(180.0, 250.0),
                backgroundColor: Colors.white,
                eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: Color(0xFF12261C),
                ),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: Color(0xFF12261C),
                ),
              ),
            ),
            const SizedBox(height: 10),
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
