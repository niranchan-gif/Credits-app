import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/borrower.dart';
import '../models/loan.dart';
import '../models/payment.dart';
import '../providers/loan_provider.dart';
import 'settings/app_lock_settings_screen.dart';
import '../utils/fmt.dart';
import 'add_borrower_screen.dart';
import 'borrower_loans_screen.dart';
import 'reports_screen.dart';

final RouteObserver<ModalRoute> routeObserver =
RouteObserver<ModalRoute>();

// ── Palette ──────────────────────────────────────────────────────────────────
const _navy = Color(0xFF0F2545);
const _navyMid = Color(0xFF1A3A6B);
const _accent = Color(0xFFF0A500);

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with RouteAware {
int _tab = 0;
final _searchCtrl = TextEditingController();
String _q = '';

@override
void initState() {
super.initState();
WidgetsBinding.instance.addPostFrameCallback((_) {
_refresh();
routeObserver.subscribe(this, ModalRoute.of(context)!);
});
}

@override
void dispose() {
_searchCtrl.dispose();
routeObserver.unsubscribe(this);
super.dispose();
}

@override
void didPopNext() => _refresh();
void _refresh() {
if (mounted) context.read<LoanProvider>().loadBorrowers();
}

@override
Widget build(BuildContext context) {
return Scaffold(
backgroundColor: const Color(0xFFF0F4F8),
    body: Consumer<LoanProvider>(builder: (ctx, prov, _) {
final s = prov.globalSummary;
final due = (s['totalDue'] ?? 0.0) as double;
final col = (s['totalCollected'] ?? 0.0) as double;
final pen = (s['totalPending'] ?? 0.0) as double;

    final all = prov.borrowers;
    final paid = prov.paidTodayIds;
    final done = prov.completedIds;

    final cList = all.where((b) => done.contains(b.id)).toList();
    final pList = all
        .where((b) => paid.contains(b.id) && !done.contains(b.id))
        .toList();
    final aList = all
        .where((b) => !done.contains(b.id) && !paid.contains(b.id))
        .toList();

    final src = [aList, pList, cList][_tab];

    // ── UPDATED: search by name, borrowerCode, OR address ──
    final items = src
        .where((b) =>
            b.name.toLowerCase().contains(_q) ||
            b.borrowerCode.toLowerCase().contains(_q) ||
            (b.address ?? '').toLowerCase().contains(_q))
        .toList();

    return Column(children: [
      // ── Gradient Header ──────────────────────────────────────
      Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [_navy, _navyMid],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title row
                Row(children: [
                  const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Credits',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.bold)),
                        Text('Loan Manager',
                            style: TextStyle(
                                color: Colors.white54, fontSize: 12)),
                      ]),
                  const Spacer(),
                  _headerBtn(
                      Icons.security,
                      'Security',
                      () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const AppLockSettingsScreen()))),
                  const SizedBox(width: 8),
                  _headerBtn(
                      Icons.bar_chart_rounded,
                      'Reports',
                      () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const ReportsScreen()))),
                ]),
                const SizedBox(height: 20),
                // Stat cards row
                Row(children: [
                  _statCard('Total Due', fmtINR(due), _accent),
                  const SizedBox(width: 10),
                  _statCard(
                      'Collected', fmtINR(col), const Color(0xFF4CAF50)),
                  const SizedBox(width: 10),
                  _statCard(
                      'Pending', fmtINR(pen), const Color(0xFFEF5350)),
                ]),
              ],
            ),
          ),
        ),
      ),

      const SizedBox(height: 16),

      // ── Search ───────────────────────────────────────────────
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 10,
                  offset: const Offset(0, 4))
            ],
          ),
          child: TextField(
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _q = v.toLowerCase()),
            decoration: InputDecoration(
              // ── UPDATED hint text ──
              hintText: 'Search by name, code or address…',
              hintStyle: const TextStyle(color: Colors.grey, fontSize: 14),
              prefixIcon: const Icon(Icons.search, color: Colors.grey),
              suffixIcon: _q.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear,
                          color: Colors.grey, size: 18),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _q = '');
                      })
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ),

      const SizedBox(height: 14),

      // ── Tab Selector ─────────────────────────────────────────
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2))
            ],
          ),
          child: Row(children: [
            _tabPill(0, 'Collect', aList.length, const Color(0xFFEF5350)),
            _tabPill(1, 'Paid', pList.length, const Color(0xFF2196F3)),
            _tabPill(2, 'Completed', cList.length, const Color(0xFF4CAF50)),
          ]),
        ),
      ),

      const SizedBox(height: 12),

      // ── List ─────────────────────────────────────────────────
      Expanded(
        child: prov.isLoading
            ? const Center(child: CircularProgressIndicator())
            : items.isEmpty
                ? _empty(_tab)
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
                    itemCount: items.length,
                    itemBuilder: (_, i) {
                      final b = items[i];
                      final bid = b.id ?? 0;
                      return _BorrowerCard(
                        borrower: b,
                        showPaidBadge: _tab == 1,
                        showCompletedBadge: _tab == 2,
                        onPaymentSaved: _refresh,
                        paidLoanCount:
                            prov.paidLoanCountsToday[bid] ?? 0,
                        totalLoanCount:
                            prov.todayLoanCounts[bid] ?? b.loanCount,
                      );
                    },
                  ),
      ),
    ]);
  }),
  floatingActionButton: FloatingActionButton.extended(
    backgroundColor: _navy,
    elevation: 4,
    icon: const Icon(Icons.person_add_alt_1, color: Colors.white),
    label: const Text('Add Borrower',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
    onPressed: () async {
      await Navigator.push(context,
          MaterialPageRoute(builder: (_) => const AddBorrowerScreen()));
    },
  ),
);

}

Widget _headerBtn(IconData icon, String tip, VoidCallback onTap) => Tooltip(
message: tip,
child: InkWell(
onTap: onTap,
borderRadius: BorderRadius.circular(12),
child: Container(
padding: const EdgeInsets.all(10),
decoration: BoxDecoration(
color: Colors.white.withValues(alpha: 0.12),
borderRadius: BorderRadius.circular(12),
),
child: Icon(icon, color: Colors.white, size: 22),
),
),
);

Widget _statCard(String label, String value, Color color) => Expanded(
child: Container(
padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
decoration: BoxDecoration(
color: Colors.white.withValues(alpha: 0.1),
borderRadius: BorderRadius.circular(14),
border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
),
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
Text(label,
style: const TextStyle(color: Colors.white60, fontSize: 10)),
const SizedBox(height: 4),
FittedBox(
fit: BoxFit.scaleDown,
alignment: Alignment.centerLeft,
child: Text(value,
style: TextStyle(
color: color,
fontWeight: FontWeight.bold,
fontSize: 14)),
),
],
),
),
);

Widget _tabPill(int index, String label, int count, Color color) {
final sel = _tab == index;
return Expanded(
child: GestureDetector(
onTap: () => setState(() {
_tab = index;
_searchCtrl.clear();
_q = '';
}),
child: AnimatedContainer(
duration: const Duration(milliseconds: 200),
padding: const EdgeInsets.symmetric(vertical: 10),
decoration: BoxDecoration(
color: sel ? color : Colors.transparent,
borderRadius: BorderRadius.circular(12),
),
child: Column(mainAxisSize: MainAxisSize.min, children: [
Text('$count',
style: TextStyle(
color: sel ? Colors.white : color,
fontWeight: FontWeight.bold,
fontSize: 17)),
const SizedBox(height: 2),
FittedBox(
fit: BoxFit.scaleDown,
child: Padding(
padding: const EdgeInsets.symmetric(horizontal: 4),
child: Text(label,
style: TextStyle(
color: sel
? Colors.white.withValues(alpha: 0.9)
: Colors.grey.shade500,
fontSize: 11,
fontWeight: FontWeight.w600)),
),
),
]),
),
),
);
}

Widget _empty(int tab) {
final msgs = [
[
Icons.check_circle_outline_rounded,
'All collected for today!',
'Great job 🎉'
],
[
Icons.hourglass_bottom_rounded,
'No payments today yet',
'Paid borrowers appear here'
],
[
Icons.emoji_events_rounded,
'No completed borrowers',
'Cleared borrowers appear here'
],
];
final m = msgs[tab];
return Center(
child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
Container(
padding: const EdgeInsets.all(24),
decoration: BoxDecoration(
color: Colors.white,
shape: BoxShape.circle,
boxShadow: [
BoxShadow(
color: Colors.black.withValues(alpha: 0.06), blurRadius: 16)
],
),
child: Icon(m[0] as IconData, size: 48, color: Colors.grey.shade300),
),
const SizedBox(height: 20),
Text(m[1] as String,
style: const TextStyle(
fontWeight: FontWeight.bold,
fontSize: 16,
color: Color(0xFF2D3748))),
const SizedBox(height: 6),
Text(m[2] as String,
style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
]),
);
}

}

// ─────────────────────────────────────────────────────────────────────────────
// Borrower Card
// ─────────────────────────────────────────────────────────────────────────────

class _BorrowerCard extends StatelessWidget {
final Borrower borrower;
final bool showPaidBadge;
final bool showCompletedBadge;
final VoidCallback? onPaymentSaved;
/// How many of this borrower's loans were paid today.
final int paidLoanCount;
/// Total active loans for today's collection.
final int totalLoanCount;

const _BorrowerCard({
required this.borrower,
this.showPaidBadge = false,
this.showCompletedBadge = false,
this.onPaymentSaved,
this.paidLoanCount = 0,
this.totalLoanCount = 0,
});

  Future _handlePay(BuildContext context) async {
final prov = context.read<LoanProvider>();
final loans = await prov.getLoans(borrower.id!);
final active = loans.where((l) => l.status == 'active').toList();
if (!context.mounted) return;
if (active.isEmpty) {
ScaffoldMessenger.of(context)
.showSnackBar(const SnackBar(content: Text('No active loans.')));
return;
}
final loan = active.length == 1
? active.first
: await showDialog(
        context: context, builder: (ctx) => _LoanPickerDialog(loans: active));
if (loan == null || !context.mounted) return;
_showPaySheet(context, loan);
}

void _showPaySheet(BuildContext context, Loan loan) {
final amtCtrl = TextEditingController();
final noteCtrl = TextEditingController();
DateTime date = DateTime.now();
final provider = context.read<LoanProvider>();
// Capture messenger BEFORE any async gap — the card's context may become
// stale after addPayment() triggers notifyListeners() and moves the
// borrower to a different tab.
final messenger = ScaffoldMessenger.of(context);

showModalBottomSheet(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
          24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
                child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Record Payment',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                      Text(
                          '${borrower.name} • ${borrower.borrowerCode}',
                          style: const TextStyle(
                              color: Colors.grey, fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ]),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                    color: const Color(0xFFF0F4F8),
                    borderRadius: BorderRadius.circular(8)),
                child: Text(fmtINR(loan.loanAmount),
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _navy,
                        fontSize: 13)),
              ),
            ]),
            const SizedBox(height: 20),
            TextField(
              controller: amtCtrl,
              keyboardType: TextInputType.number,
              autofocus: true,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                labelText: 'Amount (₹)',
                prefixIcon: const Icon(Icons.currency_rupee),
                filled: true,
                fillColor: const Color(0xFFF0F4F8),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 12),
            Row(children: [
              const Icon(Icons.calendar_today,
                  size: 16, color: Colors.grey),
              const SizedBox(width: 8),
              Text(DateFormat('dd MMM yyyy').format(date),
                  style: const TextStyle(fontSize: 13)),
              const Spacer(),
              TextButton(
                onPressed: () async {
                  final p = await showDatePicker(
                      context: ctx,
                      initialDate: date,
                      firstDate: DateTime(2000),
                      lastDate: DateTime.now());
                  if (p != null) set(() => date = p);
                },
                child: const Text('Change Date'),
              ),
            ]),
            const SizedBox(height: 12),
            TextField(
              controller: noteCtrl,
              decoration: InputDecoration(
                labelText: 'Notes (optional)',
                prefixIcon: const Icon(Icons.notes),
                filled: true,
                fillColor: const Color(0xFFF0F4F8),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: _navy,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14))),
                onPressed: () async {
                  final amt = double.tryParse(amtCtrl.text.trim());
                  if (amt == null || amt <= 0) {
                    ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                        content: Text('Enter a valid amount')));
                    return;
                  }
                  // Grab note text before popping
                  final noteText = noteCtrl.text.trim();

                  // Pop the bottom sheet FIRST so the widget tree can
                  // safely rebuild when addPayment → notifyListeners fires.
                  Navigator.pop(ctx);

                  try {
                    await provider.addPayment(Payment(
                        loanId: loan.id!,
                        amount: amt,
                        paymentDate: date,
                        notes: noteText.isEmpty ? null : noteText));

                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text('Payment saved successfully!'),
                        backgroundColor: Color(0xFF4CAF50),
                        duration: Duration(seconds: 2),
                      ),
                    );
                    // No need to call onPaymentSaved — addPayment()
                    // already calls loadBorrowers() internally.
                  } catch (e) {
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text('Error: $e'),
                        backgroundColor: Colors.redAccent,
                      ),
                    );
                  }
                },
                child: const Text('Save Payment',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600)),
              ),
            ),
          ]),
    );
  }),
);

}

@override
Widget build(BuildContext context) {
final b = borrower;
final balance = b.totalBalance;

// Partial payment = some loans paid today, but not all
final bool isPartial = !showCompletedBadge &&
    !showPaidBadge &&
    totalLoanCount > 1 &&
    paidLoanCount > 0 &&
    paidLoanCount < totalLoanCount;

const _amber = Color(0xFFF59E0B);

final Color accentColor = showCompletedBadge
    ? const Color(0xFF4CAF50)
    : showPaidBadge
        ? const Color(0xFF2196F3)
        : isPartial
            ? _amber
            : balance > 0
                ? const Color(0xFFEF5350)
                : const Color(0xFF4CAF50);

return Dismissible(
  key: ValueKey('bc_${b.id}_${showPaidBadge}_$showCompletedBadge'),
  direction: DismissDirection.startToEnd,
  confirmDismiss: (_) async {
    await _handlePay(context);
    return false;
  },
  background: Container(
    margin: const EdgeInsets.only(bottom: 12),
    decoration: BoxDecoration(
        color: const Color(0xFF4CAF50),
        borderRadius: BorderRadius.circular(16)),
    alignment: Alignment.centerLeft,
    padding: const EdgeInsets.symmetric(horizontal: 24),
    child: const Row(children: [
      Icon(Icons.payment_rounded, color: Colors.white, size: 24),
      SizedBox(width: 8),
      Text('Pay',
          style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16)),
    ]),
  ),
  child: Container(
    margin: const EdgeInsets.only(bottom: 12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4))
      ],
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => BorrowerLoansScreen(borrower: b))),
      child: IntrinsicHeight(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Row(children: [
            // Accent bar
            Container(
              width: 5,
              decoration: BoxDecoration(
                color: accentColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                ),
              ),
            ),
            const SizedBox(width: 14),
            // Avatar
            CircleAvatar(
              backgroundColor: accentColor.withValues(alpha: 0.12),
              radius: 22,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Text(b.borrowerCode,
                      style: TextStyle(
                          color: accentColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 13)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(b.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: Color(0xFF1A202C)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 3),
                  Row(children: [
                    const Icon(Icons.phone, size: 12, color: Colors.grey),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(b.phone,
                          style:
                              const TextStyle(color: Colors.grey, fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                    // ── Partial payment progress badge ──
                    if (isPartial) ...[
                      const SizedBox(width: 6),
                      _pill('$paidLoanCount/$totalLoanCount Paid', _amber),
                    ],
                    if (showPaidBadge) ...[
                      const SizedBox(width: 6),
                      _pill('Paid Today', const Color(0xFF2196F3)),
                    ],
                    if (showCompletedBadge) ...[
                      const SizedBox(width: 6),
                      _pill('Cleared', const Color(0xFF4CAF50)),
                    ],
                  ]),
                  // ── Address Row (Always reserve space for uniform card size) ──
                  const SizedBox(height: 2),
                  Row(children: [
                    Icon(Icons.location_on,
                        size: 11,
                        color: (b.address ?? '').isNotEmpty
                            ? Colors.grey
                            : Colors.transparent),
                    const SizedBox(width: 3),
                    Expanded(
                      child: Text((b.address ?? '').isNotEmpty ? b.address! : '',
                          style: const TextStyle(
                              color: Colors.grey, fontSize: 11),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                  ]),
                ],
              ),
            ),
            // Balance + loan progress
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 110),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(fmtINR(balance),
                          style: TextStyle(
                              color: accentColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 15)),
                    ),
                    if (isPartial)
                      // Show X/Y progress under the amount
                      Text('$paidLoanCount of $totalLoanCount',
                          style: const TextStyle(
                              color: _amber,
                              fontSize: 10,
                              fontWeight: FontWeight.w600))
                    else
                      Text(
                          b.loanCount == 0
                              ? 'No Loans'
                              : balance > 0
                                  ? 'Due'
                                  : 'Cleared',
                          style: const TextStyle(
                              color: Colors.grey, fontSize: 11)),
                  ],
                ),
              ),
            ),
          ]),
        ),
      ),
    ),
  ),
);

}

Widget _pill(String label, Color color) => Container(
padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
decoration: BoxDecoration(
color: color.withValues(alpha: 0.1),
borderRadius: BorderRadius.circular(20),
),
child: Text(label,
style: TextStyle(
fontSize: 9, color: color, fontWeight: FontWeight.bold)),
);
}

// ─────────────────────────────────────────────────────────────────────────────
// Loan Picker Dialog
// ─────────────────────────────────────────────────────────────────────────────

class _LoanPickerDialog extends StatelessWidget {
final List loans;
const _LoanPickerDialog({required this.loans});

@override
Widget build(BuildContext context) {
return AlertDialog(
shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
title: const Text('Which loan?',
style: TextStyle(fontWeight: FontWeight.bold)),
contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
content: SizedBox(
width: double.maxFinite,
child: ListView.separated(
shrinkWrap: true,
itemCount: loans.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
final l = loans[i];
return ListTile(
onTap: () => Navigator.pop(context, l),
leading: const CircleAvatar(
backgroundColor: Color(0xFFF0F4F8),
child: Icon(Icons.receipt_long, color: _navy, size: 18),
),
title: Text(fmtINR(l.loanAmount),
style: const TextStyle(fontWeight: FontWeight.bold)),
subtitle: Text(DateFormat('dd MMM yyyy').format(l.loanDate),
style: const TextStyle(fontSize: 12, color: Colors.grey)),
trailing: const Icon(Icons.chevron_right, size: 18),
);
},
),
),
actions: [
TextButton(
onPressed: () => Navigator.pop(context),
child: const Text('Cancel')),
],
);
}
}