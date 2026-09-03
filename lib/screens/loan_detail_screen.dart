import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../models/borrower.dart';
import '../models/loan.dart';
import '../models/payment.dart';
import '../providers/loan_provider.dart';
import '../services/excel_export_service.dart';
import '../utils/actions.dart';
import '../utils/fmt.dart';
import '../utils/app_colors.dart';
import '../widgets/premium_card.dart';
import '../services/backup_freshness_service.dart';

class LoanDetailScreen extends StatefulWidget {
  final Borrower borrower;
  final Loan loan;

  const LoanDetailScreen({super.key, required this.borrower, required this.loan});

  @override
  State<LoanDetailScreen> createState() => _LoanDetailScreenState();
}

class _LoanDetailScreenState extends State<LoanDetailScreen> {
  List<Payment> _payments = [];
  double _totalPaid = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final provider = context.read<LoanProvider>();
    final payments = await provider.getPayments(widget.loan.id ?? 0);
    final totalPaid = await provider.getTotalPaid(widget.loan.id ?? 0);
    if (mounted) {
      setState(() {
        _payments = payments;
        _totalPaid = totalPaid;
        _loading = false;
      });
    }
  }

  Future<void> _onRefresh() async {
    await BackupFreshnessService().checkFreshness();
    await _loadData();
  }

  Future<void> _exportExcel() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final path = await ExcelExportService.exportLoanReport(
        borrower: widget.borrower,
        loan: widget.loan,
        payments: _payments,
      );
      showOpenFileSnackBar(messenger: messenger, path: path);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Export failed: $e'), backgroundColor: AppColors.error));
    }
  }

  void _showAddPaymentDialog() {
    final amountCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    DateTime selectedDate = DateTime.now();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setModalState) {
          return Container(
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(32))),
            padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Add Payment', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: AppColors.accent.withOpacity( 0.1), borderRadius: BorderRadius.circular(8)),
                      child: Text(widget.borrower.displayBorrowerCode, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.accent, fontSize: 12)),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: amountCtrl,
                  keyboardType: TextInputType.number,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Amount Paid (₹)', prefixIcon: HugeIcon(icon: HugeIcons.strokeRoundedCoins01)),
                ),
                const SizedBox(height: 16),
                _buildListTile(
                  icon: HugeIcons.strokeRoundedCalendar01,
                  title: 'Payment Date',
                  subtitle: DateFormat('dd MMMM yyyy').format(selectedDate),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: selectedDate,
                      firstDate: DateTime(2000),
                      lastDate: DateTime.now(),
                      builder: (context, child) => Theme(data: Theme.of(context).copyWith(colorScheme: Theme.of(context).colorScheme.copyWith(primary: AppColors.accent, surface: Theme.of(context).colorScheme.surface)), child: child!),
                    );
                    if (picked != null) setModalState(() => selectedDate = picked);
                  },
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: notesCtrl,
                  decoration: const InputDecoration(labelText: 'Notes (Optional)', prefixIcon: HugeIcon(icon: HugeIcons.strokeRoundedNote01)),
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: () async {
                    final amtStr = amountCtrl.text.trim();
                    if (amtStr.isEmpty || double.tryParse(amtStr) == null) return;
                    final payment = Payment(
                      loanId: widget.loan.id ?? 0,
                      amount: double.parse(amtStr),
                      paymentDate: selectedDate,
                      notes: notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
                    );
                    await context.read<LoanProvider>().addPayment(payment);
                    if (context.mounted) {
                      Navigator.pop(ctx);
                      _loadData();
                    }
                  },
                  child: const Text('Confirm Payment'),
                ),
              ],
            ),
          );
        });
      },
    );
  }

  Widget _buildListTile({required dynamic icon, required String title, required String subtitle, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface.withOpacity( 0.1), borderRadius: BorderRadius.circular(16), border: Border.all(color: Theme.of(context).colorScheme.outline.withOpacity( 0.1))),
        child: Row(
          children: [
            Icon(icon, color: AppColors.accent, size: 20),
            const SizedBox(width: 16),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity( 0.6), fontSize: 11)),
              Text(subtitle, style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.bold, fontSize: 14)),
            ]),
            const Spacer(),
            HugeIcon(icon: HugeIcons.strokeRoundedArrowRight01, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity( 0.6)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loan = widget.loan;
    final totalDue = loan.totalDue();
    final balance = totalDue - _totalPaid;
    final progress = totalDue > 0 ? (_totalPaid / totalDue).clamp(0.0, 1.0) : 0.0;
    final days = DateTime.now().difference(loan.loanDate).inDays;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Loan Details'),
        actions: [
          _buildPopupMenu(),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
          : RefreshIndicator(
              onRefresh: _onRefresh,
              color: AppColors.accent,
              backgroundColor: Theme.of(context).colorScheme.surface,
              child: Column(
                children: [
                  _buildLoanStatusCard(loan, totalDue, balance, progress, days),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
                    child: Row(
                      children: [
                        const HugeIcon(icon: HugeIcons.strokeRoundedClock02, size: 18, color: AppColors.accent),
                        const SizedBox(width: 10),
                        Text('Payment History', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Theme.of(context).colorScheme.onSurface)),
                        const Spacer(),
                        Text('${_payments.length} entries', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity( 0.6), fontSize: 13)),
                      ],
                    ),
                  ),
                  Expanded(child: _buildPaymentList()),
                ],
              ),
            ),
      floatingActionButton: ValueListenableBuilder<bool>(
        valueListenable: BackupFreshnessService.isReadOnlyMode,
        builder: (context, isReadOnly, child) {
          if (isReadOnly) return const SizedBox.shrink();
          return child!;
        },
        child: FloatingActionButton.extended(
          backgroundColor: AppColors.accent,
          foregroundColor: Theme.of(context).colorScheme.surface,
          icon: const HugeIcon(icon: HugeIcons.strokeRoundedAdd01),
          label: const Text('Add Payment', style: TextStyle(fontWeight: FontWeight.bold)),
          onPressed: _showAddPaymentDialog,
        ),
      ),
    );
  }

  Widget _buildPopupMenu() {
    return ValueListenableBuilder<bool>(
      valueListenable: BackupFreshnessService.isReadOnlyMode,
      builder: (context, isReadOnly, _) {
        return PopupMenuButton<String>(
          icon: const HugeIcon(icon: HugeIcons.strokeRoundedMoreVertical),
          onSelected: (value) {
            if (value == 'download') { _exportExcel(); }
            else if (value == 'delete') {
              if (isReadOnly) return;
              _confirmDelete(context);
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'download', child: Row(children: [HugeIcon(icon: HugeIcons.strokeRoundedDownload01, size: 18), SizedBox(width: 12), Text('Download Report')])),
            if (!isReadOnly) ...[
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'delete', child: Row(children: [HugeIcon(icon: HugeIcons.strokeRoundedDelete01, size: 18, color: AppColors.error), SizedBox(width: 12), Text('Delete Loan', style: TextStyle(color: AppColors.error))])),
            ],
          ],
        );
      },
    );
  }

  Widget _buildLoanStatusCard(Loan loan, double totalDue, double balance, double progress, int days) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: PremiumCard(
        gradient: AppColors.surfaceGradient,
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(loan.status.toUpperCase(), style: TextStyle(color: loan.status == 'active' ? AppColors.info : AppColors.success, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.5)),
                    const SizedBox(height: 4),
                    Text(balance > 0 ? 'Balance Due' : 'Fully Paid', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
                  ],
                ),
                Text(fmtINR(balance), style: TextStyle(color: balance > 0 ? AppColors.error : AppColors.success, fontWeight: FontWeight.bold, fontSize: 28)),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _miniStat('Principal', fmtINR(loan.loanAmount)),
                _miniStat('Interest', fmtINR(loan.interestAmount)),
                _miniStat('Paid', fmtINR(_totalPaid)),
              ],
            ),
            const SizedBox(height: 24),
            Stack(
              children: [
                Container(height: 8, decoration: BoxDecoration(color: Colors.white.withOpacity( 0.05), borderRadius: BorderRadius.circular(4))),
                AnimatedContainer(
                  duration: const Duration(seconds: 1),
                  height: 8,
                  width: (MediaQuery.of(context).size.width - 88) * progress,
                  decoration: BoxDecoration(gradient: AppColors.primaryGradient, borderRadius: BorderRadius.circular(4)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Active for $days days', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity( 0.6), fontSize: 11)),
                Text('${(progress * 100).toStringAsFixed(0)}% Complete', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 11, fontWeight: FontWeight.bold)),
              ],
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 500.ms).scale(begin: const Offset(0.95, 0.95));
  }

  Widget _miniStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity( 0.6), fontSize: 10)),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.bold, fontSize: 14)),
      ],
    );
  }

  Widget _buildPaymentList() {
    if (_payments.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            HugeIcon(icon: HugeIcons.strokeRoundedCheckmarkCircle01, size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity( 0.2)),
            const SizedBox(height: 16),
            Text('No payments recorded yet', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity( 0.6))),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
      itemCount: _payments.length,
      itemBuilder: (ctx, i) {
        final p = _payments[i];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          child: PremiumCard(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: AppColors.success.withOpacity( 0.1), borderRadius: BorderRadius.circular(12)),
                  child: const HugeIcon(icon: HugeIcons.strokeRoundedArrowDown01, color: AppColors.success, size: 20),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(fmtINR(p.amount), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.success)),
                      if (p.notes != null) Text(p.notes!, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity( 0.6), fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(DateFormat('dd MMM').format(p.paymentDate), style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    ValueListenableBuilder<bool>(
                      valueListenable: BackupFreshnessService.isReadOnlyMode,
                      builder: (context, isReadOnly, _) {
                        if (isReadOnly) return const SizedBox.shrink();
                        return GestureDetector(
                          onTap: () => _deletePayment(p),
                          child: HugeIcon(icon: HugeIcons.strokeRoundedDelete01, size: 16, color: AppColors.error.withOpacity(0.6)),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ).animate().fadeIn(duration: 400.ms).slideX(begin: 0.1, end: 0);
      },
    );
  }

  Future<void> _deletePayment(Payment p) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Payment?'),
        content: Text('Remove ${fmtINR(p.amount)} payment from ${DateFormat('dd MMM').format(p.paymentDate)}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), style: ElevatedButton.styleFrom(backgroundColor: AppColors.error), child: const Text('Delete')),
        ],
      ),
    );
    if (confirm == true && mounted) {
      await context.read<LoanProvider>().deletePayment(p.id ?? 0, widget.loan.id ?? 0);
      _loadData();
    }
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Loan?'),
        content: const Text('Permanently delete this loan and all associated payments?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), style: ElevatedButton.styleFrom(backgroundColor: AppColors.error), child: const Text('Delete')),
        ],
      ),
    );
    if (confirm == true && context.mounted) {
      await context.read<LoanProvider>().deleteLoan(widget.loan.id ?? 0);
      if (context.mounted) Navigator.pop(context);
    }
  }
}

