import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/borrower.dart';
import '../models/loan.dart';
import '../providers/loan_provider.dart';

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
    );
    if (picked != null) {
      setState(() => _loanDate = picked);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    final daysText = _installmentDaysCtrl.text.trim();
    final installmentDays = daysText.isNotEmpty ? int.tryParse(daysText) : null;

    final loan = Loan(
      borrowerId: widget.borrower.id!,
      loanAmount: double.parse(_loanAmountCtrl.text.trim()),
      interestAmount: double.parse(
          _interestAmountCtrl.text.trim().isEmpty ? '0' : _interestAmountCtrl.text.trim()),
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
      backgroundColor: const Color(0xFFF5F7FF),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E3A5F),
        title: const Text('Add New Loan', style: TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _sectionLabel('Loan Details for ${widget.borrower.name}'),
            _buildField(
              controller: _loanAmountCtrl,
              label: 'Loan Amount (₹)',
              icon: Icons.currency_rupee,
              keyboardType: TextInputType.number,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Amount required';
                if (double.tryParse(v) == null) return 'Enter valid amount';
                return null;
              },
            ),
            const SizedBox(height: 12),
              GestureDetector(
                onTap: _pickDate,
                child: AbsorbPointer(
                  child: InputDecorator(
                    decoration: _inputDecoration('Loan Date', Icons.calendar_today),
                    child: Text(
                      '${_loanDate.day}/${_loanDate.month}/${_loanDate.year}',
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _buildField(
                controller: _installmentDaysCtrl,
                label: 'Installment Days (Optional)',
                icon: Icons.timer,
                keyboardType: TextInputType.number,
                onChanged: (v) => setState(() {}),
                validator: (v) {
                  if (v != null && v.trim().isNotEmpty && int.tryParse(v) == null) {
                    return 'Enter a valid number of days';
                  }
                  return null;
                },
              ),
              if (_calculatedEndDate != null) ...[
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    'End Date: ${_calculatedEndDate!.day}/${_calculatedEndDate!.month}/${_calculatedEndDate!.year}',
                    style: const TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
            _buildField(
              controller: _interestAmountCtrl,
              label: 'Interest Amount (₹)',
              icon: Icons.currency_rupee,
              keyboardType: TextInputType.number,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Amount required';
                if (double.tryParse(v) == null) return 'Invalid';
                return null;
              },
            ),
            const SizedBox(height: 12),
            _buildField(
              controller: _notesCtrl,
              label: 'Notes (Optional)',
              icon: Icons.notes,
              maxLines: 2,
            ),
            const SizedBox(height: 28),
            SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E3A5F),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                icon: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save, color: Colors.white),
                label: const Text(
                  'Save Loan',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
                onPressed: _isSaving ? null : _save,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(label,
          style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: Color(0xFF1E3A5F))),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: const Color(0xFF1E3A5F)),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade200)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF1E3A5F))),
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
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      validator: validator,
      onChanged: onChanged,
      decoration: _inputDecoration(label, icon),
    );
  }
}
