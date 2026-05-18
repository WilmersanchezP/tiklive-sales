import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:tiklive_sales/shared/models/order_model.dart';

import 'web_download_stub.dart'
    if (dart.library.html) 'web_download_web.dart';

class ExportService {
  static final _dateFormat = DateFormat('dd/MM/yyyy HH:mm', 'es');
  static final _fileDate = DateFormat('yyyyMMdd_HHmm');

  // ── Excel export ─────────────────────────────────────────────────────────────
  Future<void> exportOrdersToExcel(
    List<OrderModel> orders, {
    String title = 'Ventas',
  }) async {
    final excel = Excel.createExcel();
    final sheet = excel['Pedidos'];

    final headers = [
      'Fecha', 'Producto', 'Color', 'Talla', 'Cantidad',
      'Cliente', 'Pago', 'Estado', 'Total', 'Notas',
    ];
    for (var i = 0; i < headers.length; i++) {
      final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
      cell.value = TextCellValue(headers[i]);
      cell.cellStyle = CellStyle(
        bold: true,
        backgroundColorHex: ExcelColor.fromHexString('#6366F1'),
        fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
      );
    }

    for (var i = 0; i < orders.length; i++) {
      final o = orders[i];
      final row = [
        _dateFormat.format(o.createdAt),
        o.productName,
        o.color ?? '',
        o.size ?? '',
        o.quantity.toString(),
        o.customerName,
        o.paymentMethod.label,
        o.status.label,
        o.totalPrice?.toStringAsFixed(2) ?? '',
        o.notes ?? '',
      ];
      for (var j = 0; j < row.length; j++) {
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: j, rowIndex: i + 1))
            .value = TextCellValue(row[j]);
      }
    }

    final bytes = excel.encode();
    if (bytes == null) return;

    await _download(
      Uint8List.fromList(bytes),
      fileName: 'tiklive_${title}_${_fileDate.format(DateTime.now())}.xlsx',
      mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
  }

  // ── PDF export ───────────────────────────────────────────────────────────────
  Future<void> exportOrdersToPdf(
    List<OrderModel> orders, {
    String title = 'Reporte de Ventas',
    String? sessionTitle,
  }) async {
    final doc = pw.Document();
    final now = DateTime.now();
    final totalRevenue = orders.fold<double>(
      0,
      (sum, o) => sum + (o.totalPrice ?? 0),
    );

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'TikLive Sales',
              style: pw.TextStyle(
                fontSize: 24,
                fontWeight: pw.FontWeight.bold,
                color: const PdfColor(0.39, 0.40, 0.95),
              ),
            ),
            pw.Text(title, style: const pw.TextStyle(fontSize: 16)),
            if (sessionTitle != null)
              pw.Text('Live: $sessionTitle',
                  style: const pw.TextStyle(fontSize: 12)),
            pw.Text(
              'Generado: ${_dateFormat.format(now)}',
              style: const pw.TextStyle(fontSize: 10),
            ),
            pw.Divider(),
          ],
        ),
        build: (context) => [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              _pdfStatBox('Total Pedidos', orders.length.toString()),
              _pdfStatBox('Ingresos', '\$${totalRevenue.toStringAsFixed(2)}'),
              _pdfStatBox(
                'Pendientes',
                orders.where((o) => o.status == OrderStatus.pending).length.toString(),
              ),
            ],
          ),
          pw.SizedBox(height: 16),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300),
            columnWidths: {
              0: const pw.FlexColumnWidth(2),
              1: const pw.FlexColumnWidth(1.5),
              2: const pw.FlexColumnWidth(1),
              3: const pw.FlexColumnWidth(1),
              4: const pw.FlexColumnWidth(1),
              5: const pw.FlexColumnWidth(1.5),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(
                  color: PdfColor(0.39, 0.40, 0.95),
                ),
                children: ['Producto', 'Cliente', 'Talla', 'Cant.', 'Pago', 'Estado']
                    .map((h) => pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text(
                            h,
                            style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.white,
                              fontSize: 9,
                            ),
                          ),
                        ))
                    .toList(),
              ),
              ...orders.map(
                (o) => pw.TableRow(
                  children: [
                    '${o.productName} ${o.color ?? ''}',
                    o.customerName,
                    '${o.size ?? '-'}',
                    '${o.quantity}',
                    o.paymentMethod.label,
                    o.status.label,
                  ]
                      .map((cell) => pw.Padding(
                            padding: const pw.EdgeInsets.all(5),
                            child: pw.Text(cell, style: const pw.TextStyle(fontSize: 8)),
                          ))
                      .toList(),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    final bytes = await doc.save();
    await _download(
      bytes,
      fileName: 'tiklive_${_fileDate.format(now)}.pdf',
      mimeType: 'application/pdf',
    );
  }

  // ── CSV export ───────────────────────────────────────────────────────────────
  Future<void> exportOrdersToCsv(List<OrderModel> orders) async {
    final buffer = StringBuffer();
    buffer.writeln('Fecha,Producto,Color,Talla,Cantidad,Cliente,Pago,Estado,Total');
    for (final o in orders) {
      buffer.writeln([
        _dateFormat.format(o.createdAt),
        '"${o.productName}"',
        o.color ?? '',
        o.size ?? '',
        o.quantity,
        '"${o.customerName}"',
        o.paymentMethod.label,
        o.status.label,
        o.totalPrice?.toStringAsFixed(2) ?? '',
      ].join(','));
    }

    await _download(
      Uint8List.fromList(utf8.encode(buffer.toString())),
      fileName: 'tiklive_${_fileDate.format(DateTime.now())}.csv',
      mimeType: 'text/csv; charset=utf-8',
    );
  }

  // ── Download helper ──────────────────────────────────────────────────────────
  Future<void> _download(
    Uint8List bytes, {
    required String fileName,
    required String mimeType,
  }) async {
    if (kIsWeb) {
      await triggerWebDownload(bytes, fileName, mimeType);
      return;
    }
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes);
    await Share.shareXFiles([XFile(file.path)], subject: fileName);
  }

  pw.Widget _pdfStatBox(String label, String value) => pw.Container(
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(
          color: const PdfColor(0.97, 0.97, 1.0),
          borderRadius: pw.BorderRadius.circular(6),
        ),
        child: pw.Column(
          children: [
            pw.Text(value,
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                )),
            pw.Text(label, style: const pw.TextStyle(fontSize: 9)),
          ],
        ),
      );
}
