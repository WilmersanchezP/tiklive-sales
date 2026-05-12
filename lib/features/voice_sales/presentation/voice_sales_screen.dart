import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:tiklive_sales/core/theme/app_theme.dart';
import 'package:tiklive_sales/features/voice_sales/providers/voice_sales_provider.dart';
import 'package:tiklive_sales/shared/models/order_model.dart';

class VoiceSalesScreen extends ConsumerWidget {
  const VoiceSalesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(voiceSalesProvider);
    final notifier = ref.read(voiceSalesProvider.notifier);

    return Scaffold(
      backgroundColor: AppColors.surface900,
      appBar: AppBar(
        title: Row(
          children: [
            const Text('Ventas por Voz'),
            const SizedBox(width: 12),
            if (state.currentSessionId != null)
              _LiveBadge(),
          ],
        ),
        actions: [
          if (state.currentSessionId == null)
            TextButton.icon(
              icon: const Icon(Icons.play_arrow_rounded, color: AppColors.accentGreen),
              label: const Text('Iniciar Live', style: TextStyle(color: AppColors.accentGreen)),
              onPressed: () => _showStartSessionDialog(context, notifier),
            )
          else
            TextButton.icon(
              icon: const Icon(Icons.stop_rounded, color: AppColors.accentRed),
              label: const Text('Finalizar Live', style: TextStyle(color: AppColors.accentRed)),
              onPressed: () => notifier.endLiveSession(),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: Row(
        children: [
          // Left panel — main recording UI
          Expanded(
            flex: 3,
            child: _MainPanel(state: state, notifier: notifier),
          ),
          // Right panel — live order feed (visible on wide screens)
          if (MediaQuery.of(context).size.width > 800)
            SizedBox(
              width: 320,
              child: _OrderFeedPanel(orders: state.sessionOrders),
            ),
        ],
      ),
    );
  }

  void _showStartSessionDialog(BuildContext context, VoiceSalesNotifier notifier) {
    final controller = TextEditingController(
      text: 'Live ${DateFormat('dd/MM HH:mm').format(DateTime.now())}',
    );
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface800,
        title: const Text('Iniciar sesión Live'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Nombre del live',
            hintText: 'Ej: Live ropa verano',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              notifier.startLiveSession(controller.text.trim());
              Navigator.pop(ctx);
            },
            child: const Text('Iniciar'),
          ),
        ],
      ),
    );
  }
}

// ── Main recording panel ──────────────────────────────────────────────────────
class _MainPanel extends ConsumerWidget {
  final VoiceSalesState state;
  final VoiceSalesNotifier notifier;

  const _MainPanel({required this.state, required this.notifier});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Transcript display
          if (state.transcript.isNotEmpty) ...[
            _TranscriptCard(transcript: state.transcript),
            const SizedBox(height: 16),
          ],

          // Error banner
          if (state.errorMessage != null) ...[
            _ErrorBanner(message: state.errorMessage!),
            const SizedBox(height: 16),
          ],

          // Extracted order preview
          if (state.extractedOrder != null) ...[
            _ExtractedOrderCard(
              order: state.extractedOrder!,
              onConfirm: () => notifier.confirmOrder(),
              onDiscard: () => notifier.discardExtracted(),
              isLoading: state.isSavingOrder,
            ),
            const SizedBox(height: 24),
          ],

          // Big microphone button
          _MicrophoneButton(
            state: state.recordingState,
            onTap: () => _handleMicTap(context),
          ),

          const SizedBox(height: 16),
          _RecordingStateLabel(state: state.recordingState),

          const SizedBox(height: 32),

          // Quick commands hint
          if (state.recordingState == RecordingState.idle) _QuickCommandsHint(),
        ],
      ),
    );
  }

  Future<void> _handleMicTap(BuildContext context) async {
    switch (state.recordingState) {
      case RecordingState.idle:
        await notifier.startRecording();
      case RecordingState.recording:
        await notifier.stopAndProcess();
      case RecordingState.processing:
        break; // Disable button during processing
    }
  }
}

// ── Microphone button ─────────────────────────────────────────────────────────
class _MicrophoneButton extends StatelessWidget {
  final RecordingState state;
  final VoidCallback onTap;

  const _MicrophoneButton({required this.state, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isRecording = state == RecordingState.recording;
    final isProcessing = state == RecordingState.processing;

    return GestureDetector(
      onTap: isProcessing ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: 140,
        height: 140,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isRecording
              ? AppColors.recordingRed
              : isProcessing
                  ? AppColors.accentAmber
                  : AppColors.primary,
          boxShadow: [
            BoxShadow(
              color: (isRecording
                      ? AppColors.recordingRed
                      : AppColors.primary)
                  .withOpacity(0.4),
              blurRadius: isRecording ? 40 : 20,
              spreadRadius: isRecording ? 10 : 2,
            ),
          ],
        ),
        child: isProcessing
            ? const Center(
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 3,
                ),
              )
            : Icon(
                isRecording ? Icons.stop_rounded : Icons.mic_rounded,
                size: 64,
                color: Colors.white,
              ),
      )
          .animate(target: isRecording ? 1 : 0)
          .scaleXY(end: 1.08, duration: 600.ms, curve: Curves.easeInOut)
          .then()
          .scaleXY(end: 1.0, duration: 600.ms, curve: Curves.easeInOut),
    );
  }
}

class _RecordingStateLabel extends StatelessWidget {
  final RecordingState state;

  const _RecordingStateLabel({required this.state});

  @override
  Widget build(BuildContext context) => Text(
        switch (state) {
          RecordingState.idle => 'Toca para hablar',
          RecordingState.recording => 'Escuchando... toca para procesar',
          RecordingState.processing => 'Interpretando con IA...',
        },
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 14,
        ),
      );
}

// ── Transcript card ───────────────────────────────────────────────────────────
class _TranscriptCard extends StatelessWidget {
  final String transcript;

  const _TranscriptCard({required this.transcript});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface700,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.surface500),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.record_voice_over_rounded,
                    size: 14, color: AppColors.textMuted),
                const SizedBox(width: 6),
                Text(
                  'Transcripción',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '"$transcript"',
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 15,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.1, end: 0);
}

// ── Extracted order card ──────────────────────────────────────────────────────
class _ExtractedOrderCard extends StatelessWidget {
  final ExtractedOrder order;
  final VoidCallback onConfirm;
  final VoidCallback onDiscard;
  final bool isLoading;

  const _ExtractedOrderCard({
    required this.order,
    required this.onConfirm,
    required this.onDiscard,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surface800,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.primary.withOpacity(0.4), width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.auto_awesome_rounded,
                          size: 12, color: AppColors.primaryLight),
                      const SizedBox(width: 4),
                      const Text(
                        'IA detectó',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.primaryLight,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Text(
                  '${(order.confidence * 100).round()}% confianza',
                  style: TextStyle(
                    fontSize: 11,
                    color: order.confidence >= 0.8
                        ? AppColors.accentGreen
                        : AppColors.accentAmber,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Product info
            Text(
              order.productName,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (order.color != null) _Chip(order.color!, Icons.palette_outlined),
                if (order.size != null) _Chip('Talla ${order.size!}', Icons.straighten_rounded),
                _Chip('x${order.quantity}', Icons.inventory_2_outlined),
              ],
            ),
            const Divider(height: 24),
            // Customer & payment
            if (order.customerName != null)
              _InfoRow(Icons.person_outline_rounded, 'Cliente', order.customerName!),
            _InfoRow(
              Icons.payment_rounded,
              'Pago',
              order.paymentMethod.label,
            ),
            _InfoRow(
              Icons.flag_outlined,
              'Estado',
              order.status.label,
            ),
            if (order.notes != null) ...[
              const SizedBox(height: 4),
              _InfoRow(Icons.notes_rounded, 'Notas', order.notes!),
            ],
            const SizedBox(height: 20),
            // Action buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: isLoading ? null : onDiscard,
                    icon: const Icon(Icons.close_rounded, size: 18),
                    label: const Text('Descartar'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.accentRed,
                      side: const BorderSide(color: AppColors.accentRed),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: isLoading ? null : onConfirm,
                    icon: isLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check_rounded, size: 18),
                    label: Text(isLoading ? 'Guardando...' : 'Confirmar Pedido'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.15, end: 0);
}

class _Chip extends StatelessWidget {
  final String label;
  final IconData icon;

  const _Chip(this.label, this.icon);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.surface700,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.surface500),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: AppColors.textMuted),
            const SizedBox(width: 5),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      );
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow(this.icon, this.label, this.value);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Icon(icon, size: 14, color: AppColors.textMuted),
            const SizedBox(width: 8),
            Text('$label:', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(width: 6),
            Text(value, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14)),
          ],
        ),
      );
}

// ── Order feed panel ──────────────────────────────────────────────────────────
class _OrderFeedPanel extends StatelessWidget {
  final List<OrderModel> orders;

  const _OrderFeedPanel({required this.orders});

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surface800,
          border: Border(left: BorderSide(color: AppColors.surface600)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.receipt_long_rounded, size: 16, color: AppColors.textMuted),
                  const SizedBox(width: 8),
                  Text(
                    'Pedidos del Live (${orders.length})',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: orders.isEmpty
                  ? const Center(
                      child: Text(
                        'Sin pedidos aún.\nEmpieza grabando.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textMuted),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: orders.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (ctx, i) => _OrderFeedItem(order: orders[i]),
                    ),
            ),
          ],
        ),
      );
}

class _OrderFeedItem extends StatelessWidget {
  final OrderModel order;

  const _OrderFeedItem({required this.order});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface700,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    order.productName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: AppColors.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _StatusBadge(order.status),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${order.customerName} • ${order.paymentMethod.label}',
              style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
          ],
        ),
      ).animate().fadeIn(duration: 300.ms).slideX(begin: 0.1, end: 0);
}

class _StatusBadge extends StatelessWidget {
  final OrderStatus status;

  const _StatusBadge(this.status);

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      OrderStatus.confirmed => AppColors.accentGreen,
      OrderStatus.reserved => AppColors.accentAmber,
      OrderStatus.pending => AppColors.textMuted,
      _ => AppColors.textMuted,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        status.label,
        style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

// ── Live badge ────────────────────────────────────────────────────────────────
class _LiveBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.accentRed.withOpacity(0.15),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: AppColors.accentRed.withOpacity(0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: AppColors.accentRed,
                shape: BoxShape.circle,
              ),
            )
                .animate(onPlay: (c) => c.repeat())
                .fadeIn(duration: 500.ms)
                .then()
                .fadeOut(duration: 500.ms),
            const SizedBox(width: 5),
            const Text(
              'LIVE',
              style: TextStyle(
                fontSize: 10,
                color: AppColors.accentRed,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      );
}

// ── Error banner ──────────────────────────────────────────────────────────────
class _ErrorBanner extends StatelessWidget {
  final String message;

  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.accentRed.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.accentRed.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline_rounded,
                color: AppColors.accentRed, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: AppColors.accentRed, fontSize: 13),
              ),
            ),
          ],
        ),
      );
}

// ── Quick commands hint ────────────────────────────────────────────────────────
class _QuickCommandsHint extends StatelessWidget {
  const _QuickCommandsHint();

  static const _examples = [
    '"Vende una camisa negra talla M para Ana"',
    '"Dos jeans azul 32 para Carlos, contra entrega"',
    '"Reserva un bolso rosado para María"',
  ];

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text(
            'Ejemplos de comandos',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 12),
          ..._examples.map(
            (e) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.surface700,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  e,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ),
          ),
        ],
      );
}
