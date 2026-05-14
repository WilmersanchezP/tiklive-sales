import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:tiklive_sales/core/constants/app_constants.dart';

enum RecordingState { idle, recording, processing }

class VoiceService {
  final AudioRecorder _recorder = AudioRecorder();
  final Dio _dio = Dio();

  // Native (iOS/Android/desktop)
  String? _currentAudioPath;

  // Web: collect stream chunks instead of using blob URL.
  // The blob URL approach via package:http is unreliable in Flutter web
  // because BrowserClient may not handle blob: scheme correctly.
  StreamSubscription<Uint8List>? _streamSub;
  final List<Uint8List> _webChunks = [];

  Future<bool> requestMicrophonePermission() async {
    if (kIsWeb) return true;
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  Future<bool> startRecording() async {
    final hasPermission = await requestMicrophonePermission();
    if (!hasPermission) return false;

    try {
      await _streamSub?.cancel();
      _streamSub = null;
      _webChunks.clear();

      if (kIsWeb) {
        final stream = await _recorder.startStream(
          const RecordConfig(
            encoder: AudioEncoder.opus,
            bitRate: 128000,
            sampleRate: 16000,
            numChannels: 1,
          ),
        );
        _streamSub = stream.listen(
          (chunk) => _webChunks.add(chunk),
          onError: (e) => debugPrint('[VoiceService] Stream error: $e'),
        );
      } else {
        final dir = await getTemporaryDirectory();
        _currentAudioPath =
            '${dir.path}/voice_order_${DateTime.now().millisecondsSinceEpoch}.m4a';

        await _recorder.start(
          const RecordConfig(
            encoder: AudioEncoder.aacLc,
            bitRate: 128000,
            sampleRate: 16000,
            numChannels: 1,
          ),
          path: _currentAudioPath!,
        );
      }
      return true;
    } catch (e) {
      debugPrint('[VoiceService] Start recording error: $e');
      return false;
    }
  }

  Future<String?> stopRecordingAndTranscribe({String language = 'es'}) async {
    if (!await _recorder.isRecording()) {
      debugPrint('[VoiceService] Not recording — aborting stop');
      return null;
    }

    await _recorder.stop();

    if (kIsWeb) {
      await _streamSub?.cancel();
      _streamSub = null;

      if (_webChunks.isEmpty) {
        debugPrint('[VoiceService] No audio chunks captured on web');
        return null;
      }

      final bytes = Uint8List.fromList(
        _webChunks.expand((c) => c).toList(),
      );
      _webChunks.clear();
      debugPrint('[VoiceService] Sending ${bytes.length} bytes to Whisper');

      return _callWhisperApi(
        MultipartFile.fromBytes(bytes, filename: 'audio.webm'),
        language: language,
      );
    } else {
      if (_currentAudioPath == null) return null;
      return _transcribeFile(_currentAudioPath!, language: language);
    }
  }

  Future<String?> _transcribeFile(String path, {required String language}) async {
    final file = File(path);
    if (!file.existsSync()) return null;

    return _callWhisperApi(
      MultipartFile.fromFileSync(path, filename: 'audio.m4a'),
      language: language,
    );
  }

  Future<String?> _callWhisperApi(
    MultipartFile audioFile, {
    required String language,
  }) async {
    try {
      final formData = FormData.fromMap({
        'file': audioFile,
        'model': AppConstants.whisperModel,
        'language': language,
        'response_format': 'json',
      });

      final response = await _dio.post(
        '${AppConstants.openAiBaseUrl}/audio/transcriptions',
        data: formData,
        options: Options(
          headers: {
            'Authorization': 'Bearer ${AppConstants.openAiKey}',
          },
        ),
      );

      final text = (response.data as Map<String, dynamic>)['text'] as String?;
      debugPrint('[VoiceService] Whisper transcript: $text');
      return text;
    } on DioException catch (e) {
      debugPrint('[VoiceService] Whisper error ${e.response?.statusCode}: ${e.response?.data}');
      return null;
    } catch (e) {
      debugPrint('[VoiceService] Unexpected error: $e');
      return null;
    }
  }

  Future<bool> isRecording() => _recorder.isRecording();

  Future<void> cancelRecording() async {
    if (await _recorder.isRecording()) {
      await _recorder.cancel();
    }
    await _streamSub?.cancel();
    _streamSub = null;
    _webChunks.clear();
    _cleanupTempFile();
  }

  void _cleanupTempFile() {
    if (_currentAudioPath != null) {
      final f = File(_currentAudioPath!);
      if (f.existsSync()) f.deleteSync();
    }
    _currentAudioPath = null;
  }

  void dispose() {
    _streamSub?.cancel();
    _recorder.dispose();
  }
}
