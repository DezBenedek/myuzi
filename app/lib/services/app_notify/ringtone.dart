import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

Future<String> ensureRingtoneFile() async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/myuzi_ringtone.wav');
  if (!await file.exists()) {
    await file.writeAsBytes(buildRingtoneWav(), flush: true);
  }
  return file.path;
}

Uint8List buildRingtoneWav() {
  const sampleRate = 22050;
  const durationSec = 1.2;
  final total = (sampleRate * durationSec).round();
  final data = BytesBuilder();
  final dataSize = total * 2;
  final fileSize = 36 + dataSize;
  final header = ByteData(44);
  void writeString(int offset, String s) {
    for (var i = 0; i < s.length; i++) {
      header.setUint8(offset + i, s.codeUnitAt(i));
    }
  }

  writeString(0, 'RIFF');
  header.setUint32(4, fileSize, Endian.little);
  writeString(8, 'WAVE');
  writeString(12, 'fmt ');
  header.setUint32(16, 16, Endian.little);
  header.setUint16(20, 1, Endian.little);
  header.setUint16(22, 1, Endian.little);
  header.setUint32(24, sampleRate, Endian.little);
  header.setUint32(28, sampleRate * 2, Endian.little);
  header.setUint16(32, 2, Endian.little);
  header.setUint16(34, 16, Endian.little);
  writeString(36, 'data');
  header.setUint32(40, dataSize, Endian.little);
  data.add(header.buffer.asUint8List());

  for (var i = 0; i < total; i++) {
    final t = i / sampleRate;
    double amp = 0;
    if (t < 0.35 || (t > 0.45 && t < 0.8)) {
      final env = (t < 0.35)
          ? (t / 0.05).clamp(0.0, 1.0) * ((0.35 - t) / 0.05).clamp(0.0, 1.0)
          : ((t - 0.45) / 0.05).clamp(0.0, 1.0) * ((0.8 - t) / 0.05).clamp(0.0, 1.0);
      amp = 0.35 * env * (sin(2 * pi * 880 * t) + 0.5 * sin(2 * pi * 1174 * t));
    }
    final sample = (amp * 32767).round().clamp(-32768, 32767);
    data.add([sample & 0xff, (sample >> 8) & 0xff]);
  }
  return data.toBytes();
}
