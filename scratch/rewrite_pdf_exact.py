import os

file_path = r'd:\vscode\credit\lib\services\borrower_pdf_service.dart'

content = """import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:screenshot/screenshot.dart';

import '../models/borrower.dart';

class BorrowerPdfService {
  static const double _pageWidth = 1200;
  static const double _pageHeight = 1698;
  static const int _paymentsPerPageFirst = 15;
  static const int _paymentsPerPageNext = 25;

  static const Color _brand = Color(0xFF133629); // Dark Green
  static const Color _textDark = Color(0xFF1E293B);
  static const Color _divider = Color(0xFFE2E8F0);
  static const Color _bg = Colors.white;

  static Future<Uint8List> generate({
    required BuildContext context,
    required Borrower borrower,
    required List<Map<String, dynamic>> allPayments,
    required double totalPaid,
    required double balanceToPay,
  }) async {
    final pdf = pw.Document();
    final screenshotController = ScreenshotController();

    // Reverse payments so they are in chronological order (Oldest first) 
    // This makes S.No 1 be the first payment ever made, exactly like the image.
    final List<Map<String, dynamic>> chronoPayments = List.from(allPayments.reversed);

    final List<List<Map<String, dynamic>>> pages = [];
    int startIndex = 0;
    
    if (chronoPayments.isNotEmpty) {
      final firstPageCount = chronoPayments.length > _paymentsPerPageFirst ? _paymentsPerPageFirst : chronoPayments.length;
      pages.add(chronoPayments.sublist(0, firstPageCount));
      startIndex = firstPageCount;
    } else {
      pages.add([]);
    }

    while (startIndex < chronoPayments.length) {
      final remaining = chronoPayments.length - startIndex;
      final count = remaining > _paymentsPerPageNext ? _paymentsPerPageNext : remaining;
      pages.add(chronoPayments.sublist(startIndex, startIndex + count));
      startIndex += count;
    }

    int globalPaymentOffset = 0;
    for (int i = 0; i < pages.length; i++) {
      final isFirstPage = i == 0;
      final pagePayments = pages[i];
      
      final Widget pageWidget = _buildPageWidget(
        borrower: borrower,
        pagePayments: pagePayments,
        totalPaid: totalPaid,
        balanceToPay: balanceToPay,
        isFirstPage: isFirstPage,
        pageIndex: i,
        totalPages: pages.length,
        globalPaymentOffset: globalPaymentOffset,
      );

      final Uint8List imageBytes = await screenshotController.captureFromWidget(
        pageWidget,
        delay: const Duration(milliseconds: 100),
        pixelRatio: 2.0,
        context: context,
      );

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.zero,
          build: (pw.Context ctx) {
            return pw.FullPage(
              ignoreMargins: true,
              child: pw.Image(pw.MemoryImage(imageBytes), fit: pw.BoxFit.fill),
            );
          },
        ),
      );

      globalPaymentOffset += pagePayments.length;
    }

    return pdf.save();
  }

  static Widget _buildPageWidget({
    required Borrower borrower,
    required List<Map<String, dynamic>> pagePayments,
    required double totalPaid,
    required double balanceToPay,
    required bool isFirstPage,
    required int pageIndex,
    required int totalPages,
    required int globalPaymentOffset,
  }) {
    final todayStr = DateFormat('dd-MM-yyyy').format(DateTime.now());

    return Directionality(
      textDirection: ui.TextDirection.ltr,
      child: Container(
        width: _pageWidth,
        height: _pageHeight,
        color: _bg,
        child: Column(
          children: [
            // Top Dark Green Strip
            Container(height: 16, color: _brand),
            
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header Row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'STATEMENT',
                          style: TextStyle(color: _brand, fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 1.5),
                        ),
                        Text(
                          'தேதி: $todayStr',
                          style: const TextStyle(color: Color(0xFF475569), fontSize: 24, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 30),

                    if (isFirstPage) ...[
                      // Borrower Details Box
                      _buildBorrowerDetails(borrower, totalPaid, balanceToPay),
                      const SizedBox(height: 40),
                      
                      const Text(
                        'கட்டண விவரம்',
                        style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: _textDark),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Payment Table
                    _buildPaymentTable(pagePayments, globalPaymentOffset),
                    
                    const Spacer(),
                    
                    if (totalPages > 1) ...[
                       const Divider(color: _divider, thickness: 2),
                       const SizedBox(height: 10),
                       Center(
                         child: Text(
                           'Page ${pageIndex + 1} of $totalPages', 
                           style: const TextStyle(color: Colors.grey, fontSize: 18)
                         )
                       ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _buildBorrowerDetails(Borrower borrower, double totalPaid, double balanceToPay) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _divider, width: 2),
      ),
      padding: const EdgeInsets.all(30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${borrower.name} (${borrower.displayBorrowerCode})',
            style: const TextStyle(color: _brand, fontSize: 32, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Text(
            'தொலைபேசி: ${borrower.phone}',
            style: const TextStyle(color: Color(0xFF64748B), fontSize: 22),
          ),
          const SizedBox(height: 30),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF4), // Light Green
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFBBF7D0), width: 2),
                  ),
                  child: Text(
                    'செலுத்திய தொகை: ₹${totalPaid.toStringAsFixed(0)}',
                    style: const TextStyle(color: Color(0xFF166534), fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2), // Light Red
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFECACA), width: 2),
                  ),
                  child: Text(
                    'மீதமுள்ள தொகை: ₹${balanceToPay.toStringAsFixed(0)}',
                    style: const TextStyle(color: Color(0xFF991B1B), fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static Widget _buildPaymentTable(List<Map<String, dynamic>> payments, int globalOffset) {
    if (payments.isEmpty) {
      return Container(
        decoration: BoxDecoration(border: Border.all(color: _divider, width: 2), borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.all(30),
        child: const Center(
          child: Text('கட்டண விவரங்கள் எதுவும் இல்லை. (No payments yet)', style: TextStyle(color: Colors.grey, fontSize: 22, fontStyle: FontStyle.italic)),
        ),
      );
    }

    return Column(
      children: [
        // Header
        Container(
          decoration: const BoxDecoration(
            color: _brand,
            borderRadius: BorderRadius.only(topLeft: Radius.circular(8), topRight: Radius.circular(8)),
          ),
          child: Row(
            children: [
              _cell('வ.எண்', isHeader: true, flex: 1, align: Alignment.center),
              _cell('தேதி', isHeader: true, flex: 3, align: Alignment.center),
              _cell('தொகை (₹)', isHeader: true, flex: 2, align: Alignment.centerRight),
            ],
          ),
        ),
        // Rows
        ...List.generate(payments.length, (i) {
          final payment = payments[i];
          final isEven = i % 2 == 0;
          final dateStr = DateFormat('dd-MM-yyyy').format(payment['date'] as DateTime);
          final amtStr = '₹ ${(payment['amount'] as num).toStringAsFixed(0)}';
          final sNo = globalOffset + i + 1;
          final isLast = i == payments.length - 1;

          return Container(
            decoration: BoxDecoration(
              color: isEven ? Colors.white : const Color(0xFFF8FAFC),
              border: Border(
                left: const BorderSide(color: _divider, width: 2),
                right: const BorderSide(color: _divider, width: 2),
                bottom: BorderSide(color: _divider, width: isLast ? 2 : 1),
              ),
              borderRadius: isLast ? const BorderRadius.only(bottomLeft: Radius.circular(8), bottomRight: Radius.circular(8)) : null,
            ),
            child: Row(
              children: [
                _cell('$sNo', flex: 1, align: Alignment.center),
                _cell(dateStr, flex: 3, align: Alignment.center),
                _cell(amtStr, flex: 2, align: Alignment.centerRight),
              ],
            ),
          );
        }),
      ],
    );
  }

  static Widget _cell(String text, {int flex = 1, bool isHeader = false, Alignment align = Alignment.centerLeft}) {
    return Expanded(
      flex: flex,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
        alignment: align,
        child: Text(
          text,
          style: TextStyle(
            color: isHeader ? Colors.white : _textDark,
            fontSize: isHeader ? 20 : 20,
            fontWeight: isHeader ? FontWeight.bold : FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
"""

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)
