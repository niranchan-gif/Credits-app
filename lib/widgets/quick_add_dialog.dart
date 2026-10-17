import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/loan_provider.dart';
import '../models/borrower.dart';
import '../models/day_note.dart';
import '../utils/app_colors.dart';
import '../utils/fmt.dart';
import '../database/db_helper.dart';
import '../utils/date_parser.dart';
import '../services/google_drive_excel_backup_service.dart';

class QuickAddDialog extends StatefulWidget {
  const QuickAddDialog({super.key});

  @override
  State<QuickAddDialog> createState() => _QuickAddDialogState();
}

enum _QuickAddField { code, amount }

class _QuickAddDialogState extends State<QuickAddDialog> {
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();
  final _amountController = TextEditingController();
  final _codeFocusNode = FocusNode();
  final _amountFocusNode = FocusNode();

  _QuickAddField _activeField = _QuickAddField.code;
  DateTime _selectedDate = DateTime.now();
  Borrower? _matchedBorrower;
  bool _hasPaidToday = false;
  bool _isInactive = false;
  
  static String? _persistedLastCode;
  String? _lastEnteredCode;
  double _dayTotal = 0.0;
  bool _hasDayNote = false;

  Timer? _paymentCheckTimer;
  final Map<String, Borrower> _borrowerLookup = {};
  List<Borrower>? _lastBorrowersRef;

  void _rebuildBorrowerLookup(List<Borrower> borrowers) {
    _borrowerLookup.clear();
    for (final b in borrowers) {
      if (b.isDummy) continue;
      final code = b.borrowerCode.trim();
      if (code.isNotEmpty) {
        _borrowerLookup[code] = b;
        final numCode = int.tryParse(code);
        if (numCode != null) {
          _borrowerLookup[numCode.toString()] = b;
        }
      }
      final disp = b.displayBorrowerCode.trim();
      if (disp.isNotEmpty) {
        _borrowerLookup[disp] = b;
        final numDisp = int.tryParse(disp);
        if (numDisp != null) {
          _borrowerLookup[numDisp.toString()] = b;
        }
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _lastEnteredCode = _persistedLastCode;
    _loadPersistedLastCode();
    // Fetch borrowers if empty just in case
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.read<LoanProvider>().borrowers.isEmpty) {
        context.read<LoanProvider>().loadBorrowers();
      }
      _loadDayTotal();
      _loadDayNote();
      _codeFocusNode.requestFocus();
    });
  }

  Future<void> _loadPersistedLastCode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedCode = prefs.getString('quick_add_last_entered_code');
      if (savedCode != null && savedCode.isNotEmpty) {
        if (mounted) {
          setState(() {
            _persistedLastCode = savedCode;
            _lastEnteredCode = savedCode;
          });
        }
        return;
      }
      
      // Fallback: fetch most recent payment's borrower code from DB
      if (mounted) {
        final lastCode = await context.read<LoanProvider>().getLastPaymentBorrowerCode();
        if (lastCode != null && lastCode.isNotEmpty && mounted) {
          setState(() {
            _persistedLastCode = lastCode;
            _lastEnteredCode = lastCode;
          });
          prefs.setString('quick_add_last_entered_code', lastCode);
        }
      }
    } catch (_) {}
  }

  Future<void> _loadDayTotal() async {
    if (!mounted) return;
    try {
      final total = await context.read<LoanProvider>().getTotalCollectedOnDate(_selectedDate);
      if (mounted) {
        setState(() {
          _dayTotal = total;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadDayNote() async {
    if (!mounted) return;
    try {
      final note = await context.read<LoanProvider>().getDayNote(_selectedDate);
      if (mounted) {
        setState(() {
          _hasDayNote = note != null && note.notes.trim().isNotEmpty && !note.isDeleted;
        });
      }
    } catch (_) {}
  }

  bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year && date.month == now.month && date.day == now.day;
  }

  void _checkIfPaidOnSelectedDate({bool immediate = false}) {
    _paymentCheckTimer?.cancel();
    if (_matchedBorrower == null || _isInactive) return;
    
    final borrowerId = _matchedBorrower!.id ?? 0;
    final date = _selectedDate;

    void runQuery() {
      if (!mounted) return;
      final provider = context.read<LoanProvider>();
      provider.hasPaymentOnDate(borrowerId, date).then((hasPaid) {
        if (mounted && _matchedBorrower?.id == borrowerId && _selectedDate == date) {
          if (_hasPaidToday != hasPaid) {
            setState(() {
              _hasPaidToday = hasPaid;
            });
          }
        }
      });
    }

    if (immediate) {
      runQuery();
    } else {
      _paymentCheckTimer = Timer(const Duration(milliseconds: 180), runQuery);
    }
  }

  @override
  void dispose() {
    _paymentCheckTimer?.cancel();
    _codeController.dispose();
    _amountController.dispose();
    _codeFocusNode.dispose();
    _amountFocusNode.dispose();
    super.dispose();
  }

  void _onCodeChanged(String value) {
    final code = value.trim();
    if (code.isEmpty) {
      _paymentCheckTimer?.cancel();
      if (_matchedBorrower != null || _hasPaidToday || _isInactive) {
        setState(() {
          _matchedBorrower = null;
          _hasPaidToday = false;
          _isInactive = false;
        });
      }
      return;
    }
    
    final inputNum = int.tryParse(code);
    final borrower = _borrowerLookup[code] ??
        (inputNum != null ? _borrowerLookup[inputNum.toString()] : null);
    
    if (borrower == null) {
      _paymentCheckTimer?.cancel();
      if (_matchedBorrower != null || _hasPaidToday || _isInactive) {
        setState(() {
          _matchedBorrower = null;
          _hasPaidToday = false;
          _isInactive = false;
        });
      }
      return;
    }

    final inactive = borrower.isClosed || borrower.totalBalance <= 0;
    final borrowerChanged = _matchedBorrower?.id != borrower.id || _isInactive != inactive;
    
    if (borrowerChanged) {
      setState(() {
        _matchedBorrower = borrower;
        _isInactive = inactive;
        _hasPaidToday = false;
      });
    }
    
    if (!inactive) {
      _checkIfPaidOnSelectedDate();
    } else {
      _paymentCheckTimer?.cancel();
    }
  }

  void _onKeyPress(String key) {
    HapticFeedback.selectionClick();
    final controller = _activeField == _QuickAddField.code ? _codeController : _amountController;
    final text = controller.text;
    final selection = controller.selection;
    final start = selection.isValid && selection.start >= 0 ? selection.start : text.length;
    final end = selection.isValid && selection.end >= 0 ? selection.end : text.length;

    // Disallow non-numeric characters for borrower code
    if (_activeField == _QuickAddField.code && !RegExp(r'^[0-9]$').hasMatch(key)) return;

    // Disallow anything other than digits and '.' for amount
    if (_activeField == _QuickAddField.amount && !RegExp(r'^[0-9.]$').hasMatch(key)) return;

    // Disallow multiple decimal points for amount
    if (key == '.' && text.contains('.')) return;

    final newText = text.replaceRange(start, end, key);
    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + key.length),
    );

    if (_activeField == _QuickAddField.code) {
      _onCodeChanged(newText);
    } else {
      setState(() {});
    }
  }

  void _onBackspace() {
    HapticFeedback.lightImpact();
    final controller = _activeField == _QuickAddField.code ? _codeController : _amountController;
    final text = controller.text;
    final selection = controller.selection;
    final start = selection.isValid && selection.start >= 0 ? selection.start : text.length;
    final end = selection.isValid && selection.end >= 0 ? selection.end : text.length;

    if (start != end) {
      final newText = text.replaceRange(start, end, '');
      controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: start),
      );
      if (_activeField == _QuickAddField.code) {
        _onCodeChanged(newText);
      } else {
        setState(() {});
      }
    } else if (start > 0) {
      final newText = text.replaceRange(start - 1, start, '');
      controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: start - 1),
      );
      if (_activeField == _QuickAddField.code) {
        _onCodeChanged(newText);
      } else {
        setState(() {});
      }
    } else if (_activeField == _QuickAddField.amount && text.isEmpty) {
      setState(() => _activeField = _QuickAddField.code);
      _codeFocusNode.requestFocus();
    }
  }

  void _onClearField() {
    HapticFeedback.mediumImpact();
    final controller = _activeField == _QuickAddField.code ? _codeController : _amountController;
    controller.clear();
    if (_activeField == _QuickAddField.code) {
      _onCodeChanged('');
    } else {
      setState(() {});
    }
  }

  void _onNext() {
    HapticFeedback.lightImpact();
    if (_activeField == _QuickAddField.code) {
      if (_codeController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter borrower code'),
            duration: Duration(seconds: 1),
          ),
        );
        return;
      }
      if (_matchedBorrower == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invalid borrower code'),
            duration: Duration(seconds: 1),
          ),
        );
        return;
      }
      if (_isInactive) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Payment blocked: Borrower has no active loans.'),
            backgroundColor: AppColors.error,
            duration: Duration(seconds: 2),
          ),
        );
        return;
      }
      setState(() {
        _activeField = _QuickAddField.amount;
      });
      _amountFocusNode.requestFocus();
    } else {
      if (!_isInactive) {
        _submitPayment();
      }
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).brightness == Brightness.dark
                ? const ColorScheme.dark(
                    primary: AppColors.accent,
                    onPrimary: AppColors.background,
                    surface: AppColors.surfaceDark,
                    onSurface: Colors.white,
                  )
                : const ColorScheme.light(
                    primary: AppColors.accent,
                    onPrimary: Colors.white,
                    surface: Colors.white,
                    onSurface: Colors.black,
                  ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
      
      _loadDayTotal();
      _loadDayNote();
      _checkIfPaidOnSelectedDate(immediate: true);
      
      // Move focus back to amount if a borrower is already matched
      if (_matchedBorrower != null) {
        setState(() => _activeField = _QuickAddField.amount);
        _amountFocusNode.requestFocus();
      } else {
        setState(() => _activeField = _QuickAddField.code);
        _codeFocusNode.requestFocus();
      }
    }
  }

  Future<void> _showDayTransactions(BuildContext context) async {
    HapticFeedback.selectionClick();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return _DayTransactionsSheet(
          selectedDate: _selectedDate,
          isDark: isDark,
          onChanged: () {
            _loadDayTotal();
            _checkIfPaidOnSelectedDate(immediate: true);
          },
        );
      },
    );

    if (mounted) {
      _loadDayTotal();
      _loadDayNote();
      _checkIfPaidOnSelectedDate(immediate: true);
    }
  }

  Future<void> _submitPayment() async {
    if (!_formKey.currentState!.validate()) return;
    
    if (_matchedBorrower == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid Borrower Code')),
      );
      return;
    }

    if (_isInactive) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Payment blocked: Borrower has no active loans.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    if (_hasPaidToday) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(LucideIcons.alertTriangle, color: AppColors.warning),
              SizedBox(width: 8),
              Text('Duplicate Payment'),
            ],
          ),
          content: const Text(
            'This borrower already has a payment recorded for the selected date.\n\nDo you want to add another payment?',
            style: TextStyle(fontSize: 16),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.warning,
                foregroundColor: Colors.white,
              ),
              child: const Text('Proceed Anyway'),
            ),
          ],
        ),
      );
      
      if (confirm != true) {
        return; // User canceled the submission
      }
    }

    final amountStr = _amountController.text.trim();
    if (amountStr.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter an amount'),
            duration: Duration(seconds: 1),
          ),
        );
      }
      setState(() => _activeField = _QuickAddField.amount);
      _amountFocusNode.requestFocus();
      return;
    }

    final amount = double.tryParse(amountStr);
    if (amount == null || amount <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a valid positive amount')),
        );
      }
      return;
    }

    try {
      if (!mounted) return;
      final provider = context.read<LoanProvider>();
      await provider.quickPayFlexible(
        _matchedBorrower!.id!,
        amount,
        paymentDate: _selectedDate,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Paid ₹$amount to ${_matchedBorrower!.name}'),
            backgroundColor: AppColors.success,
            duration: const Duration(seconds: 2),
          ),
        );
        
        // Save the last entered code
        final savedCode = _matchedBorrower!.borrowerCode;
        _persistedLastCode = savedCode;
        _lastEnteredCode = savedCode;
        SharedPreferences.getInstance().then((prefs) {
          prefs.setString('quick_add_last_entered_code', savedCode);
        }).catchError((_) {});

        _loadDayTotal();

        // Reset for next entry, KEEPING THE DATE!
        _codeController.clear();
        _amountController.clear();
        setState(() {
          _matchedBorrower = null;
          _hasPaidToday = false;
          _isInactive = false;
          _activeField = _QuickAddField.code;
        });
        
        Future.delayed(const Duration(milliseconds: 50), () {
          if (mounted) {
            FocusScope.of(context).requestFocus(_codeFocusNode);
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Widget _buildFieldSelector(bool isDark) {
    final codeText = _codeController.text.isEmpty ? '---' : _codeController.text;
    final amountText = _amountController.text.isEmpty ? '0' : '₹${_amountController.text}';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3.5),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E2024) : const Color(0xFFDEE2E8),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _activeField = _QuickAddField.code);
                  _codeFocusNode.requestFocus();
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                  decoration: BoxDecoration(
                    color: _activeField == _QuickAddField.code
                        ? AppColors.accent
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: _activeField == _QuickAddField.code
                        ? [
                            BoxShadow(
                              color: AppColors.accent.withValues(alpha: 0.4),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        LucideIcons.hash,
                        size: 15,
                        color: _activeField == _QuickAddField.code
                            ? Colors.white
                            : (isDark ? Colors.grey[400] : Colors.grey[700]),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Code: $codeText',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: _activeField == _QuickAddField.code
                                ? FontWeight.bold
                                : FontWeight.w600,
                            color: _activeField == _QuickAddField.code
                                ? Colors.white
                                : (isDark ? Colors.grey[300] : Colors.grey[800]),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: GestureDetector(
                onTap: _isInactive ? null : () {
                  HapticFeedback.selectionClick();
                  setState(() => _activeField = _QuickAddField.amount);
                  _amountFocusNode.requestFocus();
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                  decoration: BoxDecoration(
                    color: _activeField == _QuickAddField.amount
                        ? AppColors.accent
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: _activeField == _QuickAddField.amount
                        ? [
                            BoxShadow(
                              color: AppColors.accent.withValues(alpha: 0.4),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        LucideIcons.indianRupee,
                        size: 15,
                        color: _activeField == _QuickAddField.amount
                            ? Colors.white
                            : (isDark ? Colors.grey[400] : Colors.grey[700]),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Amount: $amountText',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: _activeField == _QuickAddField.amount
                                ? FontWeight.bold
                                : FontWeight.w600,
                            color: _activeField == _QuickAddField.amount
                                ? Colors.white
                                : (isDark ? Colors.grey[300] : Colors.grey[800]),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDueBreakdown(bool isDark) {
    final currentDue = _matchedBorrower?.totalBalance ?? 0.0;
    final amountText = _amountController.text.trim();
    final enteredAmount = double.tryParse(amountText) ?? 0.0;
    final hasBorrower = _matchedBorrower != null;
    final remaining = currentDue - enteredAmount;

    String formatVal(double val) {
      final isNegative = val < 0;
      final absVal = val.abs();
      if (absVal == absVal.truncateToDouble()) {
        return isNegative ? '-${fmtINR(absVal)}' : fmtINR(absVal);
      }
      return '${isNegative ? '-' : ''}₹${absVal.toStringAsFixed(2)}';
    }

    final dueDisplay = hasBorrower ? formatVal(currentDue) : '-';
    final amountDisplay = enteredAmount > 0
        ? formatVal(enteredAmount)
        : (amountText.isNotEmpty ? '₹$amountText' : '₹0');
    final remainingDisplay = hasBorrower ? formatVal(remaining) : '-';

    Color remainingColor;
    if (!hasBorrower) {
      remainingColor = isDark ? Colors.grey[400]! : Colors.grey[600]!;
    } else if (enteredAmount <= 0) {
      remainingColor = Theme.of(context).colorScheme.onSurface;
    } else if (remaining == 0) {
      remainingColor = isDark ? const Color(0xFF4ADE80) : const Color(0xFF16A34A);
    } else if (remaining < 0) {
      remainingColor = isDark ? const Color(0xFF60A5FA) : const Color(0xFF2563EB);
    } else {
      remainingColor = isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706);
    }

    return Row(
      children: [
        // Box 1: Current Due
        _buildInfoBox(
          title: 'Current Due',
          value: dueDisplay,
          isDark: isDark,
          valueColor: hasBorrower
              ? (isDark ? Colors.white : AppColors.textPrimary)
              : (isDark ? Colors.grey[400] : Colors.grey[600]),
        ),
        const SizedBox(width: 8),
        // Box 2: Amount
        _buildInfoBox(
          title: 'Amount',
          value: amountDisplay,
          isDark: isDark,
          valueColor: enteredAmount > 0
              ? (isDark ? const Color(0xFF34D399) : AppColors.accent)
              : (isDark ? Colors.grey[400] : Colors.grey[600]),
          customBorderColor: _activeField == _QuickAddField.amount
              ? (isDark ? Colors.white : AppColors.accent)
              : null,
          onTap: () {
            if (!_isInactive) {
              setState(() => _activeField = _QuickAddField.amount);
              _amountFocusNode.requestFocus();
            }
          },
        ),
        const SizedBox(width: 8),
        // Box 3: Remaining
        _buildInfoBox(
          title: 'Remaining',
          value: remainingDisplay,
          isDark: isDark,
          valueColor: remainingColor,
          customBg: hasBorrower && enteredAmount > 0 && remaining == 0
              ? (isDark
                  ? AppColors.success.withValues(alpha: 0.15)
                  : AppColors.success.withValues(alpha: 0.08))
              : null,
          customBorderColor: hasBorrower && enteredAmount > 0 && remaining == 0
              ? AppColors.success.withValues(alpha: 0.4)
              : null,
        ),
      ],
    );
  }

  Widget _buildInfoBox({
    required String title,
    required String value,
    required bool isDark,
    Color? customBg,
    Color? customBorderColor,
    Color? valueColor,
    VoidCallback? onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 54,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: customBg ?? (isDark ? Colors.grey[850] : Colors.grey[100]),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: customBorderColor ?? (isDark ? Colors.grey[800]! : Colors.grey[300]!),
              width: customBorderColor != null ? 1.5 : 1.0,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.1,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.2,
                  fontWeight: FontWeight.bold,
                  color: valueColor ?? Theme.of(context).colorScheme.onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNumKey({
    required String text,
    VoidCallback? onTap,
    VoidCallback? onLongPress,
    Widget? child,
    Color? customBg,
    Color? customTextColor,
    Border? customBorder,
    required bool isDark,
    bool isSymbol = false,
    double height = 48,
  }) {
    final bgColor = customBg ?? (isSymbol
        ? (isDark ? const Color(0xFF262930) : const Color(0xFFD6DBE4))
        : (isDark ? const Color(0xFF2E3138) : Colors.white));
    final textColor = customTextColor ?? (isDark ? Colors.white : const Color(0xFF0F172A));

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2.5, vertical: 2.5),
        child: Material(
          color: bgColor,
          elevation: isDark ? 1 : 2,
          shadowColor: isDark 
              ? Colors.black.withValues(alpha: 0.5) 
              : Colors.black.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            borderRadius: BorderRadius.circular(14),
            splashColor: AppColors.accent.withValues(alpha: 0.35),
            highlightColor: AppColors.accent.withValues(alpha: 0.2),
            child: Container(
              height: height,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: customBorder ?? Border.all(
                  color: isDark 
                      ? Colors.white.withValues(alpha: 0.16) 
                      : Colors.black.withValues(alpha: 0.12),
                  width: 1.2,
                ),
              ),
              alignment: Alignment.center,
              child: child ?? Text(
                text,
                style: TextStyle(
                  fontSize: isSymbol ? 22 : 24,
                  fontWeight: FontWeight.w700,
                  color: textColor,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }


  Widget _buildNumPad(bool isDark) {
    final isCode = _activeField == _QuickAddField.code;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF202226) : const Color(0xFFE8EBF0),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.07),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildFieldSelector(isDark),
          const SizedBox(height: 6),
          // Row 1: 1, 2, 3
          Row(
            children: [
              _buildNumKey(text: '1', onTap: () => _onKeyPress('1'), isDark: isDark),
              _buildNumKey(text: '2', onTap: () => _onKeyPress('2'), isDark: isDark),
              _buildNumKey(text: '3', onTap: () => _onKeyPress('3'), isDark: isDark),
            ],
          ),
          // Row 2: 4, 5, 6
          Row(
            children: [
              _buildNumKey(text: '4', onTap: () => _onKeyPress('4'), isDark: isDark),
              _buildNumKey(text: '5', onTap: () => _onKeyPress('5'), isDark: isDark),
              _buildNumKey(text: '6', onTap: () => _onKeyPress('6'), isDark: isDark),
            ],
          ),
          // Row 3: 7, 8, 9
          Row(
            children: [
              _buildNumKey(text: '7', onTap: () => _onKeyPress('7'), isDark: isDark),
              _buildNumKey(text: '8', onTap: () => _onKeyPress('8'), isDark: isDark),
              _buildNumKey(text: '9', onTap: () => _onKeyPress('9'), isDark: isDark),
            ],
          ),
          // Row 4: ., 0, ⌫ (backspace)
          Row(
            children: [
              _buildNumKey(
                text: '.',
                onTap: isCode ? null : () => _onKeyPress('.'),
                isDark: isDark,
                isSymbol: true,
                customTextColor: isCode
                    ? (isDark ? Colors.white24 : Colors.black26)
                    : null,
              ),
              _buildNumKey(text: '0', onTap: () => _onKeyPress('0'), isDark: isDark),
              _buildNumKey(
                text: '',
                onTap: _onBackspace,
                onLongPress: _onClearField,
                isDark: isDark,
                customBg: isDark
                    ? const Color(0xFF353942)
                    : const Color(0xFFDFE3EA),
                customBorder: Border.all(
                  color: isDark ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.1),
                  width: 1.2,
                ),
                child: Icon(
                  Icons.backspace_outlined,
                  size: 21,
                  color: isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // Action button row: Notes button + Next / Save button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2.5, vertical: 2.5),
            child: Row(
              children: [
                _buildNotesButton(isDark),
                const SizedBox(width: 6),
                Expanded(
                  child: SizedBox(
                    height: 46,
                    child: Material(
                      color: _isInactive ? Colors.grey : AppColors.accent,
                      borderRadius: BorderRadius.circular(14),
                      elevation: isDark ? 1 : 2,
                      child: InkWell(
                        onTap: _onNext,
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: _isInactive ? Colors.grey : AppColors.accent,
                              width: 1.2,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                isCode ? 'Next' : 'Save',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Icon(
                                isCode ? LucideIcons.arrowRight : LucideIcons.checkCircle,
                                size: 18,
                                color: Colors.white,
                              ),
                            ],
                          ),
                        ),
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
  }

  /// Keyboard Notes button matching tactile numpad styling with badge indicator
  Widget _buildNotesButton(bool isDark) {
    final hasNote = _hasDayNote;
    return SizedBox(
      width: 105,
      height: 46,
      child: Material(
        color: hasNote
            ? (isDark ? const Color(0xFF382E1E) : const Color(0xFFFEF3C7))
            : (isDark ? const Color(0xFF2C3038) : const Color(0xFFDEE3EA)),
        borderRadius: BorderRadius.circular(14),
        elevation: isDark ? 1 : 2,
        child: InkWell(
          onTap: () => _showDayNotesDialog(context),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: hasNote
                    ? const Color(0xFFF59E0B)
                    : (isDark
                        ? Colors.white.withValues(alpha: 0.12)
                        : Colors.black.withValues(alpha: 0.1)),
                width: hasNote ? 1.4 : 1.2,
              ),
            ),
            alignment: Alignment.center,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      LucideIcons.fileText,
                      size: 17,
                      color: hasNote
                          ? const Color(0xFFF59E0B)
                          : (isDark ? Colors.white.withValues(alpha: 0.9) : const Color(0xFF0F172A)),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'Notes',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: hasNote
                            ? (isDark ? const Color(0xFFFBBF24) : const Color(0xFFB45309))
                            : (isDark ? Colors.white.withValues(alpha: 0.9) : const Color(0xFF0F172A)),
                      ),
                    ),
                  ],
                ),
                if (hasNote)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        color: Color(0xFFF59E0B),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showDayNotesDialog(BuildContext parentContext) async {
    HapticFeedback.mediumImpact();
    final isDark = Theme.of(parentContext).brightness == Brightness.dark;
    DateTime dialogDate = _selectedDate;
    final loanProvider = parentContext.read<LoanProvider>();
    final messenger = ScaffoldMessenger.of(parentContext);
    
    // Load initial note for dialogDate
    DayNote? note = await loanProvider.getDayNote(dialogDate);
    final notesController = TextEditingController(text: note?.notes ?? '');
    
    if (!parentContext.mounted) return;

    await showModalBottomSheet<void>(
      context: parentContext,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (modalContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final mediaQuery = MediaQuery.of(context);
            final screenWidth = mediaQuery.size.width;
            final bottomInset = mediaQuery.viewInsets.bottom;
            final hasNote = note != null && note!.notes.trim().isNotEmpty && !note!.isDeleted;
            
            return Padding(
              padding: EdgeInsets.only(bottom: bottomInset),
              child: SizedBox(
                width: screenWidth,
                child: Material(
                  color: isDark ? const Color(0xFF1C1E22) : Colors.white,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                  elevation: 12,
                  child: SafeArea(
                    top: false,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: mediaQuery.size.height * 0.85,
                      ),
                      child: SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Drag handle
                              Center(
                                child: Container(
                                  width: 38,
                                  height: 4,
                                  decoration: BoxDecoration(
                                    color: isDark ? Colors.grey[700] : Colors.grey[300],
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),

                              // Header Row
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: hasNote
                                          ? const Color(0xFFF59E0B).withValues(alpha: 0.15)
                                          : (isDark ? Colors.white.withValues(alpha: 0.08) : AppColors.accent.withValues(alpha: 0.1)),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      LucideIcons.edit3,
                                      color: hasNote ? const Color(0xFFF59E0B) : (isDark ? Colors.white : AppColors.accent),
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Day Closing Notes',
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          DateFormat('EEEE, dd MMM yyyy').format(dialogDate),
                                          style: TextStyle(
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w500,
                                            color: isDark ? Colors.grey[400] : Colors.grey[600],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Date Picker button to switch date if needed
                                  OutlinedButton.icon(
                                    onPressed: () async {
                                      final picked = await showDatePicker(
                                        context: modalContext,
                                        initialDate: dialogDate,
                                        firstDate: DateTime(2020),
                                        lastDate: DateTime.now().add(const Duration(days: 365)),
                                      );
                                      if (picked != null && picked != dialogDate) {
                                        final newNote = await loanProvider.getDayNote(picked);
                                        setModalState(() {
                                          dialogDate = picked;
                                          note = newNote;
                                          notesController.text = newNote?.notes ?? '';
                                        });
                                      }
                                    },
                                    icon: const Icon(LucideIcons.calendar, size: 14),
                                    label: const Text('Change Date', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      minimumSize: Size.zero,
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      side: BorderSide(
                                        color: isDark ? Colors.white24 : Colors.black12,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),

                              // Notes Text Field
                              TextFormField(
                                controller: notesController,
                                minLines: 3,
                                maxLines: 5,
                                maxLength: 500,
                                style: const TextStyle(fontSize: 14.5),
                                decoration: InputDecoration(
                                  hintText: 'Enter your notes for this day (e.g. closing tally, special borrower promises, reminders)...',
                                  hintStyle: TextStyle(
                                    fontSize: 13,
                                    color: isDark ? Colors.grey[500] : Colors.grey[400],
                                  ),
                                  filled: true,
                                  fillColor: isDark ? const Color(0xFF25282E) : const Color(0xFFF3F4F6),
                                  contentPadding: const EdgeInsets.all(14),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide(
                                      color: isDark ? Colors.white12 : Colors.black12,
                                    ),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide(
                                      color: isDark ? Colors.white12 : Colors.black12,
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: const BorderSide(
                                      color: AppColors.accent,
                                      width: 1.5,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),

                              // Buttons Row
                              Row(
                                children: [
                                  if (hasNote) ...[
                                    TextButton.icon(
                                      onPressed: () async {
                                        final confirm = await showDialog<bool>(
                                          context: modalContext,
                                          builder: (ctx) => AlertDialog(
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                            title: const Text('Delete Day Note?'),
                                            content: Text('Are you sure you want to delete the note for ${DateFormat('dd MMM yyyy').format(dialogDate)}?'),
                                            actions: [
                                              TextButton(
                                                onPressed: () => Navigator.of(ctx).pop(false),
                                                style: TextButton.styleFrom(minimumSize: Size.zero),
                                                child: const Text('Cancel'),
                                              ),
                                              TextButton(
                                                onPressed: () => Navigator.of(ctx).pop(true),
                                                style: TextButton.styleFrom(minimumSize: Size.zero),
                                                child: const Text('Delete', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.bold)),
                                              ),
                                            ],
                                          ),
                                        );
                                        if (confirm == true) {
                                          await loanProvider.deleteDayNote(dialogDate);
                                          if (dialogDate.year == _selectedDate.year &&
                                              dialogDate.month == _selectedDate.month &&
                                              dialogDate.day == _selectedDate.day) {
                                            _loadDayNote();
                                          }
                                          if (modalContext.mounted) {
                                            Navigator.of(modalContext).pop();
                                          }
                                          if (mounted) {
                                            messenger.showSnackBar(
                                              SnackBar(
                                                content: Text('Note deleted for ${DateFormat('dd MMM yyyy').format(dialogDate)}'),
                                                behavior: SnackBarBehavior.floating,
                                                duration: const Duration(seconds: 2),
                                              ),
                                            );
                                          }
                                        }
                                      },
                                      style: TextButton.styleFrom(
                                        minimumSize: Size.zero,
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      icon: const Icon(LucideIcons.trash2, size: 15, color: AppColors.error),
                                      label: const Text('Delete', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.bold, fontSize: 13)),
                                    ),
                                    const Spacer(),
                                  ] else ...[
                                    const Spacer(),
                                  ],
                                  TextButton(
                                    onPressed: () => Navigator.of(modalContext).pop(),
                                    style: TextButton.styleFrom(
                                      minimumSize: Size.zero,
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    child: Text(
                                      'Cancel',
                                      style: TextStyle(
                                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton.icon(
                                    onPressed: () async {
                                      final text = notesController.text.trim();
                                      await loanProvider.saveDayNote(dialogDate, text);
                                      
                                      // Trigger immediate Drive Excel backup as well in background
                                      try {
                                        GoogleDriveExcelBackupService().performBackup();
                                      } catch (_) {}

                                      if (dialogDate.year == _selectedDate.year &&
                                          dialogDate.month == _selectedDate.month &&
                                          dialogDate.day == _selectedDate.day) {
                                        _loadDayNote();
                                      }

                                      if (modalContext.mounted) {
                                        Navigator.of(modalContext).pop();
                                      }
                                      if (mounted) {
                                        messenger.showSnackBar(
                                          SnackBar(
                                            content: Row(
                                              children: [
                                                const Icon(LucideIcons.checkCircle, color: Colors.white, size: 17),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Text(
                                                    'Note saved for ${DateFormat('dd MMM yyyy').format(dialogDate)} & synced to GDrive',
                                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            backgroundColor: const Color(0xFF059669),
                                            behavior: SnackBarBehavior.floating,
                                            duration: const Duration(seconds: 3),
                                          ),
                                        );
                                      }
                                    },
                                    icon: const Icon(LucideIcons.check, size: 16, color: Colors.white),
                                    label: const Text('Save Note', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.accent,
                                      foregroundColor: Colors.white,
                                      minimumSize: Size.zero,
                                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borrowers = context.watch<LoanProvider>().borrowers;
    if (!identical(_lastBorrowersRef, borrowers)) {
      _rebuildBorrowerLookup(borrowers);
      _lastBorrowersRef = borrowers;
    }

    return Dialog.fullscreen(
      backgroundColor: isDark ? AppColors.backgroundDark : AppColors.background,
      child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Top Form Elements - RepaintBoundary isolates form changes from numpad
                    Expanded(
                      child: RepaintBoundary(
                        child: SingleChildScrollView(
                          physics: const ClampingScrollPhysics(),
                          child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Header
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: isDark ? Colors.white.withValues(alpha: 0.1) : AppColors.accent.withValues(alpha: 0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(LucideIcons.zap, color: isDark ? Colors.white : AppColors.accent, size: 22),
                                ),
                                const SizedBox(width: 12),
                                const Text(
                                  'Quick Add',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            IconButton(
                              icon: const Icon(LucideIcons.x),
                              onPressed: () => Navigator.of(context).pop(),
                              splashRadius: 24,
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        
                        // Date Selector (50%) & Realtime Day Total Box (50%) Row (Static 54dp)
                        IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Date Selector Box (50% Space)
                              Expanded(
                                child: InkWell(
                                  onTap: () => _selectDate(context),
                                  borderRadius: BorderRadius.circular(14),
                                  child: Container(
                                    height: 54,
                                    padding: const EdgeInsets.symmetric(horizontal: 12),
                                    decoration: BoxDecoration(
                                      color: isDark ? Colors.grey[850] : Colors.grey[100],
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: isDark ? Colors.grey[800]! : Colors.grey[300]!,
                                      ),
                                    ),
                                    alignment: Alignment.center,
                                    child: Row(
                                      children: [
                                        Icon(
                                          LucideIcons.calendar,
                                          size: 16,
                                          color: isDark ? Colors.white : AppColors.accent,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            DateFormat('dd MMM yyyy').format(_selectedDate),
                                            style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        Icon(
                                          LucideIcons.chevronDown,
                                          size: 16,
                                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              // Day Total Realtime Box (50% Space)
                              Expanded(
                                child: InkWell(
                                  onTap: () => _showDayTransactions(context),
                                  borderRadius: BorderRadius.circular(14),
                                  child: Container(
                                    height: 54,
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: isDark ? Colors.grey[850] : Colors.grey[100],
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: isDark ? Colors.grey[800]! : Colors.grey[300]!,
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              _isToday(_selectedDate) ? "Today's Total" : "Day Total",
                                              style: TextStyle(
                                                fontSize: 11,
                                                height: 1.1,
                                                fontWeight: FontWeight.w600,
                                                color: isDark ? Colors.grey[400] : Colors.grey[600],
                                              ),
                                            ),
                                            Icon(
                                              LucideIcons.arrowUpRight,
                                              size: 13,
                                              color: isDark ? const Color(0xFF34D399) : const Color(0xFF059669),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          fmtINR(_dayTotal),
                                          style: TextStyle(
                                            fontSize: 15,
                                            height: 1.2,
                                            fontWeight: FontWeight.bold,
                                            color: isDark ? const Color(0xFF34D399) : const Color(0xFF059669),
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        
                        // Borrower Name Display Box (Static 54dp)
                        Container(
                          height: 54,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            color: _codeController.text.isEmpty
                                ? (isDark ? Colors.grey[850] : Colors.grey[200])
                                : _matchedBorrower != null 
                                    ? (_isInactive 
                                        ? AppColors.error.withValues(alpha: 0.1)
                                        : (_hasPaidToday ? AppColors.warning.withValues(alpha: 0.1) : AppColors.success.withValues(alpha: 0.1)))
                                    : AppColors.error.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: _codeController.text.isEmpty
                                  ? (isDark ? Colors.grey[800]! : Colors.grey[300]!)
                                  : _matchedBorrower != null
                                      ? (_isInactive 
                                          ? AppColors.error.withValues(alpha: 0.3)
                                          : (_hasPaidToday ? AppColors.warning.withValues(alpha: 0.3) : AppColors.success.withValues(alpha: 0.3)))
                                      : AppColors.error.withValues(alpha: 0.3),
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Row(
                            children: [
                              Icon(
                                _codeController.text.isEmpty 
                                    ? LucideIcons.search 
                                    : _matchedBorrower != null 
                                        ? (_isInactive ? LucideIcons.userX : (_hasPaidToday ? LucideIcons.alertTriangle : LucideIcons.userCheck)) 
                                        : LucideIcons.userX,
                                color: _codeController.text.isEmpty
                                    ? (isDark ? Colors.grey[400] : Colors.grey[600])
                                    : _matchedBorrower != null 
                                        ? (_isInactive ? AppColors.error : (_hasPaidToday ? AppColors.warning : AppColors.success))
                                        : AppColors.error,
                                size: 19,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _codeController.text.isEmpty
                                          ? 'Enter code to find borrower'
                                          : _matchedBorrower != null ? _matchedBorrower!.name : 'Borrower not found',
                                      style: TextStyle(
                                        color: _codeController.text.isEmpty
                                            ? (isDark ? Colors.grey[400] : Colors.grey[600])
                                            : _matchedBorrower != null 
                                                ? (_isInactive 
                                                    ? AppColors.error 
                                                    : (_hasPaidToday ? AppColors.warning : (isDark ? Colors.green[300] : Colors.green[800])))
                                                : (isDark ? Colors.red[300] : Colors.red[800]),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    if ((_hasPaidToday || _isInactive) && _matchedBorrower != null) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        _isInactive ? 'No active loans (Cleared/Closed)' : 'Already paid on selected date',
                                        style: TextStyle(
                                          color: _isInactive ? AppColors.error : AppColors.warning,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        
                        // Borrower Code Input and Last Entered Code Box Row (Static 54dp)
                        IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(minHeight: 54),
                                  child: TextFormField(
                                    controller: _codeController,
                                    focusNode: _codeFocusNode,
                                    readOnly: true,
                                    showCursor: true,
                                    keyboardType: TextInputType.none,
                                    textInputAction: TextInputAction.next,
                                    onFieldSubmitted: (_) => _onNext(),
                                    onChanged: _onCodeChanged,
                                    enableInteractiveSelection: false,
                                    textAlignVertical: TextAlignVertical.center,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    onTap: () {
                                      setState(() => _activeField = _QuickAddField.code);
                                    },
                                    decoration: InputDecoration(
                                      labelText: 'Borrower Code',
                                      hintText: 'Enter code...',
                                      isDense: true,
                                      contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 14,
                                      ),
                                      prefixIcon: Icon(
                                        LucideIcons.hash,
                                        size: 18,
                                        color: _activeField == _QuickAddField.code
                                            ? (isDark ? Colors.white : AppColors.accent)
                                            : null,
                                      ),
                                      suffixIcon: _codeController.text.isNotEmpty && _activeField == _QuickAddField.code
                                          ? IconButton(
                                              icon: const Icon(LucideIcons.x, size: 16),
                                              onPressed: () {
                                                _codeController.clear();
                                                _onCodeChanged('');
                                              },
                                              splashRadius: 18,
                                            )
                                          : null,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(14),
                                        borderSide: BorderSide(
                                          color: _activeField == _QuickAddField.code
                                            ? (isDark ? Colors.white : AppColors.accent)
                                            : (isDark ? Colors.grey[800]! : Colors.grey[300]!),
                                          width: _activeField == _QuickAddField.code ? 2 : 1,
                                        ),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(14),
                                        borderSide: BorderSide(
                                          color: isDark ? Colors.white : AppColors.accent,
                                          width: 2,
                                        ),
                                      ),
                                    ),
                                    validator: (value) {
                                      if (value == null || value.trim().isEmpty) {
                                        return 'Required';
                                      }
                                      if (_matchedBorrower == null) {
                                        return 'Invalid';
                                      }
                                      return null;
                                    },
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: InkWell(
                                  onTap: (_lastEnteredCode != null && _lastEnteredCode != '-')
                                      ? () {
                                          HapticFeedback.selectionClick();
                                          _codeController.text = _lastEnteredCode!;
                                          _onCodeChanged(_lastEnteredCode!);
                                          setState(() => _activeField = _QuickAddField.code);
                                          _codeFocusNode.requestFocus();
                                        }
                                      : null,
                                  borderRadius: BorderRadius.circular(14),
                                  child: Container(
                                    constraints: const BoxConstraints(minHeight: 54),
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: isDark ? Colors.grey[850] : Colors.grey[100],
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: isDark ? Colors.grey[800]! : Colors.grey[300]!,
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          'Last Entered',
                                          style: TextStyle(
                                            fontSize: 11,
                                            height: 1.1,
                                            color: isDark ? Colors.grey[400] : Colors.grey[600],
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          _lastEnteredCode ?? '-',
                                          style: TextStyle(
                                            fontSize: 16,
                                            height: 1.2,
                                            fontWeight: FontWeight.bold,
                                            color: Theme.of(context).colorScheme.onSurface,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        
                        // Amount Input Box (Static 54dp)
                        ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 54),
                          child: TextFormField(
                            controller: _amountController,
                            focusNode: _amountFocusNode,
                            enabled: !_isInactive,
                            readOnly: true,
                            showCursor: true,
                            keyboardType: TextInputType.none,
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _onNext(),
                            onChanged: (_) => setState(() {}),
                            enableInteractiveSelection: false,
                            textAlignVertical: TextAlignVertical.center,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                            onTap: () {
                              if (!_isInactive) {
                                setState(() => _activeField = _QuickAddField.amount);
                              }
                            },
                            decoration: InputDecoration(
                              labelText: 'Amount',
                              hintText: 'Enter amount...',
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 14,
                              ),
                              prefixIcon: Icon(
                                LucideIcons.indianRupee,
                                size: 18,
                                color: _activeField == _QuickAddField.amount
                                    ? (isDark ? Colors.white : AppColors.accent)
                                    : null,
                              ),
                              suffixIcon: _amountController.text.isNotEmpty && _activeField == _QuickAddField.amount
                                  ? IconButton(
                                      icon: const Icon(LucideIcons.x, size: 16),
                                      onPressed: () {
                                        _amountController.clear();
                                        setState(() {});
                                      },
                                      splashRadius: 18,
                                    )
                                  : null,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide(
                                  color: _activeField == _QuickAddField.amount
                                      ? (isDark ? Colors.white : AppColors.accent)
                                      : (isDark ? Colors.grey[800]! : Colors.grey[300]!),
                                  width: _activeField == _QuickAddField.amount ? 2 : 1,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide(
                                  color: isDark ? Colors.white : AppColors.accent,
                                  width: 2,
                                ),
                              ),
                              disabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide(color: Colors.grey[400]!, width: 1),
                              ),
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Amount is required';
                              }
                              if (double.tryParse(value) == null || double.parse(value) <= 0) {
                                return 'Enter a valid amount';
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(height: 12),
                        
                        // Real-time Current Due, Amount, and Remaining Boxes
                        _buildDueBreakdown(isDark),
                      ],
                    ),
                  ),
                ),
              ),
                const SizedBox(height: 8),

                // FIXED IN PLACE AT BOTTOM:
                // Custom Themed NumPad
                RepaintBoundary(
                  child: _buildNumPad(isDark),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DayTransactionsSheet extends StatefulWidget {
  final DateTime selectedDate;
  final bool isDark;
  final VoidCallback onChanged;

  const _DayTransactionsSheet({
    required this.selectedDate,
    required this.isDark,
    required this.onChanged,
  });

  @override
  State<_DayTransactionsSheet> createState() => _DayTransactionsSheetState();
}

class _DayTransactionsSheetState extends State<_DayTransactionsSheet> {
  List<Map<String, dynamic>> _transactions = [];
  bool _loading = true;
  double _totalCollected = 0.0;
  DayNote? _dayNote;

  @override
  void initState() {
    super.initState();
    _fetchTransactions();
  }

  Future<void> _fetchTransactions() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final data = await DBHelper().getDateRangeReport(widget.selectedDate, widget.selectedDate);
      final dn = await DBHelper().getDayNote(widget.selectedDate);
      if (mounted) {
        final list = List<Map<String, dynamic>>.from(data['transactions']);
        list.sort((a, b) {
          final cA = _getEffectiveCreatedAt(a);
          final cB = _getEffectiveCreatedAt(b);
          final cmp = cB.compareTo(cA);
          if (cmp != 0) return cmp;
          final idA = (a['id'] as num?)?.toInt() ?? 0;
          final idB = (b['id'] as num?)?.toInt() ?? 0;
          return idB.compareTo(idA);
        });

        setState(() {
          _transactions = list;
          _totalCollected = (data['totalCollected'] as num?)?.toDouble() ?? 0.0;
          _dayNote = dn;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  int _getEffectiveCreatedAt(Map<String, dynamic> tx) {
    final c = tx['created_at'];
    if (c is int && c > 0) return c;
    if (c is num && c > 0) return c.toInt();
    return DateParser.safeParse(tx['date']).millisecondsSinceEpoch;
  }

  Future<void> _deleteTransaction(Map<String, dynamic> tx) async {
    final type = tx['type'] as String? ?? '';
    final id = tx['id'] as int?;
    final amount = (tx['amount'] as num?)?.toDouble() ?? 0.0;
    final borrowerName = tx['borrower_name'] as String? ?? 'Transaction';

    if (id == null || (type != 'Collected' && type != 'Lent')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot delete this transaction type')),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(LucideIcons.trash2, color: AppColors.error, size: 20),
            SizedBox(width: 8),
            Text('Delete Transaction', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'Are you sure you want to delete this $type of ${fmtINR(amount)} for $borrowerName?',
          style: const TextStyle(fontSize: 14),
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
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    try {
      final provider = context.read<LoanProvider>();
      if (type == 'Collected') {
        final loanId = tx['loan_id'] as int? ?? 0;
        await provider.deletePayment(id, loanId);
      } else if (type == 'Lent') {
        await provider.deleteLoan(id);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Transaction deleted successfully'),
            backgroundColor: AppColors.success,
            duration: Duration(seconds: 2),
          ),
        );
      }

      widget.onChanged();
      _fetchTransactions();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting transaction: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final dateStr = DateFormat('dd MMM yyyy').format(widget.selectedDate);
    final isTodayDate = _isDateToday(widget.selectedDate);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.82,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E2024) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.15),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag Handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[700] : Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            LucideIcons.receipt,
                            size: 18,
                            color: isDark ? Colors.white : AppColors.accent,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            isTodayDate ? "Today's Transactions" : "Day Transactions",
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        dateStr,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                // Total Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF34D399).withValues(alpha: 0.15)
                        : const Color(0xFF059669).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isDark
                          ? const Color(0xFF34D399).withValues(alpha: 0.3)
                          : const Color(0xFF059669).withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        LucideIcons.trendingUp,
                        size: 13,
                        color: isDark ? const Color(0xFF34D399) : const Color(0xFF059669),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        fmtINR(_totalCollected),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: isDark ? const Color(0xFF34D399) : const Color(0xFF059669),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(LucideIcons.x, size: 20),
                  onPressed: () => Navigator.pop(context),
                  splashRadius: 20,
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            color: isDark ? Colors.grey[800] : Colors.grey[200],
          ),

          // Day Note Banner if present
          if (_dayNote != null && _dayNote!.notes.trim().isNotEmpty && !_dayNote!.isDeleted)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 10, 16, 4),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF2E2718) : const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.45),
                  width: 1.2,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(LucideIcons.fileText, size: 16, color: Color(0xFFF59E0B)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Day Closing Note',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFF59E0B),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _dayNote!.notes,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.35,
                            color: isDark ? Colors.grey[200] : const Color(0xFF78350F),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          // Content List
          Flexible(
            child: _loading
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 48),
                    child: Center(
                      child: CircularProgressIndicator(color: AppColors.accent),
                    ),
                  )
                : _transactions.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                LucideIcons.receipt,
                                size: 48,
                                color: isDark ? Colors.grey[600] : Colors.grey[350],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                "No transactions recorded on this date",
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                "Payments collected will show up here.",
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark ? Colors.grey[500] : Colors.grey[500],
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                        shrinkWrap: true,
                        itemCount: _transactions.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final tx = _transactions[index];
                          final type = tx['type'] as String? ?? 'Collected';
                          final amount = (tx['amount'] as num?)?.toDouble() ?? 0.0;
                          final dateStr = tx['date'] as String? ?? '';
                          final borrowerName = tx['borrower_name'] as String? ?? '';
                          String borrowerCode = tx['borrower_code'] as String? ?? '';
                          if (borrowerCode.contains('_del_')) {
                            borrowerCode = borrowerCode.split('_del_').first;
                          }

                          DateTime? date;
                          try {
                            date = DateParser.safeParse(dateStr);
                            final createdAt = tx['created_at'];
                            if (createdAt is int && createdAt > 0 && date.hour == 0 && date.minute == 0 && date.second == 0) {
                              final createdDt = DateTime.fromMillisecondsSinceEpoch(createdAt);
                              if (createdDt.year == date.year && createdDt.month == date.month && createdDt.day == date.day) {
                                date = createdDt;
                              }
                            }
                          } catch (_) {}

                          IconData icon;
                          Color color;
                          String sign;
                          if (type == 'Lent') {
                            icon = LucideIcons.arrowUpRight;
                            color = AppColors.warning;
                            sign = "-";
                          } else if (type == 'Collected') {
                            icon = LucideIcons.arrowDownLeft;
                            color = AppColors.success;
                            sign = "+";
                          } else if (type == 'Service') {
                            icon = LucideIcons.wrench;
                            color = AppColors.success;
                            sign = "+";
                          } else {
                            icon = LucideIcons.receipt;
                            color = AppColors.error;
                            sign = "-";
                          }

                          final dfTimeOnly = DateFormat('hh:mm a');
                          final dfDateOnly = DateFormat('dd MMM');
                          final formattedTime = date != null
                              ? ((date.hour == 0 && date.minute == 0 && date.second == 0)
                                  ? dfDateOnly.format(date)
                                  : dfTimeOnly.format(date))
                              : dateStr;

                          final canDelete = type == 'Collected' || type == 'Lent';

                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF282B30) : const Color(0xFFF3F4F6),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isDark ? Colors.grey[800]! : Colors.grey[300]!,
                                width: 0.8,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(7),
                                  decoration: BoxDecoration(
                                    color: color.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(icon, color: color, size: 16),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          if (borrowerCode.isNotEmpty) ...[
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                              decoration: BoxDecoration(
                                                color: AppColors.accent.withValues(alpha: 0.12),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                borrowerCode,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 11,
                                                  color: AppColors.accent,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                          ],
                                          Flexible(
                                            child: Text(
                                              borrowerName,
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13,
                                                color: isDark ? Colors.white : AppColors.textPrimary,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 3),
                                      Row(
                                        children: [
                                          Text(
                                            type,
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w500,
                                              color: color,
                                            ),
                                          ),
                                          if (formattedTime.isNotEmpty) ...[
                                            Text(
                                              " • $formattedTime",
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: isDark ? Colors.grey[400] : Colors.grey[600],
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      "$sign${fmtINR(amount)}",
                                      style: TextStyle(
                                        color: color,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                                if (canDelete) ...[
                                  const SizedBox(width: 6),
                                  IconButton(
                                    icon: const Icon(LucideIcons.trash2, size: 16, color: AppColors.error),
                                    tooltip: 'Delete',
                                    onPressed: () => _deleteTransaction(tx),
                                    splashRadius: 18,
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  bool _isDateToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year && date.month == now.month && date.day == now.day;
  }
}
