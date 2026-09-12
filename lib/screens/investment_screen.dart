import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../providers/loan_provider.dart';
import '../utils/fmt.dart';
import '../utils/date_parser.dart';
import '../utils/app_colors.dart';

enum _TimeFilter { all, thisMonth, thisYear }

class InvestmentScreen extends StatefulWidget {
  const InvestmentScreen({super.key});

  @override
  State<InvestmentScreen> createState() => _InvestmentScreenState();
}

class _InvestmentScreenState extends State<InvestmentScreen> {
  _TimeFilter _activeFilter = _TimeFilter.all;
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      final q = _searchCtrl.text.trim().toLowerCase();
      if (q != _searchQuery) {
        setState(() => _searchQuery = q);
      }
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Add Investment Bottom Sheet
  // ───────────────────────────────────────────────────────────────────────────

  void _showAddInvestmentSheet() {
    final amountCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    DateTime selectedDate = DateTime.now();
    bool isSubmitting = false;

    final presetNotes = ['Owner Capital', 'Working Capital', 'Bank Transfer', 'Emergency Top-up'];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final surfaceColor = Theme.of(ctx).colorScheme.surface;
        final onSurface = Theme.of(ctx).colorScheme.onSurface;
        final onSurfaceVariant = Theme.of(ctx).colorScheme.onSurfaceVariant;

        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            return Container(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 12,
                bottom: MediaQuery.of(modalCtx).viewInsets.bottom + 24,
              ),
              decoration: BoxDecoration(
                color: surfaceColor,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 30,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Handle Bar
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: onSurfaceVariant.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),

                    // Header
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.accent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(LucideIcons.trendingUp, color: AppColors.accent, size: 20),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Add Capital Investment',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: onSurface,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Inject capital into your business cash reserve',
                                style: TextStyle(fontSize: 12, color: onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),

                    // Amount Input
                    TextField(
                      controller: amountCtrl,
                      autofocus: true,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: onSurface,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Investment Amount (₹)',
                        labelStyle: TextStyle(fontSize: 14, color: onSurfaceVariant),
                        prefixIcon: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 14),
                          child: Icon(LucideIcons.indianRupee, size: 22, color: AppColors.accent),
                        ),
                        prefixIconConstraints: const BoxConstraints(minWidth: 48),
                        filled: true,
                        fillColor: isDark
                            ? Colors.white.withValues(alpha: 0.05)
                            : Colors.black.withValues(alpha: 0.03),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(color: onSurfaceVariant.withValues(alpha: 0.2)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(color: onSurfaceVariant.withValues(alpha: 0.2)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(color: AppColors.accent, width: 2),
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Date Picker Tile
                    InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: modalCtx,
                          initialDate: selectedDate,
                          firstDate: DateTime(2000),
                          lastDate: DateTime.now().add(const Duration(days: 1)),
                          builder: (context, child) {
                            return Theme(
                              data: Theme.of(context).copyWith(
                                colorScheme: Theme.of(context).colorScheme.copyWith(primary: AppColors.accent),
                              ),
                              child: child!,
                            );
                          },
                        );
                        if (picked != null) {
                          setModalState(() => selectedDate = picked);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.05)
                              : Colors.black.withValues(alpha: 0.03),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: onSurfaceVariant.withValues(alpha: 0.2)),
                        ),
                        child: Row(
                          children: [
                            const Icon(LucideIcons.calendar, size: 20, color: AppColors.accent),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Investment Date',
                                    style: TextStyle(fontSize: 11, color: onSurfaceVariant),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    DateFormat('EEE, dd MMMM yyyy').format(selectedDate),
                                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: onSurface),
                                  ),
                                ],
                              ),
                            ),
                            Icon(LucideIcons.chevronRight, size: 16, color: onSurfaceVariant),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Notes Input
                    TextField(
                      controller: notesCtrl,
                      style: TextStyle(fontSize: 14, color: onSurface),
                      decoration: InputDecoration(
                        labelText: 'Notes / Source (Optional)',
                        labelStyle: TextStyle(fontSize: 13, color: onSurfaceVariant),
                        prefixIcon: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 14),
                          child: Icon(LucideIcons.fileText, size: 20, color: AppColors.accent),
                        ),
                        prefixIconConstraints: const BoxConstraints(minWidth: 48),
                        filled: true,
                        fillColor: isDark
                            ? Colors.white.withValues(alpha: 0.05)
                            : Colors.black.withValues(alpha: 0.03),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(color: onSurfaceVariant.withValues(alpha: 0.2)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(color: onSurfaceVariant.withValues(alpha: 0.2)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(color: AppColors.accent, width: 2),
                        ),
                      ),
                    ),

                    const SizedBox(height: 10),

                    // Preset Note Suggestions
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: presetNotes.map((note) {
                        return ActionChip(
                          label: Text(
                            note,
                            style: TextStyle(fontSize: 11, color: onSurfaceVariant),
                          ),
                          backgroundColor: isDark
                              ? Colors.white.withValues(alpha: 0.06)
                              : Colors.black.withValues(alpha: 0.04),
                          side: BorderSide(color: onSurfaceVariant.withValues(alpha: 0.15)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          onPressed: () {
                            notesCtrl.text = note;
                            setModalState(() {});
                          },
                        );
                      }).toList(),
                    ),

                    const SizedBox(height: 24),

                    // Submit Button
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          foregroundColor: Colors.white,
                          elevation: 2,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        icon: isSubmitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(LucideIcons.check, size: 20),
                        label: Text(
                          isSubmitting ? 'Saving...' : 'Add Investment',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        onPressed: isSubmitting
                            ? null
                            : () async {
                                final amount = double.tryParse(amountCtrl.text.trim()) ?? 0;
                                if (amount <= 0) {
                                  HapticFeedback.vibrate();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Please enter a valid investment amount.'),
                                      backgroundColor: AppColors.error,
                                    ),
                                  );
                                  return;
                                }

                                setModalState(() => isSubmitting = true);
                                HapticFeedback.mediumImpact();

                                await Provider.of<LoanProvider>(context, listen: false).addInvestment(
                                  amount,
                                  selectedDate,
                                  notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
                                );

                                if (modalCtx.mounted) {
                                  Navigator.pop(modalCtx);
                                }
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Added ${fmtINR(amount)} to investments successfully.'),
                                      backgroundColor: AppColors.success,
                                    ),
                                  );
                                }
                              },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Delete Investment Confirmation
  // ───────────────────────────────────────────────────────────────────────────

  Future<void> _deleteInvestment(int id, double amount, DateTime date) async {
    HapticFeedback.lightImpact();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(LucideIcons.alertTriangle, color: AppColors.error, size: 22),
            SizedBox(width: 10),
            Text('Delete Investment?'),
          ],
        ),
        content: Text(
          'Are you sure you want to remove the investment of ${fmtINR(amount)} from ${DateFormat('dd MMM yyyy').format(date)}?\n\nThis will update your total invested capital and on-hand cash reserve.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      HapticFeedback.mediumImpact();
      await Provider.of<LoanProvider>(context, listen: false).deleteInvestment(id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Investment deleted successfully.'),
            backgroundColor: AppColors.accent,
          ),
        );
      }
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Main Build
  // ───────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Capital Investments'),
        elevation: 0,
      ),
      body: Consumer<LoanProvider>(
        builder: (context, provider, _) {
          final allInvestments = provider.investments;
          final totalInvested = provider.totalInvested;
          final now = DateTime.now();

          // Apply filters
          final filteredInvestments = allInvestments.where((inv) {
            final date = DateParser.safeParse(inv['inv_date']);
            if (_activeFilter == _TimeFilter.thisMonth) {
              if (date.year != now.year || date.month != now.month) return false;
            } else if (_activeFilter == _TimeFilter.thisYear) {
              if (date.year != now.year) return false;
            }

            if (_searchQuery.isNotEmpty) {
              final notes = (inv['notes'] ?? '').toString().toLowerCase();
              final amountStr = ((inv['amount'] as num?)?.toDouble() ?? 0.0).toString();
              if (!notes.contains(_searchQuery) && !amountStr.contains(_searchQuery)) {
                return false;
              }
            }
            return true;
          }).toList();

          return CustomScrollView(
            slivers: [
              // 1. Hero Portfolio Card (Total Invested)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
                sliver: SliverToBoxAdapter(
                  child: _buildPortfolioHero(
                    totalInvested: totalInvested,
                    isDark: isDark,
                  ),
                ),
              ),

              // 2. Search & Time Filter Controls
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
                sliver: SliverToBoxAdapter(
                  child: _buildControls(
                    allCount: allInvestments.length,
                    isDark: isDark,
                  ),
                ),
              ),

              // 3. Transactions Header
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                sliver: SliverToBoxAdapter(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Investment History',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface,
                          letterSpacing: 0.2,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.accent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${filteredInvestments.length} record${filteredInvestments.length == 1 ? '' : 's'}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.accent,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // 4. Transaction List or Empty State
              if (filteredInvestments.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _buildEmptyState(
                    hasInvestments: allInvestments.isNotEmpty,
                    isDark: isDark,
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(18, 4, 18, 100),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (ctx, idx) {
                        final inv = filteredInvestments[idx];
                        return _buildInvestmentCard(inv, isDark);
                      },
                      childCount: filteredInvestments.length,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.white,
        elevation: 4,
        icon: const Icon(LucideIcons.plus, size: 20),
        label: const Text(
          'Add Investment',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        onPressed: _showAddInvestmentSheet,
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Hero Portfolio Card
  // ───────────────────────────────────────────────────────────────────────────

  Widget _buildPortfolioHero({
    required double totalInvested,
    required bool isDark,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF0F382C), const Color(0xFF07211A)]
              : [const Color(0xFF285A48), const Color(0xFF1B3F32)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F382C).withValues(alpha: isDark ? 0.4 : 0.25),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.12),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Total Invested',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Colors.white.withValues(alpha: 0.8),
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              fmtINR(totalInvested),
              style: const TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: -0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Controls: Search & Filter Tabs
  // ───────────────────────────────────────────────────────────────────────────

  Widget _buildControls({
    required int allCount,
    required bool isDark,
  }) {
    final surfaceColor = Theme.of(context).colorScheme.surface;
    final onSurfaceVariant = Theme.of(context).colorScheme.onSurfaceVariant;

    return Column(
      children: [
        // Search bar
        Container(
          height: 46,
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: onSurfaceVariant.withValues(alpha: 0.15),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: TextField(
            controller: _searchCtrl,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Search notes or amount...',
              hintStyle: TextStyle(fontSize: 13, color: onSurfaceVariant.withValues(alpha: 0.7)),
              prefixIcon: Icon(LucideIcons.search, size: 18, color: onSurfaceVariant),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(LucideIcons.x, size: 16),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),

        const SizedBox(height: 10),

        // Filter Pills Row
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildFilterChip(
                label: 'All Time',
                filter: _TimeFilter.all,
                icon: LucideIcons.layers,
              ),
              const SizedBox(width: 8),
              _buildFilterChip(
                label: 'This Month',
                filter: _TimeFilter.thisMonth,
                icon: LucideIcons.calendarDays,
              ),
              const SizedBox(width: 8),
              _buildFilterChip(
                label: 'This Year',
                filter: _TimeFilter.thisYear,
                icon: LucideIcons.calendarRange,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFilterChip({
    required String label,
    required _TimeFilter filter,
    required IconData icon,
  }) {
    final isSelected = _activeFilter == filter;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _activeFilter = filter);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.accent
              : (isDark ? const Color(0xFF2C2C2E) : Colors.white),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? AppColors.accent
                : Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.2),
            width: 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.accent.withValues(alpha: 0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: isSelected ? Colors.white : AppColors.accent,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected
                    ? Colors.white
                    : Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Investment Transaction Card
  // ───────────────────────────────────────────────────────────────────────────

  Widget _buildInvestmentCard(Map<String, dynamic> inv, bool isDark) {
    final amount = (inv['amount'] as num?)?.toDouble() ?? 0.0;
    final date = DateParser.safeParse(inv['inv_date']);
    final notes = inv['notes'] as String?;
    final id = inv['id'] as int;

    final onSurface = Theme.of(context).colorScheme.onSurface;
    final onSurfaceVariant = Theme.of(context).colorScheme.onSurfaceVariant;

    // Check if date is today or yesterday
    final now = DateTime.now();
    final isToday = date.year == now.year && date.month == now.month && date.day == now.day;
    final yesterday = now.subtract(const Duration(days: 1));
    final isYesterday = date.year == yesterday.year && date.month == yesterday.month && date.day == yesterday.day;

    String dateLabel;
    if (isToday) {
      dateLabel = 'Today';
    } else if (isYesterday) {
      dateLabel = 'Yesterday';
    } else {
      dateLabel = DateFormat('dd MMM yyyy').format(date);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: onSurfaceVariant.withValues(alpha: 0.12),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Left Growth Badge
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    AppColors.accent.withValues(alpha: 0.2),
                    AppColors.accent.withValues(alpha: 0.06),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(
                  color: AppColors.accent.withValues(alpha: 0.3),
                  width: 1.5,
                ),
              ),
              child: const Center(
                child: Icon(
                  LucideIcons.arrowUpRight,
                  color: AppColors.accent,
                  size: 20,
                ),
              ),
            ),

            const SizedBox(width: 14),

            // Middle: Amount & Notes
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '+ ${fmtINR(amount)}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppColors.accent,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: isToday
                              ? AppColors.accent.withValues(alpha: 0.12)
                              : onSurfaceVariant.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          dateLabel,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: isToday ? FontWeight.bold : FontWeight.w500,
                            color: isToday ? AppColors.accent : onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  if (notes != null && notes.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 2),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.06)
                            : Colors.black.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        notes,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: onSurface.withValues(alpha: 0.85),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    )
                  else
                    Text(
                      'Capital Infusion',
                      style: TextStyle(
                        fontSize: 12,
                        color: onSurfaceVariant.withValues(alpha: 0.7),
                      ),
                    ),
                ],
              ),
            ),

            // Trailing Delete Action
            IconButton(
              icon: Icon(
                LucideIcons.trash2,
                size: 18,
                color: onSurfaceVariant.withValues(alpha: 0.6),
              ),
              splashRadius: 20,
              onPressed: () => _deleteInvestment(id, amount, date),
            ),
          ],
        ),
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Empty State
  // ───────────────────────────────────────────────────────────────────────────

  Widget _buildEmptyState({
    required bool hasInvestments,
    required bool isDark,
  }) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final onSurfaceVariant = Theme.of(context).colorScheme.onSurfaceVariant;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Multi-ring glowing icon container
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.accent.withValues(alpha: 0.08),
                border: Border.all(
                  color: AppColors.accent.withValues(alpha: 0.2),
                  width: 2,
                ),
              ),
              child: Center(
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.accent.withValues(alpha: 0.15),
                  ),
                  child: const Icon(
                    LucideIcons.piggyBank,
                    size: 32,
                    color: AppColors.accent,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              hasInvestments ? 'No Matching Investments' : 'No Capital Injected Yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              hasInvestments
                  ? 'Try changing the time filter or clearing your search term.'
                  : 'Add capital investments to fund your loan disbursements and accurately monitor liquidity.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            if (hasInvestments)
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  side: const BorderSide(color: AppColors.accent),
                ),
                icon: const Icon(LucideIcons.rotateCcw, size: 16, color: AppColors.accent),
                label: const Text('Clear Filters', style: TextStyle(color: AppColors.accent)),
                onPressed: () {
                  _searchCtrl.clear();
                  setState(() {
                    _activeFilter = _TimeFilter.all;
                    _searchQuery = '';
                  });
                },
              )
            else
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(LucideIcons.plus, size: 18),
                label: const Text('Add First Investment', style: TextStyle(fontWeight: FontWeight.bold)),
                onPressed: _showAddInvestmentSheet,
              ),
          ],
        ),
      ),
    );
  }
}
