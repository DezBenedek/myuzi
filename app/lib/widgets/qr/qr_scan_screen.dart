import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../providers/connectivity_provider.dart';
import '../../providers/providers.dart';
import '../../services/api_client.dart';
import '../../services/toast.dart';
import 'qr_parse.dart';

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

    try {
      await _controller.stop();
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
