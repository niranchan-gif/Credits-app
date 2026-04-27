class Expense {
  int? id;
  double amount;
  DateTime expenseDate;
  String category;
  String? notes;

  Expense({
    this.id,
    required this.amount,
    required this.expenseDate,
    required this.category,
    this.notes,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'amount': amount,
      'expense_date': expenseDate.toIso8601String(),
      'category': category,
      'notes': notes,
    };
  }

  factory Expense.fromMap(Map<String, dynamic> map) {
    return Expense(
      id: map['id'],
      amount: (map['amount'] as num).toDouble(),
      expenseDate: DateTime.parse(map['expense_date']),
      category: map['category'] ?? 'General',
      notes: map['notes'],
    );
  }
}
