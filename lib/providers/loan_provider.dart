import 'package:flutter/foundation.dart';
import '../database/db_helper.dart';
import '../models/borrower.dart';
import '../models/loan.dart';
import '../models/payment.dart';
import '../models/expense.dart';

class LoanProvider extends ChangeNotifier {
  final DBHelper _db = DBHelper();

  List<Borrower> _borrowers = [];
  List<Borrower> get borrowers => _borrowers;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  /// Borrower IDs that received a payment today (resets automatically at midnight).
  Set<int> _paidTodayIds = {};
  Set<int> get paidTodayIds => _paidTodayIds;

  /// Borrower IDs that have some loans paid today and some still pending.
  Set<int> _partiallyPaidTodayIds = {};
  Set<int> get partiallyPaidTodayIds => _partiallyPaidTodayIds;

  /// Number of loans paid today per borrower.
  Map<int, int> _paidLoanCountsToday = {};
  Map<int, int> get paidLoanCountsToday => _paidLoanCountsToday;

  /// Number of loans considered for today's collection status per borrower.
  Map<int, int> _todayLoanCounts = {};
  Map<int, int> get todayLoanCounts => _todayLoanCounts;

  /// Borrower IDs where all loans are cleared.
  Set<int> _completedIds = {};
  Set<int> get completedIds => _completedIds;

  // Global summary kept in state — refreshed on every data mutation
  Map<String, dynamic> _globalSummary = {
    'totalLoaned': 0.0,
    'totalInterest': 0.0,
    'totalDue': 0.0,
    'totalCollected': 0.0,
    'totalPending': 0.0,
    'totalBorrowers': 0,
  };
  Map<String, dynamic> get globalSummary => _globalSummary;

  /// Expenses list
  List<Expense> _expenses = [];
  List<Expense> get expenses => _expenses;

  /// Total invested (for on-hand calculation)
  double _totalInvested = 0.0;
  double get totalInvested => _totalInvested;

  /// Total expenses
  double _totalExpenses = 0.0;
  double get totalExpenses => _totalExpenses;

  /// On-hand calculation: Invested - Total Loaned + Total Collected - Total Expenses
  double get onHand {
    final totalLoaned = (_globalSummary['totalLoaned'] ?? 0.0) as double;
    final totalCollected = (_globalSummary['totalCollected'] ?? 0.0) as double;
    return _totalInvested - totalLoaned + totalCollected - _totalExpenses;
  }

  /// Loads borrowers AND refreshes global summary in one call.
  /// Called after every mutation so UI is always consistent.
  Future<void> loadBorrowers() async {
    _isLoading = true;
    notifyListeners();
    _borrowers = await _db.getAllBorrowers();
    _globalSummary = await _db.getGlobalSummary();
    _paidLoanCountsToday = await _db.getPaidLoanCountsToday();
    final clearedPaidLoanCountsToday =
        await _db.getClearedPaidLoanCountsToday();
    _todayLoanCounts = {
      for (final borrower in _borrowers)
        if (borrower.id != null)
          borrower.id!: borrower.loanCount +
              (clearedPaidLoanCountsToday[borrower.id] ?? 0)
    };
    _paidTodayIds = await _db.getBorrowersPaidToday();
    _completedIds = await _db.getCompletedBorrowerIds();
    _partiallyPaidTodayIds = _borrowers
        .where((b) {
          final id = b.id;
          if (id == null || b.loanCount == 0) return false;
          final paidCount = _paidLoanCountsToday[id] ?? 0;
          final todayLoanCount = _todayLoanCounts[id] ?? b.loanCount;
          return todayLoanCount > 1 &&
              paidCount > 0 &&
              paidCount < todayLoanCount;
        })
        .map((b) => b.id!)
        .toSet();

    // Load expenses and invested amount
    final expensesList = await _db.getAllExpenses();
    _expenses = expensesList.map((e) => Expense.fromMap(e)).toList();
    _totalExpenses = await _db.getTotalExpenses();
    _totalInvested = await _db.getTotalInvested();

    _isLoading = false;
    notifyListeners();
  }



  Future<String> generateBorrowerCode() async {
    return await _db.generateBorrowerCode();
  }

  Future<Borrower?> getBorrowerByPhone(String phone) async {
    return await _db.getBorrowerByPhone(phone);
  }

  Future<List<Borrower>> searchBorrowers(String query) async {
    return await _db.searchBorrowers(query);
  }

  Future<void> addBorrower(Borrower borrower, Loan? initialLoan) async {
    final borrowerId = await _db.insertBorrower(borrower);
    if (initialLoan != null) {
      initialLoan.borrowerId = borrowerId;
      await _db.insertLoan(initialLoan);
    }
    await loadBorrowers();
  }

  Future<void> updateBorrower(Borrower borrower) async {
    await _db.updateBorrower(borrower);
    await loadBorrowers();
  }

  Future<void> deleteBorrower(int id) async {
    await _db.deleteBorrower(id);
    await loadBorrowers(); // summary refreshed here too
  }

  // ── Loans ──────────────────────────────────────────────────

  Future<List<Loan>> getLoans(int borrowerId) async {
    return await _db.getLoansForBorrower(borrowerId);
  }

  Future<void> addLoan(Loan loan) async {
    await _db.insertLoan(loan);
    await loadBorrowers();
  }

  Future<void> updateLoan(Loan loan) async {
    await _db.updateLoan(loan);
    await loadBorrowers();
  }

  Future<void> deleteLoan(int id) async {
    await _db.deleteLoan(id);
    await loadBorrowers();
  }

  // ── Payments ───────────────────────────────────────────────

  Future<List<Payment>> getPayments(int loanId) async {
    return await _db.getPaymentsForLoan(loanId);
  }

  Future<double> getTotalPaid(int loanId) async {
    return await _db.getTotalPaidByLoan(loanId);
  }

  Future<Set<int>> getLoanIdsPaidToday(int borrowerId) async {
    return await _db.getLoanIdsPaidTodayForBorrower(borrowerId);
  }

  Future<void> addPayment(Payment payment) async {
    await _db.insertPayment(payment);

    // Auto-clear loan if fully paid
    final loan = await _db.getLoanById(payment.loanId);
    if (loan != null) {
      final totalPaid = await _db.getTotalPaidByLoan(loan.id!);
      if (totalPaid >= loan.totalDue() && loan.status != 'cleared') {
        loan.status = 'cleared';
        await _db.updateLoan(loan);
      }
    }

    await loadBorrowers(); // summary updated here too
  }

  Future<void> deletePayment(int paymentId, int loanId) async {
    await _db.deletePayment(paymentId);

    // Reactivate loan if now underpaid
    final loan = await _db.getLoanById(loanId);
    if (loan != null && loan.status == 'cleared') {
      final totalPaid = await _db.getTotalPaidByLoan(loan.id!);
      if (totalPaid < loan.totalDue()) {
        loan.status = 'active';
        await _db.updateLoan(loan);
      }
    }

    await loadBorrowers(); // summary updated here too
  }

  /// Kept for backward compatibility — now just returns cached state.
  Future<Map<String, dynamic>> getGlobalSummary() async {
    return _globalSummary;
  }

  /// Add a new expense and refresh summary
  Future<void> addExpense(Expense expense) async {
    await _db.insertExpense(expense.toMap());
    await loadBorrowers(); // This will reload expenses and recalculate on-hand
  }

  /// Delete an expense and refresh summary
  Future<void> deleteExpense(int expenseId) async {
    await _db.deleteExpense(expenseId);
    await loadBorrowers(); // This will reload expenses and recalculate on-hand
  }
}
