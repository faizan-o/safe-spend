import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:record/record.dart';

/// Records what the user says so the workflow (Gemini) can listen to it.
/// This works on every phone, in the browser and on desktop, with no need for
/// the phone's own speech service.
abstract class AudioCapture {
  /// Starts recording. Returns false when the microphone cannot be used
  /// (for example the permission was refused). [onLevel] gets 0..1 loudness.
  Future<bool> start({void Function(double level)? onLevel});

  /// Stops and returns a WAV file, or null when there was (almost) no sound.
  Future<Uint8List?> stop();

  /// Stops and throws the recording away.
  Future<void> cancel();

  Future<void> dispose();

  /// A short technical note about the last recording (length, measured sample rate).
  String? get info => null;
}

/// Records 16 kHz mono 16-bit sound with the `record` package and wraps it in a WAV header.
class PcmAudioCapture implements AudioCapture {
  static const int _sampleRate = 16000;

  /// Never keep more than 30 seconds.
  static const int _maxBytes = _sampleRate * 2 * 30;

  /// Anything shorter than this is treated as "nothing heard".
  static const int _minBytes = _sampleRate * 2 ~/ 3;

  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _subscription;
  BytesBuilder _pcm = BytesBuilder(copy: false);
  DateTime? _startedAt;
  DateTime? _lastChunkAt;
  int _firstChunkBytes = 0;
  String? _info;

  @override
  String? get info => _info;

  @override
  Future<bool> start({void Function(double level)? onLevel}) async {
    if (!await _recorder.hasPermission()) return false;
    _pcm = BytesBuilder(copy: false);
    _startedAt = null;
    _lastChunkAt = null;
    _firstChunkBytes = 0;
    final stream = await _recorder.startStream(const RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: _sampleRate,
      numChannels: 1,
      autoGain: true,
      echoCancel: !kIsWeb, // the browser's echo canceller can cut quiet speech
      noiseSuppress: true,
    ));
    _subscription = stream.listen((chunk) {
      final now = DateTime.now();
      if (_startedAt == null) {
        _startedAt = now;
        _firstChunkBytes = chunk.length;
      }
      _lastChunkAt = now;
      if (_pcm.length < _maxBytes) _pcm.add(chunk);
      if (onLevel != null) onLevel(_level(chunk));
    });
    return true;
  }

  @override
  Future<Uint8List?> stop() async {
    await _halt();
    final pcm = _pcm.takeBytes();
    if (pcm.length < _minBytes) return null;
    final rate = _measuredRate(pcm.length);
    _normalize(pcm);
    _info = '${(pcm.length / 2 / rate).toStringAsFixed(1)} s of sound, ${pcm.length ~/ 1024} KB, sample rate $rate Hz';
    return _wav(pcm, rate);
  }

  @override
  Future<void> cancel() async {
    await _halt();
    _pcm = BytesBuilder(copy: false);
  }

  @override
  Future<void> dispose() async {
    await _halt();
    await _recorder.dispose();
  }

  Future<void> _halt() async {
    try {
      await _recorder.stop();
    } catch (_) {}
    await _subscription?.cancel();
    _subscription = null;
  }

  /// Browsers sometimes record at 44.1 or 48 kHz even when 16 kHz was asked for. Labelling that
  /// sound as 16 kHz plays it slowed down and unintelligible, so the rate is measured from how
  /// much sound arrived in how much time and snapped to the nearest standard rate.
  int _measuredRate(int bytes) {
    final start = _startedAt;
    final end = _lastChunkAt;
    if (start == null || end == null) return _sampleRate;
    final seconds = end.difference(start).inMilliseconds / 1000;
    if (seconds < 0.6) return _sampleRate; // too short to measure reliably
    // The first chunk arrives at time zero, so it does not count towards the elapsed time.
    final measured = (bytes - _firstChunkBytes) / 2 / seconds;
    const standard = [8000, 11025, 16000, 22050, 24000, 32000, 44100, 48000];
    var best = _sampleRate;
    var bestError = double.infinity;
    for (final rate in standard) {
      final error = (measured - rate).abs() / rate;
      if (error < bestError) {
        bestError = error;
        best = rate;
      }
    }
    // Only trust the measurement when it clearly matches a standard rate.
    return bestError < 0.2 ? best : _sampleRate;
  }

  /// Laptop and browser microphones are often quiet. Raise the volume so the loudest part reaches
  /// about 70% of full scale (never more than 10x), which makes speech far easier to understand.
  static void _normalize(Uint8List pcm) {
    final data = ByteData.sublistView(pcm);
    final count = pcm.length ~/ 2;
    var peak = 0;
    for (var i = 0; i < count; i++) {
      final v = data.getInt16(i * 2, Endian.little).abs();
      if (v > peak) peak = v;
    }
    if (peak < 150) return; // only noise, amplifying would make it worse
    final gain = (0.7 * 32767 / peak).clamp(1.0, 10.0);
    if (gain < 1.2) return;
    for (var i = 0; i < count; i++) {
      final v = data.getInt16(i * 2, Endian.little);
      data.setInt16(i * 2, (v * gain).round().clamp(-32768, 32767), Endian.little);
    }
  }

  /// Loudness of one chunk from 0 to 1 (quiet room is about 0.02, speech 0.2 to 0.8).
  static double _level(Uint8List chunk) {
    final count = chunk.length ~/ 2;
    if (count == 0) return 0;
    final data = ByteData.sublistView(chunk);
    var sum = 0.0;
    for (var i = 0; i < count; i++) {
      final sample = data.getInt16(i * 2, Endian.little).toDouble();
      sum += sample * sample;
    }
    final rms = _sqrt(sum / count);
    return (rms / 6000).clamp(0.0, 1.0).toDouble();
  }

  static double _sqrt(double value) {
    if (value <= 0) return 0;
    var x = value;
    for (var i = 0; i < 20; i++) {
      x = 0.5 * (x + value / x);
    }
    return x;
  }

  static Uint8List _wav(Uint8List pcm, int sampleRate) {
    final header = ByteData(44);
    void tag(int offset, String text) {
      for (var i = 0; i < 4; i++) {
        header.setUint8(offset + i, text.codeUnitAt(i));
      }
    }

    tag(0, 'RIFF');
    header.setUint32(4, 36 + pcm.length, Endian.little);
    tag(8, 'WAVE');
    tag(12, 'fmt ');
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little); // PCM
    header.setUint16(22, 1, Endian.little); // mono
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, sampleRate * 2, Endian.little);
    header.setUint16(32, 2, Endian.little);
    header.setUint16(34, 16, Endian.little);
    tag(36, 'data');
    header.setUint32(40, pcm.length, Endian.little);
    final out = BytesBuilder(copy: false)
      ..add(header.buffer.asUint8List())
      ..add(pcm);
    return out.takeBytes();
  }
}
