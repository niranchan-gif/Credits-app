import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../database/db_helper.dart';
import '../services/backup_freshness_service.dart';
import '../models/borrower.dart';
import '../models/loan.dart';
import '../models/payment.dart';
import '../providers/loan_provider.dart';
import '../services/excel_export_service.dart';
import '../utils/actions.dart';
import '../utils/fmt.dart';
import '../utils/app_colors.dart';
import '../widgets/premium_card.dart';
import 'investment_screen.dart';
import 'on_hand_cash_screen.dart';
import 'completed_loans_screen.dart';
import 'date_range_report_screen.dart';

class ReportSummary {
  final Map<String, dynamic> globalSummary;
  final List<BorrowerReport> reports;
  final double totalInvested;
  final double totalExpenses;
  final double totalServiceCosts;

  ReportSummary({
    required this.globalSummary,
    required this.reports,
    required this.totalInvested,
    required this.totalExpenses,
    required this.totalServiceCosts,
  });
}

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  ReportSummary? _cachedSummary;
  bool _loading = true;
  bool _exporting = false;
  bool _isLoadingReports = false;
  bool _hasError = false;
  String _errorMessage = '';

  Map<String, dynamic>? get _summary => _cachedSummary?.globalSummary;
  List<BorrowerReport> get _reports => _cachedSummary?.reports ?? [];
  double get _totalInvested => _cachedSummary?.totalInvested ?? 0.0;
  double get _totalExpenses => _cachedSummary?.totalExpenses ?? 0.0;
  double get _totalServiceCosts => _cachedSummary?.totalServiceCosts ?? 0.0;

  @override
  void initState() {
    super.initState();
    _loadReports();
    // Invalidate and refresh cache dynamically whenever LoanProvider notifies changes
    context.read<LoanProvider>().addListener(_onProviderChanged);
  }

  @override
  void dispose() {
    try {
      context.read<LoanProvider>().removeListener(_onProviderChanged);
    } catch (_) {}
    super.dispose();
  }

  void _onProviderChanged() {
    if (mounted) {
      _loadReports(force: true);
    }
  }

  Future<void> _loadReports({bool force = false}) async {
    if (_isLoadingReports) return;
    if (_cachedSummary != null && !force) {
      setState(() {
        _loading = false;
        _hasError = false;
      });
      return;
    }

    setState(() {
      // Premium UI: Only show full-screen spinner if no cached data exists
      if (_cachedSummary == null) {
        _loading = true;
      }
      _hasError = false;
      _errorMessage = '';
      _isLoadingReports = true;
    });

    try {
      final summary = await _calculateSummary().timeout(const Duration(seconds: 10));
      if (mounted) {
        setState(() {
          _cachedSummary = summary;
          _loading = false;
          _isLoadingReports = false;
        });
      }
    } on TimeoutException catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _isLoadingReports = false;
          _hasError = true;
          _errorMessage = "Loading took too long. Please verify your database integrity.";
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _isLoadingReports = false;
          _hasError = true;
          _errorMessage = "Failed to load reports: $e";
        });
      }
    }
  }

  Future<ReportSummary> _calculateSummary() async {
    final dbHelper = DBHelper();
    
    // 1. Get global summary in one fast query
    final globalSummary = await dbHelper.getGlobalSummary();
    
    // 2. Get reports breakdown in one highly-optimized query
    final rawReports = await dbHelper.getReportsBreakdown();
    
    // 3. Get total invested, total expenses, and total service costs
    final totalInvested = await dbHelper.getTotalInvested();
    final totalExpenses = await dbHelper.getTotalExpenses();
    final totalServiceCosts = await dbHelper.getTotalServiceCosts();
    
    final reports = rawReports.map((map) {
      final borrower = Borrower.fromMap(map);
      return BorrowerReport(
        borrower: borrower,
        totalLoanAmount: (map['total_loan_amount'] as num).toDouble(),
        totalInterest: (map['total_interest_amount'] as num).toDouble(),
        totalDue: (map['total_due'] as num).toDouble(),
        totalPaid: (map['total_paid'] as num).toDouble(),
      );
    }).toList();
    
    // Sort reports by balance descending
    reports.sort((a, b) => b.balance.compareTo(a.balance));
    
    return ReportSummary(
      globalSummary: globalSummary,
      reports: reports,
      totalInvested: totalInvested,
      totalExpenses: totalExpenses,
      totalServiceCosts: totalServiceCosts,
    );
  }

  Future<void> _onRefresh() async {
    await BackupFreshnessService().checkFreshness();
    await _loadReports(force: true);
  }

  Future<void> _exportOverallExcel() async {
    if (_exporting) return;

    setState(() => _exporting = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final provider = context.read<LoanProvider>();
      await provider.loadBorrowers();
      final borrowers = provider.borrowers;
      final loansPerBorrower = <int, List<Loan>>{};
      final paymentsPerLoan = <int, List<Payment>>{};

      for (final borrower in borrowers) {
        final borrowerId = borrower.id;
        if (borrowerId == null) continue;
        final loans = await provider.getLoans(borrowerId);
        loansPerBorrower[borrowerId] = loans;
        for (final loan in loans) {
          final loanId = loan.id;
          if (loanId == null) continue;
          paymentsPerLoan[loanId] = await provider.getPayments(loanId);
        }
      }

      final summary = _cachedSummary?.globalSummary ?? provider.globalSummary;
      final totalInv = _cachedSummary?.totalInvested ?? await DBHelper().getTotalInvested();

      final path = await ExcelExportService.exportOverallReport(
        borrowers: borrowers,
        loansPerBorrower: loansPerBorrower,
        paymentsPerLoan: paymentsPerLoan,
        summary: summary,
        totalInvested: totalInv,
        expenses: await DBHelper().getAllExpenses(),
        serviceCosts: await DBHelper().getAllServiceCosts(),
      );

      if (!mounted) return;
      showOpenFileSnackBar(
        messenger: messenger,
        path: path,
      );
      await _loadReports(force: true);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text('Export failed: $e'),
        backgroundColor: AppColors.error,
      ));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          title: const Text('Financial Reports'),
        ),
        body: const Center(
          child: CircularProgressIndicator(color: AppColors.accent),
        ),
      );
    }

    if (_hasError) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          title: const Text('Financial Reports'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(LucideIcons.alertTriangle, color: AppColors.error, size: 48),
                const SizedBox(height: 16),
                Text(
                  _errorMessage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () => _loadReports(force: true),
                  icon: const Icon(LucideIcons.refreshCw, size: 16),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final totalLoanedEver = (_summary?['totalLoaned'] ?? 0.0) as double;
    final totalCollectedEver = (_summary?['totalCollected'] ?? 0.0) as double;

    final activeCollected = (_summary?['activePending'] != null
        ? ((_summary?['totalDue'] ?? 0.0) as double) -
            ((_summary?['totalPending'] ?? 0.0) as double)
        : totalCollectedEver);
    final totalBorrowers = _summary?['totalBorrowers'] ?? 0;

    final totalToRecover =
        _reports.fold<double>(0.0, (sum, r) => sum + r.totalDue);
    final totalPending = (_summary?['totalPending'] ?? 0.0) as double;

    final onHand = context.watch<LoanProvider>().onHand;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Financial Reports'),
        actions: [
          IconButton(
            tooltip: 'Download Excel',
            onPressed: _loading || _exporting ? null : _exportOverallExcel,
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
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
          : RefreshIndicator(
              onRefresh: _onRefresh,
              color: AppColors.accent,
              backgroundColor: Theme.of(context).colorScheme.surface,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 100),
                children: [
                  _buildHeaderSection(),
                  const SizedBox(height: 24),
                  
                  _buildStatRow(
                    _statCard('On Hand Cash', fmtINR(onHand), LucideIcons.home, 
                      onHand >= 0 ? AppColors.success : AppColors.error, 
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const OnHandCashScreen()),
                        );
                        if (mounted) _loadReports(force: true);
                      }),
                  ),
                  const SizedBox(height: 16),
                  
                  Row(
                    children: [
                      _statCard('Borrowers', '$totalBorrowers', LucideIcons.users, AppColors.info),
                      const SizedBox(width: 16),
                      _statCard('To Recover', fmtINR(totalToRecover), LucideIcons.coins, AppColors.warning),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  Row(
                    children: [
                      _statCard('Collected', fmtINR(activeCollected), LucideIcons.checkCircle, AppColors.success),
                      const SizedBox(width: 16),
                      _statCard('Pending', fmtINR(totalPending), LucideIcons.clock, AppColors.error),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  Row(
                    children: [
                      _statCard('Completed', fmtINR(totalCollectedEver), LucideIcons.checkSquare, AppColors.success, 
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const CompletedLoansScreen()),
                          );
                          if (mounted) _loadReports(force: true);
                        }),
                      const SizedBox(width: 16),
                      _statCard('Date Range', 'Select Period', LucideIcons.calendarRange, AppColors.secondary, 
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const DateRangeReportScreen()),
                          );
                          if (mounted) _loadReports(force: true);
                        }),
                    ],
                  ),
                  const SizedBox(height: 24),

                  if (onHand < 0 && _totalInvested > 0)
                    _buildWarningCard(totalLoanedEver),



                  _sectionLabel('Borrower Breakdown'),
                  const SizedBox(height: 16),
                  ..._reports.asMap().entries.map((entry) => 
                    _buildBorrowerReportCard(entry.value)
                      .animate()
                      .fadeIn(duration: 400.ms)
                      .slideX(begin: 0.1, end: 0)
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildHeaderSection() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _sectionLabel('Overall Summary'),
        TextButton.icon(
          onPressed: () async {
            await Navigator.push(context, MaterialPageRoute(builder: (_) => const InvestmentScreen()));
            if (mounted) await _loadReports(force: true);
          },
          icon: const Icon(LucideIcons.coins, size: 16),
          label: const Text('Investments'),
        ),
      ],
    );
  }

  Widget _buildWarningCard(double totalLoanedEver) {
    return PremiumCard(
      color: AppColors.error.withOpacity( 0.1),
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(16),
      borderRadius: 16,
      border: Border.all(color: AppColors.error.withOpacity( 0.3)),
      child: Row(
        children: [
          const Icon(LucideIcons.alertTriangle, color: AppColors.error, size: 24),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              'Over-deployed! You have lent ${fmtINR(totalLoanedEver)} but only ${fmtINR(_totalInvested)} is invested.',
              style: const TextStyle(color: AppColors.error, fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }


  Widget _sectionLabel(String label) {
    return Text(label, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Theme.of(context).colorScheme.onSurface));
  }

  Widget _statCard(String label, String value, IconData icon, Color color, {VoidCallback? onTap}) {
    return Expanded(
      child: PremiumCard(
        padding: EdgeInsets.zero,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: color.withOpacity( 0.1), borderRadius: BorderRadius.circular(12)),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(height: 16),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Theme.of(context).colorScheme.onSurface)),
                ),
                Text(label, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatRow(Widget card) {
    return Row(children: [card]);
  }

  Widget _buildBorrowerReportCard(BorrowerReport r) {
    final b = r.borrower;
    final progress = r.totalDue > 0 ? (r.totalPaid / r.totalDue).clamp(0.0, 1.0) : 0.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: PremiumCard(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: AppColors.accent.withOpacity( 0.1), borderRadius: BorderRadius.circular(8)),
                  child: Text(b.displayBorrowerCode, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.accent)),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(b.name, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Theme.of(context).colorScheme.onSurface))),
                Text(fmtINR(r.balance), style: TextStyle(color: r.balance > 0 ? AppColors.error : AppColors.success, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _miniStatItem('Principal', fmtINR(r.totalLoanAmount)),
                _miniStatItem('Interest', fmtINR(r.totalInterest)),
                _miniStatItem('Collected', fmtINR(r.totalPaid)),
              ],
            ),
            const SizedBox(height: 20),
            Stack(
              children: [
                Container(height: 6, decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(3))),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 1000),
                  height: 6,
                  width: (MediaQuery.of(context).size.width - 80) * progress,
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Progress', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity( 0.6), fontSize: 11)),
                Text('${(progress * 100).toStringAsFixed(0)}%', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 11, fontWeight: FontWeight.bold)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniStatItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity( 0.6))),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Theme.of(context).colorScheme.onSurface)),
      ],
    );
  }
}

class BorrowerReport {
  final Borrower borrower;
  final double totalLoanAmount;
  final double totalInterest;
  final double totalDue;
  final double totalPaid;

  BorrowerReport({
    required this.borrower,
    required this.totalLoanAmount,
    required this.totalInterest,
    required this.totalDue,
    required this.totalPaid,
  });

  double get balance => totalDue - totalPaid;
}

