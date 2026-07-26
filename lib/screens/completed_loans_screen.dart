import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';

import '../database/db_helper.dart';
import '../utils/app_colors.dart';
import '../utils/fmt.dart';
import '../widgets/premium_card.dart';

class CompletedLoansScreen extends StatefulWidget {
  const CompletedLoansScreen({super.key});

  @override
  State<CompletedLoansScreen> createState() => _CompletedLoansScreenState();
}

class _CompletedLoansScreenState extends State<CompletedLoansScreen> {
  List<Map<String, dynamic>> _allLoans = [];
  List<Map<String, dynamic>> _filteredLoans = [];
  bool _loading = true;
  String _query = '';
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final data = await DBHelper().getCompletedLoans();
      if (mounted) {
        setState(() {
          _allLoans = data;
          _filteredLoans = data;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _filter(String query) {
    setState(() {
      _query = query;
      _filteredLoans = _allLoans.where((loan) {
        final name = (loan['borrower_name'] as String? ?? '').toLowerCase();
        final code = (loan['borrower_code'] as String? ?? '').toLowerCase();
        final q = query.toLowerCase();
        return name.contains(q) || code.contains(q);
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text("Completed Loans"),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: _filter,
                    decoration: InputDecoration(
                      hintText: "Search name or code...",
                      prefixIcon: const Icon(LucideIcons.search, size: 20),
                      suffixIcon: _query.isNotEmpty
                          ? IconButton(
                              icon: const Icon(LucideIcons.x, size: 16),
                              onPressed: () {
                                _searchCtrl.clear();
                                _filter('');
                              },
                            )
                          : null,
                    ),
                  ),
                ),
                Expanded(
                  child: _filteredLoans.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(LucideIcons.checkSquare, size: 64, color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.2)),
                              const SizedBox(height: 16),
                              Text(
                                _query.isEmpty ? "No completed loans found" : "No matching completed loans",
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.6),
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
                          itemCount: _filteredLoans.length,
                          itemBuilder: (context, index) {
                            final loan = _filteredLoans[index];
                            final borrowerName = loan['borrower_name'] as String? ?? '';
                            String borrowerCode = loan['borrower_code'] as String? ?? '';
                            if (borrowerCode.contains('_del_')) {
                              borrowerCode = borrowerCode.split('_del_').first;
                            }
                            final loanAmount = (loan['loan_amount'] as num?)?.toDouble() ?? 0.0;
                            final interestAmount = (loan['interest_amount'] as num?)?.toDouble() ?? 0.0;
                            final totalLoan = loanAmount + interestAmount;
                            
                            final loanDateStr = loan['loan_date'] as String? ?? '';
                            final endDateStr = loan['end_date'] as String? ?? '';
                            
                            DateTime? loanDate;
                            DateTime? endDate;
                            try {
                              loanDate = DateTime.parse(loanDateStr);
                            } catch (_) {}
                            try {
                              endDate = DateTime.parse(endDateStr);
                            } catch (_) {}

                            final df = DateFormat('dd MMM yyyy');

                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              child: PremiumCard(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: AppColors.accent.withOpacity(0.1),
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: Text(
                                                borrowerCode,
                                                style: const TextStyle(
                                                  color: AppColors.accent,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Text(
                                              borrowerName,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 15,
                                              ),
                                            ),
                                          ],
                                        ),
                                        Text(
                                          fmtINR(totalLoan),
                                          style: const TextStyle(
                                            color: AppColors.success,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    const Divider(height: 1),
                                    const SizedBox(height: 12),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              "Principal: ${fmtINR(loanAmount)}",
                                              style: TextStyle(
                                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                                                fontSize: 12,
                                              ),
                                            ),
                                            Text(
                                              "Interest: ${fmtINR(interestAmount)}",
                                              style: TextStyle(
                                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          children: [
                                            if (loanDate != null)
                                              Text(
                                                "Lent: ${df.format(loanDate)}",
                                                style: TextStyle(
                                                  color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.7),
                                                  fontSize: 11,
                                                ),
                                              ),
                                            if (endDate != null)
                                              Text(
                                                "Cleared: ${df.format(endDate)}",
                                                style: const TextStyle(
                                                  color: AppColors.success,
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 11,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
