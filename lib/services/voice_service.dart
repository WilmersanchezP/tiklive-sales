import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
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
    if (kIsWeb) return true;
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  Future<bool> startRecording() async {
    final hasPermission = await requestMicrophonePermission();
    if (!hasPermission) return false;

    try {
      final dir = kIsWeb ? null : await getTemporaryDirectory();
      _currentAudioPath = kIsWeb
          ? null
          : '${dir!.path}/voice_order_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _recorder.start(
        RecordConfig(
          encoder: kIsWeb ? AudioEncoder.opus : AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: _currentAudioPath ?? '',
      );
      return true;
    } catch (e) {
      // Browser denied microphone permission
      debugPrint('[VoiceService] Start recording error: $e');
      return false;
    }
  }

  Future<String?> stopRecordingAndTranscribe({String language = 'es'}) async {
    if (!await _recorder.isRecording()) return null;

    if (kIsWeb) {
      // On web, stop() returns a blob URL string like "blob:https://..."
      final blobUrl = await _recorder.stop();
      return _transcribeBlobUrl(blobUrl, language: language);
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

  // Fetch actual audio bytes from the blob URL, then send to Whisper
  Future<String?> _transcribeBlobUrl(String? blobUrl, {required String language}) async {
    if (blobUrl == null || blobUrl.isEmpty) return null;

    try {
      final response = await http.get(Uri.parse(blobUrl));
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) return null;

      return _callWhisperApi(
        MultipartFile.fromBytes(
          response.bodyBytes,
          filename: 'audio.webm',
        ),
        language: language,
      );
    } catch (e) {
      debugPrint('[VoiceService] Blob fetch error: $e');
      return null;
    }
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
