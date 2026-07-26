import 'package:flutter/foundation.dart';
import '../database/db_helper.dart';
import '../models/borrower.dart';
import '../models/loan.dart';
import '../models/payment.dart';
import '../models/expense.dart';
import '../models/service_cost.dart';
import '../services/auto_backup_manager.dart';

class LoanProvider extends ChangeNotifier {
  final DBHelper _db = DBHelper();

  LoanProvider() {
    // Sync is manual-only or disabled. Loading all borrowers on startup.
    loadBorrowers();
  }

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

  /// Investments list
  List<Map<String, dynamic>> _investments = [];
  List<Map<String, dynamic>> get investments => _investments;

  /// Total invested (for on-hand calculation)
  double _totalInvested = 0.0;
  double get totalInvested => _totalInvested;

  /// Total expenses
  double _totalExpenses = 0.0;
  double get totalExpenses => _totalExpenses;

  /// Month expenses
  double _monthExpenses = 0.0;
  double get monthExpenses => _monthExpenses;

  double _todayCollection = 0.0;
  double get todayCollection => _todayCollection;

  int _todayCompletedLoansCount = 0;
  int get todayCompletedLoansCount => _todayCompletedLoansCount;

  int get todayNewBorrowersCount {
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
    final endOfToday = DateTime(now.year, now.month, now.day, 23, 59, 59, 999).millisecondsSinceEpoch;
    return _borrowers.where((b) => b.createdAt >= startOfToday && b.createdAt <= endOfToday).length;
  }

  /// Service costs list
  List<ServiceCost> _serviceCosts = [];
  List<ServiceCost> get serviceCosts => _serviceCosts;

  double _totalServiceCosts = 0.0;
  double get totalServiceCosts => _totalServiceCosts;

  double _todayServiceCosts = 0.0;
  double get todayServiceCosts => _todayServiceCosts;

  double _monthServiceCosts = 0.0;
  double get monthServiceCosts => _monthServiceCosts;

  /// On-hand calculation: Invested - Total Loaned + Total Collected - Total Expenses + Total Service Costs
  double get onHand {
    final totalLoaned = (_globalSummary['totalLoaned'] ?? 0.0) as double;
    final totalCollected = (_globalSummary['totalCollected'] ?? 0.0) as double;
    return _totalInvested - totalLoaned + totalCollected - _totalExpenses + _totalServiceCosts;
  }

  /// Loads borrowers AND refreshes global summary in one call.
  /// Called after every mutation so UI is always consistent.
  // Getters for the new tabs
  List<Borrower> get collectBorrowers => _borrowers.where((b) => !b.isDummy && !b.isClosed && b.totalBalance > 0 && !_paidTodayIds.contains(b.id)).toList();
  List<Borrower> get paidBorrowers => _borrowers.where((b) => !b.isDummy && !b.isClosed && b.totalBalance > 0 && _paidTodayIds.contains(b.id)).toList();
  List<Borrower> get closedBorrowers => _borrowers.where((b) => !b.isDummy && (b.isClosed || b.totalBalance <= 0)).toList();
  List<Borrower> get dummyBorrowers => _borrowers.where((b) => b.isDummy).toList();

  Future<void> loadBorrowers({bool refresh = true}) async {
    if (refresh) {
      _borrowers = [];
    }
    
    _isLoading = true;
    notifyListeners();

    try {
      // Fix existing soft-deleted borrowers that are holding onto unique borrower codes
      final db = await _db.database;
      await db.rawUpdate('''
        UPDATE borrowers 
        SET borrower_code = borrower_code || '_del_' || updated_at
        WHERE is_deleted = 1 AND borrower_code NOT LIKE '%_del_%'
      ''');

      final newBorrowers = await _db.getAllBorrowers(includeDummy: true);
      _borrowers = newBorrowers;
      
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
      // _completedIds is no longer used for tabs, as Closed relies on isClosed.
      // Keeping it for legacy logic if needed, but it's empty now to prevent conflicts.
      _completedIds = {};
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

      // Load expenses, invested amount, and service costs
      final expensesList = await _db.getAllExpenses();
      _expenses = expensesList.map((e) => Expense.fromMap(e)).toList();
      _totalExpenses = await _db.getTotalExpenses();
      _totalInvested = await _db.getTotalInvested();
      _investments = await _db.getAllInvestments();
      _todayCollection = await _db.getTodayCollection();
      _todayCompletedLoansCount = await _db.getTodayCompletedLoansCount();

      final serviceCostsList = await _db.getAllServiceCosts();
      _serviceCosts = serviceCostsList.map((sc) => ServiceCost.fromMap(sc)).toList();
      _totalServiceCosts = await _db.getTotalServiceCosts();

      // Calculate today and month service costs
      final now = DateTime.now();
      final startOfToday = DateTime(now.year, now.month, now.day);
      final startOfMonth = DateTime(now.year, now.month, 1);
      
      _todayServiceCosts = _serviceCosts
          .where((sc) => !sc.dateCreated.isBefore(startOfToday))
          .fold<double>(0.0, (sum, sc) => sum + sc.amount);
          
      _monthServiceCosts = _serviceCosts
          .where((sc) => !sc.dateCreated.isBefore(startOfMonth))
          .fold<double>(0.0, (sum, sc) => sum + sc.amount);

      _monthExpenses = _expenses
          .where((e) => !e.expenseDate.isBefore(startOfMonth))
          .fold<double>(0.0, (sum, e) => sum + e.amount);
    } catch (e) {
      debugPrint('LoanProvider: Error in loadBorrowers: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
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
    AutoBackupManager().triggerBackupPending();
    await loadBorrowers();
  }

  Future<void> updateBorrower(Borrower borrower) async {
    await _db.updateBorrower(borrower);
    AutoBackupManager().triggerBackupPending();
    await loadBorrowers();
  }

  Future<void> deleteBorrower(int id) async {
    await _db.deleteBorrower(id);
    AutoBackupManager().triggerBackupPending();
    await loadBorrowers();
  }

  Future<void> moveToDummy(int id) async {
    await _db.moveToDummyBorrower(id);
    AutoBackupManager().triggerBackupPending();
    await loadBorrowers();
  }

  Future<void> moveToActive(int id) async {
    await _db.moveToActiveBorrower(id);
    AutoBackupManager().triggerBackupPending();
    await loadBorrowers();
  }

  // ── Loans ──────────────────────────────────────────────────

  Future<List<Loan>> getLoans(int borrowerId) async {
    return await _db.getLoansForBorrower(borrowerId);
  }

  Future<void> addLoan(Loan loan) async {
    await _db.insertLoan(loan);
    AutoBackupManager().triggerBackupPending();
    await loadBorrowers();
  }

  Future<void> updateLoan(Loan loan) async {
    await _db.updateLoan(loan);
    AutoBackupManager().triggerBackupPending();
    await loadBorrowers();
  }

  Future<void> deleteLoan(int id) async {
    await _db.deleteLoan(id);
    AutoBackupManager().triggerBackupPending();
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
    await _db.executePaymentTransaction(payment);
    AutoBackupManager().triggerBackupPending();
    await loadBorrowers();
  }

  Future<void> deletePayment(int paymentId, int loanId) async {
    await _db.executeDeletePaymentTransaction(paymentId, loanId);
    AutoBackupManager().triggerBackupPending();
    await loadBorrowers();
  }

  Future<Map<String, dynamic>> getGlobalSummary() async {
    return _globalSummary;
  }

  /// Add a new expense and refresh summary
  Future<void> addExpense(Expense expense) async {
    await _db.insertExpense(expense.toMap());
    AutoBackupManager().triggerBackupPending();
    await loadBorrowers();
  }

  /// Delete an expense and refresh summary
  Future<void> deleteExpense(int expenseId) async {
    await _db.deleteExpense(expenseId);
    AutoBackupManager().triggerBackupPending();
    await loadBorrowers();
  }

  /// Swipe to Pay: Distributes a manual amount among all active loans.
  Future<void> quickPayFlexible(int borrowerId, double totalAmount) async {
    await _db.executeQuickPayFlexibleTransaction(borrowerId, totalAmount);
    AutoBackupManager().triggerBackupPending();
    await loadBorrowers();
  }

  // ── Investments ─────────────────────────────────────────────

  /// Add a new investment and refresh summary
  Future<void> addInvestment(double amount, DateTime date, String? notes) async {
    await _db.insertInvestment({
      'amount': amount,
      'inv_date': date.toIso8601String(),
      'notes': notes,
    });
    AutoBackupManager().triggerBackupPending();
    await loadBorrowers();
  }

  /// Delete an investment and refresh summary
  Future<void> deleteInvestment(int id) async {
    await _db.deleteInvestment(id);
    AutoBackupManager().triggerBackupPending();
    await loadBorrowers();
  }

  // ── Service Costs ───────────────────────────────────────────

  /// Add a new service cost and refresh summary
  Future<void> addServiceCost(double amount, String? description, DateTime date, String? createdBy) async {
    final serviceCost = ServiceCost(
      amount: amount,
      description: description,
      dateCreated: date,
      createdBy: createdBy,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
    await _db.insertServiceCost(serviceCost.toMap());
    AutoBackupManager().triggerBackupPending();
    await loadBorrowers();
  }

  /// Delete a service cost and refresh summary
  Future<void> deleteServiceCost(int id) async {
    await _db.deleteServiceCost(id);
    AutoBackupManager().triggerBackupPending();
    await loadBorrowers();
  }
}

