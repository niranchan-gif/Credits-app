import os

file_path = r'd:\vscode\credit\lib\services\borrower_pdf_service.dart'

content = """import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:screenshot/screenshot.dart';

import '../models/borrower.dart';

class BorrowerPdfService {
  // A4 dimensions at 72 PPI are 595 x 842.
  // We'll use a larger logical size with the same aspect ratio for crisp rendering.
  static const double _pageWidth = 1200;
  static const double _pageHeight = 1698; // 1200 * (842/595) = 1698.15
  static const int _paymentsPerPageFirst = 15;
  static const int _paymentsPerPageNext = 22;

  static const Color _brand = Color(0xFF1F4E46);
  static const Color _textDark = Color(0xFF1E293B);
  static const Color _divider = Color(0xFFE2E8F0);
  static const Color _bg = Color(0xFFF8FAFC);

  /// Generates the PDF by rendering Flutter widgets off-screen (which handles 
  /// complex text shaping like Tamil ligatures perfectly) and placing them as images.
  static Future<Uint8List> generate({
    required BuildContext context,
    required Borrower borrower,
    required List<Map<String, dynamic>> payments,
    required double totalPaid,
    required double balanceToPay,
  }) async {
    final pdf = pw.Document();
    final screenshotController = ScreenshotController();

    // Calculate pagination
    final List<List<Map<String, dynamic>>> pages = [];
    int startIndex = 0;
    
    // First page holds header + borrower details + some payments
    if (payments.isNotEmpty) {
      final firstPageCount = payments.length > _paymentsPerPageFirst ? _paymentsPerPageFirst : payments.length;
      pages.add(payments.sublist(0, firstPageCount));
      startIndex = firstPageCount;
    } else {
      pages.add([]);
    }

    // Subsequent pages
    while (startIndex < payments.length) {
      final remaining = payments.length - startIndex;
      final count = remaining > _paymentsPerPageNext ? _paymentsPerPageNext : remaining;
      pages.add(payments.sublist(startIndex, startIndex + count));
      startIndex += count;
    }

    // Render each page
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

      // Render to image
      final Uint8List imageBytes = await screenshotController.captureFromWidget(
        pageWidget,
        delay: const Duration(milliseconds: 100),
        pixelRatio: 2.0, // High res for sharp PDF
        context: context,
      );

      // Add to PDF
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
    final todayStr = DateFormat('dd MMM yyyy').format(DateTime.now());

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Container(
        width: _pageWidth,
        height: _pageHeight,
        color: _bg,
        child: Column(
          children: [
            // Header (only on first page, or repeated if preferred. We'll repeat a smaller version or the same)
            if (isFirstPage) _buildHeader(todayStr),
            if (!isFirstPage) _buildSmallHeader(borrower, pageIndex, totalPages),
            
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 30),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (isFirstPage) ...[
                      _buildBorrowerDetails(borrower, totalPaid, balanceToPay),
                      const SizedBox(height: 30),
                      Text(
                        'கட்டண வரலாறு (Payment History)',
                        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: _textDark),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Table
                    _buildPaymentTable(pagePayments, globalPaymentOffset),
                    
                    const Spacer(),
                    
                    // Footer
                    const Divider(color: _divider, thickness: 2),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Page ${pageIndex + 1} of $totalPages', style: const TextStyle(color: Colors.grey, fontSize: 18)),
                        const Text('Generated securely via offline system', style: TextStyle(color: Colors.grey, fontSize: 18)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _buildHeader(String todayStr) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: _brand, width: 8)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 25),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(color: _brand, borderRadius: BorderRadius.circular(12)),
                child: const Center(
                  child: Icon(Icons.account_balance_wallet, color: Colors.white, size: 35),
                ),
              ),
              const SizedBox(width: 20),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text('STATEMENT', style: TextStyle(color: _brand, fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 2)),
                  Text('கடன் அறிக்கை', style: TextStyle(color: Colors.grey, fontSize: 18)),
                ],
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text('Generated On', style: TextStyle(color: Colors.grey, fontSize: 16)),
              const SizedBox(height: 4),
              Text(todayStr, style: const TextStyle(color: _textDark, fontSize: 22, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }

  static Widget _buildSmallHeader(Borrower borrower, int pageIndex, int totalPages) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: _divider, width: 2)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('Statement - ${borrower.name}', style: const TextStyle(color: _textDark, fontSize: 24, fontWeight: FontWeight.bold)),
          Text('Page ${pageIndex + 1} of $totalPages', style: const TextStyle(color: Colors.grey, fontSize: 20)),
        ],
      ),
    );
  }

  static Widget _buildBorrowerDetails(Borrower borrower, double totalPaid, double balanceToPay) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _divider, width: 2),
      ),
      padding: const EdgeInsets.all(30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(borrower.name, style: const TextStyle(color: _textDark, fontSize: 38, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Icon(Icons.phone, size: 24, color: Colors.grey),
                        const SizedBox(width: 8),
                        Text(borrower.phone, style: const TextStyle(color: _textDark, fontSize: 22)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.location_on, size: 24, color: Colors.grey),
                        const SizedBox(width: 8),
                        Text(borrower.location.isEmpty ? 'N/A' : borrower.location, style: const TextStyle(color: _textDark, fontSize: 22)),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(color: _brand.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                child: Text(borrower.displayBorrowerCode, style: const TextStyle(color: _brand, fontSize: 28, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 30),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: const Color(0xFFF0FDF4), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFBBF7D0))),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Total Paid (செலுத்தியது)', style: TextStyle(color: Color(0xFF166534), fontSize: 18)),
                      const SizedBox(height: 8),
                      Text('₹ ${totalPaid.toStringAsFixed(0)}', style: const TextStyle(color: Color(0xFF166534), fontSize: 32, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: const Color(0xFFFEF2F2), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFFECACA))),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Balance (நிலுவை)', style: TextStyle(color: Color(0xFF991B1B), fontSize: 18)),
                      const SizedBox(height: 8),
                      Text('₹ ${balanceToPay.toStringAsFixed(0)}', style: const TextStyle(color: Color(0xFF991B1B), fontSize: 32, fontWeight: FontWeight.bold)),
                    ],
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
        decoration: BoxDecoration(border: Border.all(color: _divider, width: 2), borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.all(40),
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
            borderRadius: BorderRadius.only(topLeft: Radius.circular(12), topRight: Radius.circular(12)),
          ),
          child: Row(
            children: [
              _cell('வ.எண்', isHeader: true, flex: 1),
              _cell('தேதி (Date)', isHeader: true, flex: 3),
              _cell('தொகை (Amount)', isHeader: true, flex: 2, align: Alignment.centerRight),
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
              color: isEven ? Colors.white : const Color(0xFFF1F5F9),
              border: Border(
                left: const BorderSide(color: _divider, width: 2),
                right: const BorderSide(color: _divider, width: 2),
                bottom: BorderSide(color: _divider, width: isLast ? 2 : 1),
              ),
              borderRadius: isLast ? const BorderRadius.only(bottomLeft: Radius.circular(12), bottomRight: Radius.circular(12)) : null,
            ),
            child: Row(
              children: [
                _cell('$sNo', flex: 1),
                _cell(dateStr, flex: 3),
                _cell(amtStr, flex: 2, align: Alignment.centerRight, isBold: true),
              ],
            ),
          );
        }),
      ],
    );
  }

  static Widget _cell(String text, {int flex = 1, bool isHeader = false, Alignment align = Alignment.centerLeft, bool isBold = false}) {
    return Expanded(
      flex: flex,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
        alignment: align,
        child: Text(
          text,
          style: TextStyle(
            color: isHeader ? Colors.white : _textDark,
            fontSize: isHeader ? 22 : 24,
            fontWeight: isHeader || isBold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
"""

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)
