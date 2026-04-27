import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../database/db_helper.dart';
import '../models/borrower.dart';
import '../models/loan.dart';
import '../models/payment.dart';
import '../providers/loan_provider.dart';
import '../services/excel_export_service.dart';
import '../utils/actions.dart';
import '../utils/fmt.dart';
import 'investment_screen.dart';
import 'add_expense_dialog.dart';
import 'expense_history_screen.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  Map<String, dynamic>? _summary;
  List<_BorrowerReport> _reports = [];
  bool _loading = true;
  bool _exporting = false;
  double _totalInvested = 0.0;
  double _totalExpenses = 0.0;

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  Future<void> _loadReports() async {
    if (!mounted) return;
    setState(() => _loading = true);

    final provider = context.read<LoanProvider>();
    // Force fresh borrower list from DB (catches deletions done in other screens)
    await provider.loadBorrowers();
    final summary = provider.globalSummary;
    final borrowers = provider.borrowers;
    final totalInvested = await DBHelper().getTotalInvested();
    final totalExpenses = await DBHelper().getTotalExpenses();

    final reports = <_BorrowerReport>[];
    for (final b in borrowers) {
      final loans = await provider.getLoans(b.id!);
      // Only aggregate active (uncleared) loans
      final activeLoans = loans.where((l) => l.status == 'active').toList();
      double totalLoanAmount = 0;
      double totalInterest = 0;
      double totalDue = 0;
      double totalPaid = 0;

      for (var loan in activeLoans) {
        totalLoanAmount += loan.loanAmount;
        totalInterest += loan.interestAmount;
        totalDue += loan.totalDue();
        totalPaid += await provider.getTotalPaid(loan.id!);
      }

      reports.add(_BorrowerReport(
        borrower: b,
        totalLoanAmount: totalLoanAmount,
        totalInterest: totalInterest,
        totalDue: totalDue,
        totalPaid: totalPaid,
      ));
    }

    reports.sort((a, b) => b.balance.compareTo(a.balance));

    if (mounted) {
      setState(() {
        _summary = summary;
        _reports = reports;
        _totalInvested = totalInvested;
        _totalExpenses = totalExpenses;
        _loading = false;
      });
    }
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

      final path = await ExcelExportService.exportOverallReport(
        borrowers: borrowers,
        loansPerBorrower: loansPerBorrower,
        paymentsPerLoan: paymentsPerLoan,
        summary: provider.globalSummary,
        totalInvested: await DBHelper().getTotalInvested(),
      );

      if (!mounted) return;
      showOpenFileSnackBar(
        messenger: messenger,
        path: path,
      );
      await _loadReports();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text('Export failed: $e'),
        backgroundColor: Colors.redAccent,
      ));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // All-time totals: used ONLY for On Hand formula (Invested − ever lent + ever returned)
    final totalLoanedEver = (_summary?['totalLoaned'] ?? 0.0) as double;
    final totalCollectedEver = (_summary?['totalCollected'] ?? 0.0) as double;

    // Active-loan totals: used for Collected / Pending display cards
    final activeCollected = (_summary?['activePending'] != null
        ? ((_summary?['totalDue'] ?? 0.0) as double) -
            ((_summary?['totalPending'] ?? 0.0) as double)
        : totalCollectedEver);
    final totalBorrowers = _summary?['totalBorrowers'] ?? 0;

    // Compute from per-borrower active-loan reports (only active loans in _reports)
    final totalToRecover =
        _reports.fold<double>(0.0, (sum, r) => sum + r.totalDue);
    final totalPending = (_summary?['totalPending'] ?? 0.0) as double;

    // On Hand = Invested − ever lent (principal only) + ever returned − expenses
    // This stays correct even after all loans are cleared.
    final onHand = _totalInvested - totalLoanedEver + totalCollectedEver - _totalExpenses;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FF),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E3A5F),
        title: const Text('📊 Reports', style: TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            tooltip: 'Download Excel',
            onPressed: _loading || _exporting ? null : _exportOverallExcel,
            icon: _exporting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.download_outlined, color: Colors.white),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(14),
              children: [
                // ── Overall Summary header row ─────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _sectionLabel('Overall Summary'),
                    GestureDetector(
                      onTap: () async {
                        await Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const InvestmentScreen()));
                        if (mounted) await _loadReports();
                      },
                      child: Row(
                        children: [
                          Icon(Icons.savings_outlined,
                              size: 15, color: Colors.orangeAccent.shade700),
                          const SizedBox(width: 4),
                          Text(
                            'Investments',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.orangeAccent.shade700,
                            ),
                          ),
                          Icon(Icons.chevron_right,
                              size: 16, color: Colors.orangeAccent.shade700),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // ── On Hand — full width ───────────────────────────
                Row(children: [
                  _statCard(
                      'On Hand',
                      fmtINR(onHand),
                      Icons.account_balance,
                      onHand >= 0 ? Colors.green : Colors.redAccent,
                      () => _showOnHandOptions(context)),
                ]),
                const SizedBox(height: 10),

                // ── 2×2 stat grid ──────────────────────────────────
                Row(children: [
                  _statCard('Borrowers', '$totalBorrowers', Icons.people,
                      Colors.blueAccent, null),
                  const SizedBox(width: 10),
                  _statCard('To Recover', fmtINR(totalToRecover),
                      Icons.receipt_long, Colors.deepOrangeAccent, null),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  _statCard('Collected', fmtINR(activeCollected),
                      Icons.check_circle, Colors.greenAccent, null),
                  const SizedBox(width: 10),
                  _statCard('Pending', fmtINR(totalPending),
                      Icons.pending_actions, Colors.redAccent, null),
                ]),
                const SizedBox(height: 14),

                // ── Warning: over-deployed ────────────────────────
                if (onHand < 0 && _totalInvested > 0)
                  Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.redAccent, width: 1.2),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded,
                            color: Colors.redAccent, size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Over-deployed! You have lent ${fmtINR(totalLoanedEver)} '
                            'but only ${fmtINR(_totalInvested)} is invested. '
                            'Add more investment or recover pending dues.',
                            style: const TextStyle(
                                color: Colors.redAccent,
                                fontSize: 12,
                                fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  ),

                // ── Per Borrower Breakdown ─────────────────────
                _sectionLabel('Per Borrower Breakdown'),
                const SizedBox(height: 8),
                ..._reports.map((r) => _buildBorrowerReportRow(r)),
              ],
            ),
    );
  }

  void _showOnHandOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Cash Management',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: const Icon(Icons.add_circle_outline,
                  color: Color(0xFF0F2545)),
              title: const Text('Add Expense'),
              subtitle: const Text('Record an expense from your on-hand cash'),
              onTap: () async {
                Navigator.pop(ctx);
                await showDialog(
                  context: context,
                  builder: (_) => const AddExpenseDialog(),
                );
                // Refresh reports after expense is added
                if (mounted) await _loadReports();
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.history, color: Color(0xFF0F2545)),
              title: const Text('View Expense History'),
              subtitle: const Text('See all recorded expenses'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ExpenseHistoryScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String label) {
    return Text(label,
        style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: Color(0xFF1E3A5F)));
  }

  Widget _statCard(String label, String value, IconData icon, Color color,
      VoidCallback? onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 6,
                  offset: const Offset(0, 2))
            ],
            border: onTap != null
                ? Border.all(color: color.withValues(alpha: 0.3), width: 1.2)
                : null,
          ),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: color.withValues(alpha: 0.15),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(value,
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: color)),
                    ),
                    Text(label,
                        style:
                            const TextStyle(fontSize: 11, color: Colors.grey)),
                  ],
                ),
              ),
              if (onTap != null)
                Icon(Icons.chevron_right,
                    color: color.withValues(alpha: 0.6), size: 18),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBorrowerReportRow(_BorrowerReport r) {
    final b = r.borrower;
    final progress =
        r.totalDue > 0 ? (r.totalPaid / r.totalDue).clamp(0.0, 1.0) : 0.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 4,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF1E3A5F).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(b.borrowerCode,
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1E3A5F))),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(b.name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(fmtINR(r.balance),
                  style: TextStyle(
                      color: r.balance > 0 ? Colors.red : Colors.green,
                      fontWeight: FontWeight.bold)),
            ),
          ]),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _miniStat('Principal', fmtINR(r.totalLoanAmount)),
              _miniStat('Interest', fmtINR(r.totalInterest)),
              _miniStat('To Recover', fmtINR(r.totalDue)),
              _miniStat('Collected', fmtINR(r.totalPaid)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 5,
              backgroundColor: Colors.grey[200],
              valueColor: AlwaysStoppedAnimation<Color>(
                  progress >= 1.0 ? Colors.green : Colors.blue),
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String label, String value) {
    return Expanded(
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          ),
          Text(label,
              style: const TextStyle(fontSize: 10, color: Colors.grey)),
        ],
      ),
    );
  }
}

class _BorrowerReport {
  final Borrower borrower;
  final double totalLoanAmount;
  final double totalInterest;
  final double totalDue;
  final double totalPaid;

  _BorrowerReport({
    required this.borrower,
    required this.totalLoanAmount,
    required this.totalInterest,
    required this.totalDue,
    required this.totalPaid,
  });

  double get balance => totalDue - totalPaid;
}
