import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tiklive_sales/services/ai_service.dart';
import 'package:tiklive_sales/services/supabase_service.dart';
import 'package:tiklive_sales/services/voice_service.dart';
import 'package:tiklive_sales/shared/models/order_model.dart';

// ── Service providers ─────────────────────────────────────────────────────────
final voiceServiceProvider = Provider<VoiceService>((_) => VoiceService());
final aiServiceProvider = Provider<AiService>((_) => AiService());
final supabaseServiceProvider = Provider<SupabaseService>((_) => SupabaseService());

// ── Recording state ───────────────────────────────────────────────────────────
class VoiceSalesState {
  final RecordingState recordingState;
  final String transcript;
  final ExtractedOrder? extractedOrder;
  final String? errorMessage;
  final bool isSavingOrder;
  final List<OrderModel> sessionOrders;
  final String? currentSessionId;

  const VoiceSalesState({
    this.recordingState = RecordingState.idle,
    this.transcript = '',
    this.extractedOrder,
    this.errorMessage,
    this.isSavingOrder = false,
    this.sessionOrders = const [],
    this.currentSessionId,
  });

  VoiceSalesState copyWith({
    RecordingState? recordingState,
    String? transcript,
    ExtractedOrder? extractedOrder,
    String? errorMessage,
    bool clearExtracted = false,
    bool clearError = false,
    bool? isSavingOrder,
    List<OrderModel>? sessionOrders,
    String? currentSessionId,
  }) =>
      VoiceSalesState(
        recordingState: recordingState ?? this.recordingState,
        transcript: transcript ?? this.transcript,
        extractedOrder: clearExtracted ? null : extractedOrder ?? this.extractedOrder,
        errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
        isSavingOrder: isSavingOrder ?? this.isSavingOrder,
        sessionOrders: sessionOrders ?? this.sessionOrders,
        currentSessionId: currentSessionId ?? this.currentSessionId,
      );
}

class VoiceSalesNotifier extends StateNotifier<VoiceSalesState> {
  final VoiceService _voice;
  final AiService _ai;
  final SupabaseService _db;

  VoiceSalesNotifier(this._voice, this._ai, this._db)
      : super(const VoiceSalesState());

  // ── Recording flow ───────────────────────────────────────────────────────────
  Future<void> startRecording() async {
    final started = await _voice.startRecording();
    if (!started) {
      state = state.copyWith(
        errorMessage:
            'No se pudo acceder al micrófono.\n'
            'En Safari iOS: Ajustes → Safari → Micrófono → Permitir.\n'
            'Si tienes Lockdown Mode activo, desactívalo para esta página.',
      );
      return;
    }
    state = state.copyWith(
      recordingState: RecordingState.recording,
      clearExtracted: true,
      clearError: true,
      transcript: '',
    );
  }

  Future<void> stopAndProcess() async {
    state = state.copyWith(recordingState: RecordingState.processing);

    // 1. Transcribe audio via Whisper
    final transcript = await _voice.stopRecordingAndTranscribe();
    if (transcript == null) {
      final err = _voice.lastError ?? 'unknown';
      final msg = switch (err) {
        'no_chunks' => 'Audio no capturado (0 bytes). Mantén presionado mientras hablas.',
        String e when e.startsWith('whisper_401') => 'API key inválida. Contacta al administrador.',
        String e when e.startsWith('whisper_') => 'Error al conectar con Whisper ($err). Verifica tu conexión.',
        _ => 'Error al procesar el audio ($err). Intenta de nuevo.',
      };
      state = state.copyWith(recordingState: RecordingState.idle, errorMessage: msg);
      return;
    }
    if (transcript.trim().isEmpty) {
      state = state.copyWith(
        recordingState: RecordingState.idle,
        errorMessage: 'No se detectó habla. Habla más fuerte y cerca del micrófono.',
      );
      return;
    }
    state = state.copyWith(transcript: transcript);

    // 2. Extract order via GPT
    final extracted = await _ai.extractOrderFromTranscript(transcript);
    if (extracted == null) {
      state = state.copyWith(
        recordingState: RecordingState.idle,
        errorMessage: 'No se pudo interpretar el pedido. Intenta de nuevo.',
      );
      return;
    }

    state = state.copyWith(
      recordingState: RecordingState.idle,
      extractedOrder: extracted,
    );

    // Save transcript to audit log
    await _db.saveTranscript(
      transcript: transcript,
      orderId: null,
      sessionId: state.currentSessionId,
    );
  }

  Future<void> cancelRecording() async {
    await _voice.cancelRecording();
    state = state.copyWith(
      recordingState: RecordingState.idle,
      clearExtracted: true,
      transcript: '',
    );
  }

  // ── Order confirmation ────────────────────────────────────────────────────────
  Future<bool> confirmOrder() async {
    final extracted = state.extractedOrder;
    if (extracted == null) return false;

    state = state.copyWith(isSavingOrder: true);

    try {
      final order = OrderModel(
        id: '',
        productName: extracted.productName,
        color: extracted.color,
        size: extracted.size,
        quantity: extracted.quantity,
        customerName: extracted.customerName ?? 'Cliente Live',
        paymentMethod: extracted.paymentMethod,
        status: extracted.status,
        createdAt: DateTime.now(),
        liveSessionId: state.currentSessionId,
        notes: extracted.notes,
      );

      final saved = await _db.createOrder(order);

      state = state.copyWith(
        isSavingOrder: false,
        clearExtracted: true,
        transcript: '',
        sessionOrders: [saved, ...state.sessionOrders],
      );
      return true;
    } catch (e) {
      state = state.copyWith(
        isSavingOrder: false,
        errorMessage: 'Error al guardar el pedido: $e',
      );
      return false;
    }
  }

  void discardExtracted() {
    state = state.copyWith(
      clearExtracted: true,
      transcript: '',
    );
  }

  void updateExtracted(ExtractedOrder updated) {
    state = state.copyWith(extractedOrder: updated);
  }

  // ── Session management ────────────────────────────────────────────────────────
  Future<void> startLiveSession(String title) async {
    try {
      final session = await _db.startLiveSession(title);
      final id = session['id'] as String?;
      if (id == null) {
        state = state.copyWith(errorMessage: 'No se pudo iniciar la sesión live.');
        return;
      }
      state = state.copyWith(currentSessionId: id);
    } catch (e) {
      state = state.copyWith(errorMessage: 'Error al iniciar sesión: $e');
    }
  }

  Future<void> endLiveSession() async {
    if (state.currentSessionId == null) return;
    try {
      await _db.endLiveSession(state.currentSessionId!);
      state = state.copyWith(currentSessionId: null);
    } catch (e) {
      state = state.copyWith(errorMessage: 'Error al finalizar sesión: $e');
    }
  }

  @override
  void dispose() {
    _voice.dispose();
    super.dispose();
  }
}

final voiceSalesProvider =
    StateNotifierProvider<VoiceSalesNotifier, VoiceSalesState>(
  (ref) => VoiceSalesNotifier(
    ref.watch(voiceServiceProvider),
    ref.watch(aiServiceProvider),
    ref.watch(supabaseServiceProvider),
  ),
);
