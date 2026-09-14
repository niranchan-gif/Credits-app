import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/loan_provider.dart';
import '../models/borrower.dart';
import '../utils/app_colors.dart';
import '../utils/fmt.dart';
import '../database/db_helper.dart';
import '../utils/date_parser.dart';

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

  @override
  void initState() {
    super.initState();
    _lastEnteredCode = _persistedLastCode;
    _amountController.addListener(_onFieldControllerChanged);
    _codeController.addListener(_onFieldControllerChanged);
    _loadPersistedLastCode();
    // Fetch borrowers if empty just in case
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.read<LoanProvider>().borrowers.isEmpty) {
        context.read<LoanProvider>().loadBorrowers();
      }
      _loadDayTotal();
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

  bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year && date.month == now.month && date.day == now.day;
  }

  void _onFieldControllerChanged() {
    if (mounted) setState(() {});
  }

  void _checkIfPaidOnSelectedDate() {
    if (_matchedBorrower == null || _isInactive) return;
    
    final provider = context.read<LoanProvider>();
    provider.hasPaymentOnDate(_matchedBorrower!.id ?? 0, _selectedDate).then((hasPaid) {
      if (mounted && _matchedBorrower != null) {
        setState(() {
          _hasPaidToday = hasPaid;
        });
      }
    });
  }

  @override
  void dispose() {
    _amountController.removeListener(_onFieldControllerChanged);
    _codeController.removeListener(_onFieldControllerChanged);
    _codeController.dispose();
    _amountController.dispose();
    _codeFocusNode.dispose();
    _amountFocusNode.dispose();
    super.dispose();
  }

  void _onCodeChanged(String value) {
    if (value.trim().isEmpty) {
      setState(() {
        _matchedBorrower = null;
        _hasPaidToday = false;
        _isInactive = false;
      });
      return;
    }
    
    final provider = context.read<LoanProvider>();
    final code = value.trim();
    try {
      final borrower = provider.borrowers.firstWhere(
        (b) => b.borrowerCode == code && !b.isDummy,
      );
      
      final inactive = borrower.isClosed || borrower.totalBalance <= 0;
      
      setState(() {
        _matchedBorrower = borrower;
        _isInactive = inactive;
        _hasPaidToday = false;
      });
      
      if (!inactive) {
        _checkIfPaidOnSelectedDate();
      }
    } catch (_) {
      setState(() {
        _matchedBorrower = null;
        _hasPaidToday = false;
        _isInactive = false;
      });
    }
  }

  void _onKeyPress(String key) {
    HapticFeedback.selectionClick();
    final controller = _activeField == _QuickAddField.code ? _codeController : _amountController;
    final text = controller.text;
    final selection = controller.selection;
    final start = selection.isValid && selection.start >= 0 ? selection.start : text.length;
    final end = selection.isValid && selection.end >= 0 ? selection.end : text.length;

    // Disallow decimal point for borrower code
    if (_activeField == _QuickAddField.code && key == '.') return;

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
      _checkIfPaidOnSelectedDate();
      
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
            _checkIfPaidOnSelectedDate();
          },
        );
      },
    );

    if (mounted) {
      _loadDayTotal();
      _checkIfPaidOnSelectedDate();
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
  }) {
    final bgColor = customBg ?? (isDark ? const Color(0xFF2E3138) : Colors.white);
    final textColor = customTextColor ?? (isDark ? Colors.white : const Color(0xFF0F172A));

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3.5, vertical: 3),
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
              height: 52,
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
                  fontSize: 24,
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
          // Row 4: Backspace, 0, Action (Next / Save)
          Row(
            children: [
              // Bottom-Left: Backspace
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
                  Icons.backspace_rounded,
                  size: 22,
                  color: isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626),
                ),
              ),
              // Middle: 0
              _buildNumKey(text: '0', onTap: () => _onKeyPress('0'), isDark: isDark),
              // Bottom-Right: Next / Save Action
              _buildNumKey(
                text: '',
                onTap: _onNext,
                isDark: isDark,
                customBg: _isInactive ? Colors.grey : AppColors.accent,
                customBorder: Border.all(
                  color: _isInactive ? Colors.grey : AppColors.accent,
                  width: 1.2,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      isCode ? 'Next' : 'Save',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      isCode ? LucideIcons.arrowRight : LucideIcons.checkCircle,
                      size: 17,
                      color: Colors.white,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
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
                // Top Form Elements - All boxes are static with fixed dimensions
                Expanded(
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
                const SizedBox(height: 8),

                // FIXED IN PLACE AT BOTTOM:
                // Custom Themed NumPad
                _buildNumPad(isDark),
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

    if (confirm != true) return;

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
