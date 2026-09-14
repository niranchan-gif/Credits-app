import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

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
  String? _selectedAddress;

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

          final collectList = provider.collectBorrowers;
          final paidList = provider.paidBorrowers;
          final completedList = provider.closedBorrowers;
          final dummyList = provider.dummyBorrowers;

          // Extract all unique non-empty addresses
          final allAddresses = provider.borrowers
              .map((b) => b.address?.trim())
              .where((a) => a != null && a.isNotEmpty)
              .cast<String>()
              .toSet()
              .toList()
            ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

          // Count borrowers per address
          final Map<String, int> addressCounts = {};
          for (final b in provider.borrowers) {
            final addr = b.address?.trim();
            if (addr != null && addr.isNotEmpty) {
              addressCounts[addr] = (addressCounts[addr] ?? 0) + 1;
            }
          }

          final source = [_collectSafe(collectList), _collectSafe(paidList), _collectSafe(completedList), _collectSafe(dummyList)][_tab];

          return Consumer<LoanProvider>(
            key: ValueKey<int>(_tab),
            builder: (context, provider, _) {
                final items = source.where((b) {
                  // Address filter
                  if (_selectedAddress != null && _selectedAddress!.isNotEmpty) {
                    final addr = (b.address ?? '').trim().toLowerCase();
                    if (addr != _selectedAddress!.trim().toLowerCase()) {
                      return false;
                    }
                  }

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
                  child: MediaQuery.removePadding(
                    context: context,
                    removeTop: true,
                    child: CustomScrollView(
                      slivers: [
                        SliverToBoxAdapter(child: _buildHeader(totalDue, totalCollected, totalPending, todayCollection, provider)),
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
                          sliver: SliverToBoxAdapter(
                            child: _buildSearch(allAddresses, addressCounts, provider),
                          ),
                        ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 2, 16, 12),
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
                ),
                );
              },
            );
        },
      ),
    );
  }

  Widget _buildHeader(double due, double collected, double pending, double today, LoanProvider provider) {
    return Container(
      width: double.infinity,
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        gradient: Theme.of(context).brightness == Brightness.dark ? AppColors.surfaceGradientDark : AppColors.surfaceGradient,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
      ),
      child: Stack(
        children: [
          // Decorative Background Elements
          Positioned(
            top: -40,
            right: -40,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
              ),
            ),
          ),
          Positioned(
            top: 80,
            left: -50,
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.06),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + 12, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Hero(
                      tag: 'logo_hero',
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Image.asset(
                          'assets/icon/logo.png',
                          height: 38, // Refined size
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    const SyncStatusIndicator(compact: true),
                  ],
                ),
                const SizedBox(height: 24),
                Stack(
                  clipBehavior: Clip.none,
                  children: [
              // 1. Financial Element: Trending Up (Top Right)
              Positioned(
                top: -15,
                right: -10,
                child: Icon(
                  LucideIcons.trendingUp,
                  size: 80,
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.10),
                ),
              ),
              // 2. Financial Element: Pie Chart (Bottom Left)
              Positioned(
                bottom: -20,
                left: -15,
                child: Transform.rotate(
                  angle: -0.2,
                  child: Icon(
                    LucideIcons.pieChart,
                    size: 90,
                    color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.12),
                  ),
                ),
              ),
              PremiumCard(
                padding: EdgeInsets.zero,
                gradient: AppColors.primaryGradient,
                child: Stack(
                  children: [
                    // Inner professional watermark icon
                    Positioned(
                      right: -20,
                      bottom: -20,
                      child: Icon(
                        LucideIcons.banknote,
                        size: 120,
                        color: Colors.white.withValues(alpha: 0.10),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                "Today's Collection",
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.88),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  letterSpacing: 0.2,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.15),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  LucideIcons.calendarCheck,
                                  size: 16,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            fmtINR(today),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 34,
                              fontWeight: FontWeight.bold,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildActionButtons(context),
        ],
      ),
    ),
  ],
),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ValueListenableBuilder<bool>(
      valueListenable: BackupFreshnessService.isReadOnlyMode,
      builder: (context, isReadOnly, _) {
        return Row(
          children: [
            // Quick Add Button (Primary Accent)
            Expanded(
              child: Container(
                height: 46,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: isReadOnly
                      ? null
                      : [
                          BoxShadow(
                            color: AppColors.accent.withValues(alpha: 0.25),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                ),
                child: Material(
                  color: isReadOnly
                      ? (isDark ? Colors.white12 : Colors.grey.shade300)
                      : AppColors.accent,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    onTap: isReadOnly
                        ? null
                        : () {
                            HapticFeedback.lightImpact();
                            showDialog(
                              context: context,
                              builder: (context) => const QuickAddDialog(),
                            );
                          },
                    borderRadius: BorderRadius.circular(14),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          LucideIcons.zap,
                          size: 16,
                          color: isReadOnly
                              ? (isDark ? Colors.white38 : Colors.grey)
                              : Colors.white,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          "Quick Add",
                          style: TextStyle(
                            color: isReadOnly
                                ? (isDark ? Colors.white38 : Colors.grey)
                                : Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            letterSpacing: 0.1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Add Borrower Button (Secondary Outlined / Tinted)
            Expanded(
              child: Container(
                height: 46,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: isReadOnly
                      ? null
                      : [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                ),
                child: Material(
                  color: isReadOnly
                      ? (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.shade100)
                      : (isDark ? Colors.white.withValues(alpha: 0.08) : AppColors.accent.withValues(alpha: 0.07)),
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    onTap: isReadOnly
                        ? null
                        : () {
                            HapticFeedback.lightImpact();
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const AddBorrowerScreen(),
                              ),
                            );
                          },
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isReadOnly
                              ? (isDark ? Colors.white12 : Colors.grey.shade300)
                              : (isDark ? Colors.white24 : AppColors.accent.withValues(alpha: 0.35)),
                          width: 1.2,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            LucideIcons.userPlus,
                            size: 16,
                            color: isReadOnly
                                ? (isDark ? Colors.white38 : Colors.grey)
                                : (isDark ? Colors.white : AppColors.accent),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            "Add Borrower",
                            style: TextStyle(
                              color: isReadOnly
                                  ? (isDark ? Colors.white38 : Colors.grey)
                                  : (isDark ? Colors.white : AppColors.accent),
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              letterSpacing: 0.1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSearch(List<String> addresses, Map<String, int> counts, LoanProvider provider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: "Search name, ID, address...",
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
            if (addresses.isNotEmpty) ...[
              const SizedBox(width: 8),
              _buildAddressFilterButton(addresses, counts, provider),
            ],
          ],
        ),
        if (_selectedAddress != null) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppColors.accent.withValues(alpha: 0.25),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(LucideIcons.mapPin, size: 12, color: AppColors.accent),
                    const SizedBox(width: 5),
                    Text(
                      _selectedAddress!,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.accent,
                      ),
                    ),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: () => setState(() => _selectedAddress = null),
                      child: const Icon(LucideIcons.x, size: 13, color: AppColors.accent),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => setState(() => _selectedAddress = null),
                child: Text(
                  "Clear filter",
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildAddressFilterButton(List<String> addresses, Map<String, int> counts, LoanProvider provider) {
    final hasActiveFilter = _selectedAddress != null && _selectedAddress!.isNotEmpty;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showAddressFilterModal(addresses, counts, provider),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 50,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: hasActiveFilter
                ? AppColors.accent
                : (isDark ? const Color(0xFF1E2622) : Theme.of(context).colorScheme.surface),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: hasActiveFilter
                  ? AppColors.accent
                  : (isDark ? Colors.white.withValues(alpha: 0.12) : const Color(0xFF285A48).withValues(alpha: 0.14)),
              width: 1,
            ),
            boxShadow: hasActiveFilter
                ? [
                    BoxShadow(
                      color: AppColors.accent.withValues(alpha: 0.3),
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
                LucideIcons.slidersHorizontal,
                size: 18,
                color: hasActiveFilter
                    ? Colors.white
                    : (isDark ? Colors.white : AppColors.accent),
              ),
              if (hasActiveFilter) ...[
                const SizedBox(width: 6),
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showAddressFilterModal(List<String> addresses, Map<String, int> counts, LoanProvider provider) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final searchFilterCtrl = TextEditingController();
    String filterQuery = '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final filteredOptions = addresses.where((a) {
              if (filterQuery.trim().isEmpty) return true;
              return a.toLowerCase().contains(filterQuery.toLowerCase().trim());
            }).toList();

            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.75,
              ),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1A231F) : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 12),
                  // Drag handle
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white24 : Colors.black12,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Title & Clear
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.accent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(LucideIcons.mapPin, size: 18, color: AppColors.accent),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Filter by Address",
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white : const Color(0xFF15221B),
                                ),
                              ),
                              Text(
                                "${addresses.length} unique addresses found",
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark ? const Color(0xFF8FA89A) : const Color(0xFF5A7A68),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_selectedAddress != null)
                          TextButton(
                            onPressed: () {
                              setState(() => _selectedAddress = null);
                              Navigator.pop(ctx);
                            },
                            child: const Text("Clear", style: TextStyle(color: AppColors.error)),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  // Search within addresses
                  if (addresses.length > 4)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: TextField(
                        controller: searchFilterCtrl,
                        onChanged: (val) => setModalState(() => filterQuery = val),
                        decoration: InputDecoration(
                          hintText: "Search addresses...",
                          prefixIcon: const Icon(LucideIcons.search, size: 18),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 10),
                          filled: true,
                          fillColor: isDark ? const Color(0xFF141C18) : const Color(0xFFF2F6F4),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  const Divider(height: 1),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      children: [
                        // "All Addresses" option
                        ListTile(
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: _selectedAddress == null
                                  ? AppColors.accent
                                  : (isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05)),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              LucideIcons.layoutGrid,
                              size: 16,
                              color: _selectedAddress == null
                                  ? Colors.white
                                  : (isDark ? Colors.white70 : Colors.black54),
                            ),
                          ),
                          title: Text(
                            "All Addresses",
                            style: TextStyle(
                              fontWeight: _selectedAddress == null ? FontWeight.bold : FontWeight.w500,
                              color: _selectedAddress == null
                                  ? AppColors.accent
                                  : (isDark ? Colors.white : Colors.black87),
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                "${provider.borrowers.length}",
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark ? Colors.white38 : Colors.black38,
                                ),
                              ),
                              if (_selectedAddress == null) ...[
                                const SizedBox(width: 8),
                                const Icon(LucideIcons.check, size: 18, color: AppColors.accent),
                              ],
                            ],
                          ),
                          onTap: () {
                            setState(() => _selectedAddress = null);
                            Navigator.pop(ctx);
                          },
                        ),
                        ...filteredOptions.map((addr) {
                          final isSelected = _selectedAddress != null &&
                              _selectedAddress!.toLowerCase() == addr.toLowerCase();
                          final count = counts[addr] ?? 0;

                          return ListTile(
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? AppColors.accent
                                    : (isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05)),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                LucideIcons.mapPin,
                                size: 16,
                                color: isSelected
                                    ? Colors.white
                                    : (isDark ? Colors.white70 : Colors.black54),
                              ),
                            ),
                            title: Text(
                              addr,
                              style: TextStyle(
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                color: isSelected
                                    ? AppColors.accent
                                    : (isDark ? Colors.white : Colors.black87),
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    "$count ${count == 1 ? 'borrower' : 'borrowers'}",
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isDark ? Colors.white70 : Colors.black54,
                                    ),
                                  ),
                                ),
                                if (isSelected) ...[
                                  const SizedBox(width: 8),
                                  const Icon(LucideIcons.check, size: 18, color: AppColors.accent),
                                ],
                              ],
                            ),
                            onTap: () {
                              setState(() {
                                _selectedAddress = isSelected ? null : addr;
                              });
                              Navigator.pop(ctx);
                            },
                          );
                        }),
                        if (filteredOptions.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 32),
                            child: Center(
                              child: Text(
                                "No addresses matching '$filterQuery'",
                                style: TextStyle(
                                  color: isDark ? Colors.white38 : Colors.black38,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildTabs(int collect, int paid, int completed, int dummy) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark ? AppColors.cardBorderDark : AppColors.cardBorderLight,
          width: 1,
        ),
        boxShadow: isDark
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ]
            : [
                BoxShadow(
                  color: const Color(0xFF0F172A).withValues(alpha: 0.04),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ],
      ),
      child: Row(
        children: [
          _tabItem(0, "Collect", collect.toString(), AppColors.accent),
          _tabItem(1, "Paid", paid.toString(), AppColors.accent),
          _tabItem(2, "Closed", completed.toString(), AppColors.accent),
          _tabItem(3, "Inactive", dummy.toString(), Colors.grey),
        ],
      ),
    );
  }

  Widget _tabItem(int index, String label, String topText, Color color) {
    final isSelected = _tab == index;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _tab = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          decoration: BoxDecoration(
            color: isSelected
                ? (isDark
                    ? AppColors.accent.withValues(alpha: 0.22)
                    : AppColors.accent.withValues(alpha: 0.12))
                : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
            border: isSelected
                ? Border.all(
                    color: isDark
                        ? color.withValues(alpha: 0.3)
                        : color.withValues(alpha: 0.2),
                    width: 1,
                  )
                : null,
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: isDark ? 0.2 : 0.12),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    )
                  ]
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  topText,
                  style: TextStyle(
                    color: isSelected ? color : theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  color: isSelected
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.65),
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.normal,
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
      margin: const EdgeInsets.only(bottom: 14),
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
            color: isPaid ? AppColors.accent.withValues(alpha: 0.85) : AppColors.accent,
            borderRadius: BorderRadius.circular(20),
          ),
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.only(left: 24),
          child: Row(
            children: [
              Icon(
                isPaid ? LucideIcons.check : LucideIcons.checkCircle, 
                color: Colors.white, 
                size: 24
              ),
              const SizedBox(width: 12),
              Text(
                isPaid ? "Done ✓" : "Quick Pay",
                style: const TextStyle(
                  color: Colors.white,
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    // Loan progress calculation
    final paidCount = provider.paidLoanCountsToday[b.id] ?? 0;
    final totalCount = provider.todayLoanCounts[b.id] ?? b.loanCount;
    final hasMultipleLoans = totalCount > 1;

    final avatarColor = due ? AppColors.error : AppColors.accent;

    return PremiumCard(
      padding: EdgeInsets.zero,
      color: isPaid
          ? AppColors.accent.withValues(alpha: 0.05)
          : (isDark ? AppColors.surfaceDark : AppColors.surface),
      boxShadow: AppDecorations.subtleShadowCard(isDark).boxShadow,
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
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Hero(
                tag: 'borrower_code_${b.id}',
                child: Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: avatarColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: avatarColor.withValues(alpha: 0.25),
                      width: 1,
                    ),
                  ),
                  child: Center(
                    child: Material(
                      color: Colors.transparent,
                      child: Text(
                        b.displayBorrowerCode,
                        style: TextStyle(
                          color: avatarColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
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
                                  color: theme.colorScheme.onSurface,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  letterSpacing: -0.2,
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
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.error.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: AppColors.error.withValues(alpha: 0.35),
                                width: 0.8,
                              ),
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
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                            decoration: BoxDecoration(
                              color: AppColors.secondary.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(7),
                              border: Border.all(
                                color: AppColors.secondary.withValues(alpha: 0.3),
                                width: 0.8,
                              ),
                            ),
                            child: Text(
                              "$paidCount/$totalCount",
                              style: TextStyle(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          b.phone,
                          style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 12),
                        ),
                        if (b.address != null && b.address!.trim().isNotEmpty) ...[
                          Text(
                            " • ",
                            style: TextStyle(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5), fontSize: 12),
                          ),
                          Icon(LucideIcons.mapPin, size: 10.5, color: AppColors.accent.withValues(alpha: 0.8)),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(
                              b.address!.trim(),
                              style: TextStyle(
                                color: _selectedAddress != null && _selectedAddress!.toLowerCase() == b.address!.trim().toLowerCase()
                                    ? AppColors.accent
                                    : theme.colorScheme.onSurfaceVariant,
                                fontSize: 12,
                                fontWeight: _selectedAddress != null && _selectedAddress!.toLowerCase() == b.address!.trim().toLowerCase()
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
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
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isPaid
                          ? AppColors.accent.withValues(alpha: 0.1)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      isPaid ? "Collected" : "Pending",
                      style: TextStyle(
                        color: isPaid
                            ? AppColors.accent
                            : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
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
                                  const Icon(LucideIcons.checkCircle, color: Colors.white, size: 14),
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
                      prefixIcon: Icon(LucideIcons.indianRupee),
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
    final hasFilter = _selectedAddress != null || _query.isNotEmpty;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _selectedAddress != null ? LucideIcons.mapPin : LucideIcons.users,
            size: 64,
            color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.2),
          ),
          const SizedBox(height: 16),
          Text(
            _selectedAddress != null
                ? "No borrowers found in '$_selectedAddress'"
                : "No borrowers found",
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              fontSize: 16,
            ),
          ),
          if (hasFilter) ...[
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _selectedAddress = null;
                  _query = '';
                  _searchCtrl.clear();
                });
              },
              icon: const Icon(LucideIcons.x, size: 14),
              label: const Text("Clear Filters"),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.accent,
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<T> _collectSafe<T>(List<T> list) => List<T>.from(list);
}
