import 'dart:io';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

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
import '../services/borrower_pdf_service.dart';

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

  // Native channel for direct WhatsApp sharing (bypasses the share sheet)
  static const _whatsappChannel =
      MethodChannel('com.example.credit/whatsapp_share');

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
    final provider = context.watch<LoanProvider>();
    final b = provider.borrowers
        .firstWhere((x) => x.id == widget.borrower.id, orElse: () => widget.borrower);
        
    debugPrint('UI Build: Borrower id=${b.id}, isDummy=${b.isDummy}, code=${b.borrowerCode}');

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
                                style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w600, fontSize: 17),
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
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22, color: Theme.of(context).colorScheme.onSurface),
                        ),
                        const Spacer(),
                        Text('${_loans.length} loans', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity( 0.6), fontSize: 17)),
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
          if (isReadOnly || b.isDummy) return const SizedBox.shrink();
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
            debugPrint('UI: Menu selected = $value, isDummy = ${b.isDummy}');
            if (value == 'download') {
              _exportExcel();
            } else if (value == 'edit') {
              if (isReadOnly) return;
              await showDialog(
                context: context,
                builder: (_) => AddBorrowerScreen(borrower: b),
              );
              _loadData();
            } else if (value == 'delete') {
              if (isReadOnly) return;
              _confirmMoveToInactive(context);
            } else if (value == 'restore') {
              if (isReadOnly) return;
              _confirmRestore(context);
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
            ],
            if (!isReadOnly && !b.isDummy) ...[
              const PopupMenuItem(
                value: 'delete',
                child: Row(children: [Icon(LucideIcons.archive, size: 18, color: AppColors.error), SizedBox(width: 12), Text('Move to Inactive', style: TextStyle(color: AppColors.error))]),
              ),
            ],
            if (!isReadOnly && b.isDummy) ...[
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'restore',
                child: Row(children: [Icon(LucideIcons.refreshCcw, size: 18, color: AppColors.success), SizedBox(width: 12), Text('Move to Active', style: TextStyle(color: AppColors.success))]),
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
                      child: Text(b.displayBorrowerCode, style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.bold, fontSize: 17, letterSpacing: 1.5)),
                    ),
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Send Full Statement',
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    if (b.phone.trim().isEmpty) {
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text('Phone number not available'),
                          backgroundColor: AppColors.error,
                        ),
                      );
                      return;
                    }

                    // 1. Gather borrower details & loans
                    final provider = context.read<LoanProvider>();
                    final allBorrowerLoans = await provider.getLoans(b.id ?? 0);

                    if (allBorrowerLoans.isEmpty) {
                      messenger.showSnackBar(const SnackBar(content: Text('No loans available to share.')));
                      return;
                    }

                    List<Loan>? targetLoans = allBorrowerLoans;

                    if (allBorrowerLoans.length > 1) {
                      targetLoans = await showDialog<List<Loan>>(
                        context: context,
                        builder: (BuildContext context) {
                          return AlertDialog(
                            title: const Text('Select Loan to Share', style: TextStyle(fontWeight: FontWeight.bold)),
                            backgroundColor: Theme.of(context).colorScheme.surface,
                            content: SizedBox(
                              width: double.maxFinite,
                              child: ListView.builder(
                                shrinkWrap: true,
                                itemCount: allBorrowerLoans.length + 1,
                                itemBuilder: (context, index) {
                                  if (index == 0) {
                                    return ListTile(
                                      leading: const Icon(LucideIcons.copy, color: AppColors.accent),
                                      title: const Text('All Loans (Combined)', style: TextStyle(fontWeight: FontWeight.bold)),
                                      onTap: () => Navigator.of(context).pop(allBorrowerLoans),
                                    );
                                  }
                                  final loan = allBorrowerLoans[index - 1];
                                  final dateStr = DateFormat('dd MMM yyyy').format(loan.loanDate);
                                  return ListTile(
                                    leading: const Icon(LucideIcons.fileText, color: AppColors.accentLight),
                                    title: Text('Loan - $dateStr'),
                                    subtitle: Text('Amount: ₹${loan.loanAmount.toStringAsFixed(0)}'),
                                    onTap: () => Navigator.of(context).pop([loan]),
                                  );
                                },
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(context).pop(null),
                                child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
                              ),
                            ],
                          );
                        },
                      );
                      
                      if (targetLoans == null) return; // User canceled
                    }

                    double loanAmount = 0.0;
                    double totalPaid = 0.0;
                    final List<Map<String, dynamic>> allPayments = [];

                    for (final loan in targetLoans) {
                      loanAmount += loan.totalDue();
                      final payments = await provider.getPayments(loan.id ?? 0);
                      for (final p in payments) {
                        totalPaid += p.amount;
                        allPayments.add({
                          'date': p.paymentDate,
                          'amount': p.amount,
                        });
                      }
                    }

                    // 2. Sort payments by date ascending
                    allPayments.sort((a, b) => (a['date'] as DateTime).compareTo(b['date'] as DateTime));

                    // 3. Generate payment history string
                    double balanceToPay = 0.0;
                    if (targetLoans.length == 1) {
                      balanceToPay = (loanAmount - totalPaid);
                    } else {
                      balanceToPay = (b.totalBalance as num?)?.toDouble() ?? (loanAmount - totalPaid);
                    }
                    
                    if (balanceToPay < 0) balanceToPay = 0.0;
                      final todayStr = DateFormat('dd-MM-yyyy').format(DateTime.now());

                    try {
                      // Show loading snackbar
                      messenger.showSnackBar(
                        const SnackBar(content: Text('Generating PDF report...')),
                      );
                      
                      final pdfBytes = await BorrowerPdfService.generate(
                        context: context,
                        borrower: b,
                        totalPaid: totalPaid,
                        balanceToPay: balanceToPay,
                        
                        allPayments: allPayments,
                      );

                      messenger.hideCurrentSnackBar();

                      // Save PDF only to temporary cache (does not store files in permanent Desktop/Downloads storage)
                      final tempDir = await getTemporaryDirectory();
                      final filePath = '${tempDir.path}${Platform.pathSeparator}Report.pdf';
                      final file = File(filePath);
                      await file.writeAsBytes(pdfBytes);

                      // Format phone number for WhatsApp
                      String digits = b.phone.replaceAll(RegExp(r'\D'), '');
                      if (digits.length == 10) {
                        digits = '91$digits';
                      }

                      final summaryMsg =
                          'வணக்கம்,\n'
                          'பெயர்: ${b.name} (${b.displayBorrowerCode})\n'
                          'இதுவரை செலுத்திய தொகை: ₹${totalPaid.toStringAsFixed(0)}\n'
                          'செலுத்த வேண்டிய தொகை: ₹${balanceToPay.toStringAsFixed(0)}\n'
                          'உங்கள் கட்டண விபரங்கள் அடங்கிய ரசீது இத்துடன் இணைக்கப்பட்டுள்ளது.\n'
                          'தேதி: $todayStr\n'
                          'நன்றி';

                      if (Platform.isAndroid) {
                        // Android: use the native method channel to fire a targeted
                        // ACTION_SEND intent directly at WhatsApp with the jid extra.
                        // This opens WhatsApp straight to the borrower's chat with
                        // the PDF already attached — no share sheet, no contact picker.
                        bool nativeSuccess = false;
                        try {
                          await _whatsappChannel.invokeMethod('shareToWhatsApp', {
                            'filePath': filePath,
                            'phone': digits,
                            'text': '',
                          });
                          nativeSuccess = true;
                        } on PlatformException catch (_) {
                          // WhatsApp not installed or intent failed — fall back to share sheet
                          nativeSuccess = false;
                        }

                        if (!nativeSuccess) {
                          // Fallback: generic share sheet so the user can still share
                          await SharePlus.instance.share(
                            ShareParams(
                              files: [XFile(filePath, mimeType: 'application/pdf')],
                              text: '',
                              subject: 'கடன் அறிக்கை - ${b.name}',
                            ),
                          );
                        }
                      } else if (Platform.isIOS) {
                        // iOS: share sheet (iOS has no equivalent jid targeting)
                        await SharePlus.instance.share(
                          ShareParams(
                            files: [XFile(filePath, mimeType: 'application/pdf')],
                            text: '',
                            subject: 'கடன் அறிக்கை - ${b.name}',
                          ),
                        );
                      } else {
                        // Windows / other platforms: open WhatsApp Web + clipboard
                        final webUrl =
                            'https://web.whatsapp.com/send?phone=$digits';
                        final uri = Uri.parse(webUrl);
                        if (await canLaunchUrl(uri)) {
                          await launchUrl(uri,
                              mode: LaunchMode.externalApplication);
                        } else {
                          final fallbackUri = Uri.parse(
                              'https://wa.me/$digits');
                          await launchUrl(fallbackUri,
                              mode: LaunchMode.externalApplication);
                        }
                        if (Platform.isWindows) {
                          try {
                            await Process.run('powershell.exe', [
                              '-NoProfile',
                              '-Command',
                              "Set-Clipboard -Path '$filePath'",
                            ]);
                          } catch (_) {}
                          messenger.showSnackBar(
                            SnackBar(
                              behavior: SnackBarBehavior.floating,
                              backgroundColor: AppColors.accent,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              content: const Text(
                                'WhatsApp Web opened! Press Ctrl + V in the chat to attach & send the PDF.',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              duration: const Duration(seconds: 5),
                            ),
                          );
                        }
                      }
                    } catch (e) {
                      messenger.hideCurrentSnackBar();
                      messenger.showSnackBar(
                        SnackBar(content: Text('Failed to generate PDF: $e'), backgroundColor: AppColors.error),
                      );
                    }
                  },
                  icon: const Icon(LucideIcons.share2, color: AppColors.accent, size: 20),
                ),
                const SizedBox(width: 8),
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
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.bold, fontSize: 28),
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
                    Text('Loan Age', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity( 0.6), fontSize: 15)),
                    const SizedBox(height: 4),
                    Text('${b.loanAgeDays} Days', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.bold, fontSize: 19)),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('Status', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity( 0.6), fontSize: 15)),
                    const SizedBox(height: 4),
                    Text(
                      b.overdueStatus == 'OVERDUE' ? '🔴 OVERDUE (Exceeded 140-Day limit)' : 'ACTIVE',
                      style: TextStyle(
                        color: b.overdueStatus == 'OVERDUE' ? AppColors.error : AppColors.success,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
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
                    Expanded(child: Text(b.notes!, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 16, fontStyle: FontStyle.italic))),
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
                        Text(DateFormat('dd MMM yyyy').format(loan.loanDate), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 21, color: Theme.of(context).colorScheme.onSurface)),
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
                              child: Text(isActive ? 'ACTIVE' : 'CLEARED', style: TextStyle(color: isActive ? AppColors.info : AppColors.success, fontWeight: FontWeight.bold, fontSize: 14)),
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
                          Text('${loan.installmentDays} days • Ends ${loan.endDate != null ? DateFormat('dd MMM').format(loan.endDate!) : 'N/A'}', style: TextStyle(fontSize: 16, color: Theme.of(context).colorScheme.onSurfaceVariant)),
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
          Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity( 0.6), fontSize: 15)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 19, color: Theme.of(context).colorScheme.onSurface)),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmMoveToInactive(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Move to Inactive?'),
        content: const Text('This borrower will be hidden from the active list.\nAll loans, payments, and history will remain safely stored.\nYou can restore this borrower later.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Move'),
          ),
        ],
      ),
    );
    if (confirm == true && context.mounted) {
      debugPrint('UI: Moving to inactive. ID=${widget.borrower.id}, Code=${widget.borrower.borrowerCode}');
      await context.read<LoanProvider>().moveToDummy(widget.borrower.id ?? 0);
      debugPrint('UI: Provider reload complete');
    }
  }

  Future<void> _confirmRestore(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Move to Active?'),
        content: const Text('This borrower will be restored to the active borrower list.\nAll existing loans and history will remain unchanged.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (confirm == true && context.mounted) {
      debugPrint('UI: Restoring to active. ID=${widget.borrower.id}, Code=${widget.borrower.borrowerCode}');
      await context.read<LoanProvider>().moveToActive(widget.borrower.id ?? 0);
      debugPrint('UI: Provider reload complete');
    }
  }


}

