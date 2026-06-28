import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

class WavAudio {
  WavAudio({
    required this.name,
    required this.sampleRate,
    required this.channels,
    required this.samples,
  });

  final String name;
  final int sampleRate;
  final int channels;
  final List<double> samples;
}

class WavDecoder {
  WavAudio decode(String name, Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    if (_fourCc(bytes, 0) != 'RIFF' || _fourCc(bytes, 8) != 'WAVE') {
      throw const WavDecodeException('Only RIFF/WAVE files are supported.');
    }

    int? audioFormat;
    int? channels;
    int? sampleRate;
    int? bitsPerSample;
    int? blockAlign;
    int? dataOffset;
    int? dataSize;

    var offset = 12;
    while (offset + 8 <= bytes.length) {
      final chunkId = _fourCc(bytes, offset);
      final chunkSize = data.getUint32(offset + 4, Endian.little);
      final chunkData = offset + 8;

      if (chunkId == 'fmt ') {
        audioFormat = data.getUint16(chunkData, Endian.little);
        channels = data.getUint16(chunkData + 2, Endian.little);
        sampleRate = data.getUint32(chunkData + 4, Endian.little);
        blockAlign = data.getUint16(chunkData + 12, Endian.little);
        bitsPerSample = data.getUint16(chunkData + 14, Endian.little);
      } else if (chunkId == 'data') {
        dataOffset = chunkData;
        dataSize = chunkSize;
      }

      offset = chunkData + chunkSize + (chunkSize.isOdd ? 1 : 0);
    }

    if (audioFormat == null ||
        channels == null ||
        sampleRate == null ||
        bitsPerSample == null ||
        blockAlign == null ||
        dataOffset == null ||
        dataSize == null) {
      throw const WavDecodeException(
        'The WAV file is missing required fmt or data chunks.',
      );
    }

    if (audioFormat != 1 && audioFormat != 3) {
      throw const WavDecodeException(
        'Only PCM and IEEE float WAV files are supported.',
      );
    }

    final bytesPerSample = bitsPerSample ~/ 8;
    if (![2, 3, 4].contains(bytesPerSample)) {
      throw WavDecodeException('$bitsPerSample-bit WAV is not supported yet.');
    }

    final frameCount = dataSize ~/ blockAlign;
    final mono = List<double>.filled(frameCount, 0);
    var cursor = dataOffset;
    for (var frame = 0; frame < frameCount; frame += 1) {
      var sum = 0.0;
      for (var channel = 0; channel < channels; channel += 1) {
        sum += _readSample(data, cursor, bitsPerSample, audioFormat);
        cursor += bytesPerSample;
      }
      mono[frame] = (sum / math.max(1, channels)).clamp(-1.0, 1.0);
      final frameEnd = dataOffset + (frame + 1) * blockAlign;
      cursor = frameEnd;
    }

    return WavAudio(
      name: name,
      sampleRate: sampleRate,
      channels: channels,
      samples: mono,
    );
  }

  double _readSample(ByteData data, int offset, int bitsPerSample, int format) {
    if (format == 3) {
      return data.getFloat32(offset, Endian.little).clamp(-1.0, 1.0);
    }
    return switch (bitsPerSample) {
      16 => data.getInt16(offset, Endian.little) / 32768,
      24 => _readInt24(data, offset) / 8388608,
      32 => data.getInt32(offset, Endian.little) / 2147483648,
      _ => throw WavDecodeException('$bitsPerSample-bit WAV is not supported.'),
    };
  }

  int _readInt24(ByteData data, int offset) {
    final b0 = data.getUint8(offset);
    final b1 = data.getUint8(offset + 1);
    final b2 = data.getUint8(offset + 2);
    var value = b0 | (b1 << 8) | (b2 << 16);
    if ((value & 0x800000) != 0) {
      value |= 0xff000000;
    }
    return value.toSigned(32);
  }

  String _fourCc(Uint8List bytes, int offset) {
    return ascii.decode(bytes.sublist(offset, offset + 4));
  }
}

class WavDecodeException implements Exception {
  const WavDecodeException(this.message);

  final String message;

  @override
  String toString() => message;
}
