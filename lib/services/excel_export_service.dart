import 'dart:io';
import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/borrower.dart';
import '../models/loan.dart';
import '../models/payment.dart';
import '../utils/date_parser.dart';

class ExcelExportService {
  static Future<void> _requestStoragePermission() async {
    if (!Platform.isAndroid) return;

    final sdkInt = await _getAndroidSdkInt();
    final status = sdkInt >= 30
        ? await Permission.manageExternalStorage.request()
        : await Permission.storage.request();
    if (!status.isGranted) {
      throw Exception('Storage permission denied. Cannot save file.');
    }
  }

  /// Exports a single borrower's full report (all loans + payments) as Excel.
  /// Returns the saved file path or throws on failure.
  static Future<String> exportBorrowerReport({
    required Borrower borrower,
    required List<Loan> loans,
    required Map<int, List<Payment>> paymentsPerLoan,
  }) async {
    await _requestStoragePermission();

    final excel = Excel.createExcel();

    // ── Sheet 1: Borrower Summary ────────────────────────────────
    final summarySheet = excel['Borrower Info'];
    excel.setDefaultSheet('Borrower Info');

    _addHeaderRow(summarySheet, ['Field', 'Value']);
    _addRow(summarySheet, ['Unique ID', borrower.borrowerCode]);
    _addRow(summarySheet, ['Name', borrower.name]);
    _addRow(summarySheet, ['Phone', borrower.phone]);
    _addRow(summarySheet, ['Address', borrower.address ?? '-']);
    _addRow(summarySheet, ['Notes', borrower.notes ?? '-']);

    double totalLoan = 0, totalInterest = 0, totalDue = 0, totalPaid = 0;
    for (final l in loans) {
      final paid =
          paymentsPerLoan[l.id]?.fold<double>(0.0, (s, p) => s + p.amount) ??
              0.0;
      totalLoan += l.loanAmount;
      totalInterest += l.interestAmount;
      totalDue += l.totalDue();
      totalPaid += paid;
    }
    final totalBalance = totalDue - totalPaid;

    summarySheet.appendRow([TextCellValue('')]);
    _addHeaderRow(summarySheet, ['Summary', 'Amount (₹)']);
    _addRow(summarySheet, ['Total Loans Given', totalLoan.toStringAsFixed(2)]);
    _addRow(summarySheet, ['Total Interest', totalInterest.toStringAsFixed(2)]);
    _addRow(summarySheet, ['Total Due', totalDue.toStringAsFixed(2)]);
    _addRow(summarySheet, ['Total Paid', totalPaid.toStringAsFixed(2)]);
    _addRow(summarySheet, ['Pending Balance', totalBalance.toStringAsFixed(2)]);

    // ── Sheet 2: Loan History ────────────────────────────────────
    final loanSheet = excel['Loan History'];
    _addHeaderRow(loanSheet, [
      'Loan #',
      'Loan Date',
      'Principal (₹)',
      'Interest (₹)',
      'Total Due (₹)',
      'Total Paid (₹)',
      'Balance (₹)',
      'Status',
    ]);

    for (int i = 0; i < loans.length; i++) {
      final l = loans[i];
      final payments = paymentsPerLoan[l.id] ?? [];
      final paid = payments.fold<double>(0.0, (s, p) => s + p.amount);
      final balance = l.totalDue() - paid;

      _addRow(loanSheet, [
        (i + 1).toString(),
        DateFormat('dd/MM/yyyy').format(l.loanDate),
        l.loanAmount.toStringAsFixed(2),
        l.interestAmount.toStringAsFixed(2),
        l.totalDue().toStringAsFixed(2),
        paid.toStringAsFixed(2),
        balance.toStringAsFixed(2),
        l.status.toUpperCase(),
      ]);
    }

    // ── Sheet 3: Payment History ─────────────────────────────────
    final paymentSheet = excel['Payment History'];
    _addHeaderRow(paymentSheet, [
      'Loan #',
      'Loan Date',
      'Payment Date',
      'Amount Paid (₹)',
      'Notes',
    ]);

    for (int i = 0; i < loans.length; i++) {
      final l = loans[i];
      // Sort payments oldest → newest
      final payments = (paymentsPerLoan[l.id] ?? [])
        ..sort((a, b) => a.paymentDate.compareTo(b.paymentDate));
      for (final p in payments) {
        _addRow(paymentSheet, [
          (i + 1).toString(),
          DateFormat('dd/MM/yyyy').format(l.loanDate),
          DateFormat('dd/MM/yyyy').format(p.paymentDate),
          p.amount.toStringAsFixed(2),
          p.notes ?? '-',
        ]);
      }
    }

    // Remove default empty sheet
    excel.delete('Sheet1');

    final bytes = excel.encode();
    if (bytes == null) throw Exception('Failed to encode Excel file.');
    final fileName =
        'Borrower_${borrower.borrowerCode}_${borrower.name.replaceAll(' ', '_')}_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.xlsx';

    // ── Save File ────────────────────────────────────────────────
    final dir = await _getSaveDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  static void _addHeaderRow(Sheet sheet, List<String> headers) {
    sheet.appendRow(headers.map((h) => TextCellValue(h)).toList());
  }

  static void _addRow(Sheet sheet, List<String> values) {
    sheet.appendRow(values.map((v) => TextCellValue(v)).toList());
  }

  static Future<Directory> _getSaveDirectory() async {
    if (Platform.isAndroid) {
      // Save to Downloads on Android
      final dir = Directory('/storage/emulated/0/Download/LoanReports');
      if (!await dir.exists()) await dir.create(recursive: true);
      return dir;
    } else {
      return await getApplicationDocumentsDirectory();
    }
  }

  static Future<int> _getAndroidSdkInt() async {
    try {
      final result = await Process.run('getprop', ['ro.build.version.sdk']);
      return int.tryParse(result.stdout.toString().trim()) ?? 29;
    } catch (_) {
      return 29;
    }
  }

  /// Exports a single loan's summary and payment history as Excel.
  static Future<String> exportLoanReport({
    required Borrower borrower,
    required Loan loan,
    required List<Payment> payments,
  }) async {
    await _requestStoragePermission();

    final excel = Excel.createExcel();

    // ── Sheet 1: Loan Summary ────────────────────────────────────
    final summarySheet = excel['Loan Summary'];
    excel.setDefaultSheet('Loan Summary');

    final totalPaid = payments.fold<double>(0.0, (s, p) => s + p.amount);
    final balance = loan.totalDue() - totalPaid;

    _addHeaderRow(summarySheet, ['Field', 'Value']);
    _addRow(summarySheet, ['Borrower Name', borrower.name]);
    _addRow(summarySheet, ['Borrower ID', borrower.borrowerCode]);
    _addRow(summarySheet, ['Phone', borrower.phone]);
    summarySheet.appendRow([TextCellValue('')]);
    _addHeaderRow(summarySheet, ['Loan Detail', 'Amount (₹)']);
    _addRow(summarySheet,
        ['Loan Date', DateFormat('dd/MM/yyyy').format(loan.loanDate)]);
    _addRow(summarySheet, ['Principal', loan.loanAmount.toStringAsFixed(2)]);
    _addRow(summarySheet, ['Interest', loan.interestAmount.toStringAsFixed(2)]);
    _addRow(summarySheet, ['Total Due', loan.totalDue().toStringAsFixed(2)]);
    _addRow(summarySheet, ['Total Paid', totalPaid.toStringAsFixed(2)]);
    _addRow(summarySheet, ['Balance', balance.toStringAsFixed(2)]);
    _addRow(summarySheet, ['Status', loan.status.toUpperCase()]);
    if (loan.notes != null && loan.notes!.isNotEmpty) {
      _addRow(summarySheet, ['Notes', loan.notes!]);
    }

    // ── Sheet 2: Payment History ─────────────────────────────────
    final paymentSheet = excel['Payment History'];
    _addHeaderRow(
        paymentSheet, ['#', 'Payment Date', 'Amount Paid (₹)', 'Notes']);
    // Sort oldest → newest
    final sortedPayments = List<Payment>.from(payments)
      ..sort((a, b) => a.paymentDate.compareTo(b.paymentDate));
    for (int i = 0; i < sortedPayments.length; i++) {
      final p = sortedPayments[i];
      _addRow(paymentSheet, [
        (i + 1).toString(),
        DateFormat('dd/MM/yyyy').format(p.paymentDate),
        p.amount.toStringAsFixed(2),
        p.notes ?? '-',
      ]);
    }

    excel.delete('Sheet1');

    final bytes = excel.encode();
    if (bytes == null) throw Exception('Failed to encode Excel file.');
    final fileName =
        'Loan_${borrower.borrowerCode}_${DateFormat('yyyyMMdd').format(loan.loanDate)}_${DateFormat('HHmm').format(DateTime.now())}.xlsx';

    final dir = await _getSaveDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  /// Exports an overall report for all borrowers, loans, and payments.
  static Future<String> exportOverallReport({
    required List<Borrower> borrowers,
    required Map<int, List<Loan>> loansPerBorrower,
    required Map<int, List<Payment>> paymentsPerLoan,
    required Map<String, dynamic> summary,
    required double totalInvested,
    required List<Map<String, dynamic>> expenses,
    required List<Map<String, dynamic>> serviceCosts,
  }) async {
    await _requestStoragePermission();

    final excel = Excel.createExcel();
    final now = DateTime.now();

    final totalLoanedEver = (summary['totalLoaned'] as num?)?.toDouble() ?? 0.0;
    final totalCollectedEver =
        (summary['totalCollected'] as num?)?.toDouble() ?? 0.0;
    final totalDue = (summary['totalDue'] as num?)?.toDouble() ?? 0.0;
    final totalPending = (summary['totalPending'] as num?)?.toDouble() ?? 0.0;
    final activeCollected = totalDue - totalPending;
    final totalExpenses = expenses.fold<double>(0.0, (s, e) => s + ((e['amount'] as num?)?.toDouble() ?? 0.0));
    final totalServiceCosts = serviceCosts.fold<double>(0.0, (s, sc) => s + ((sc['amount'] as num?)?.toDouble() ?? 0.0));
    final onHand = totalInvested - totalLoanedEver + totalCollectedEver - totalExpenses + totalServiceCosts;

    final summarySheet = excel['Overall Summary'];
    excel.setDefaultSheet('Overall Summary');
    _addHeaderRow(summarySheet, ['Field', 'Value']);
    _addRow(summarySheet,
        ['Report Date', DateFormat('dd/MM/yyyy HH:mm').format(now)]);
    _addRow(summarySheet, ['Total Borrowers', borrowers.length.toString()]);
    _addRow(summarySheet, ['Total Invested', totalInvested.toStringAsFixed(2)]);
    _addRow(summarySheet,
        ['Total Loaned Ever', totalLoanedEver.toStringAsFixed(2)]);
    _addRow(summarySheet,
        ['Total Collected Ever', totalCollectedEver.toStringAsFixed(2)]);
    _addRow(summarySheet, ['Total Service Costs', totalServiceCosts.toStringAsFixed(2)]);
    _addRow(summarySheet, ['On Hand', onHand.toStringAsFixed(2)]);
    summarySheet.appendRow([TextCellValue('')]);
    _addHeaderRow(summarySheet, ['Active Loans', 'Amount']);
    _addRow(summarySheet, ['To Recover', totalDue.toStringAsFixed(2)]);
    _addRow(summarySheet, ['Collected', activeCollected.toStringAsFixed(2)]);
    _addRow(summarySheet, ['Pending', totalPending.toStringAsFixed(2)]);

    final borrowerSheet = excel['Borrowers'];
    _addHeaderRow(borrowerSheet, [
      'Borrower ID',
      'Name',
      'Phone',
      'Active Loans',
      'Principal',
      'Interest',
      'To Recover',
      'Collected',
      'Pending',
      'Loan Age (Days)',
      'Overdue Status',
    ]);

    for (final borrower in borrowers) {
      final loans = loansPerBorrower[borrower.id] ?? [];
      final activeLoans = loans.where((l) => l.status == 'active').toList();
      double principal = 0;
      double interest = 0;
      double due = 0;
      double paid = 0;

      for (final loan in activeLoans) {
        final loanPaid = paymentsPerLoan[loan.id]
                ?.fold<double>(0.0, (sum, p) => sum + p.amount) ??
            0.0;
        principal += loan.loanAmount;
        interest += loan.interestAmount;
        due += loan.totalDue();
        paid += loanPaid;
      }

      _addRow(borrowerSheet, [
        borrower.borrowerCode,
        borrower.name,
        borrower.phone,
        activeLoans.length.toString(),
        principal.toStringAsFixed(2),
        interest.toStringAsFixed(2),
        due.toStringAsFixed(2),
        paid.toStringAsFixed(2),
        (due - paid).toStringAsFixed(2),
        borrower.loanAgeDays.toString(),
        borrower.overdueStatus,
      ]);
    }

    final loanSheet = excel['Loans'];
    _addHeaderRow(loanSheet, [
      'Borrower ID',
      'Borrower Name',
      'Loan Date',
      'Principal',
      'Interest',
      'Total Due',
      'Total Paid',
      'Balance',
      'Status',
      'Notes',
    ]);

    for (final borrower in borrowers) {
      final loans = loansPerBorrower[borrower.id] ?? [];
      for (final loan in loans) {
        final paid = paymentsPerLoan[loan.id]
                ?.fold<double>(0.0, (sum, p) => sum + p.amount) ??
            0.0;
        _addRow(loanSheet, [
          borrower.borrowerCode,
          borrower.name,
          DateFormat('dd/MM/yyyy').format(loan.loanDate),
          loan.loanAmount.toStringAsFixed(2),
          loan.interestAmount.toStringAsFixed(2),
          loan.totalDue().toStringAsFixed(2),
          paid.toStringAsFixed(2),
          (loan.totalDue() - paid).toStringAsFixed(2),
          loan.status.toUpperCase(),
          loan.notes ?? '-',
        ]);
      }
    }

    final paymentSheet = excel['Payments'];
    _addHeaderRow(paymentSheet, [
      'Borrower ID',
      'Borrower Name',
      'Loan Date',
      'Payment Date',
      'Amount Paid',
      'Notes',
    ]);

    for (final borrower in borrowers) {
      final loans = loansPerBorrower[borrower.id] ?? [];
      for (final loan in loans) {
        final payments = List<Payment>.from(paymentsPerLoan[loan.id] ?? [])
          ..sort((a, b) => a.paymentDate.compareTo(b.paymentDate));
        for (final payment in payments) {
          _addRow(paymentSheet, [
            borrower.borrowerCode,
            borrower.name,
            DateFormat('dd/MM/yyyy').format(loan.loanDate),
            DateFormat('dd/MM/yyyy').format(payment.paymentDate),
            payment.amount.toStringAsFixed(2),
            payment.notes ?? '-',
          ]);
        }
      }
    }

    final expenseSheet = excel['Expense History'];
    _addHeaderRow(expenseSheet, [
      'Date',
      'Amount (₹)',
      'Category',
      'Notes',
    ]);

    final sortedExpenses = List<Map<String, dynamic>>.from(expenses)
      ..sort((a, b) => (a['expense_date'] as String).compareTo(b['expense_date'] as String));

    for (final expense in sortedExpenses) {
      final dateStr = expense['expense_date']?.toString() ?? '';
      final d = DateParser.safeParse(dateStr);
      
      _addRow(expenseSheet, [
        DateFormat('dd/MM/yyyy HH:mm').format(d),
        (expense['amount'] as num).toDouble().toStringAsFixed(2),
        expense['category']?.toString() ?? '-',
        expense['notes']?.toString() ?? '-',
      ]);
    }

    final serviceCostsSheet = excel['SERVICE_COSTS'];
    _addHeaderRow(serviceCostsSheet, [
      'Date',
      'Amount (₹)',
      'Description',
      'Created By',
    ]);

    final sortedServiceCosts = List<Map<String, dynamic>>.from(serviceCosts)
      ..sort((a, b) => (a['dateCreated'] as String).compareTo(b['dateCreated'] as String));

    for (final sc in sortedServiceCosts) {
      final dateStr = sc['dateCreated']?.toString() ?? '';
      final d = DateParser.safeParse(dateStr);
      
      _addRow(serviceCostsSheet, [
        DateFormat('dd/MM/yyyy HH:mm').format(d),
        (sc['amount'] as num).toDouble().toStringAsFixed(2),
        sc['description']?.toString() ?? '-',
        sc['createdBy']?.toString() ?? '-',
      ]);
    }

    excel.delete('Sheet1');

    final bytes = excel.encode();
    if (bytes == null) throw Exception('Failed to encode Excel file.');
    final fileName =
        'Credits_Overall_Report_${DateFormat('yyyyMMdd_HHmm').format(now)}.xlsx';

    final dir = await _getSaveDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes);
    return file.path;
  }
}

