import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:tiklive_sales/core/constants/app_constants.dart';
import 'package:tiklive_sales/shared/models/order_model.dart';

// ── System prompt for order extraction ────────────────────────────────────────
const _extractionSystemPrompt = '''
Eres un asistente especializado en procesar órdenes de ventas durante transmisiones en vivo de TikTok en Latinoamérica.
Tu tarea es extraer información de ventas de un texto transcrito en español y devolver ÚNICAMENTE un objeto JSON válido.

Extrae y devuelve exactamente estos campos:
{
  "product_name": "nombre del producto detectado (string requerido)",
  "color": "color detectado o null",
  "size": "talla detectada (S/M/L/XL/XXL/32/34/36/etc) o null",
  "quantity": número entero (por defecto 1),
  "customer_name": "nombre del cliente o null",
  "payment_method": "CASH | COD | TRANSFER | PENDING",
  "status": "CONFIRMED | RESERVED | PENDING",
  "notes": "notas adicionales o null",
  "confidence": número del 0.0 al 1.0 indicando tu certeza
}

Reglas de mapeo:
- payment_method: "contra entrega"/"COD"/"contra-entrega" → "COD"
  "efectivo"/"cash" → "CASH"
  "transferencia"/"Nequi"/"Bancolombia"/"Yappy"/"Sinpe" → "TRANSFER"
  cualquier otro → "PENDING"

- status: "reserva"/"reservar"/"aparta"/"apartar" → "RESERVED"
  "vende"/"vendido"/"confirma"/"confirmado"/"compra" → "CONFIRMED"
  cualquier otro → "PENDING"

Responde ÚNICAMENTE con el JSON, sin explicación, sin markdown, sin backticks.
''';

// ── System prompt for assistant queries ───────────────────────────────────────
String _buildAssistantSystemPrompt(Map<String, dynamic> context) => '''
Eres el asistente inteligente de TikLive Sales, una app de gestión de ventas en vivo para TikTok.
Responde en español de forma concisa y directa.
Contexto actual del negocio:
${jsonEncode(context)}

Responde preguntas sobre ventas, inventario y pedidos usando únicamente los datos del contexto.
Si no tienes la información exacta, dilo claramente.
''';

class AiService {
  final Dio _dio = Dio();

  // ── Extract order from voice transcript ────────────────────────────────────
  Future<ExtractedOrder?> extractOrderFromTranscript(String transcript) async {
    if (transcript.trim().isEmpty) return null;

    try {
      final response = await _dio.post(
        '${AppConstants.openAiBaseUrl}/chat/completions',
        data: {
          'model': AppConstants.chatModel,
          'messages': [
            {'role': 'system', 'content': _extractionSystemPrompt},
            {
              'role': 'user',
              'content': 'Transcripción: "$transcript"',
            },
          ],
          'temperature': 0.1, // Low temp for consistent structured extraction
          'max_tokens': 300,
          'response_format': {'type': 'json_object'},
        },
        options: Options(
          headers: {
            'Authorization': 'Bearer ${AppConstants.openAiKey}',
            'Content-Type': 'application/json',
          },
        ),
      );

      final content = (response.data['choices'] as List).first['message']['content'] as String;
      final json = jsonDecode(content) as Map<String, dynamic>;

      return ExtractedOrder(
        productName: json['product_name'] as String? ?? 'Producto sin identificar',
        color: json['color'] as String?,
        size: json['size'] as String?,
        quantity: (json['quantity'] as num?)?.toInt() ?? 1,
        customerName: json['customer_name'] as String?,
        paymentMethod: _parsePaymentMethod(json['payment_method'] as String?),
        status: _parseOrderStatus(json['status'] as String?),
        notes: json['notes'] as String?,
        rawTranscript: transcript,
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0.8,
      );
    } on DioException catch (e) {
      debugPrint('[AiService] Extraction error: ${e.response?.data}');
      return null;
    } catch (e) {
      debugPrint('[AiService] Parse error: $e');
      return null;
    }
  }

  // ── AI assistant for voice queries ─────────────────────────────────────────
  Future<String> askAssistant({
    required String query,
    required Map<String, dynamic> businessContext,
  }) async {
    try {
      final response = await _dio.post(
        '${AppConstants.openAiBaseUrl}/chat/completions',
        data: {
          'model': AppConstants.chatModel,
          'messages': [
            {
              'role': 'system',
              'content': _buildAssistantSystemPrompt(businessContext),
            },
            {'role': 'user', 'content': query},
          ],
          'temperature': 0.3,
          'max_tokens': 200,
        },
        options: Options(
          headers: {
            'Authorization': 'Bearer ${AppConstants.openAiKey}',
            'Content-Type': 'application/json',
          },
        ),
      );

      return (response.data['choices'] as List).first['message']['content'] as String;
    } on DioException catch (e) {
      debugPrint('[AiService] Assistant error: ${e.response?.data}');
      return 'Lo siento, no pude procesar tu consulta. Intenta de nuevo.';
    }
  }

  // ── TikTok comment analysis ─────────────────────────────────────────────────
  Future<bool> isPotentialOrder(String comment) async {
    // Fast heuristic — avoid unnecessary API calls
    final lowerComment = comment.toLowerCase();
    const orderKeywords = [
      'quiero', 'dame', 'compro', 'pido', 'pedido', 'reservo', 'uno', 'dos',
      'tres', 'talla', 'size', 'precio', 'cuanto', 'disponible',
    ];
    return orderKeywords.any(lowerComment.contains);
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  PaymentMethod _parsePaymentMethod(String? raw) => switch (raw?.toUpperCase()) {
        'CASH' => PaymentMethod.cash,
        'COD' => PaymentMethod.cod,
        'TRANSFER' => PaymentMethod.transfer,
        _ => PaymentMethod.pending,
      };

  OrderStatus _parseOrderStatus(String? raw) => switch (raw?.toUpperCase()) {
        'CONFIRMED' => OrderStatus.confirmed,
        'RESERVED' => OrderStatus.reserved,
        _ => OrderStatus.pending,
      };
}
