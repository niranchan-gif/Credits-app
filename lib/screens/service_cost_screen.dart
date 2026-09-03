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

class ServiceCostScreen extends StatefulWidget {
  const ServiceCostScreen({super.key});

  @override
  State<ServiceCostScreen> createState() => _ServiceCostScreenState();
}

class _ServiceCostScreenState extends State<ServiceCostScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  String _query = '';
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _amountCtrl.dispose();
    _descriptionCtrl.dispose();
    _searchCtrl.dispose();
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
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
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
    
    // Get creator email from Google Sign-In, or fallback to 'Local Device'
    final createdBy = GoogleDriveService().currentUser?.email ?? 'Local Device';

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
      setState(() {
        _selectedDate = DateTime.now();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Service cost recorded successfully!'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  void _confirmDelete(int id, double amount) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Service Cost?'),
        content: Text('Are you sure you want to delete this service cost entry of ${fmtINR(amount)}? This will restore the hand cash balance.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await context.read<LoanProvider>().deleteServiceCost(id);
              if (mounted) {
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
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Service Costs'),
      ),
      body: Consumer<LoanProvider>(
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
              // 1. Summary Cards
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                sliver: SliverToBoxAdapter(
                  child: Row(
                    children: [
                      _summaryCard('Total Service Cost', fmtINR(provider.totalServiceCosts), LucideIcons.wallet, AppColors.error),
                      const SizedBox(width: 16),
                      _summaryCard('This Month', fmtINR(provider.monthServiceCosts), LucideIcons.calendarRange, AppColors.warning),
                    ],
                  ),
                ),
              ),

              // 2. Add Service Cost Entry Form
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
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) return 'Amount is required';
                              final amt = double.tryParse(v.trim());
                              if (amt == null) return 'Enter a valid number';
                              if (amt <= 0) return 'Amount must be greater than 0';
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
                                color: Theme.of(context).colorScheme.surface.withOpacity( 0.1),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: Theme.of(context).colorScheme.outline.withOpacity( 0.1),
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(LucideIcons.calendar, color: Colors.white, size: 20),
                                  const SizedBox(width: 16),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Service Cost Date',
                                        style: TextStyle(
                                          color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity( 0.6),
                                          fontSize: 11,
                                        ),
                                      ),
                                      Text(
                                        DateFormat('dd MMMM yyyy').format(_selectedDate),
                                        style: TextStyle(
                                          color: Theme.of(context).colorScheme.onSurface,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const Spacer(),
                                  Icon(LucideIcons.chevronRight, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity( 0.6)),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          ElevatedButton.icon(
                            onPressed: _submitServiceCost,
                            icon: const Icon(LucideIcons.plus, size: 18),
                            label: const Text('Add Entry', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // 3. Search Bar for Service Costs
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                sliver: SliverToBoxAdapter(
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: (v) => setState(() => _query = v),
                    decoration: InputDecoration(
                      hintText: "Search descriptions or creators...",
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

              // 4. History List Section Header
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
                          color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity( 0.6),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // 5. History List Cards
              if (costs.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(LucideIcons.receipt, size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity( 0.2)),
                          const SizedBox(height: 16),
                          Text(
                            'No service costs found',
                            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity( 0.6)),
                          ),
                        ],
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
                                    color: AppColors.error.withOpacity( 0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(LucideIcons.arrowUpRight, color: AppColors.error, size: 20),
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
                                          color: Theme.of(context).colorScheme.onSurface,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'By ${sc.createdBy ?? "Unknown"} • ${DateFormat('dd MMM yyyy').format(sc.dateCreated)}',
                                        style: TextStyle(
                                          color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity( 0.6),
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
                                    GestureDetector(
                                      onTap: () {
                                        if (sc.id != null) {
                                          _confirmDelete(sc.id!, sc.amount);
                                        }
                                      },
                                      child: Icon(
                                        LucideIcons.trash2,
                                        size: 16,
                                        color: AppColors.error.withOpacity( 0.6),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ).animate().fadeIn(duration: 400.ms).slideX(begin: 0.1, end: 0);
                      },
                      childCount: costs.length,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _summaryCard(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: PremiumCard(
        padding: const EdgeInsets.all(16),
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
              child: Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Theme.of(context).colorScheme.onSurface)),
            ),
            Text(label, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

