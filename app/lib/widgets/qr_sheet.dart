import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../providers/connectivity_provider.dart';
import '../providers/providers.dart';
import '../services/api_client.dart';
import '../services/toast.dart';

/// Parses MyÜzi user id from QR payload (`…/u/{id}` or raw id).
String? parseQrUserId(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  final uri = Uri.tryParse(text);
  if (uri != null) {
    final parts = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    final i = parts.indexOf('u');
    if (i >= 0 && i + 1 < parts.length) {
      final id = parts[i + 1];
      if (id.isNotEmpty) return id;
    }
  }
  final m = RegExp(r'(?:^|/)u/([A-Za-z0-9_-]+)').firstMatch(text);
  if (m != null) return m.group(1);
  if (RegExp(r'^[A-Za-z0-9_-]{8,}$').hasMatch(text)) return text;
  return null;
}

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
                Navigator.pop(context);
                Navigator.of(context).push(
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

class QrScanScreen extends ConsumerStatefulWidget {
  const QrScanScreen({super.key});

  @override
  ConsumerState<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends ConsumerState<QrScanScreen> {
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
  );
  var _inviteToFamily = false;
  var _handling = false;
  String? _lastRaw;
  DateTime? _cooldownUntil;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handling || !mounted) return;
    final now = DateTime.now();
    if (_cooldownUntil != null && now.isBefore(_cooldownUntil!)) return;

    final raw = capture.barcodes
        .map((b) => b.rawValue)
        .whereType<String>()
        .firstWhere((s) => s.trim().isNotEmpty, orElse: () => '');
    if (raw.isEmpty || raw == _lastRaw) return;
    _lastRaw = raw;

    final userId = parseQrUserId(raw);
    if (userId == null) {
      _cooldownUntil = now.add(const Duration(seconds: 2));
      showAppToast(context, 'Érvénytelen MyÜzi QR', error: true);
      return;
    }

    setState(() => _handling = true);
    await _controller.stop();

    try {
      if (!ref.read(connectivityProvider)) {
        if (mounted) showAppToast(context, 'Nincs internet', error: true);
        return;
      }

      final card = await ref.read(apiProvider).userCard(userId);
      if (!mounted) return;
      if (card['isSelf'] == true) {
        showAppToast(context, 'Ez a saját QR kódod');
        return;
      }

      final user = Map<String, dynamic>.from(card['user'] as Map? ?? {});
      final name = user['name'] as String? ?? 'Felhasználó';
      final sameFamily = card['sameFamily'] == true;

      if (_inviteToFamily) {
        final result = await ref.read(apiProvider).inviteUserById(userId);
        if (!mounted) return;
        showAppToast(context, result.message);
        Navigator.pop(context);
        return;
      }

      if (sameFamily) {
        final conversationId = await ref.read(apiProvider).openDirect(userId);
        if (!mounted) return;
        Navigator.pop(context);
        context.push('/chat/$conversationId');
        return;
      }

      if (!mounted) return;
      showAppToast(
        context,
        '$name nincs a családodban. Kapcsold be a „Meghívás a családba” kapcsolót.',
        error: true,
      );
    } on ApiException catch (e) {
      _cooldownUntil = DateTime.now().add(const Duration(seconds: 2));
      if (mounted) showAppToast(context, e.message, error: true);
    } catch (_) {
      _cooldownUntil = DateTime.now().add(const Duration(seconds: 2));
      if (mounted) showAppToast(context, 'Beolvasás sikertelen', error: true);
    } finally {
      _handling = false;
      _lastRaw = null;
      if (mounted) {
        try {
          await _controller.start();
        } catch (_) {}
        setState(() {});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('QR beolvasás')),
      body: Column(
        children: [
          Expanded(
            child: ClipRRect(
              child: MobileScanner(
                controller: _controller,
                onDetect: _onDetect,
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Meghívás a családba'),
                    subtitle: Text(
                      _inviteToFamily
                          ? 'A beolvasott személy meghívót kap. Ha már más családban van, elfogadáskor ki kell lépnie.'
                          : 'Kapcsolat / üzenet, ha már egy családban vagytok.',
                      style: t.textTheme.bodySmall,
                    ),
                    value: _inviteToFamily,
                    onChanged: _handling
                        ? null
                        : (v) => setState(() => _inviteToFamily = v),
                  ),
                  if (_handling) ...[
                    const SizedBox(height: 8),
                    const LinearProgressIndicator(),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
