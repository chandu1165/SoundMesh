import 'dart:typed_data';

class WavEncoder {
  Uint8List encodeMono16({
    required List<double> samples,
    required int sampleRate,
  }) {
    const channels = 1;
    const bitsPerSample = 16;
    const bytesPerSample = bitsPerSample ~/ 8;
    final dataSize = samples.length * channels * bytesPerSample;
    final bytes = Uint8List(44 + dataSize);
    final data = ByteData.sublistView(bytes);

    _writeString(data, 0, 'RIFF');
    data.setUint32(4, 36 + dataSize, Endian.little);
    _writeString(data, 8, 'WAVE');
    _writeString(data, 12, 'fmt ');
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, 1, Endian.little);
    data.setUint16(22, channels, Endian.little);
    data.setUint32(24, sampleRate, Endian.little);
    data.setUint32(28, sampleRate * channels * bytesPerSample, Endian.little);
    data.setUint16(32, channels * bytesPerSample, Endian.little);
    data.setUint16(34, bitsPerSample, Endian.little);
    _writeString(data, 36, 'data');
    data.setUint32(40, dataSize, Endian.little);

    var offset = 44;
    for (final sample in samples) {
      final clamped = sample.clamp(-1.0, 1.0);
      final value = (clamped < 0 ? clamped * 32768 : clamped * 32767).round();
      data.setInt16(offset, value, Endian.little);
      offset += 2;
    }

    return bytes;
  }

  void _writeString(ByteData data, int offset, String value) {
    for (var i = 0; i < value.length; i += 1) {
      data.setUint8(offset + i, value.codeUnitAt(i));
    }
  }
}
