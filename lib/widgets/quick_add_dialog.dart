import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../providers/loan_provider.dart';
import '../models/borrower.dart';
import '../utils/app_colors.dart';
import '../widgets/premium_card.dart';

class QuickAddDialog extends StatefulWidget {
  const QuickAddDialog({Key? key}) : super(key: key);

  @override
  State<QuickAddDialog> createState() => _QuickAddDialogState();
}

class _QuickAddDialogState extends State<QuickAddDialog> {
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();
  final _amountController = TextEditingController();
  final _codeFocusNode = FocusNode();
  final _amountFocusNode = FocusNode();

  DateTime _selectedDate = DateTime.now();
  Borrower? _matchedBorrower;
  bool _hasPaidToday = false;
  bool _isInactive = false;
  String? _lastEnteredCode;

  @override
  void initState() {
    super.initState();
    // Fetch borrowers if empty just in case
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.read<LoanProvider>().borrowers.isEmpty) {
        context.read<LoanProvider>().loadBorrowers();
      }
      _codeFocusNode.requestFocus();
    });
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
      
      _checkIfPaidOnSelectedDate();
      
      // Move focus back to amount if a borrower is already matched
      if (_matchedBorrower != null) {
        _amountFocusNode.requestFocus();
      } else {
        _codeFocusNode.requestFocus();
      }
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
          title: Row(
            children: [
              Icon(LucideIcons.alertTriangle, color: AppColors.warning),
              const SizedBox(width: 8),
              const Text('Duplicate Payment'),
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
      _amountFocusNode.requestFocus();
      return;
    }

    final amount = double.tryParse(amountStr);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid positive amount')),
      );
      return;
    }

    try {
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
        _lastEnteredCode = _matchedBorrower!.borrowerCode;

        // Reset for next entry, KEEPING THE DATE!
        _codeController.clear();
        _amountController.clear();
        setState(() {
          _matchedBorrower = null;
          _hasPaidToday = false;
          _isInactive = false;
        });
        
        Future.delayed(const Duration(milliseconds: 50), () {
          if (mounted) {
            FocusScope.of(context).requestFocus(_codeFocusNode);
            SystemChannels.textInput.invokeMethod('TextInput.show');
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Dialog.fullscreen(
      backgroundColor: isDark ? AppColors.backgroundDark : AppColors.background,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
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
                            color: AppColors.accent.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(LucideIcons.zap, color: AppColors.accent, size: 24),
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
                const SizedBox(height: 24),
                
                // Date Selector (Persistent)
                InkWell(
                  onTap: () => _selectDate(context),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.grey[850] : Colors.grey[100],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDark ? Colors.grey[800]! : Colors.grey[300]!,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(LucideIcons.calendar, size: 20, color: AppColors.accent),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            DateFormat('dd MMM yyyy').format(_selectedDate),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Icon(LucideIcons.chevronDown, size: 16, color: isDark ? Colors.grey[400] : Colors.grey[600]),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                
                // Name Display
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: _codeController.text.isEmpty
                        ? (isDark ? Colors.grey[850] : Colors.grey[200])
                        : _matchedBorrower != null 
                            ? (_isInactive 
                                ? AppColors.error.withOpacity(0.1)
                                : (_hasPaidToday ? AppColors.warning.withOpacity(0.1) : AppColors.success.withOpacity(0.1)))
                            : AppColors.error.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _codeController.text.isEmpty
                          ? (isDark ? Colors.grey[800]! : Colors.grey[300]!)
                          : _matchedBorrower != null
                              ? (_isInactive 
                                  ? AppColors.error.withOpacity(0.3)
                                  : (_hasPaidToday ? AppColors.warning.withOpacity(0.3) : AppColors.success.withOpacity(0.3)))
                              : AppColors.error.withOpacity(0.3),
                    ),
                  ),
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
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
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
                                fontSize: 16,
                              ),
                            ),
                            if ((_hasPaidToday || _isInactive) && _matchedBorrower != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                _isInactive ? 'No active loans (Cleared/Closed)' : 'Already paid on selected date',
                                style: TextStyle(
                                  color: _isInactive ? AppColors.error : AppColors.warning,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                
                // Borrower Code Input and Last Entered Code
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _codeController,
                        focusNode: _codeFocusNode,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.next,
                        onChanged: _onCodeChanged,
                        onFieldSubmitted: (_) {
                          if (_matchedBorrower != null) {
                            _amountFocusNode.requestFocus();
                          }
                        },
                        decoration: InputDecoration(
                          labelText: 'Borrower Code',
                          hintText: 'Enter code...',
                          prefixIcon: const Icon(LucideIcons.hash),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: AppColors.accent, width: 2),
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
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        height: 60,
                        decoration: BoxDecoration(
                          color: isDark ? Colors.grey[850] : Colors.grey[100],
                          borderRadius: BorderRadius.circular(12),
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
                                fontSize: 10,
                                color: isDark ? Colors.grey[400] : Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _lastEnteredCode ?? '-',
                              style: TextStyle(
                                fontSize: 16,
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
                  ],
                ),
                const SizedBox(height: 20),
                
                // Amount Input
                TextFormField(
                  controller: _amountController,
                  focusNode: _amountFocusNode,
                  enabled: !_isInactive,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  textInputAction: TextInputAction.next,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                  ],
                  onEditingComplete: () {
                    // This prevents the default unfocus behavior!
                    if (!_isInactive) _submitPayment();
                  },
                  decoration: InputDecoration(
                    labelText: 'Amount',
                    hintText: 'Enter amount...',
                    prefixIcon: const Icon(LucideIcons.indianRupee),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AppColors.accent, width: 2),
                    ),
                    disabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
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
                const SizedBox(height: 28),
                
                // Submit Button
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isInactive ? null : _submitPayment,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isInactive ? Colors.grey : AppColors.accent,
                      foregroundColor: _isInactive ? Colors.white70 : AppColors.background,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: _isInactive ? 0 : 2,
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(LucideIcons.checkCircle, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Save & Next',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
    );
  }
}
