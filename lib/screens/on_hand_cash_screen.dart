import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../providers/loan_provider.dart';
import '../utils/fmt.dart';
import '../utils/app_colors.dart';
import '../widgets/premium_card.dart';
import '../services/google_drive_service.dart';
import 'add_expense_dialog.dart';
import '../services/backup_freshness_service.dart';

class OnHandCashScreen extends StatefulWidget {
  const OnHandCashScreen({super.key});

  @override
  State<OnHandCashScreen> createState() => _OnHandCashScreenState();
}

class _OnHandCashScreenState extends State<OnHandCashScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('On Hand Cash'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          indicatorColor: AppColors.accent,
          labelColor: AppColors.accent,
          unselectedLabelColor:
              Theme.of(context).colorScheme.onSurfaceVariant.withOpacity( 0.6),
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          unselectedLabelStyle: const TextStyle(fontSize: 13),
          tabs: const [
            Tab(text: 'Expense'),
            Tab(text: 'Expense History'),
            Tab(text: 'Service Cost'),
            Tab(text: 'Service Cost History'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _ExpenseTab(),
          _ExpenseHistoryTab(),
          _ServiceCostTab(),
          _ServiceCostHistoryTab(),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TAB 1: Expense (Add Form)
// ─────────────────────────────────────────────────────────────────────────────

class _ExpenseTab extends StatelessWidget {
  const _ExpenseTab();

  @override
  Widget build(BuildContext context) {
    return Consumer<LoanProvider>(
      builder: (context, provider, _) {
        final totalExpenses = provider.totalExpenses;
        final monthExpenses = provider.monthExpenses;

        return CustomScrollView(
          slivers: [
            // Summary Cards
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: [
                    _SummaryCard(
                      label: 'Total Expenses',
                      value: fmtINR(totalExpenses),
                      icon: LucideIcons.wallet,
                      color: AppColors.error,
                    ),
                    const SizedBox(width: 16),
                    _SummaryCard(
                      label: 'This Month',
                      value: fmtINR(monthExpenses),
                      icon: LucideIcons.calendarRange,
                      color: AppColors.warning,
                    ),
                  ],
                ),
              ),
            ),

            // Add Expense Button Card
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
              sliver: SliverToBoxAdapter(
                child: PremiumCard(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Add Expense',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Record a new expense entry for tracking.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant
                              .withOpacity( 0.7),
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: ValueListenableBuilder<bool>(
                          valueListenable: BackupFreshnessService.isReadOnlyMode,
                          builder: (context, isReadOnly, _) {
                            return ElevatedButton.icon(
                              onPressed: isReadOnly
                                  ? null
                                  : () {
                                      showDialog(
                                        context: context,
                                        builder: (_) => const AddExpenseDialog(),
                                      );
                                    },
                              icon: const Icon(LucideIcons.plus, size: 18),
                              label: const Text(
                                'Add Expense Entry',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1, end: 0),
              ),
            ),

            // Recent Expenses Preview
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 12),
              sliver: SliverToBoxAdapter(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Recent Expenses',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      '${provider.expenses.length} total',
                      style: TextStyle(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurfaceVariant
                            .withOpacity( 0.6),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            if (provider.expenses.isEmpty)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
                sliver: SliverToBoxAdapter(
                  child: PremiumCard(
                    padding: const EdgeInsets.all(32),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(LucideIcons.receipt,
                              size: 40,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant
                                  .withOpacity( 0.2)),
                          const SizedBox(height: 12),
                          Text(
                            'No expenses recorded yet',
                            style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant
                                    .withOpacity( 0.6)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final e = provider.expenses[index];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: PremiumCard(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: AppColors.error.withOpacity( 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(LucideIcons.arrowUpRight,
                                    color: AppColors.error, size: 20),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      e.category,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface,
                                      ),
                                    ),
                                    if (e.notes != null && e.notes!.isNotEmpty)
                                      Text(
                                        e.notes!,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant
                                              .withOpacity( 0.6),
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    Text(
                                      DateFormat('dd MMM yyyy')
                                          .format(e.expenseDate),
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant
                                            .withOpacity( 0.5),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                fmtINR(e.amount),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: AppColors.error,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                          .animate()
                          .fadeIn(duration: 300.ms, delay: (index * 40).ms)
                          .slideX(begin: 0.1, end: 0);
                    },
                    childCount:
                        provider.expenses.length > 5 ? 5 : provider.expenses.length,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TAB 2: Expense History
// ─────────────────────────────────────────────────────────────────────────────

class _ExpenseHistoryTab extends StatefulWidget {
  const _ExpenseHistoryTab();

  @override
  State<_ExpenseHistoryTab> createState() => _ExpenseHistoryTabState();
}

class _ExpenseHistoryTabState extends State<_ExpenseHistoryTab> {
  String _query = '';
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _deleteExpense(BuildContext context, int expenseId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Expense?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await context.read<LoanProvider>().deleteExpense(expenseId);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Expense deleted')),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<LoanProvider>(
      builder: (context, provider, _) {
        final expenses = provider.expenses.where((e) {
          if (_query.isEmpty) return true;
          final q = _query.toLowerCase();
          return e.category.toLowerCase().contains(q) ||
              (e.notes ?? '').toLowerCase().contains(q) ||
              e.amount.toString().contains(q);
        }).toList();

        return CustomScrollView(
          slivers: [
            // Summary Card
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: [
                    _SummaryCard(
                      label: 'Total Expenses',
                      value: fmtINR(provider.totalExpenses),
                      icon: LucideIcons.wallet,
                      color: AppColors.error,
                    ),
                    const SizedBox(width: 16),
                    _SummaryCard(
                      label: 'This Month',
                      value: fmtINR(provider.monthExpenses),
                      icon: LucideIcons.calendarRange,
                      color: AppColors.warning,
                    ),
                  ],
                ),
              ),
            ),

            // Search Bar
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              sliver: SliverToBoxAdapter(
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: 'Search expenses...',
                    prefixIcon: const Icon(LucideIcons.search, size: 20),
                    suffixIcon: _query.isNotEmpty
                        ? IconButton(
                            icon: const Icon(LucideIcons.x, size: 16),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _query = '');
                            },
                          )
                        : null,
                  ),
                ),
              ),
            ),

            // Header
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
              sliver: SliverToBoxAdapter(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Expense History',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      '${expenses.length} entries',
                      style: TextStyle(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurfaceVariant
                            .withOpacity( 0.6),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // List
            if (expenses.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(LucideIcons.receipt,
                          size: 48,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant
                              .withOpacity( 0.2)),
                      const SizedBox(height: 16),
                      Text(
                        'No expenses found',
                        style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant
                                .withOpacity( 0.6)),
                      ),
                    ],
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final e = expenses[index];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: PremiumCard(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: AppColors.error.withOpacity( 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(LucideIcons.arrowUpRight,
                                    color: AppColors.error, size: 20),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      e.category,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      DateFormat('dd MMM yyyy')
                                          .format(e.expenseDate),
                                      style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant
                                            .withOpacity( 0.6),
                                        fontSize: 11,
                                      ),
                                    ),
                                    if (e.notes != null && e.notes!.isNotEmpty)
                                      Text(
                                        e.notes!,
                                        style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant
                                              .withOpacity( 0.5),
                                          fontSize: 11,
                                          fontStyle: FontStyle.italic,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    fmtINR(e.amount),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: AppColors.error,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  ValueListenableBuilder<bool>(
                                    valueListenable: BackupFreshnessService.isReadOnlyMode,
                                    builder: (context, isReadOnly, _) {
                                      if (isReadOnly) return const SizedBox.shrink();
                                      return GestureDetector(
                                        onTap: () {
                                          if (e.id != null) {
                                            _deleteExpense(context, e.id!);
                                          }
                                        },
                                        child: Icon(
                                          LucideIcons.trash2,
                                          size: 16,
                                          color:
                                              AppColors.error.withOpacity( 0.6),
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      )
                          .animate()
                          .fadeIn(duration: 400.ms, delay: (index * 50).ms)
                          .slideX(begin: 0.1, end: 0);
                    },
                    childCount: expenses.length,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TAB 3: Service Cost (Add Form)
// ─────────────────────────────────────────────────────────────────────────────

class _ServiceCostTab extends StatefulWidget {
  const _ServiceCostTab();

  @override
  State<_ServiceCostTab> createState() => _ServiceCostTabState();
}

class _ServiceCostTabState extends State<_ServiceCostTab> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  DateTime _selectedDate = DateTime.now();

  @override
  void dispose() {
    _amountCtrl.dispose();
    _descriptionCtrl.dispose();
    super.dispose();
  }

  Future<void> _selectDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context).colorScheme.copyWith(
                primary: AppColors.accent,
                surface: Theme.of(context).colorScheme.surface,
              ),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _submitServiceCost() async {
    if (!_formKey.currentState!.validate()) return;
    final amount = double.tryParse(_amountCtrl.text.trim());
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid amount greater than 0.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    final description = _descriptionCtrl.text.trim();
    final createdBy =
        GoogleDriveService().currentUser?.email ?? 'Local Device';
    final provider = context.read<LoanProvider>();
    await provider.addServiceCost(
      amount,
      description.isEmpty ? null : description,
      _selectedDate,
      createdBy,
    );
    if (mounted) {
      _amountCtrl.clear();
      _descriptionCtrl.clear();
      setState(() => _selectedDate = DateTime.now());
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Service cost recorded successfully!'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<LoanProvider>(
      builder: (context, provider, _) {
        return CustomScrollView(
          slivers: [
            // Summary Cards
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: [
                    _SummaryCard(
                      label: 'Total Service Cost',
                      value: fmtINR(provider.totalServiceCosts),
                      icon: LucideIcons.wallet,
                      color: AppColors.error,
                    ),
                    const SizedBox(width: 16),
                    _SummaryCard(
                      label: 'This Month',
                      value: fmtINR(provider.monthServiceCosts),
                      icon: LucideIcons.calendarRange,
                      color: AppColors.warning,
                    ),
                  ],
                ),
              ),
            ),

            // Add Service Cost Form Card
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
              sliver: SliverToBoxAdapter(
                child: PremiumCard(
                  padding: const EdgeInsets.all(20),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Add Service Cost',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _amountCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return 'Amount is required';
                            }
                            final amt = double.tryParse(v.trim());
                            if (amt == null) return 'Enter a valid number';
                            if (amt <= 0) {
                              return 'Amount must be greater than 0';
                            }
                            return null;
                          },
                          decoration: const InputDecoration(
                            labelText: 'Service Cost Amount (₹) *',
                            prefixIcon: Icon(LucideIcons.coins),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _descriptionCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Service Description (Optional)',
                            prefixIcon: Icon(LucideIcons.text),
                          ),
                        ),
                        const SizedBox(height: 16),
                        InkWell(
                          onTap: () => _selectDate(context),
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surface
                                  .withOpacity( 0.1),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Theme.of(context)
                                    .colorScheme
                                    .outline
                                    .withOpacity( 0.1),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(LucideIcons.calendar,
                                    color: AppColors.accent, size: 20),
                                const SizedBox(width: 16),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Service Cost Date',
                                      style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant
                                            .withOpacity( 0.6),
                                        fontSize: 11,
                                      ),
                                    ),
                                    Text(
                                      DateFormat('dd MMMM yyyy')
                                          .format(_selectedDate),
                                      style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                                const Spacer(),
                                Icon(LucideIcons.chevronRight,
                                    size: 16,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant
                                        .withOpacity( 0.6)),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: ValueListenableBuilder<bool>(
                            valueListenable: BackupFreshnessService.isReadOnlyMode,
                            builder: (context, isReadOnly, _) {
                              return ElevatedButton.icon(
                                onPressed: isReadOnly ? null : _submitServiceCost,
                                icon: const Icon(LucideIcons.plus, size: 18),
                                label: const Text('Add Entry',
                                    style:
                                        TextStyle(fontWeight: FontWeight.bold)),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1, end: 0),
              ),
            ),

            const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TAB 4: Service Cost History
// ─────────────────────────────────────────────────────────────────────────────

class _ServiceCostHistoryTab extends StatefulWidget {
  const _ServiceCostHistoryTab();

  @override
  State<_ServiceCostHistoryTab> createState() => _ServiceCostHistoryTabState();
}

class _ServiceCostHistoryTabState extends State<_ServiceCostHistoryTab> {
  String _query = '';
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _confirmDelete(BuildContext context, int id, double amount) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Service Cost?'),
        content: Text(
            'Are you sure you want to delete this service cost entry of ${fmtINR(amount)}? This will restore the hand cash balance.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await context.read<LoanProvider>().deleteServiceCost(id);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Service cost record deleted')),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<LoanProvider>(
      builder: (context, provider, _) {
        final costs = provider.serviceCosts.where((sc) {
          if (_query.isEmpty) return true;
          final q = _query.toLowerCase();
          return (sc.description ?? '').toLowerCase().contains(q) ||
              sc.amount.toString().contains(q) ||
              (sc.createdBy ?? '').toLowerCase().contains(q);
        }).toList();

        return CustomScrollView(
          slivers: [
            // Summary Cards
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: [
                    _SummaryCard(
                      label: 'Total Service Cost',
                      value: fmtINR(provider.totalServiceCosts),
                      icon: LucideIcons.wallet,
                      color: AppColors.error,
                    ),
                    const SizedBox(width: 16),
                    _SummaryCard(
                      label: 'This Month',
                      value: fmtINR(provider.monthServiceCosts),
                      icon: LucideIcons.calendarRange,
                      color: AppColors.warning,
                    ),
                  ],
                ),
              ),
            ),

            // Search Bar
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              sliver: SliverToBoxAdapter(
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: 'Search descriptions or creators...',
                    prefixIcon: const Icon(LucideIcons.search, size: 20),
                    suffixIcon: _query.isNotEmpty
                        ? IconButton(
                            icon: const Icon(LucideIcons.x, size: 16),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _query = '');
                            },
                          )
                        : null,
                  ),
                ),
              ),
            ),

            // Header
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
              sliver: SliverToBoxAdapter(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Service Cost History',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      '${costs.length} entries',
                      style: TextStyle(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurfaceVariant
                            .withOpacity( 0.6),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // List
            if (costs.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(LucideIcons.receipt,
                          size: 48,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant
                              .withOpacity( 0.2)),
                      const SizedBox(height: 16),
                      Text(
                        'No service costs found',
                        style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant
                                .withOpacity( 0.6)),
                      ),
                    ],
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final sc = costs[index];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: PremiumCard(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color:
                                      AppColors.error.withOpacity( 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(LucideIcons.arrowUpRight,
                                    color: AppColors.error, size: 20),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      sc.description ?? 'Service Cost',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'By ${sc.createdBy ?? "Unknown"} • ${DateFormat('dd MMM yyyy').format(sc.dateCreated)}',
                                      style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant
                                            .withOpacity( 0.6),
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    fmtINR(sc.amount),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: AppColors.error,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  ValueListenableBuilder<bool>(
                                    valueListenable: BackupFreshnessService.isReadOnlyMode,
                                    builder: (context, isReadOnly, _) {
                                      if (isReadOnly) return const SizedBox.shrink();
                                      return GestureDetector(
                                        onTap: () {
                                          if (sc.id != null) {
                                            _confirmDelete(
                                                context, sc.id!, sc.amount);
                                          }
                                        },
                                        child: Icon(
                                          LucideIcons.trash2,
                                          size: 16,
                                          color: AppColors.error
                                              .withOpacity( 0.6),
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      )
                          .animate()
                          .fadeIn(duration: 400.ms, delay: (index * 50).ms)
                          .slideX(begin: 0.1, end: 0);
                    },
                    childCount: costs.length,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared Summary Card Widget
// ─────────────────────────────────────────────────────────────────────────────

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: PremiumCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity( 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 16),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

