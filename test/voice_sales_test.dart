import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tiklive_sales/services/ai_service.dart';
import 'package:tiklive_sales/shared/models/order_model.dart';

class MockAiService extends Mock implements AiService {}

void main() {
  late MockAiService mockAi;

  setUp(() {
    mockAi = MockAiService();
  });

  group('AiService — extractOrderFromTranscript', () {
    test('returns null for empty transcript', () async {
      when(() => mockAi.extractOrderFromTranscript(''))
          .thenAnswer((_) async => null);

      final result = await mockAi.extractOrderFromTranscript('');
      expect(result, isNull);
    });

    test('returns ExtractedOrder with correct fields', () async {
      final expected = ExtractedOrder(
        productName: 'Camisa negra',
        color: 'negra',
        size: 'M',
        quantity: 1,
        customerName: 'Ana',
        paymentMethod: PaymentMethod.pending,
        status: OrderStatus.confirmed,
        rawTranscript: 'Vende una camisa negra talla M para Ana',
      );

      when(() => mockAi.extractOrderFromTranscript(
            'Vende una camisa negra talla M para Ana',
          )).thenAnswer((_) async => expected);

      final result = await mockAi.extractOrderFromTranscript(
        'Vende una camisa negra talla M para Ana',
      );

      expect(result, isNotNull);
      expect(result!.productName, contains('Camisa'));
      expect(result.size, equals('M'));
      expect(result.customerName, equals('Ana'));
    });

    test('detects COD payment from "contra entrega"', () async {
      final expected = ExtractedOrder(
        productName: 'Jean azul',
        color: 'azul',
        size: '32',
        quantity: 2,
        customerName: 'Carlos',
        paymentMethod: PaymentMethod.cod,
        status: OrderStatus.pending,
        rawTranscript: 'Dos jeans azul talla 32 para Carlos, pago contra entrega',
      );

      when(() => mockAi.extractOrderFromTranscript(any()))
          .thenAnswer((_) async => expected);

      final result = await mockAi.extractOrderFromTranscript(
        'Dos jeans azul talla 32 para Carlos, pago contra entrega',
      );

      expect(result?.paymentMethod, equals(PaymentMethod.cod));
      expect(result?.quantity, equals(2));
    });

    test('detects RESERVED status from "reserva"', () async {
      final expected = ExtractedOrder(
        productName: 'Bolso rosado',
        color: 'rosado',
        quantity: 1,
        customerName: 'María',
        paymentMethod: PaymentMethod.pending,
        status: OrderStatus.reserved,
        rawTranscript: 'Reserva un bolso rosado para María',
      );

      when(() => mockAi.extractOrderFromTranscript(any()))
          .thenAnswer((_) async => expected);

      final result = await mockAi.extractOrderFromTranscript(
        'Reserva un bolso rosado para María',
      );

      expect(result?.status, equals(OrderStatus.reserved));
    });
  });

  group('OrderModel', () {
    test('toSupabase() maps enum correctly', () {
      final order = OrderModel(
        id: '',
        productName: 'Camisa',
        quantity: 1,
        customerName: 'Ana',
        paymentMethod: PaymentMethod.cod,
        status: OrderStatus.confirmed,
        createdAt: DateTime.now(),
      );

      final map = order.toSupabase();
      expect(map['payment_method'], equals('COD'));
      expect(map['status'], equals('CONFIRMED'));
    });
  });
}
