import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
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

  // Native
  String? _currentAudioPath;

  // Web stream approach
  StreamSubscription<Uint8List>? _streamSub;
  Completer<void>? _streamDone; // signals all chunks received (stream closed)
  final List<Uint8List> _webChunks = [];
  bool _usingStream = false;
  AudioEncoder _webEncoder = AudioEncoder.opus;

  /// Last error detail from stopRecordingAndTranscribe (null = no error).
  String? lastError;

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
      _usingStream = false;

      if (kIsWeb) {
        // Detect best supported encoder for this browser
        final supportsOpus = await _recorder.isEncoderSupported(AudioEncoder.opus);
        _webEncoder = supportsOpus ? AudioEncoder.opus : AudioEncoder.aacLc;
        debugPrint('[VoiceService] encoder: $_webEncoder');

        // Primary: stream approach (direct bytes, no blob URL needed)
        try {
          final stream = await _recorder.startStream(
            RecordConfig(
              encoder: _webEncoder,
              bitRate: 128000,
              sampleRate: 16000,
              numChannels: 1,
            ),
          );
          final done = Completer<void>();
          _streamDone = done;
          _streamSub = stream.listen(
            (chunk) => _webChunks.add(chunk),
            onDone: () { if (!done.isCompleted) done.complete(); },
            onError: (e) {
              debugPrint('[VoiceService] Stream error: $e');
              if (!done.isCompleted) done.complete();
            },
            cancelOnError: false,
          );
          _usingStream = true;
          debugPrint('[VoiceService] startStream OK');
          return true;
        } catch (streamErr) {
          // Fallback: start() → blob URL (Safari/iOS compatibility)
          debugPrint('[VoiceService] startStream failed ($streamErr) — using start() fallback');
          await _recorder.start(
            RecordConfig(
              encoder: _webEncoder,
              bitRate: 128000,
              sampleRate: 16000,
              numChannels: 1,
            ),
            path: '',
          );
          _usingStream = false;
          debugPrint('[VoiceService] start() blob-URL fallback OK');
          return true;
        }
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
        return true;
      }
    } catch (e) {
      debugPrint('[VoiceService] startRecording error: $e');
      return false;
    }
  }

  Future<String?> stopRecordingAndTranscribe({String language = 'es'}) async {
    lastError = null;

    if (!await _recorder.isRecording()) {
      lastError = 'not_recording';
      debugPrint('[VoiceService] Not recording — abort');
      return null;
    }

    if (kIsWeb) {
      if (_usingStream) {
        await _recorder.stop();
        // Wait for stream to close so all chunks (including the final iOS batch)
        // are delivered before we read _webChunks. Timeout = 3 s safety net.
        await _streamDone?.future.timeout(
          const Duration(seconds: 3),
          onTimeout: () {},
        );
        await _streamSub?.cancel();
        _streamSub = null;
        _streamDone = null;

        if (_webChunks.isEmpty) {
          lastError = 'no_chunks';
          debugPrint('[VoiceService] No stream chunks captured');
          return null;
        }

        final bytes = Uint8List.fromList(_webChunks.expand((c) => c).toList());
        _webChunks.clear();
        final filename = _webEncoder == AudioEncoder.aacLc ? 'audio.m4a' : 'audio.webm';
        debugPrint('[VoiceService] Stream: ${bytes.length} bytes → $filename');

        return _callWhisperApi(
          MultipartFile.fromBytes(bytes, filename: filename),
          language: language,
        );
      } else {
        // Blob URL fallback path
        final blobUrl = await _recorder.stop();
        return _transcribeBlobUrl(blobUrl, language: language);
      }
    } else {
      await _recorder.stop();
      if (_currentAudioPath == null) return null;
      return _transcribeFile(_currentAudioPath!, language: language);
    }
  }

  Future<String?> _transcribeBlobUrl(String? blobUrl, {required String language}) async {
    if (blobUrl == null || blobUrl.isEmpty) {
      debugPrint('[VoiceService] Empty blob URL');
      return null;
    }
    debugPrint('[VoiceService] Fetching blob URL: $blobUrl');
    try {
      final response = await http.get(Uri.parse(blobUrl));
      debugPrint('[VoiceService] Blob fetch status: ${response.statusCode}, bytes: ${response.bodyBytes.length}');
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) return null;

      final filename = _webEncoder == AudioEncoder.aacLc ? 'audio.m4a' : 'audio.webm';
      return _callWhisperApi(
        MultipartFile.fromBytes(response.bodyBytes, filename: filename),
        language: language,
      );
    } catch (e) {
      debugPrint('[VoiceService] Blob fetch error: $e');
      return null;
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
          headers: {'Authorization': 'Bearer ${AppConstants.openAiKey}'},
        ),
      );

      final text = (response.data as Map<String, dynamic>)['text'] as String?;
      debugPrint('[VoiceService] Whisper: $text');
      return text;
    } on DioException catch (e) {
      lastError = 'whisper_${e.response?.statusCode ?? 'net'}';
      debugPrint('[VoiceService] Whisper error ${e.response?.statusCode}: ${e.response?.data}');
      return null;
    } catch (e) {
      lastError = 'whisper_exception';
      debugPrint('[VoiceService] Unexpected error: $e');
      return null;
    }
  }

  Future<bool> isRecording() => _recorder.isRecording();

  Future<void> cancelRecording() async {
    if (await _recorder.isRecording()) await _recorder.cancel();
    await _streamSub?.cancel();
    _streamSub = null;
    if (!(_streamDone?.isCompleted ?? true)) _streamDone?.complete();
    _streamDone = null;
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
