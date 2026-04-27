import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/borrower.dart';
import '../models/loan.dart';
import '../providers/loan_provider.dart';
import '../utils/actions.dart';
import '../utils/fmt.dart';
import 'add_borrower_screen.dart';
import 'add_loan_screen.dart';
import 'loan_detail_screen.dart';
import '../services/excel_export_service.dart';

class BorrowerLoansScreen extends StatefulWidget {
  final Borrower borrower;
  const BorrowerLoansScreen({super.key, required this.borrower});

  @override
  State<BorrowerLoansScreen> createState() => _BorrowerLoansScreenState();
}

class _BorrowerLoansScreenState extends State<BorrowerLoansScreen> {
  List<Loan> _loans = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final provider = context.read<LoanProvider>();
    final loans = await provider.getLoans(widget.borrower.id!);
    if (mounted) {
      setState(() {
        _loans = loans;
        _loading = false;
      });
    }
  }

  Future<void> _exportExcel() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final provider = context.read<LoanProvider>();
      final loans = await provider.getLoans(widget.borrower.id!);

      // Fetch payments for each loan
      final Map<int, List<dynamic>> paymentsPerLoan = {};
      for (final loan in loans) {
        paymentsPerLoan[loan.id!] = await provider.getPayments(loan.id!);
      }

      final path = await ExcelExportService.exportBorrowerReport(
        borrower: widget.borrower,
        loans: loans,
        paymentsPerLoan: Map.from(paymentsPerLoan),
      );

      showOpenFileSnackBar(
        messenger: messenger,
        path: path,
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Export failed: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.borrower;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FF),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E3A5F),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(b.name,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            Text(b.borrowerCode,
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
            onSelected: (value) async {
              if (value == 'download') {
                _exportExcel();
              } else if (value == 'edit') {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => AddBorrowerScreen(borrower: b)),
                );
                _loadData();
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
                value: 'edit',
                child: Row(children: [
                  Icon(Icons.edit_outlined, size: 20),
                  SizedBox(width: 12),
                  Text('Edit Borrower'),
                ]),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Row(children: [
                  Icon(Icons.delete_outline, size: 20, color: Colors.redAccent),
                  SizedBox(width: 12),
                  Text('Delete Borrower',
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
                _buildBorrowerInfoCard(b),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Row(children: [
                    Icon(Icons.monetization_on,
                        size: 16, color: Color(0xFF1E3A5F)),
                    SizedBox(width: 6),
                    Text('Loan History',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: Color(0xFF1E3A5F))),
                  ]),
                ),
                Expanded(child: _buildLoanList()),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF1E3A5F),
        icon: const Icon(Icons.add, color: Colors.white),
        label:
            const Text('Start New Loan', style: TextStyle(color: Colors.white)),
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => AddLoanScreen(borrower: b)),
          );
          _loadData();
        },
      ),
    );
  }

  Widget _buildBorrowerInfoCard(Borrower b) {
    return Container(
      margin: const EdgeInsets.all(14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E3A5F),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(b.borrowerCode,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        letterSpacing: 1.5)),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Call borrower',
                onPressed: () => openPhoneDialer(
                  b.phone,
                  messenger: ScaffoldMessenger.of(context),
                ),
                icon: const Icon(Icons.call, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(b.name,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 20),
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.phone, color: Colors.white70, size: 14),
              const SizedBox(width: 4),
              Text(b.phone, style: const TextStyle(color: Colors.white70)),
            ],
          ),
          if (b.address != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.location_on, color: Colors.white70, size: 14),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(b.address!,
                      style: const TextStyle(color: Colors.white70)),
                ),
              ],
            ),
          ],
          if (b.notes != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('📝 ${b.notes}',
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

  Widget _buildLoanList() {
    if (_loans.isEmpty) {
      return const Center(
        child: Text('No loans found.\nTap + to start a new loan.',
            textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      itemCount: _loans.length,
      itemBuilder: (ctx, i) {
        final loan = _loans[i];
        final isActive = loan.status == 'active';

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                  color: isActive ? Colors.blue.shade200 : Colors.grey.shade300,
                  width: isActive ? 1.5 : 1)),
          elevation: isActive ? 2 : 0,
          color: isActive ? Colors.white : Colors.grey.shade50,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => LoanDetailScreen(
                        borrower: widget.borrower, loan: loan)),
              );
              _loadData();
            },
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        DateFormat('dd MMM yyyy').format(loan.loanDate),
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: isActive
                              ? Colors.blue.shade50
                              : Colors.green.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          isActive ? 'ACTIVE' : 'CLEARED',
                          style: TextStyle(
                              color: isActive ? Colors.blue : Colors.green,
                              fontWeight: FontWeight.bold,
                              fontSize: 10),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (loan.installmentDays != null && loan.endDate != null) ...[
                    Builder(
                      builder: (context) {
                        String perDayStr = '';
                        if (loan.installmentDays! > 0) {
                          final perDay = loan.totalDue() / loan.installmentDays!;
                          final formatted = perDay % 1 == 0
                              ? perDay.toInt().toString()
                              : perDay.toStringAsFixed(2);
                          perDayStr = ' • ₹$formatted/day';
                        }
                        return Column(
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.timer, size: 12, color: Colors.grey),
                                const SizedBox(width: 4),
                                Text(
                                  '${loan.installmentDays} days$perDayStr • Ends ${DateFormat('dd MMM yyyy').format(loan.endDate!)}',
                                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                          ],
                        );
                      },
                    ),
                  ],
                  Row(
                    children: [
                      _statCol('Principal', fmtINR(loan.loanAmount)),
                      const SizedBox(width: 8),
                      _statCol('Interest', fmtINR(loan.interestAmount)),
                      const SizedBox(width: 8),
                      _statCol('Total Due', fmtINR(loan.totalDue())),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _statCol(String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Borrower?'),
        content: Text(
            'Delete ${widget.borrower.name} (${widget.borrower.borrowerCode}) '
            'and ALL their associated loans and payment records?'),
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
      await context.read<LoanProvider>().deleteBorrower(widget.borrower.id!);
      if (context.mounted) Navigator.pop(context);
    }
  }
}
