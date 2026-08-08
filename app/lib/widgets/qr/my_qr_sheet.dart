import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../providers/providers.dart';
import '../../services/api_client.dart';
import 'qr_scan_screen.dart';

Future<void> showMyQrSheet(BuildContext context, WidgetRef ref) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => const _MyQrSheet(),
  );
}

class _MyQrSheet extends ConsumerStatefulWidget {
  const _MyQrSheet();

  @override
  ConsumerState<_MyQrSheet> createState() => _MyQrSheetState();
}

class _MyQrSheetState extends ConsumerState<_MyQrSheet> {
  String? _url;
  String? _name;
  String? _error;
  var _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final qr = await ref.read(apiProvider).myQr();
      if (!mounted) return;
      setState(() {
        _url = qr.url;
        _name = qr.name;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'QR betöltése sikertelen';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final size = MediaQuery.sizeOf(context);
    final qrSize = (size.width - 80).clamp(180.0, 280.0);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 8, 20, 20 + bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('QR kódom', style: t.textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              'Mutasd meg, hogy beolvashassanak.',
              style: t.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(40),
                child: CircularProgressIndicator(),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!, style: TextStyle(color: t.colorScheme.error)),
              )
            else if (_url != null) ...[
              if (_name != null && _name!.isNotEmpty)
                Text(_name!, style: t.textTheme.titleMedium),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: QrImageView(
                  data: _url!,
                  size: qrSize,
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
            ],
            const SizedBox(height: 20),
            IconButton.filledTonal(
              tooltip: 'Másik QR beolvasása',
              iconSize: 36,
              onPressed: () {
                final navigator = Navigator.of(context);
                navigator.pop();
                navigator.push(
                  MaterialPageRoute<void>(
                    builder: (_) => const QrScanScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.photo_camera_outlined),
            ),
            const SizedBox(height: 4),
            Text('Beolvasás', style: t.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
