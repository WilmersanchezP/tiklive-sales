import 'dart:io';
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
  String? _currentAudioPath;

  Future<bool> requestMicrophonePermission() async {
    if (kIsWeb) return true; // Web handles permissions via browser
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  Future<bool> startRecording() async {
    final hasPermission = await requestMicrophonePermission();
    if (!hasPermission) return false;

    final dir = kIsWeb ? null : await getTemporaryDirectory();
    _currentAudioPath = kIsWeb
        ? null
        : '${dir!.path}/voice_order_${DateTime.now().millisecondsSinceEpoch}.m4a';

    await _recorder.start(
      RecordConfig(
        encoder: kIsWeb ? AudioEncoder.opus : AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 16000, // Whisper prefers 16kHz
        numChannels: 1,
      ),
      path: _currentAudioPath ?? '',
    );
    return true;
  }

  Future<String?> stopRecordingAndTranscribe({String language = 'es'}) async {
    if (!await _recorder.isRecording()) return null;

    if (kIsWeb) {
      final blob = await _recorder.stop();
      return _transcribeBlob(blob, language: language);
    } else {
      await _recorder.stop();
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

  Future<String?> _transcribeBlob(dynamic blob, {required String language}) async {
    if (blob == null) return null;
    // Web: blob is a String (data URL) from the record package
    return _callWhisperApi(
      MultipartFile.fromString(blob as String, filename: 'audio.webm'),
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
            'Content-Type': 'multipart/form-data',
          },
        ),
      );

      return (response.data as Map<String, dynamic>)['text'] as String?;
    } on DioException catch (e) {
      debugPrint('[VoiceService] Whisper error: ${e.response?.data}');
      return null;
    }
  }

  Future<bool> isRecording() => _recorder.isRecording();

  Future<void> cancelRecording() async {
    if (await _recorder.isRecording()) {
      await _recorder.cancel();
    }
    _cleanupTempFile();
  }

  void _cleanupTempFile() {
    if (_currentAudioPath != null && !kIsWeb) {
      final f = File(_currentAudioPath!);
      if (f.existsSync()) f.deleteSync();
    }
    _currentAudioPath = null;
  }

  void dispose() {
    _recorder.dispose();
  }
}
