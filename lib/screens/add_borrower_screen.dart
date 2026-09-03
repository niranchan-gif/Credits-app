import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'package:intl/intl.dart';
import '../models/borrower.dart';
import '../models/loan.dart';
import '../providers/loan_provider.dart';
import '../utils/app_colors.dart';
import '../widgets/premium_card.dart';

class AddBorrowerScreen extends StatefulWidget {
  final Borrower? borrower;

  const AddBorrowerScreen({super.key, this.borrower});

  @override
  State<AddBorrowerScreen> createState() => _AddBorrowerScreenState();
}

class _AddBorrowerScreenState extends State<AddBorrowerScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _codeCtrl;
  late TextEditingController _nameCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _addressCtrl;
  late TextEditingController _loanAmountCtrl;
  late TextEditingController _interestAmountCtrl;
  late TextEditingController _installmentDaysCtrl;
  late TextEditingController _notesCtrl;

  DateTime _loanDate = DateTime.now();
  bool _isSaving = false;

  bool get _isEditMode => widget.borrower != null;

  DateTime? get _calculatedEndDate {
    final daysText = _installmentDaysCtrl.text.trim();
    if (daysText.isEmpty) return null;
    final days = int.tryParse(daysText);
    if (days == null) return null;
    return _loanDate.add(Duration(days: days));
  }

  @override
  void initState() {
    super.initState();
    final b = widget.borrower;
    _codeCtrl = TextEditingController(text: b?.displayBorrowerCode ?? '');
    _nameCtrl = TextEditingController(text: b?.name ?? '');
    _phoneCtrl = TextEditingController(text: b?.phone ?? '');
    _addressCtrl = TextEditingController(text: b?.address ?? '');
    _loanAmountCtrl = TextEditingController();
    _interestAmountCtrl = TextEditingController();
    _installmentDaysCtrl = TextEditingController();
    _notesCtrl = TextEditingController(text: b?.notes ?? '');

    if (b == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final code = await context.read<LoanProvider>().generateBorrowerCode();
        if (mounted && _codeCtrl.text.isEmpty) setState(() => _codeCtrl.text = code);
      });
    }
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _loanAmountCtrl.dispose();
    _interestAmountCtrl.dispose();
    _installmentDaysCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _loanDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: AppColors.accent,
              onPrimary: Colors.white,
              surface: Theme.of(context).colorScheme.surface,
              onSurface: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _loanDate = picked);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final provider = context.read<LoanProvider>();
    final phone = _phoneCtrl.text.trim();

    if (phone.isNotEmpty) {
      final existingBorrowers = provider.borrowers.where((b) => b.phone == phone);
      if (existingBorrowers.isNotEmpty) {
        final isDuplicate = !_isEditMode || existingBorrowers.first.id != widget.borrower?.id;
        if (isDuplicate) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('A borrower with this phone already exists!'), backgroundColor: AppColors.error),
          );
          return;
        }
      }
    }

    // Validate borrower_code uniqueness if creating a borrower or editing a dummy borrower
    if (!_isEditMode || (_isEditMode && widget.borrower?.isDummy == true)) {
      final code = _codeCtrl.text.trim();
      final existingWithCode = provider.borrowers.where((b) => b.borrowerCode.toLowerCase() == code.toLowerCase() && b.id != widget.borrower?.id);
      if (existingWithCode.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('A borrower with this code already exists!'), backgroundColor: AppColors.error),
        );
        return;
      }
    }

    setState(() => _isSaving = true);

    final borrower = Borrower(
      id: widget.borrower?.id,
      syncId: widget.borrower?.syncId,
      borrowerCode: _codeCtrl.text.trim(),
      name: _nameCtrl.text.trim(),
      phone: _phoneCtrl.text.trim(),
      address: _addressCtrl.text.trim().isEmpty ? null : _addressCtrl.text.trim(),
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      isDummy: widget.borrower?.isDummy ?? false,
      isClosed: widget.borrower?.isClosed ?? false,
      isDeleted: widget.borrower?.isDeleted ?? false,
      createdAt: widget.borrower?.createdAt ?? 0,
      updatedAt: widget.borrower?.updatedAt ?? 0,
    );

    Loan? initialLoan;
    if (!_isEditMode) {
      final daysText = _installmentDaysCtrl.text.trim();
      final installmentDays = daysText.isNotEmpty ? int.tryParse(daysText) : null;
      initialLoan = Loan(
        borrowerId: 0,
        loanAmount: double.parse(_loanAmountCtrl.text.trim()),
        interestAmount: double.parse(_interestAmountCtrl.text.trim().isEmpty ? '0' : _interestAmountCtrl.text.trim()),
        loanDate: _loanDate,
        installmentDays: installmentDays,
        endDate: _calculatedEndDate,
      );
    }

    if (_isEditMode) {
      await provider.updateBorrower(borrower);
    } else {
      await provider.addBorrower(borrower, initialLoan);
    }

    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(_isEditMode ? 'Edit Borrower' : 'New Borrower'),
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionLabel('Borrower ID').animate().fadeIn(delay: 100.ms).slideX(begin: -0.1),
              _buildField(
                controller: _codeCtrl,
                label: 'Borrower Code',
                icon: HugeIcons.strokeRoundedCheckmarkBadge01,
                readOnly: _isEditMode && widget.borrower?.isDummy != true,
                validator: (v) => v == null || v.trim().isEmpty ? 'ID required' : null,
              ).animate().fadeIn(delay: 200.ms).slideX(begin: -0.1),
              const SizedBox(height: 24),
              
              _sectionLabel('Personal Details').animate().fadeIn(delay: 300.ms).slideX(begin: -0.1),
              PremiumCard(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    _buildField(
                      controller: _nameCtrl,
                      label: 'Full Name',
                      icon: HugeIcons.strokeRoundedUser,
                      validator: (v) => v == null || v.trim().isEmpty ? 'Name required' : null,
                    ),
                    const SizedBox(height: 16),
                    _buildField(
                      controller: _phoneCtrl,
                      label: 'Phone Number',
                      icon: HugeIcons.strokeRoundedCall,
                      keyboardType: TextInputType.phone,
                      validator: (v) => v != null && v.isNotEmpty && v.trim().length < 10 ? 'Enter valid phone' : null,
                    ),
                    const SizedBox(height: 16),
                    _buildField(
                      controller: _addressCtrl,
                      label: 'Address (Optional)',
                      icon: HugeIcons.strokeRoundedLocation01,
                      maxLines: 2,
                    ),
                  ],
                ),
              ).animate().fadeIn(delay: 400.ms).slideY(begin: 0.1),
              const SizedBox(height: 24),

              if (!_isEditMode) ...[
                _sectionLabel('Loan Information').animate().fadeIn(delay: 500.ms).slideX(begin: -0.1),
                PremiumCard(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      _buildField(
                        controller: _loanAmountCtrl,
                        label: 'Loan Amount (₹)',
                        icon: HugeIcons.strokeRoundedCoins01,
                        keyboardType: TextInputType.number,
                        validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 16),
                      GestureDetector(
                        onTap: _pickDate,
                        child: AbsorbPointer(
                          child: _buildField(
                            controller: TextEditingController(text: DateFormat('dd MMMM yyyy').format(_loanDate)),
                            label: 'Loan Date',
                            icon: HugeIcons.strokeRoundedCalendar01,
                            readOnly: true,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildField(
                        controller: _installmentDaysCtrl,
                        label: 'Duration (Days)',
                        icon: HugeIcons.strokeRoundedTimer01,
                        keyboardType: TextInputType.number,
                        onChanged: (v) => setState(() {}),
                      ),
                      if (_calculatedEndDate != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: AppColors.accent.withOpacity( 0.1), borderRadius: BorderRadius.circular(12)),
                          child: Text(
                            'Ends on: ${DateFormat('dd MMM yyyy').format(_calculatedEndDate!)}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      _buildField(
                        controller: _interestAmountCtrl,
                        label: 'Interest Amount (₹)',
                        icon: HugeIcons.strokeRoundedTrendingUpDown,
                        keyboardType: TextInputType.number,
                        validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                      ),
                    ],
                  ),
                ).animate().fadeIn(delay: 600.ms).slideY(begin: 0.1),
                const SizedBox(height: 24),
              ],

              _sectionLabel('Additional Notes').animate().fadeIn(delay: 700.ms).slideX(begin: -0.1),
              _buildField(
                controller: _notesCtrl,
                label: 'Internal Notes',
                icon: HugeIcons.strokeRoundedNote01,
                maxLines: 3,
              ).animate().fadeIn(delay: 800.ms).slideY(begin: 0.1),
              const SizedBox(height: 40),

              SizedBox(
                height: 56,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _save,
                  child: _isSaving 
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text(_isEditMode ? 'Update Profile' : 'Create Borrower'),
                ),
              ).animate().fadeIn(delay: 900.ms).scale(begin: const Offset(0.95, 0.95)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 12),
      child: Text(label, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Theme.of(context).colorScheme.onSurfaceVariant)),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required dynamic icon,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
    void Function(String)? onChanged,
    int maxLines = 1,
    bool readOnly = false,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      validator: validator,
      onChanged: onChanged,
      readOnly: readOnly,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
      ),
    );
  }
}

