import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../models/borrower.dart';
import '../models/loan.dart';
import '../providers/loan_provider.dart';
import '../utils/actions.dart';
import '../utils/fmt.dart';
import '../utils/app_colors.dart';
import '../widgets/premium_card.dart';
import 'add_borrower_screen.dart';
import 'add_loan_screen.dart';
import 'loan_detail_screen.dart';
import '../services/excel_export_service.dart';
import '../services/backup_freshness_service.dart';

class BorrowerLoansScreen extends StatefulWidget {
  final Borrower borrower;
  const BorrowerLoansScreen({super.key, required this.borrower});

  @override
  State<BorrowerLoansScreen> createState() => _BorrowerLoansScreenState();
}

class _BorrowerLoansScreenState extends State<BorrowerLoansScreen> {
  List<Loan> _loans = [];
  Set<int> _paidTodayLoanIds = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final provider = context.read<LoanProvider>();
    final loans = await provider.getLoans(widget.borrower.id ?? 0);
    final paidToday = await provider.getLoanIdsPaidToday(widget.borrower.id ?? 0);
    
    if (mounted) {
      setState(() {
        _loans = loans;
        _paidTodayLoanIds = paidToday;
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
      final provider = context.read<LoanProvider>();
      final loans = await provider.getLoans(widget.borrower.id ?? 0);

      final Map<int, List<dynamic>> paymentsPerLoan = {};
      for (final loan in loans) {
        paymentsPerLoan[loan.id ?? 0] = await provider.getPayments(loan.id ?? 0);
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
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.borrower;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Borrower Profile'),
        actions: [
          _buildPopupMenu(b),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
          : RefreshIndicator(
              onRefresh: _onRefresh,
              color: AppColors.accent,
              backgroundColor: AppColors.surface,
              child: Column(
                children: [
                  _buildBorrowerInfoCard(b),
                  if (b.overdueStatus == 'OVERDUE')
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      child: PremiumCard(
                        color: AppColors.error.withOpacity( 0.1),
                        border: Border.all(color: AppColors.error.withOpacity( 0.3)),
                        padding: const EdgeInsets.all(16),
                        child: const Row(
                          children: [
                            Icon(LucideIcons.alertTriangle, color: AppColors.error, size: 24),
                            SizedBox(width: 16),
                            Expanded(
                              child: Text(
                                'This borrower has exceeded the maximum due period of 140 days.',
                                style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w600, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
                    child: Row(
                      children: [
                        const Icon(LucideIcons.history, size: 18, color: AppColors.accent),
                        const SizedBox(width: 10),
                        Text(
                          'Loan History',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Theme.of(context).colorScheme.onSurface),
                        ),
                        const Spacer(),
                        Text('${_loans.length} loans', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity( 0.6), fontSize: 13)),
                      ],
                    ),
                  ),
                  Expanded(child: _buildLoanList()),
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
          foregroundColor: AppColors.background,
          icon: const Icon(LucideIcons.plus),
          label: const Text('Start New Loan', style: TextStyle(fontWeight: FontWeight.bold)),
          onPressed: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => AddLoanScreen(borrower: b)),
            );
            _loadData();
          },
        ),
      ),
    );
  }

  Widget _buildPopupMenu(Borrower b) {
    return ValueListenableBuilder<bool>(
      valueListenable: BackupFreshnessService.isReadOnlyMode,
      builder: (context, isReadOnly, _) {
        return PopupMenuButton<String>(
          icon: const Icon(LucideIcons.moreVertical),
          onSelected: (value) async {
            if (value == 'download') {
              _exportExcel();
            } else if (value == 'edit') {
              if (isReadOnly) return;
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => AddBorrowerScreen(borrower: b)),
              );
              _loadData();
            } else if (value == 'delete') {
              if (isReadOnly) return;
              _confirmDelete(context);
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(
              value: 'download',
              child: Row(children: [Icon(LucideIcons.download, size: 18), SizedBox(width: 12), Text('Download Report')]),
            ),
            if (!isReadOnly) ...[
              const PopupMenuItem(
                value: 'edit',
                child: Row(children: [Icon(LucideIcons.edit, size: 18), SizedBox(width: 12), Text('Edit Borrower')]),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'delete',
                child: Row(children: [Icon(LucideIcons.trash2, size: 18, color: AppColors.error), SizedBox(width: 12), Text('Delete Borrower', style: TextStyle(color: AppColors.error))]),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildBorrowerInfoCard(Borrower b) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: PremiumCard(
        gradient: Theme.of(context).brightness == Brightness.dark ? AppColors.surfaceGradientDark : AppColors.surfaceGradient,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Hero(
                  tag: 'borrower_code_${b.id}',
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: AppColors.accent.withOpacity( 0.1), borderRadius: BorderRadius.circular(8)),
                    child: Material(
                      color: Colors.transparent,
                      child: Text(b.borrowerCode, style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 1.5)),
                    ),
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => openPhoneDialer(b.phone, messenger: ScaffoldMessenger.of(context)),
                  icon: const Icon(LucideIcons.phone, color: AppColors.accent, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Hero(
              tag: 'borrower_name_${b.id}',
              child: Material(
                color: Colors.transparent,
                child: Text(
                  b.name,
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.bold, fontSize: 24),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(LucideIcons.phone, color: Theme.of(context).colorScheme.onSurfaceVariant, size: 14),
                const SizedBox(width: 6),
                Text(b.phone, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ],
            ),
            if (b.address != null && b.address!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(LucideIcons.mapPin, color: Theme.of(context).colorScheme.onSurfaceVariant, size: 14),
                  const SizedBox(width: 6),
                  Expanded(child: Text(b.address!, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))),
                ],
              ),
            ],
            const SizedBox(height: 16),
            const Divider(color: Colors.white10),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Loan Age', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity( 0.6), fontSize: 11)),
                    const SizedBox(height: 4),
                    Text('${b.loanAgeDays} Days', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.bold, fontSize: 15)),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('Status', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity( 0.6), fontSize: 11)),
                    const SizedBox(height: 4),
                    Text(
                      b.overdueStatus == 'OVERDUE' ? '🔴 OVERDUE (Exceeded 140-Day limit)' : 'ACTIVE',
                      style: TextStyle(
                        color: b.overdueStatus == 'OVERDUE' ? AppColors.error : AppColors.success,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (b.notes != null && b.notes!.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Theme.of(context).colorScheme.onSurface.withOpacity( 0.05), borderRadius: BorderRadius.circular(12)),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(LucideIcons.stickyNote, size: 14, color: AppColors.accentLight),
                    const SizedBox(width: 8),
                    Expanded(child: Text(b.notes!, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12, fontStyle: FontStyle.italic))),
                  ],
                ),
              ),
            ],
          ],
        ),
      ).animate().fadeIn(duration: 500.ms).slideY(begin: -0.1, end: 0),
    );
  }

  Widget _buildLoanList() {
    if (_loans.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.coins, size: 48, color: AppColors.textTertiary.withOpacity( 0.2)),
            const SizedBox(height: 16),
            const Text('No loans found.\nTap + to start a new loan.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textTertiary)),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
      itemCount: _loans.length,
      itemBuilder: (ctx, i) {
        final loan = _loans[i];
        final isActive = loan.status == 'active';

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          child: PremiumCard(
            padding: EdgeInsets.zero,
            child: InkWell(
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => LoanDetailScreen(borrower: widget.borrower, loan: loan)),
                );
                _loadData();
              },
              borderRadius: BorderRadius.circular(24),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(DateFormat('dd MMM yyyy').format(loan.loanDate), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Theme.of(context).colorScheme.onSurface)),
                        Row(
                          children: [
                            if (_paidTodayLoanIds.contains(loan.id))
                              const Padding(
                                padding: EdgeInsets.only(right: 8),
                                child: Icon(LucideIcons.checkCircle, color: AppColors.success, size: 16),
                              ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(color: isActive ? AppColors.info.withOpacity( 0.15) : AppColors.success.withOpacity( 0.2), borderRadius: BorderRadius.circular(8)),
                              child: Text(isActive ? 'ACTIVE' : 'CLEARED', style: TextStyle(color: isActive ? AppColors.info : AppColors.success, fontWeight: FontWeight.bold, fontSize: 10)),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    if (loan.installmentDays != null && loan.installmentDays! > 0) ...[
                      Row(
                        children: [
                          const Icon(LucideIcons.calendar, size: 14, color: AppColors.accentLight),
                          const SizedBox(width: 6),
                          Text('${loan.installmentDays} days • Ends ${loan.endDate != null ? DateFormat('dd MMM').format(loan.endDate!) : 'N/A'}', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],
                    Row(
                      children: [
                        _statCol('Principal', fmtINR(loan.loanAmount)),
                        _statCol('Interest', fmtINR(loan.interestAmount)),
                        _statCol('Total Due', fmtINR(loan.totalDue())),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ).animate().fadeIn(duration: 400.ms, delay: (i * 50).ms).slideX(begin: 0.1, end: 0),
        );
      },
    );
  }

  Widget _statCol(String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity( 0.6), fontSize: 11)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Theme.of(context).colorScheme.onSurface)),
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
        content: Text('This will permanently delete ${widget.borrower.name} and ALL their loan records. This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete Permanently'),
          ),
        ],
      ),
    );
    if (confirm == true && context.mounted) {
      await context.read<LoanProvider>().deleteBorrower(widget.borrower.id ?? 0);
      if (context.mounted) Navigator.pop(context);
    }
  }
}

