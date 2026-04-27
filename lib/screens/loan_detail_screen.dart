import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/borrower.dart';
import '../models/loan.dart';
import '../models/payment.dart';
import '../providers/loan_provider.dart';
import '../services/excel_export_service.dart';
import '../utils/actions.dart';
import '../utils/fmt.dart';

class LoanDetailScreen extends StatefulWidget {
  final Borrower borrower;
  final Loan loan;

  const LoanDetailScreen(
      {super.key, required this.borrower, required this.loan});

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
    final payments = await provider.getPayments(widget.loan.id!);
    final totalPaid = await provider.getTotalPaid(widget.loan.id!);
    if (mounted) {
      setState(() {
        _payments = payments;
        _totalPaid = totalPaid;
        _loading = false;
      });
    }
  }

  Future<void> _exportExcel() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final path = await ExcelExportService.exportLoanReport(
        borrower: widget.borrower,
        loan: widget.loan,
        payments: _payments,
      );
      showOpenFileSnackBar(
        messenger: messenger,
        path: path,
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text('Export failed: $e'),
        backgroundColor: Colors.redAccent,
      ));
    }
  }

  void _showAddPaymentDialog() {
    final amountCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    DateTime selectedDate = DateTime.now();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setModalState) {
          return Padding(
            padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 24,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Text('Add Payment',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E3A5F).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(widget.borrower.borrowerCode,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1E3A5F),
                            fontSize: 13)),
                  ),
                ]),
                const SizedBox(height: 16),
                TextField(
                  controller: amountCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Amount Paid (₹)',
                    prefixIcon: const Icon(Icons.currency_rupee),
                    filled: true,
                    fillColor: Colors.grey[100],
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  const Icon(Icons.calendar_today,
                      size: 18, color: Colors.grey),
                  const SizedBox(width: 8),
                  Text(
                      'Date: ${DateFormat('dd MMM yyyy').format(selectedDate)}',
                      style: const TextStyle(fontSize: 14)),
                  const Spacer(),
                  TextButton(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: selectedDate,
                        firstDate: DateTime(2000),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) {
                        setModalState(() => selectedDate = picked);
                      }
                    },
                    child: const Text('Change'),
                  ),
                ]),
                const SizedBox(height: 12),
                TextField(
                  controller: notesCtrl,
                  decoration: InputDecoration(
                    labelText: 'Notes (Optional)',
                    prefixIcon: const Icon(Icons.notes),
                    filled: true,
                    fillColor: Colors.grey[100],
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1E3A5F),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12))),
                    onPressed: () async {
                      final amtStr = amountCtrl.text.trim();
                      if (amtStr.isEmpty || double.tryParse(amtStr) == null) {
                        ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                            content: Text('Enter valid amount')));
                        return;
                      }
                      final payment = Payment(
                        loanId: widget.loan.id!,
                        amount: double.parse(amtStr),
                        paymentDate: selectedDate,
                        notes: notesCtrl.text.trim().isEmpty
                            ? null
                            : notesCtrl.text.trim(),
                      );
                      await context.read<LoanProvider>().addPayment(payment);
                      if (context.mounted) {
                        Navigator.pop(ctx);
                        _loadData();
                      }
                    },
                    child: const Text('Save Payment',
                        style: TextStyle(color: Colors.white, fontSize: 16)),
                  ),
                ),
              ],
            ),
          );
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.borrower;
    final loan = widget.loan;
    final totalDue = loan.totalDue();
    final balance = totalDue - _totalPaid;
    final progress =
        totalDue > 0 ? (_totalPaid / totalDue).clamp(0.0, 1.0) : 0.0;
    final days = DateTime.now().difference(loan.loanDate).inDays;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FF),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E3A5F),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Loan - ${b.name}',
                style: const TextStyle(color: Colors.white, fontSize: 16),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            Text(DateFormat('dd MMM yyyy').format(loan.loanDate),
                style: const TextStyle(color: Colors.white60, fontSize: 12)),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onSelected: (value) {
              if (value == 'download') {
                _exportExcel();
              } else if (value == 'delete') {
                _confirmDelete(context);
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'download',
                child: Row(children: [
                  Icon(Icons.download_outlined, size: 20),
                  SizedBox(width: 12),
                  Text('Download Report'),
                ]),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Row(children: [
                  Icon(Icons.delete_outline, size: 20, color: Colors.redAccent),
                  SizedBox(width: 12),
                  Text('Delete Loan',
                      style: TextStyle(color: Colors.redAccent)),
                ]),
              ),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildInfoCard(loan, totalDue, balance, progress, days),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Row(children: [
                    Icon(Icons.history, size: 16, color: Color(0xFF1E3A5F)),
                    SizedBox(width: 6),
                    Text('Payment History',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: Color(0xFF1E3A5F))),
                  ]),
                ),
                Expanded(child: _buildPaymentList()),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF1E3A5F),
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Add Payment', style: TextStyle(color: Colors.white)),
        onPressed: _showAddPaymentDialog,
      ),
    );
  }

  Widget _buildInfoCard(
      Loan loan, double totalDue, double balance, double progress, int days) {
    return Container(
      margin: const EdgeInsets.all(14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E3A5F),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          // ── Header row ──────────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Status badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: loan.status == 'active'
                              ? Colors.blueAccent.withValues(alpha: 0.3)
                              : Colors.greenAccent.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(loan.status.toUpperCase(),
                            style: TextStyle(
                                color: loan.status == 'active'
                                    ? Colors.blue.shade100
                                    : Colors.green.shade100,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                letterSpacing: 1.5)),
                      ),
                    ]),
              ),
              // Balance
              Flexible(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(fmtINR(balance),
                            style: TextStyle(
                                color: balance > 0
                                    ? Colors.redAccent
                                    : Colors.greenAccent,
                                fontWeight: FontWeight.bold,
                                fontSize: 24)),
                      ),
                      Text(balance > 0 ? 'Balance Due' : '✅ Cleared',
                          style: const TextStyle(
                              color: Colors.white60, fontSize: 12)),
                    ]),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(color: Colors.white24),
          const SizedBox(height: 10),
          // ── Stats row ────────────────────────────────────────
          Row(
            children: [
              _infoStat(
                  'Principal', fmtINR(loan.loanAmount), Colors.orangeAccent),
              _infoStat(
                  'Interest', fmtINR(loan.interestAmount), Colors.yellowAccent),
              _infoStat('Total Due', fmtINR(totalDue), Colors.white),
              _infoStat('Paid', fmtINR(_totalPaid), Colors.greenAccent),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Text('Loan active for: $days days',
                  style: const TextStyle(color: Colors.white60, fontSize: 12)),
              const Spacer(),
              Text('${(progress * 100).toStringAsFixed(1)}% paid',
                  style: const TextStyle(color: Colors.white60, fontSize: 12)),
            ],
          ),
          if (loan.installmentDays != null && loan.endDate != null) ...[
            Builder(
              builder: (context) {
                String perDayStr = '';
                if (loan.installmentDays! > 0) {
                  final perDay = totalDue / loan.installmentDays!;
                  final formatted = perDay % 1 == 0
                      ? perDay.toInt().toString()
                      : perDay.toStringAsFixed(2);
                  perDayStr = ' • ₹$formatted/day';
                }
                return Column(
                  children: [
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.timer, size: 12, color: Colors.white60),
                        const SizedBox(width: 4),
                        Text(
                          'Installment: ${loan.installmentDays} days$perDayStr (Ends ${DateFormat('dd MMM yyyy').format(loan.endDate!)})',
                          style: const TextStyle(color: Colors.white60, fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ],
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: Colors.white24,
              valueColor: AlwaysStoppedAnimation<Color>(progress >= 1.0
                  ? Colors.greenAccent
                  : Colors.lightBlueAccent),
            ),
          ),
          if (loan.notes != null) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('📝 ${loan.notes}',
                  style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                      fontStyle: FontStyle.italic)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _infoStat(String label, String value, Color color) {
    return Expanded(
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value,
                style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 14)),
          ),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(color: Colors.white54, fontSize: 10),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _buildPaymentList() {
    if (_payments.isEmpty) {
      return const Center(
        child: Text('No payments yet.\nTap + to record a payment.',
            textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      itemCount: _payments.length,
      itemBuilder: (ctx, i) {
        final p = _payments[i];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.green.shade50,
              child: const Icon(Icons.arrow_downward, color: Colors.green),
            ),
            title: Text(fmtINR(p.amount),
                style: const TextStyle(
                    fontWeight: FontWeight.bold, color: Colors.green)),
            subtitle: p.notes != null
                ? Text(p.notes!, style: const TextStyle(fontSize: 12))
                : null,
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(DateFormat('dd MMM yyyy').format(p.paymentDate),
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 2),
                GestureDetector(
                  onTap: () => _deletePayment(p),
                  child: const Icon(Icons.delete_outline,
                      size: 18, color: Colors.redAccent),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _deletePayment(Payment p) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Payment?'),
        content: Text('Remove ${fmtINR(p.amount)} payment on '
            '${DateFormat('dd MMM yyyy').format(p.paymentDate)}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm == true && mounted) {
      await context.read<LoanProvider>().deletePayment(p.id!, widget.loan.id!);
      _loadData();
    }
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Loan?'),
        content: const Text('Delete this loan and all its payment records?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm == true && context.mounted) {
      await context.read<LoanProvider>().deleteLoan(widget.loan.id!);
      if (context.mounted) Navigator.pop(context);
    }
  }
}
