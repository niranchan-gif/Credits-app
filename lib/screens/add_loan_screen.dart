import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';

import '../models/borrower.dart';
import '../models/loan.dart';
import '../providers/loan_provider.dart';
import '../utils/app_colors.dart';
import '../widgets/premium_card.dart';

class AddLoanScreen extends StatefulWidget {
  final Borrower borrower;

  const AddLoanScreen({super.key, required this.borrower});

  @override
  State<AddLoanScreen> createState() => _AddLoanScreenState();
}

class _AddLoanScreenState extends State<AddLoanScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _loanAmountCtrl;
  late TextEditingController _interestAmountCtrl;
  late TextEditingController _installmentDaysCtrl;
  late TextEditingController _notesCtrl;

  DateTime _loanDate = DateTime.now();
  bool _isSaving = false;

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
    _loanAmountCtrl = TextEditingController();
    _interestAmountCtrl = TextEditingController();
    _installmentDaysCtrl = TextEditingController();
    _notesCtrl = TextEditingController();
  }

  @override
  void dispose() {
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
      builder: (context, child) => Theme(data: Theme.of(context).copyWith(colorScheme: Theme.of(context).colorScheme.copyWith(primary: AppColors.accent, surface: Theme.of(context).colorScheme.surface)), child: child!),
    );
    if (picked != null) setState(() => _loanDate = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    final daysText = _installmentDaysCtrl.text.trim();
    final installmentDays = daysText.isNotEmpty ? int.tryParse(daysText) : null;

    final loan = Loan(
      borrowerId: widget.borrower.id!,
      loanAmount: double.parse(_loanAmountCtrl.text.trim()),
      interestAmount: double.parse(_interestAmountCtrl.text.trim().isEmpty ? '0' : _interestAmountCtrl.text.trim()),
      loanDate: _loanDate,
      installmentDays: installmentDays,
      endDate: _calculatedEndDate,
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
    );

    await context.read<LoanProvider>().addLoan(loan);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Add New Loan'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 40),
          children: [
            _sectionLabel('Borrower: ${widget.borrower.name}'),
            PremiumCard(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  _buildField(
                    controller: _loanAmountCtrl,
                    label: 'Loan Amount (₹)',
                    icon: LucideIcons.coins,
                    keyboardType: TextInputType.number,
                    validator: (v) => v == null || v.trim().isEmpty ? 'Amount required' : null,
                  ),
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: _pickDate,
                    child: AbsorbPointer(
                      child: _buildField(
                        controller: TextEditingController(text: DateFormat('dd MMMM yyyy').format(_loanDate)),
                        label: 'Loan Date',
                        icon: LucideIcons.calendar,
                        readOnly: true,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildField(
                    controller: _installmentDaysCtrl,
                    label: 'Duration (Days)',
                    icon: LucideIcons.timer,
                    keyboardType: TextInputType.number,
                    onChanged: (v) => setState(() {}),
                  ),
                  if (_calculatedEndDate != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.white.withOpacity( 0.1), borderRadius: BorderRadius.circular(12)),
                      child: Text(
                        'Ends on: ${DateFormat('dd MMM yyyy').format(_calculatedEndDate!)}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  _buildField(
                    controller: _interestAmountCtrl,
                    label: 'Interest Amount (₹)',
                    icon: LucideIcons.trendingUp,
                    keyboardType: TextInputType.number,
                    validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            _sectionLabel('Additional Notes'),
            _buildField(
              controller: _notesCtrl,
              label: 'Internal Notes',
              icon: LucideIcons.stickyNote,
              maxLines: 3,
            ),
            const SizedBox(height: 40),
            SizedBox(
              height: 56,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _save,
                child: _isSaving 
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('Create Loan'),
              ),
            ),
          ],
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
    required IconData icon,
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

