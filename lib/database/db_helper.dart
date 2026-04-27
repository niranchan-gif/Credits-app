import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/borrower.dart';
import '../models/loan.dart';
import '../models/payment.dart';

class DBHelper {
  static final DBHelper _instance = DBHelper._internal();
  factory DBHelper() => _instance;
  DBHelper._internal();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }

  Future<Database> _initDB() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'loan_manager.db');
    return await openDatabase(
      path,
      version: 5,
      onCreate: _createTables,
      onUpgrade: _upgradeTables,
      // REQUIRED: SQLite disables foreign keys by default.
      // Without this, ON DELETE CASCADE never runs.
      onOpen: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
  }

  Future<void> _createTables(Database db, int version) async {
    await db.execute('''
      CREATE TABLE borrowers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        borrower_code TEXT NOT NULL UNIQUE,
        name TEXT NOT NULL,
        phone TEXT NOT NULL,
        address TEXT,
        notes TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE loans (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        borrower_id INTEGER NOT NULL,
        loan_amount REAL NOT NULL,
        interest_amount REAL NOT NULL,
        loan_date TEXT NOT NULL,
        installment_days INTEGER,
        end_date TEXT,
        status TEXT NOT NULL,
        notes TEXT,
        FOREIGN KEY (borrower_id) REFERENCES borrowers(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE payments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        loan_id INTEGER NOT NULL,
        amount REAL NOT NULL,
        payment_date TEXT NOT NULL,
        notes TEXT,
        FOREIGN KEY (loan_id) REFERENCES loans(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE investments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        amount REAL NOT NULL,
        inv_date TEXT NOT NULL,
        notes TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE expenses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        amount REAL NOT NULL,
        expense_date TEXT NOT NULL,
        category TEXT NOT NULL,
        notes TEXT
      )
    ''');
  }

  Future<void> _upgradeTables(
      Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('DROP TABLE IF EXISTS payments');
      await db.execute('DROP TABLE IF EXISTS borrowers');
      await db.execute('DROP TABLE IF EXISTS loans');
      await _createTables(db, newVersion);
      return; // Since _createTables creates the latest schema, we can return here
    }
    
    if (oldVersion < 3) {
      // Add investments table
      await db.execute('''
        CREATE TABLE IF NOT EXISTS investments (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          amount REAL NOT NULL,
          inv_date TEXT NOT NULL,
          notes TEXT
        )
      ''');
    }
    
    if (oldVersion < 4) {
      // Add expenses table
      await db.execute('''
        CREATE TABLE IF NOT EXISTS expenses (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          amount REAL NOT NULL,
          expense_date TEXT NOT NULL,
          category TEXT NOT NULL,
          notes TEXT
        )
      ''');
    }

    if (oldVersion < 5) {
      // Add installment fields
      await db.execute('ALTER TABLE loans ADD COLUMN installment_days INTEGER');
      await db.execute('ALTER TABLE loans ADD COLUMN end_date TEXT');
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Borrower Operations
  // ─────────────────────────────────────────────────────────────

  Future<String> generateBorrowerCode() async {
    final db = await database;
    final result = await db.rawQuery(
        'SELECT borrower_code FROM borrowers ORDER BY id DESC LIMIT 1');
    if (result.isEmpty) return '1';
    final last = result.first['borrower_code'] as String;
    final nextNum = (int.tryParse(last) ?? 0) + 1;
    return nextNum.toString();
  }

  Future<int> insertBorrower(Borrower borrower) async {
    final db = await database;
    final code = borrower.borrowerCode.isEmpty
        ? await generateBorrowerCode()
        : borrower.borrowerCode;
    final map = borrower.toMap()
      ..remove('id')
      ..['borrower_code'] = code;
    return await db.insert('borrowers', map);
  }

  Future<List<Borrower>> getAllBorrowers() async {
    final db = await database;
    // Only count ACTIVE loans in balance/loan_count so cleared loans don't inflate numbers
    final maps = await db.rawQuery('''
      SELECT
        b.*,
        COALESCE(SUM(CASE WHEN l.status = 'active' THEN l.loan_amount + l.interest_amount ELSE 0 END), 0.0)
          - COALESCE(
              (SELECT SUM(p.amount) FROM payments p
               JOIN loans l2 ON p.loan_id = l2.id
               WHERE l2.borrower_id = b.id AND l2.status = 'active'),
            0.0) AS computed_balance,
        SUM(CASE WHEN l.status = 'active' THEN 1 ELSE 0 END) AS loan_count
      FROM borrowers b
      LEFT JOIN loans l ON l.borrower_id = b.id
      GROUP BY b.id
      ORDER BY b.name ASC
    ''');
    return maps.map((m) {
      final borrower = Borrower.fromMap(m);
      borrower.totalBalance =
          (m['computed_balance'] as num?)?.toDouble() ?? 0.0;
      borrower.loanCount = (m['loan_count'] as int?) ?? 0;
      return borrower;
    }).toList();
  }

  Future<Borrower?> getBorrowerById(int id) async {
    final db = await database;
    final maps = await db.query('borrowers', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return Borrower.fromMap(maps.first);
  }

  Future<Borrower?> getBorrowerByPhone(String phone) async {
    final db = await database;
    final maps =
        await db.query('borrowers', where: 'phone = ?', whereArgs: [phone]);
    if (maps.isEmpty) return null;
    return Borrower.fromMap(maps.first);
  }

  Future<List<Borrower>> searchBorrowers(String query) async {
    final db = await database;
    final maps = await db.query(
      'borrowers',
      where: 'name LIKE ? OR phone LIKE ? OR borrower_code LIKE ?',
      whereArgs: ['%$query%', '%$query%', '%$query%'],
      orderBy: 'name ASC',
    );
    return maps.map((m) => Borrower.fromMap(m)).toList();
  }

  Future<int> updateBorrower(Borrower borrower) async {
    final db = await database;
    return await db.update(
      'borrowers',
      borrower.toMap(),
      where: 'id = ?',
      whereArgs: [borrower.id],
    );
  }

  Future<void> deleteBorrower(int id) async {
    final db = await database;
    // Explicitly delete in order: payments → loans → borrower
    // This works even if PRAGMA foreign_keys was not yet active on older installs
    final loans = await db.query('loans',
        columns: ['id'], where: 'borrower_id = ?', whereArgs: [id]);
    for (final loan in loans) {
      await db
          .delete('payments', where: 'loan_id = ?', whereArgs: [loan['id']]);
    }
    await db.delete('loans', where: 'borrower_id = ?', whereArgs: [id]);
    await db.delete('borrowers', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> clearAllUserData() async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('payments');
      await txn.delete('loans');
      await txn.delete('borrowers');
    });
  }

  Future<void> replaceAllUserData({
    required List<Map<String, dynamic>> borrowers,
    required List<Map<String, dynamic>> loans,
    required List<Map<String, dynamic>> payments,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('payments');
      await txn.delete('loans');
      await txn.delete('borrowers');

      for (final borrower in borrowers) {
        await txn.insert('borrowers', borrower,
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final loan in loans) {
        await txn.insert('loans', loan,
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final payment in payments) {
        await txn.insert('payments', payment,
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<Map<String, dynamic>?> getBorrowerGraph(int borrowerId) async {
    final borrower = await getBorrowerById(borrowerId);
    if (borrower == null) return null;

    final loans = await getLoansForBorrower(borrowerId);
    final loanMaps = <Map<String, dynamic>>[];
    final paymentMaps = <Map<String, dynamic>>[];
    var totalDue = 0.0;
    var totalPaid = 0.0;
    DateTime? dueDate;

    for (final loan in loans) {
      loanMaps.add(loan.toMap());
      totalDue += loan.totalDue();
      dueDate ??= loan.loanDate;
      if (loan.loanDate.isBefore(dueDate)) dueDate = loan.loanDate;

      final payments = await getPaymentsForLoan(loan.id!);
      for (final payment in payments) {
        paymentMaps.add(payment.toMap());
        totalPaid += payment.amount;
      }
    }

    return {
      'borrower': borrower.toMap(),
      'loans': loanMaps,
      'payments': paymentMaps,
      'amount': totalDue,
      'paid': totalPaid,
      'remaining': (totalDue - totalPaid).clamp(0.0, double.infinity),
      'dueDate': dueDate?.toIso8601String(),
    };
  }

  Future<List<Map<String, dynamic>>> getAllBorrowerGraphs() async {
    final borrowers = await getAllBorrowers();
    final graphs = <Map<String, dynamic>>[];
    for (final borrower in borrowers) {
      final id = borrower.id;
      if (id == null) continue;
      final graph = await getBorrowerGraph(id);
      if (graph != null) graphs.add(graph);
    }
    return graphs;
  }

  // ─────────────────────────────────────────────────────────────
  // Loan Operations
  // ─────────────────────────────────────────────────────────────

  Future<int> insertLoan(Loan loan) async {
    final db = await database;
    final map = loan.toMap()..remove('id');
    return await db.insert('loans', map);
  }

  Future<List<Loan>> getLoansForBorrower(int borrowerId) async {
    final db = await database;
    final maps = await db.query(
      'loans',
      where: 'borrower_id = ?',
      whereArgs: [borrowerId],
      orderBy: 'loan_date DESC',
    );
    return maps.map((m) => Loan.fromMap(m)).toList();
  }

  Future<Loan?> getLoanById(int loanId) async {
    final db = await database;
    final maps = await db.query('loans', where: 'id = ?', whereArgs: [loanId]);
    if (maps.isEmpty) return null;
    return Loan.fromMap(maps.first);
  }

  Future<int> updateLoan(Loan loan) async {
    final db = await database;
    return await db.update(
      'loans',
      loan.toMap(),
      where: 'id = ?',
      whereArgs: [loan.id],
    );
  }

  Future<void> deleteLoan(int id) async {
    final db = await database;
    await db.delete('loans', where: 'id = ?', whereArgs: [id]);
  }

  // ─────────────────────────────────────────────────────────────
  // Payment Operations
  // ─────────────────────────────────────────────────────────────

  Future<int> insertPayment(Payment payment) async {
    final db = await database;
    final map = payment.toMap()..remove('id');
    return await db.insert('payments', map);
  }

  Future<List<Payment>> getPaymentsForLoan(int loanId) async {
    final db = await database;
    final maps = await db.query(
      'payments',
      where: 'loan_id = ?',
      whereArgs: [loanId],
      orderBy: 'payment_date DESC',
    );
    return maps.map((m) => Payment.fromMap(m)).toList();
  }

  Future<double> getTotalPaidByLoan(int loanId) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT SUM(amount) as total FROM payments WHERE loan_id = ?',
      [loanId],
    );
    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  Future<void> deletePayment(int id) async {
    final db = await database;
    await db.delete('payments', where: 'id = ?', whereArgs: [id]);
  }

  // ─────────────────────────────────────────────────────────────
  // Reports
  // ─────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getGlobalSummary() async {
    final db = await database;

    // Active-only: for "To Recover" / "Pending" display figures
    final activeLoanRes = await db.rawQuery(
        "SELECT SUM(loan_amount) as principal, SUM(interest_amount) as interest FROM loans WHERE status = 'active'");
    final activePaidRes = await db.rawQuery(
        "SELECT SUM(p.amount) as total FROM payments p JOIN loans l ON p.loan_id = l.id WHERE l.status = 'active'");

    // ALL loans (active + cleared): for On Hand calculation
    // On Hand = Invested − totalPrincipalEver + totalCollectedEver
    final allLoanRes =
        await db.rawQuery("SELECT SUM(loan_amount) as principal FROM loans");
    final allPaidRes =
        await db.rawQuery("SELECT SUM(amount) as total FROM payments");

    final countRes = await db.rawQuery('SELECT COUNT(*) as cnt FROM borrowers');

    // Active-loan figures (for display in To Recover / Pending / Collected cards)
    final activePrincipal =
        (activeLoanRes.first['principal'] as num?)?.toDouble() ?? 0.0;
    final activeInterest =
        (activeLoanRes.first['interest'] as num?)?.toDouble() ?? 0.0;
    final activeCollected =
        (activePaidRes.first['total'] as num?)?.toDouble() ?? 0.0;
    final activeDue = activePrincipal + activeInterest;

    // All-time figures (for On Hand = Invested − lent + returned)
    final totalLoanedEver =
        (allLoanRes.first['principal'] as num?)?.toDouble() ?? 0.0;
    final totalCollectedEver =
        (allPaidRes.first['total'] as num?)?.toDouble() ?? 0.0;

    return {
      'totalLoaned': totalLoanedEver, // used in On Hand formula
      'totalCollected': totalCollectedEver, // used in On Hand formula
      'activeLoaned': activePrincipal,
      'totalInterest': activeInterest,
      'totalDue': activeDue,
      'activePending': activeDue - activeCollected,
      'totalPending': activeDue - activeCollected,
      'totalBorrowers': (countRes.first['cnt'] as int?) ?? 0,
    };
  }

  // ─────────────────────────────────────────────────────────────
  // Investment Operations
  // ─────────────────────────────────────────────────────────────

  Future<int> insertInvestment(Map<String, dynamic> data) async {
    final db = await database;
    return await db.insert('investments', data);
  }

  Future<List<Map<String, dynamic>>> getAllInvestments() async {
    final db = await database;
    return await db.query('investments', orderBy: 'inv_date DESC');
  }

  Future<void> deleteInvestment(int id) async {
    final db = await database;
    await db.delete('investments', where: 'id = ?', whereArgs: [id]);
  }

  Future<double> getTotalInvested() async {
    final db = await database;
    final result =
        await db.rawQuery('SELECT SUM(amount) as total FROM investments');
    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  // ───────────────────────────────────────────────────────────────
  // Home Screen Tab Helpers
  // ───────────────────────────────────────────────────────────────

  /// Borrower IDs where every active loan has a payment recorded TODAY.
  /// Uses SQLite date() which strips the time component, so this resets
  /// automatically at midnight with no extra logic needed.
  Future<Set<int>> getBorrowersPaidToday() async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT b.id
      FROM borrowers b
      WHERE
        EXISTS (
          SELECT 1
          FROM loans active_l
          WHERE active_l.borrower_id = b.id
            AND active_l.status = 'active'
        )
        AND NOT EXISTS (
          SELECT 1
          FROM loans unpaid_l
          WHERE unpaid_l.borrower_id = b.id
            AND unpaid_l.status = 'active'
            AND NOT EXISTS (
              SELECT 1
              FROM payments p
              WHERE p.loan_id = unpaid_l.id
                AND date(p.payment_date) = date('now', 'localtime')
            )
        )
    ''');
    return result.map((r) => r['id'] as int).toSet();
  }

  /// Loan count per borrower that has at least one payment today.
  Future<Map<int, int>> getPaidLoanCountsToday() async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT l.borrower_id, COUNT(DISTINCT l.id) AS paid_count
      FROM loans l
      JOIN payments p ON p.loan_id = l.id
      WHERE date(p.payment_date) = date('now', 'localtime')
      GROUP BY l.borrower_id
    ''');
    return {
      for (final row in result)
        row['borrower_id'] as int: (row['paid_count'] as num).toInt()
    };
  }

  /// Cleared loan count per borrower that has at least one payment today.
  Future<Map<int, int>> getClearedPaidLoanCountsToday() async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT l.borrower_id, COUNT(DISTINCT l.id) AS paid_count
      FROM loans l
      JOIN payments p ON p.loan_id = l.id
      WHERE l.status != 'active'
        AND date(p.payment_date) = date('now', 'localtime')
      GROUP BY l.borrower_id
    ''');
    return {
      for (final row in result)
        row['borrower_id'] as int: (row['paid_count'] as num).toInt()
    };
  }

  /// Loan IDs for one borrower that have a payment today.
  Future<Set<int>> getLoanIdsPaidTodayForBorrower(int borrowerId) async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT DISTINCT l.id
      FROM loans l
      JOIN payments p ON p.loan_id = l.id
      WHERE l.borrower_id = ?
        AND date(p.payment_date) = date('now', 'localtime')
    ''', [borrowerId]);
    return result.map((r) => r['id'] as int).toSet();
  }

  /// Borrower IDs where every loan is cleared (and they have at least one loan).
  Future<Set<int>> getCompletedBorrowerIds() async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT b.id
      FROM borrowers b
      WHERE
        (SELECT COUNT(*) FROM loans l WHERE l.borrower_id = b.id) > 0
        AND
        (SELECT COUNT(*) FROM loans l WHERE l.borrower_id = b.id AND l.status = 'active') = 0
    ''');
    return result.map((r) => r['id'] as int).toSet();
  }

  // ─────────────────────────────────────────────────────────────
  // Expense Operations
  // ─────────────────────────────────────────────────────────────

  Future<int> insertExpense(Map<String, dynamic> data) async {
    final db = await database;
    return await db.insert('expenses', data);
  }

  Future<List<Map<String, dynamic>>> getAllExpenses() async {
    final db = await database;
    return await db.query('expenses', orderBy: 'expense_date DESC');
  }

  Future<void> deleteExpense(int id) async {
    final db = await database;
    await db.delete('expenses', where: 'id = ?', whereArgs: [id]);
  }

  Future<double> getTotalExpenses() async {
    final db = await database;
    final result =
        await db.rawQuery('SELECT SUM(amount) as total FROM expenses');
    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }
}
