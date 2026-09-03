import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:hugeicons/hugeicons.dart';

import '../providers/loan_provider.dart';
import '../models/payment.dart';
import '../utils/fmt.dart';
import '../utils/app_colors.dart';
import '../utils/app_decorations.dart';
import '../widgets/premium_card.dart';
import '../widgets/sync_status_indicator.dart';
import '../widgets/quick_add_dialog.dart';
import 'add_borrower_screen.dart';
import 'borrower_loans_screen.dart';
import '../services/backup_freshness_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<LoanProvider>().loadBorrowers();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Consumer<LoanProvider>(
        builder: (context, provider, _) {
          final summary = provider.globalSummary;

          final totalDue = (summary['totalDue'] ?? 0.0) as double;
          final totalCollected = (summary['totalCollected'] ?? 0.0) as double;
          final totalPending = (summary['totalPending'] ?? 0.0) as double;
          final todayCollection = provider.todayCollection;

          final borrowers = provider.borrowers;
          final paidIds = provider.paidTodayIds;
          final completedIds = provider.completedIds;

          final collectList = provider.collectBorrowers;
          final paidList = provider.paidBorrowers;
          final completedList = provider.closedBorrowers;
          final dummyList = provider.dummyBorrowers;

          final source = [_collectSafe(collectList), _collectSafe(paidList), _collectSafe(completedList), _collectSafe(dummyList)][_tab];

          return Consumer<LoanProvider>(
            key: ValueKey<int>(_tab),
            builder: (context, provider, _) {
                final items = source.where((b) {
                  final q = _query.toLowerCase();
                  if (q.trim().isEmpty) return true;
                  
                  final isNumeric = int.tryParse(q.trim()) != null;
                  if (isNumeric) {
                    return b.borrowerCode.toLowerCase() == q.trim();
                  }

                  return b.name.toLowerCase().contains(q) ||
                      b.borrowerCode.toLowerCase().contains(q) ||
                      (b.address ?? '').toLowerCase().contains(q);
                }).toList();

                return RefreshIndicator(
                  color: AppColors.accent,
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  onRefresh: () async {
                    await BackupFreshnessService().checkFreshness();
                    await provider.loadBorrowers();
                  },
                  child: CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(child: _buildHeader(totalDue, totalCollected, totalPending, todayCollection, provider)),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
                        sliver: SliverToBoxAdapter(child: _buildSearch()),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                        sliver: SliverToBoxAdapter(
                          child: _buildTabs(
                            collectList.length, 
                            paidList.length, 
                            completedList.length,
                            dummyList.length,
                          ),
                        ),
                      ),
                      if (items.isEmpty)
                        SliverFillRemaining(hasScrollBody: false, child: _emptyState())
                      else
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (_, i) {
                                final b = items[i];
                                return _buildDismissibleCard(context, b, provider);
                              },
                              childCount: items.length,
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            );
        },
      ),
      floatingActionButton: ValueListenableBuilder<bool>(
        valueListenable: BackupFreshnessService.isReadOnlyMode,
        builder: (context, isReadOnly, child) {
          if (isReadOnly) return const SizedBox.shrink();
          return child!;
        },
        child: Padding(
          padding: const EdgeInsets.only(bottom: 80), // Avoid overlap with bottom nav
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              FloatingActionButton.extended(
                heroTag: 'quick_add_fab',
                backgroundColor: AppColors.accent,
                foregroundColor: AppColors.background,
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
                icon: const HugeIcon(icon: HugeIcons.strokeRoundedFlash),
                label: const Text("Quick Add", style: TextStyle(fontWeight: FontWeight.bold)),
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (context) => const QuickAddDialog(),
                  );
                },
              ),
              const SizedBox(height: 12),
              FloatingActionButton.extended(
                heroTag: 'add_borrower_fab',
                backgroundColor: AppColors.accent,
                foregroundColor: AppColors.background,
                elevation: 6,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                icon: const HugeIcon(icon: HugeIcons.strokeRoundedUser),
                label: const Text("Add Borrower", style: TextStyle(fontWeight: FontWeight.bold)),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AddBorrowerScreen()),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(double due, double collected, double pending, double today, LoanProvider provider) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 60, 20, 24),
      decoration: BoxDecoration(
        gradient: Theme.of(context).brightness == Brightness.dark ? AppColors.surfaceGradientDark : AppColors.surfaceGradient,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Welcome back,",
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 14),
                  ),
                  Text(
                    "Credits Dashboard",
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SyncStatusIndicator(compact: true),
            ],
          ),
          const SizedBox(height: 24),
          PremiumCard(
            padding: const EdgeInsets.all(24),
            gradient: AppColors.primaryGradient,
            boxShadow: [
              BoxShadow(
                color: AppColors.accent.withOpacity( 0.3),
                blurRadius: 24,
                offset: const Offset(0, 10),
              )
            ],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Today's Collection",
                      style: TextStyle(
                        color: Colors.white.withOpacity( 0.8),
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    HugeIcon(icon: HugeIcons.strokeRoundedCalendarCheckIn01, color: Colors.white.withOpacity( 0.8)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  fmtINR(today),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String label, String value, dynamic icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: Colors.white.withOpacity( 0.7)),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withOpacity( 0.7),
                fontSize: 12,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }


  Widget _buildSearch() {
    return TextField(
      controller: _searchCtrl,
      onChanged: (v) => setState(() => _query = v),
      decoration: InputDecoration(
        hintText: "Search name, ID, address...",
        prefixIcon: const HugeIcon(icon: HugeIcons.strokeRoundedSearch01, size: 20),
        suffixIcon: _query.isNotEmpty
            ? IconButton(
                icon: const HugeIcon(icon: HugeIcons.strokeRoundedCancel01, size: 16),
                onPressed: () {
                  _searchCtrl.clear();
                  setState(() => _query = '');
                },
              )
            : null,
      ),
    );
  }

  Widget _buildTabs(int collect, int paid, int completed, int dummy) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity( 0.03),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          _tabItem(0, "Collect", collect.toString(), AppColors.secondary),
          _tabItem(1, "Paid", paid.toString(), AppColors.success),
          _tabItem(2, "Closed", completed.toString(), AppColors.info),
          _tabItem(3, "Inactive", dummy.toString(), Colors.grey),
        ],
      ),
    );
  }

  Widget _tabItem(int index, String label, String topText, Color color) {
    final isSelected = _tab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _tab = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
          decoration: BoxDecoration(
            color: isSelected ? Theme.of(context).scaffoldBackgroundColor : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
            boxShadow: isSelected ? [
              BoxShadow(
                color: color.withOpacity( 0.15),
                blurRadius: 12,
                offset: const Offset(0, 6),
              )
            ] : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  topText,
                  style: TextStyle(
                    color: isSelected ? color : Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? Theme.of(context).colorScheme.onSurface : Theme.of(context).colorScheme.onSurfaceVariant.withOpacity( 0.6),
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDismissibleCard(BuildContext context, dynamic b, LoanProvider provider) {
    final isPaid = provider.paidTodayIds.contains(b.id);
    
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Dismissible(
        key: Key('borrower_${b.id}'),
        direction: DismissDirection.startToEnd,
        confirmDismiss: (dir) async {
          if (BackupFreshnessService.isReadOnlyMode.value) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text("Cannot record payment in Read Only Mode"),
                backgroundColor: AppColors.error,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            );
            return false;
          }
          return await _handleQuickPay(context, b);
        },
        background: Container(
          decoration: BoxDecoration(
            color: isPaid ? AppColors.accent.withOpacity( 0.2) : AppColors.accent.withOpacity( 0.3),
            borderRadius: BorderRadius.circular(24),
          ),
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.only(left: 24),
          child: Row(
            children: [
              HugeIcon(
                icon: isPaid ? HugeIcons.strokeRoundedCheckmarkBadge01 : HugeIcons.strokeRoundedCheckmarkCircle01, 
                color: AppColors.accent, 
                size: 24
              ),
              const SizedBox(width: 12),
              Text(
                isPaid ? "Done ✓" : "Quick Pay",
                style: const TextStyle(
                  color: AppColors.accent,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
        child: _borrowerCard(b, provider),
      ),
    );
  }

  Widget _borrowerCard(dynamic b, LoanProvider provider) {
    final balance = b.totalBalance;
    final due = balance > 0;
    final isPaid = provider.paidTodayIds.contains(b.id);
    
    // Loan progress calculation
    final paidCount = provider.paidLoanCountsToday[b.id] ?? 0;
    final totalCount = provider.todayLoanCounts[b.id] ?? b.loanCount;
    final hasMultipleLoans = totalCount > 1;

    return PremiumCard(
        padding: EdgeInsets.zero,
        color: isPaid ? AppColors.accent.withOpacity( 0.05) : Theme.of(context).colorScheme.surface,
        boxShadow: AppDecorations.subtleShadowCard(Theme.of(context).brightness == Brightness.dark).boxShadow,
        child: InkWell(
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => BorrowerLoansScreen(borrower: b),
              ),
            );
            // Refresh counts when returning
            if (mounted) provider.loadBorrowers();
          },
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Hero(
                  tag: 'borrower_code_${b.id}',
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: due ? AppColors.error.withOpacity( 0.1) : AppColors.accent.withOpacity( 0.1),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Center(
                      child: Material(
                        color: Colors.transparent,
                        child: Text(
                          b.displayBorrowerCode,
                          style: TextStyle(
                            color: due ? AppColors.error : AppColors.accent,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Hero(
                              tag: 'borrower_name_${b.id}',
                              child: Material(
                                color: Colors.transparent,
                                child: Text(
                                  b.name,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.onSurface,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ),
                            ),
                          ),
                          if (b.overdueStatus == 'OVERDUE') ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppColors.error.withOpacity( 0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AppColors.error.withOpacity( 0.2)),
                              ),
                              child: Text(
                                "🔴 ${b.loanAgeDays} Days Due",
                                style: const TextStyle(
                                  color: AppColors.error,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                          if (hasMultipleLoans) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.secondary.withOpacity( 0.3),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                "$paidCount/$totalCount",
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        b.phone,
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      fmtINR(balance),
                      style: TextStyle(
                        color: due ? AppColors.error : AppColors.accent,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isPaid ? "Collected" : "Pending",
                      style: TextStyle(
                        color: isPaid ? AppColors.accent : Theme.of(context).colorScheme.onSurfaceVariant.withOpacity( 0.6),
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
          ),
        ),
      ),
    );
  }

  Future<bool> _handleQuickPay(BuildContext context, dynamic b) async {
    if (b == null || b.id == null) return false;
    final double bal = (b.totalBalance as num?)?.toDouble() ?? 0.0;
    if (bal <= 0) return false;
    
    try {
      if (!context.mounted) return false;
      
      final provider = context.read<LoanProvider>();
      final activeLoans = (await provider.getLoans(b.id ?? 0))
          .where((l) => l.status == 'active').toList();
      
      if (activeLoans.isEmpty) {
        debugPrint('Quick Pay: Borrower has no active loans.');
        return false;
      }
      
      final paidTodayLoanIds = await provider.getLoanIdsPaidToday(b.id ?? 0);
      
      final amountCtrl = TextEditingController();
      int? selectedLoanId = activeLoans.length == 1 ? activeLoans.first.id : null;
      
      if (selectedLoanId != null) {
        final l = activeLoans.first;
        if (l.installmentDays != null && l.installmentDays! > 0) {
          amountCtrl.text = (l.totalDue() / l.installmentDays!).toStringAsFixed(0);
        }
      }

      if (!context.mounted) return false;

      final result = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: Text('Quick Pay: ${b.name}'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (activeLoans.length > 1) ...[
                    const Text('Select Loan:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 8),
                    RadioGroup<int>(
                      groupValue: selectedLoanId,
                      onChanged: (val) {
                        setDialogState(() {
                          selectedLoanId = val;
                          final l = activeLoans.firstWhere((l) => (l.id ?? 0) == val, orElse: () => activeLoans.first);
                          if (l.installmentDays != null && l.installmentDays! > 0) {
                            amountCtrl.text = (l.totalDue() / l.installmentDays!).toStringAsFixed(0);
                          } else {
                            amountCtrl.text = '';
                          }
                        });
                      },
                      child: Column(
                        children: activeLoans.map((l) {
                          final isLoanPaidToday = paidTodayLoanIds.contains(l.id);
                          return RadioListTile<int>(
                            value: l.id ?? 0,
                            title: Row(
                              children: [
                                Text('Loan: ${fmtINR(l.loanAmount)}', style: const TextStyle(fontSize: 14)),
                                if (isLoanPaidToday) ...[
                                  const SizedBox(width: 8),
                                  const HugeIcon(icon: HugeIcons.strokeRoundedCheckmarkCircle01, color: AppColors.success, size: 14),
                                ],
                              ],
                            ),
                            subtitle: Text('Date: ${DateFormat('dd MMM').format(l.loanDate)}', style: const TextStyle(fontSize: 12)),
                          );
                        }).toList(),
                      ),
                    ),
                    const Divider(),
                  ],
                  const Text('Amount Received:'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amountCtrl,
                    keyboardType: TextInputType.number,
                    autofocus: activeLoans.length == 1,
                    decoration: const InputDecoration(
                      labelText: 'Amount (₹)',
                      prefixIcon: HugeIcon(icon: HugeIcons.strokeRoundedCurrency),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: selectedLoanId == null ? null : () {
                  final amt = double.tryParse(amountCtrl.text);
                  if (amt != null && amt > 0) {
                    Navigator.pop(ctx, {'loanId': selectedLoanId, 'amount': amt});
                  }
                },
                child: const Text('Confirm'),
              ),
            ],
          ),
        ),
      );

      if (result != null && context.mounted) {
        final loanId = result['loanId'] as int;
        final amount = result['amount'] as double;
        
        await context.read<LoanProvider>().addPayment(Payment(
          loanId: loanId,
          amount: amount,
          paymentDate: DateTime.now(),
          notes: 'Quick Pay (Swipe)',
        ));

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('₹$amount recorded for ${b.name}'),
              backgroundColor: AppColors.accent,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Quick Pay Exception caught: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error performing Quick Pay: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
    return false;
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          HugeIcon(icon: HugeIcons.strokeRoundedUserGroup, size: 64, color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity( 0.2)),
          const SizedBox(height: 16),
          Text(
            "No borrowers found",
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity( 0.6), fontSize: 16),
          ),
        ],
      ),
    );
  }

  List<T> _collectSafe<T>(List<T> list) => List<T>.from(list);
}
