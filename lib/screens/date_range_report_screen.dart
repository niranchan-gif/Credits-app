import 'dart:io';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';

import '../database/db_helper.dart';
import '../utils/app_colors.dart';
import '../utils/fmt.dart';
import '../widgets/premium_card.dart';
import '../services/excel_export_service.dart';
import '../utils/actions.dart';

class DateRangeReportScreen extends StatefulWidget {
  const DateRangeReportScreen({super.key});

  @override
  State<DateRangeReportScreen> createState() => _DateRangeReportScreenState();
}

class _DateRangeReportScreenState extends State<DateRangeReportScreen> with SingleTickerProviderStateMixin {
  DateTimeRange? _selectedRange;
  bool _loading = false;
  bool _exporting = false;
  
  double _totalLent = 0.0;
  double _totalCollected = 0.0;
  double _totalExpenses = 0.0;
  List<Map<String, dynamic>> _transactions = [];
  List<Map<String, dynamic>> _newBorrowers = [];
  List<Map<String, dynamic>> _closedLoans = [];

  TabController? _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    
    // Default to last 30 days
    final now = DateTime.now();
    _selectedRange = DateTimeRange(
      start: now.subtract(const Duration(days: 30)),
      end: now,
    );
    _loadReport();
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  Future<void> _loadReport() async {
    if (_selectedRange == null) return;
    setState(() => _loading = true);
    try {
      final data = await DBHelper().getDateRangeReport(_selectedRange!.start, _selectedRange!.end);
      if (mounted) {
        setState(() {
          _totalLent = data['totalLent'] as double;
          _totalCollected = data['totalCollected'] as double;
          _totalExpenses = data['totalExpenses'] as double;
          _transactions = List<Map<String, dynamic>>.from(data['transactions']);
          _newBorrowers = List<Map<String, dynamic>>.from(data['newBorrowers']);
          _closedLoans = List<Map<String, dynamic>>.from(data['closedLoans']);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _pickDateRange() async {
    final initialRange = _selectedRange ?? DateTimeRange(
      start: DateTime.now().subtract(const Duration(days: 30)),
      end: DateTime.now(),
    );
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: initialRange,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: AppColors.accent,
              onPrimary: AppColors.background,
            ),
          ),
          child: child!,
        );
      },
    );

    if (range != null && range != _selectedRange) {
      setState(() => _selectedRange = range);
      _loadReport();
    }
  }

  Future<void> _downloadReport() async {
    if (_selectedRange == null || _loading || _exporting) return;
    setState(() => _exporting = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final path = await ExcelExportService.exportDateRangeReport(
        start: _selectedRange!.start,
        end: _selectedRange!.end,
        totalLent: _totalLent,
        totalCollected: _totalCollected,
        totalExpenses: _totalExpenses,
        transactions: _transactions,
        newBorrowers: _newBorrowers,
        closedLoans: _closedLoans,
      );

      if (!mounted) return;
      showOpenFileSnackBar(
        messenger: messenger,
        path: path,
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text('Download failed: $e'),
        backgroundColor: AppColors.error,
      ));
    } finally {
      if (mounted) {
        setState(() => _exporting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd MMM yyyy');
    final dateRangeStr = _selectedRange != null
        ? '${df.format(_selectedRange!.start)} - ${df.format(_selectedRange!.end)}'
        : 'Select Date Range';

    final netCashFlow = _totalCollected - _totalLent - _totalExpenses;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text("Date Range Report"),
        actions: [
          IconButton(
            tooltip: 'Download Excel Report',
            onPressed: _loading || _exporting ? null : _downloadReport,
            icon: _exporting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent),
                  )
                : const Icon(LucideIcons.download),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // Date selector panel
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: InkWell(
              onTap: _pickDateRange,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.1)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(LucideIcons.calendar, color: AppColors.accent, size: 20),
                        const SizedBox(width: 12),
                        Text(
                          dateRangeStr,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ],
                    ),
                    const Icon(LucideIcons.chevronDown, color: AppColors.accent, size: 16),
                  ],
                ),
              ),
            ),
          ),
          
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator(color: AppColors.accent)))
          else ...[
            // Summary Dashboard Area
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Column(
                children: [
                  Row(
                    children: [
                      _statCard("Total Lent", fmtINR(_totalLent), LucideIcons.arrowUpRight, AppColors.warning),
                      const SizedBox(width: 12),
                      _statCard("Collected", fmtINR(_totalCollected), LucideIcons.arrowDownLeft, AppColors.success),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _statCard("Expenses", fmtINR(_totalExpenses), LucideIcons.receipt, AppColors.error),
                      const SizedBox(width: 12),
                      _statCard("Net Cash Flow", fmtINR(netCashFlow), LucideIcons.wallet, 
                          netCashFlow >= 0 ? AppColors.success : AppColors.error),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _statCard("New Borrowers", "${_newBorrowers.length}", LucideIcons.userPlus, AppColors.info),
                      const SizedBox(width: 12),
                      _statCard("Closed Loans", "${_closedLoans.length}", LucideIcons.checkSquare, AppColors.success),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            
            // Tab Selector
            TabBar(
              controller: _tabController,
              labelColor: AppColors.accent,
              unselectedLabelColor: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.6),
              indicatorColor: AppColors.accent,
              indicatorSize: TabBarIndicatorSize.tab,
              tabs: const [
                Tab(text: "Transactions"),
                Tab(text: "New Borrowers"),
                Tab(text: "Closed Loans"),
              ],
            ),
            
            // Tab Content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildTransactionsList(),
                  _buildNewBorrowersList(),
                  _buildClosedLoansList(),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: PremiumCard(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 16),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      value,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 10,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionsList() {
    if (_transactions.isEmpty) {
      return Center(
        child: Text(
          "No transactions recorded in this period",
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.5)),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
      itemCount: _transactions.length,
      itemBuilder: (context, index) {
        final tx = _transactions[index];
        final type = tx['type'] as String? ?? '';
        final amount = (tx['amount'] as num?)?.toDouble() ?? 0.0;
        final dateStr = tx['date'] as String? ?? '';
        final borrowerName = tx['borrower_name'] as String? ?? '';
        String borrowerCode = tx['borrower_code'] as String? ?? '';
        if (borrowerCode.contains('_del_')) {
          borrowerCode = borrowerCode.split('_del_').first;
        }

        DateTime? date;
        try {
          date = DateTime.parse(dateStr);
        } catch (_) {}

        IconData icon;
        Color color;
        String sign;
        if (type == 'Lent') {
          icon = LucideIcons.arrowUpRight;
          color = AppColors.warning;
          sign = "-";
        } else if (type == 'Collected') {
          icon = LucideIcons.arrowDownLeft;
          color = AppColors.success;
          sign = "+";
        } else {
          icon = LucideIcons.receipt;
          color = AppColors.error;
          sign = "-";
        }

        final df = DateFormat('dd MMM, hh:mm a');

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          child: PremiumCard(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 16),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (borrowerCode.isNotEmpty) ...[
                            Text(
                              "[$borrowerCode] ",
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.accent),
                            ),
                          ],
                          Expanded(
                            child: Text(
                              borrowerName,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        date != null ? df.format(date) : dateStr,
                        style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.7)),
                      ),
                    ],
                  ),
                ),
                Text(
                  "$sign${fmtINR(amount)}",
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildNewBorrowersList() {
    if (_newBorrowers.isEmpty) {
      return Center(
        child: Text(
          "No new borrowers added in this period",
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.5)),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
      itemCount: _newBorrowers.length,
      itemBuilder: (context, index) {
        final b = _newBorrowers[index];
        final name = b['name'] as String? ?? '';
        final code = b['borrower_code'] as String? ?? '';
        final phone = b['phone'] as String? ?? '';
        final address = b['address'] as String? ?? '-';
        final addedEpoch = b['created_at'] as int? ?? 0;
        
        final addedDate = DateTime.fromMillisecondsSinceEpoch(addedEpoch);
        final df = DateFormat('dd MMM yyyy, hh:mm a');

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          child: PremiumCard(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.accent.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            code,
                            style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.bold, fontSize: 11),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          name,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ],
                    ),
                    Text(
                      df.format(addedDate),
                      style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.7)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(LucideIcons.phone, size: 12, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text(phone.isNotEmpty ? phone : '-', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                    const SizedBox(width: 16),
                    const Icon(LucideIcons.mapPin, size: 12, color: Colors.grey),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        address,
                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildClosedLoansList() {
    if (_closedLoans.isEmpty) {
      return Center(
        child: Text(
          "No loans completed/closed in this period",
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.5)),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
      itemCount: _closedLoans.length,
      itemBuilder: (context, index) {
        final l = _closedLoans[index];
        final name = l['borrower_name'] as String? ?? '';
        final code = l['borrower_code'] as String? ?? '';
        final principal = (l['loan_amount'] as num?)?.toDouble() ?? 0.0;
        final interest = (l['interest_amount'] as num?)?.toDouble() ?? 0.0;
        final endStr = l['end_date'] as String? ?? '';
        
        DateTime? dateCleared;
        try {
          dateCleared = DateTime.parse(endStr);
        } catch (_) {}
        final df = DateFormat('dd MMM yyyy, hh:mm a');

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          child: PremiumCard(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.success.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            code,
                            style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.bold, fontSize: 11),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          name,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ],
                    ),
                    Text(
                      dateCleared != null ? df.format(dateCleared) : endStr,
                      style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.7)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Principal: ${fmtINR(principal)}",
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                    Text(
                      "Interest: ${fmtINR(interest)}",
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                    Text(
                      "Total: ${fmtINR(principal + interest)}",
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.success),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
