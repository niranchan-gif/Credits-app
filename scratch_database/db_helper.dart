import 'package:uuid/uuid.dart';
import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../utils/profile_prefs.dart';
import '../models/borrower.dart';
import '../models/loan.dart';
import '../models/payment.dart';
import '../utils/date_parser.dart';
import '../services/backup_freshness_service.dart';

class DBHelper {
  static final DBHelper _instance = DBHelper._internal();
  factory DBHelper() => _instance;
  DBHelper._internal();

  static Database? _database;
  static bool isRestoring = false;
  static String? _currentGoogleUserId;
  static String? _currentDbPath;
  String? get currentDbPath => _currentDbPath;

  static Future<void> openForUser(String googleUserId) async {
    if (_currentGoogleUserId == googleUserId && _database != null && _database!.isOpen) {
      return; // Already open for this user
    }
    await _instance.closeDatabase();
    _currentGoogleUserId = googleUserId;
    _database = await _instance._initDB();
  }

  /// Clears the current user ID and DB path without closing the connection.
  /// Call closeDatabase() first, then reset().
  static void reset() {
    _currentGoogleUserId = null;
    _currentDbPath = null;
  }

  Future<void> _onMutation() async {
    if (BackupFreshnessService.isReadOnlyMode.value) {
      throw Exception('Database modification blocked: Application is in Read Only Mode.');
    }
    final prefs = await ProfilePrefs.getInstance();
    final nowStr = DateTime.now().toUtc().toIso8601String();
    await prefs.setString('local_db_last_modified_timestamp', nowStr);
    debugPrint('local_db_last_modified_timestamp updated to: $nowStr');
  }

  Future<Database> get database async {
    if (_currentGoogleUserId == null) {
      throw Exception('Database requested before openForUser was called with a valid user ID.');
    }
    while (isRestoring) {
      debugPrint('DBHelper: Database is currently restoring. Awaiting restoration completion...');
      await Future.delayed(const Duration(milliseconds: 100));
    }
    if (_database != null && _database!.isOpen) {
      return _database!;
    }
    debugPrint('DBHelper: Database is either null or closed. Reinitializing database automatically...');
    _database = await _initDB();
    return _database!;
  }

  Future<void> closeDatabase() async {
    if (_database != null) {
      debugPrint('DBHelper: Closing database connection safely...');
      if (_database!.isOpen) {
        await _database!.close();
      }
      _database = null;
      debugPrint('DBHelper: Database connection successfully closed.');
    }
  }

  Future<Database> _initDB() async {
    if (_currentGoogleUserId == null) {
      throw Exception('Cannot initialize DB without a user ID.');
    }
    final docsDir = await getApplicationDocumentsDirectory();
    final dbDir = Directory(join(docsDir.path, 'databases'));
    if (!await dbDir.exists()) {
      await dbDir.create(recursive: true);
    }
    
    // For legacy migration check (from the old sqflite path)
    final oldDbPath = await getDatabasesPath();
    final legacyProfilePath = join(oldDbPath, 'db_google_$_currentGoogleUserId.db');
    final legacyPath = join(oldDbPath, 'loan_manager.db');
    
    final newFileName = 'db_google_$_currentGoogleUserId.db';
    final path = join(dbDir.path, newFileName);
    _currentDbPath = path;

    final newFile = File(path);
    final legacyProfileFile = File(legacyProfilePath);
    
    // Auto-migration logic: If old DB exists, move it to the new location
    if (await legacyProfileFile.exists()) {
      if (await newFile.exists()) {
        final newFileSize = await newFile.length();
        final legacyFileSize = await legacyProfileFile.length();
        if (legacyFileSize > newFileSize) {
          debugPrint('DBHelper: Migrating legacy profile DB (overwriting empty new DB)');
          await legacyProfileFile.copy(path);
          await legacyProfileFile.delete(); // Prevent future overwrites
        }
      } else {
        debugPrint('DBHelper: Migrating legacy profile DB to new path');
        await legacyProfileFile.rename(path);
      }
    } else {
      final legacyFile = File(legacyPath);
      if (await legacyFile.exists() && !(await newFile.exists())) {
        debugPrint('DBHelper: Migrating legacy loan_manager.db to $newFileName');
        await legacyFile.rename(path);
      }
    }

    debugPrint('Database opening: $path');
    return await openDatabase(
      path,
      version: 14,
      onCreate: _createTables,
      onUpgrade: _upgradeTables,
      onOpen: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
        // Ensure all high-performance indexes exist
        await db.execute('CREATE INDEX IF NOT EXISTS idx_borrowers_code ON borrowers(borrower_code)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_borrowers_phone ON borrowers(phone)');
    await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_borrowers_sync_id ON borrowers(sync_id)');
    await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_loans_sync_id ON loans(sync_id)');
    await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_payments_sync_id ON payments(sync_id)');
    await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_expenses_sync_id ON expenses(sync_id)');
    await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_investments_sync_id ON investments(sync_id)');
    await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_service_costs_sync_id ON service_costs(sync_id)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_loans_borrower ON loans(borrower_id)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_payments_loan ON payments(loan_id)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_payments_date ON payments(payment_date)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_borrowers_created ON borrowers(created_at)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_loans_created ON loans(created_at)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_payments_created ON payments(created_at)');
        
        // Dynamic Schema Validation
        try {
          await _validateDatabaseSchema(db);
        } catch (e) {
          debugPrint('DBHelper Schema Validation CRITICAL Error: $e');
        }

        // Dynamic Data Normalization
        try {
          final prefs = await ProfilePrefs.getInstance();
          if (prefs.getBool('db_normalized_v1') != true) {
            await _normalizeDatabaseData(db);
            await prefs.setBool('db_normalized_v1', true);
          }
        } catch (e) {
          debugPrint('DBHelper Data Normalization CRITICAL Error: $e');
        }
      },
    );
  }

  Future<void> _validateDatabaseSchema(Database db) async {
    final expectedSchema = {
      'borrowers': [
        'id', 'borrower_code', 'name', 'phone', 'address', 'notes',
        'updated_at', 'created_at', 'last_modified_device', 'is_deleted', 'is_dummy'
      ],
      'loans': [
        'id', 'borrower_id', 'loan_amount', 'interest_amount', 'loan_date',
        'installment_days', 'end_date', 'status', 'notes',
        'updated_at', 'created_at', 'last_modified_device', 'is_deleted'
      ],
      'payments': [
        'id', 'loan_id', 'amount', 'payment_date', 'notes',
        'updated_at', 'created_at', 'last_modified_device', 'is_deleted'
      ],
      'investments': [
        'id', 'amount', 'inv_date', 'notes',
        'updated_at', 'created_at', 'last_modified_device', 'is_deleted'
      ],
      'expenses': [
        'id', 'amount', 'expense_date', 'category', 'notes',
        'updated_at', 'created_at', 'last_modified_device', 'is_deleted'
      ],
      'service_costs': [
        'id', 'amount', 'description', 'dateCreated', 'createdBy', 'timestamp', 'is_deleted'
      ],
    };

    for (final entry in expectedSchema.entries) {
      final tableName = entry.key;
      final expectedCols = entry.value;

      final tblExists = Sqflite.firstIntValue(await db.rawQuery(
        "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='$tableName'"
      )) ?? 0;

      if (tblExists == 0) {
        throw Exception("Missing table '$tableName' in the database!");
      }

      final info = await db.rawQuery('PRAGMA table_info($tableName)');
      final existingCols = info.map((row) => row['name'] as String).toSet();

      for (final col in expectedCols) {
        if (!existingCols.contains(col)) {
          throw Exception("Missing column '$col' in table '$tableName'!");
        }
      }
    }

    // Silent check and repair for restore_meta
    try {
      final restoreMetaExists = Sqflite.firstIntValue(await db.rawQuery(
        "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='restore_meta'"
      )) ?? 0;
      if (restoreMetaExists == 0) {
        print('restore_meta missing - repairing');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS restore_meta (
            key TEXT PRIMARY KEY,
            value TEXT
          )
        ''');
      }
    } catch (e) {
      debugPrint('DBHelper: restore_meta validation/repair failed: $e');
    }

    debugPrint('Schema validated');
  }

  Future<void> _normalizeDatabaseData(Database db) async {
    debugPrint('DBHelper: Running database data normalization...');
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    // 1. Borrowers table
    await db.execute('''
      UPDATE borrowers 
      SET 
        created_at = CASE WHEN created_at IS NULL OR created_at = 0 THEN $nowMs ELSE created_at END,
        updated_at = CASE WHEN updated_at IS NULL OR updated_at = 0 THEN $nowMs ELSE updated_at END,
        is_deleted = CASE WHEN is_deleted IS NULL THEN 0 ELSE is_deleted END
    ''');

    // 2. Loans table
    final loans = await db.query('loans');
    for (final row in loans) {
      final id = row['id'];
      final rawLoanDate = row['loan_date'];
      final rawEndDate = row['end_date'];

      String? newLoanDate;
      if (rawLoanDate != null) {
        newLoanDate = DateParser.safeParse(rawLoanDate).toIso8601String().replaceAll('T', ' ');
      }
      String? newEndDate;
      if (rawEndDate != null) {
        newEndDate = DateParser.safeParse(rawEndDate).toIso8601String().replaceAll('T', ' ');
      }

      await db.update(
        'loans',
        {
          if (newLoanDate != null) 'loan_date': newLoanDate,
          'end_date': newEndDate,
          'loan_amount': (row['loan_amount'] as num?)?.toDouble() ?? 0.0,
          'interest_amount': (row['interest_amount'] as num?)?.toDouble() ?? 0.0,
          'created_at': row['created_at'] ?? nowMs,
          'updated_at': row['updated_at'] ?? nowMs,
          'is_deleted': row['is_deleted'] ?? 0,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    }

    // 3. Payments table
    final payments = await db.query('payments');
    for (final row in payments) {
      final id = row['id'];
      final rawPaymentDate = row['payment_date'];

      String? newPaymentDate;
      if (rawPaymentDate != null) {
        newPaymentDate = DateParser.safeParse(rawPaymentDate).toIso8601String().replaceAll('T', ' ');
      }

      await db.update(
        'payments',
        {
          if (newPaymentDate != null) 'payment_date': newPaymentDate,
          'amount': (row['amount'] as num?)?.toDouble() ?? 0.0,
          'created_at': row['created_at'] ?? nowMs,
          'updated_at': row['updated_at'] ?? nowMs,
          'is_deleted': row['is_deleted'] ?? 0,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    }

    // 4. Expenses table
    final expenses = await db.query('expenses');
    for (final row in expenses) {
      final id = row['id'];
      final rawExpenseDate = row['expense_date'];

      String? newExpenseDate;
      if (rawExpenseDate != null) {
        newExpenseDate = DateParser.safeParse(rawExpenseDate).toIso8601String().replaceAll('T', ' ');
      }

      await db.update(
        'expenses',
        {
          if (newExpenseDate != null) 'expense_date': newExpenseDate,
          'amount': (row['amount'] as num?)?.toDouble() ?? 0.0,
          'created_at': row['created_at'] ?? nowMs,
          'updated_at': row['updated_at'] ?? nowMs,
          'is_deleted': row['is_deleted'] ?? 0,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    }

    // 5. Investments table
    final investments = await db.query('investments');
    for (final row in investments) {
      final id = row['id'];
      final rawInvDate = row['inv_date'];

      String? newInvDate;
      if (rawInvDate != null) {
        newInvDate = DateParser.safeParse(rawInvDate).toIso8601String().replaceAll('T', ' ');
      }

      await db.update(
        'investments',
        {
          if (newInvDate != null) 'inv_date': newInvDate,
          'amount': (row['amount'] as num?)?.toDouble() ?? 0.0,
          'created_at': row['created_at'] ?? nowMs,
          'updated_at': row['updated_at'] ?? nowMs,
          'is_deleted': row['is_deleted'] ?? 0,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    }

    debugPrint('DBHelper: Database data normalization complete!');
  }

  Future<void> _createTables(Database db, int version) async {
    debugPrint('DBHelper ▶ Creating tables for version $version...');
    await db.execute('''
      CREATE TABLE borrowers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        borrower_code TEXT NOT NULL UNIQUE,
        name TEXT NOT NULL,
        phone TEXT NOT NULL,
        address TEXT,
        notes TEXT,
        updated_at INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL DEFAULT 0,
        last_modified_device TEXT,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        is_dummy INTEGER NOT NULL DEFAULT 0,
        sync_id TEXT NOT NULL DEFAULT ''
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
        updated_at INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL DEFAULT 0,
        last_modified_device TEXT,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (borrower_id) REFERENCES borrowers(id) ON DELETE CASCADE,
        sync_id TEXT NOT NULL DEFAULT '',
        borrower_sync_id TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE payments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        loan_id INTEGER NOT NULL,
        amount REAL NOT NULL,
        payment_date TEXT NOT NULL,
        notes TEXT,
        updated_at INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL DEFAULT 0,
        last_modified_device TEXT,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (loan_id) REFERENCES loans(id) ON DELETE CASCADE,
        sync_id TEXT NOT NULL DEFAULT '',
        loan_sync_id TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE investments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        amount REAL NOT NULL,
        inv_date TEXT NOT NULL,
        notes TEXT,
        updated_at INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL DEFAULT 0,
        last_modified_device TEXT,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        sync_id TEXT NOT NULL DEFAULT ''
      )
    ''');

    await db.execute('''
      CREATE TABLE expenses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        amount REAL NOT NULL,
        expense_date TEXT NOT NULL,
        category TEXT NOT NULL,
        notes TEXT,
        updated_at INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL DEFAULT 0,
        last_modified_device TEXT,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        sync_id TEXT NOT NULL DEFAULT ''
      )
    ''');

    await db.execute('''
      CREATE TABLE service_costs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        amount REAL NOT NULL,
        description TEXT,
        dateCreated TEXT NOT NULL,
        createdBy TEXT,
        timestamp INTEGER NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        sync_id TEXT NOT NULL DEFAULT ''
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS restore_meta (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');

    // Create Indexes
    await db.execute('CREATE INDEX IF NOT EXISTS idx_borrowers_code ON borrowers(borrower_code)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_borrowers_phone ON borrowers(phone)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_loans_borrower ON loans(borrower_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_payments_loan ON payments(loan_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_payments_date ON payments(payment_date)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_service_costs_date ON service_costs(dateCreated)');

    debugPrint('DBHelper ▶ Tables and indexes created successfully.');
  }

  Future<void> _upgradeTables(
      Database db, int oldVersion, int newVersion) async {
    debugPrint('DBHelper ▶ Migrating database from $oldVersion to $newVersion...');
    
    if (oldVersion < 10) {
      debugPrint('DBHelper ▶ Migrating to version 10 (Remove Firebase Sync columns)');
      
      final tables = ['borrowers', 'loans', 'payments', 'investments', 'expenses'];
      
      for (final table in tables) {
        final tblExists = Sqflite.firstIntValue(await db.rawQuery(
          "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='$table'"
        )) ?? 0;
        
        if (tblExists > 0) {
          await db.execute('ALTER TABLE $table RENAME TO ${table}_old');
        }
      }

      await _createTables(db, newVersion);

      final colMapping = {
        'borrowers': [
          'id', 'borrower_code', 'name', 'phone', 'address', 'notes',
          'updated_at', 'created_at', 'last_modified_device', 'is_deleted'
        ],
        'loans': [
          'id', 'borrower_id', 'loan_amount', 'interest_amount', 'loan_date',
          'installment_days', 'end_date', 'status', 'notes',
          'updated_at', 'created_at', 'last_modified_device', 'is_deleted'
        ],
        'payments': [
          'id', 'loan_id', 'amount', 'payment_date', 'notes',
          'updated_at', 'created_at', 'last_modified_device', 'is_deleted'
        ],
        'investments': [
          'id', 'amount', 'inv_date', 'notes',
          'updated_at', 'created_at', 'last_modified_device', 'is_deleted'
        ],
        'expenses': [
          'id', 'amount', 'expense_date', 'category', 'notes',
          'updated_at', 'created_at', 'last_modified_device', 'is_deleted'
        ],
      };

      for (final table in tables) {
        final tblOldExists = Sqflite.firstIntValue(await db.rawQuery(
          "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='${table}_old'"
        )) ?? 0;
        
        if (tblOldExists > 0) {
          final oldColumns = await db.rawQuery('PRAGMA table_info(${table}_old)');
          final oldColNames = oldColumns.map((row) => row['name'] as String).toSet();
          
          final intersectCols = colMapping[table]!
              .where((c) => oldColNames.contains(c))
              .toList();
          
          if (intersectCols.isNotEmpty) {
            final colsStr = intersectCols.join(', ');
            await db.execute(
              'INSERT INTO $table ($colsStr) SELECT $colsStr FROM ${table}_old'
            );
          }
          
          await db.execute('DROP TABLE IF EXISTS ${table}_old');
        }
      }
    }

    // Migrate to version 11: create service_costs table
    if (oldVersion < 11) {
      debugPrint('DBHelper ▶ Migrating to version 11 (Create service_costs table)');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS service_costs (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          amount REAL NOT NULL,
          description TEXT,
          dateCreated TEXT NOT NULL,
          createdBy TEXT,
          timestamp INTEGER NOT NULL,
          is_deleted INTEGER NOT NULL DEFAULT 0
        )
      ''');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_service_costs_date ON service_costs(dateCreated)');
    }

    // Migrate to version 12: create restore_meta table
    if (oldVersion < 12) {
      debugPrint('DBHelper ▶ Migrating to version 12 (Create restore_meta table)');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS restore_meta (
          key TEXT PRIMARY KEY,
          value TEXT
        )
      ''');
    }

    // Migrate to version 13: add is_dummy to borrowers
    if (oldVersion < 13) {
      debugPrint('DBHelper ▶ Migrating to version 13 (Add is_dummy to borrowers)');
      try {
        await db.execute('ALTER TABLE borrowers ADD COLUMN is_dummy INTEGER NOT NULL DEFAULT 0');
      } catch (e) {
        debugPrint('DBHelper: is_dummy column may already exist: $e');
      }
    }
    if (oldVersion < 14) {
      debugPrint('DBHelper - Migrating to version 14 (Adding sync_id UUID to all tables)');
      final uuid = const Uuid();
      final tables = ['borrowers', 'loans', 'payments', 'investments', 'expenses', 'service_costs'];
      
      for (final table in tables) {
        final tblExists = Sqflite.firstIntValue(await db.rawQuery(
          "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name=''"
        )) ?? 0;
        
        if (tblExists > 0) {
          try {
            await db.execute('ALTER TABLE  ADD COLUMN sync_id TEXT NOT NULL DEFAULT ""');
          } catch (e) {
            debugPrint('Column sync_id already exists in ');
          }
          final rows = await db.query(table, columns: ['id']);
          for (final row in rows) {
            final id = row['id'];
            final generatedId = uuid.v4();
            await db.update(table, {'sync_id': generatedId}, where: 'id = ?', whereArgs: [id]);
          }
          await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx__sync_id ON (sync_id)');
        }
      }
      
      try {
        await db.execute('ALTER TABLE loans ADD COLUMN borrower_sync_id TEXT');
      } catch (e) {}
      try {
        await db.execute('ALTER TABLE payments ADD COLUMN loan_sync_id TEXT');
      } catch (e) {}
      
      debugPrint('DBHelper - Backfilling relational UUIDs...');
      await db.execute("UPDATE loans SET borrower_sync_id = (SELECT sync_id FROM borrowers WHERE id = loans.borrower_id)");
      await db.execute("UPDATE payments SET loan_sync_id = (SELECT sync_id FROM loans WHERE id = payments.loan_id)");
    }


    debugPrint('DBHelper ▶ Migration completed successfully.');
  }

  // ─────────────────────────────────────────────────────────────
  // Borrower Operations
  // ─────────────────────────────────────────────────────────────

  Future<String> generateBorrowerCode() async {
    final db = await database;
    // Include ALL borrowers (active + inactive/dummy) so that the next code
    // is always higher than the highest existing code, preventing duplicates
    // with inactive borrower codes.
    final result = await db.rawQuery(
        'SELECT borrower_code FROM borrowers WHERE COALESCE(is_deleted, 0) = 0');

    if (result.isEmpty) return '1';

    // Find the highest numeric borrower code across active AND inactive borrowers
    int highest = 0;
    for (var row in result) {
      final codeStr = (row['borrower_code'] as String).split('_del_').first;
      final codeInt = int.tryParse(codeStr);
      if (codeInt != null && codeInt > highest) {
        highest = codeInt;
      }
    }

    return (highest + 1).toString();
  }

  Future<int> insertBorrower(Borrower borrower) async {
    await _onMutation();
    final db = await database;
    final code = borrower.borrowerCode.isEmpty
        ? await generateBorrowerCode()
        : borrower.borrowerCode;
    final now = DateTime.now().millisecondsSinceEpoch;
    borrower.updatedAt = now;
    borrower.createdAt = now;
    final map = borrower.toMap()
      ..remove('id')
      ..['borrower_code'] = code;
    return await db.insert('borrowers', map);
  }

  Future<List<Borrower>> getAllBorrowers({bool includeDeleted = false, int? limit, int? offset}) async {
    final db = await database;
    final deletedClause = includeDeleted ? '' : 'AND COALESCE(b.is_deleted, 0) = 0';
    final limitClause = limit != null ? 'LIMIT $limit' : '';
    final offsetClause = offset != null ? 'OFFSET $offset' : '';
    final maps = await db.rawQuery('''
      SELECT
        b.*,
        COALESCE(SUM(CASE WHEN l.status = 'active' AND COALESCE(l.is_deleted, 0) = 0 THEN l.loan_amount + l.interest_amount ELSE 0 END), 0.0)
          - COALESCE(
              (SELECT SUM(p.amount) FROM payments p
               JOIN loans l2 ON p.loan_id = l2.id
               WHERE l2.borrower_id = b.id AND l2.status = 'active' AND COALESCE(p.is_deleted, 0) = 0 AND COALESCE(l2.is_deleted, 0) = 0),
            0.0) AS computed_balance,
        SUM(CASE WHEN l.status = 'active' AND COALESCE(l.is_deleted, 0) = 0 THEN 1 ELSE 0 END) AS loan_count,
        MIN(CASE WHEN l.status = 'active' AND COALESCE(l.is_deleted, 0) = 0 THEN l.loan_date ELSE NULL END) AS oldest_active_loan_date
      FROM borrowers b
      LEFT JOIN loans l ON l.borrower_id = b.id
      WHERE 1=1 $deletedClause
      GROUP BY b.id
      ORDER BY CAST(b.borrower_code AS INTEGER) ASC
      $limitClause $offsetClause
    ''');
    return maps.map((m) {
      final borrower = Borrower.fromMap(m);
      borrower.totalBalance = (m['computed_balance'] as num?)?.toDouble() ?? 0.0;
      borrower.loanCount = (m['loan_count'] as int?) ?? 0;
      
      final oldestDateStr = m['oldest_active_loan_date'] as String?;
      if (oldestDateStr != null && oldestDateStr.isNotEmpty) {
        final oldestDate = DateParser.safeParse(oldestDateStr);
        final loanAge = DateTime.now().difference(oldestDate).inDays;
        borrower.loanAgeDays = loanAge;
        borrower.overdueStatus = loanAge > 140 ? 'OVERDUE' : 'ACTIVE';
      } else {
        borrower.loanAgeDays = 0;
        borrower.overdueStatus = 'ACTIVE';
      }
      return borrower;
    }).toList();
  }

  Future<List<Borrower>> getDummyBorrowers({int? limit, int? offset}) async {
    final db = await database;
    final limitClause = limit != null ? 'LIMIT $limit' : '';
    final offsetClause = offset != null ? 'OFFSET $offset' : '';
    final maps = await db.rawQuery('''
      SELECT
        b.*,
        COALESCE(SUM(CASE WHEN l.status = 'active' AND COALESCE(l.is_deleted, 0) = 0 THEN l.loan_amount + l.interest_amount ELSE 0 END), 0.0)
          - COALESCE(
              (SELECT SUM(p.amount) FROM payments p
               JOIN loans l2 ON p.loan_id = l2.id
               WHERE l2.borrower_id = b.id AND l2.status = 'active' AND COALESCE(p.is_deleted, 0) = 0 AND COALESCE(l2.is_deleted, 0) = 0),
            0.0) AS computed_balance,
        SUM(CASE WHEN l.status = 'active' AND COALESCE(l.is_deleted, 0) = 0 THEN 1 ELSE 0 END) AS loan_count,
        MIN(CASE WHEN l.status = 'active' AND COALESCE(l.is_deleted, 0) = 0 THEN l.loan_date ELSE NULL END) AS oldest_active_loan_date
      FROM borrowers b
      LEFT JOIN loans l ON l.borrower_id = b.id
      WHERE COALESCE(b.is_deleted, 0) = 0 AND COALESCE(b.is_dummy, 0) = 1
      GROUP BY b.id
      ORDER BY CAST(b.borrower_code AS INTEGER) ASC
      $limitClause $offsetClause
    ''');
    return maps.map((m) {
      final borrower = Borrower.fromMap(m);
      borrower.totalBalance = (m['computed_balance'] as num?)?.toDouble() ?? 0.0;
      borrower.loanCount = (m['loan_count'] as int?) ?? 0;
      
      final oldestDateStr = m['oldest_active_loan_date'] as String?;
      if (oldestDateStr != null && oldestDateStr.isNotEmpty) {
        final oldestDate = DateParser.safeParse(oldestDateStr);
        final loanAge = DateTime.now().difference(oldestDate).inDays;
        borrower.loanAgeDays = loanAge;
        borrower.overdueStatus = loanAge > 140 ? 'OVERDUE' : 'ACTIVE';
      } else {
        borrower.loanAgeDays = 0;
        borrower.overdueStatus = 'ACTIVE';
      }
      return borrower;
    }).toList();
  }

  Future<List<Borrower>> getActiveBorrowers({int? limit, int? offset}) async {
    final db = await database;
    final limitClause = limit != null ? 'LIMIT $limit' : '';
    final offsetClause = offset != null ? 'OFFSET $offset' : '';
    final maps = await db.rawQuery('''
      SELECT
        b.*,
        COALESCE(SUM(CASE WHEN l.status = 'active' AND COALESCE(l.is_deleted, 0) = 0 THEN l.loan_amount + l.interest_amount ELSE 0 END), 0.0)
          - COALESCE(
              (SELECT SUM(p.amount) FROM payments p
               JOIN loans l2 ON p.loan_id = l2.id
               WHERE l2.borrower_id = b.id AND l2.status = 'active' AND COALESCE(p.is_deleted, 0) = 0 AND COALESCE(l2.is_deleted, 0) = 0),
            0.0) AS computed_balance,
        SUM(CASE WHEN l.status = 'active' AND COALESCE(l.is_deleted, 0) = 0 THEN 1 ELSE 0 END) AS loan_count,
        MIN(CASE WHEN l.status = 'active' AND COALESCE(l.is_deleted, 0) = 0 THEN l.loan_date ELSE NULL END) AS oldest_active_loan_date
      FROM borrowers b
      LEFT JOIN loans l ON l.borrower_id = b.id
      WHERE COALESCE(b.is_deleted, 0) = 0 AND COALESCE(b.is_dummy, 0) = 0
      GROUP BY b.id
      ORDER BY CAST(b.borrower_code AS INTEGER) ASC
      $limitClause $offsetClause
    ''');
    return maps.map((m) {
      final borrower = Borrower.fromMap(m);
      borrower.totalBalance = (m['computed_balance'] as num?)?.toDouble() ?? 0.0;
      borrower.loanCount = (m['loan_count'] as int?) ?? 0;
      
      final oldestDateStr = m['oldest_active_loan_date'] as String?;
      if (oldestDateStr != null && oldestDateStr.isNotEmpty) {
        final oldestDate = DateParser.safeParse(oldestDateStr);
        final loanAge = DateTime.now().difference(oldestDate).inDays;
        borrower.loanAgeDays = loanAge;
        borrower.overdueStatus = loanAge > 140 ? 'OVERDUE' : 'ACTIVE';
      } else {
        borrower.loanAgeDays = 0;
        borrower.overdueStatus = 'ACTIVE';
      }
      return borrower;
    }).toList();
  }

  Future<bool> isDatabaseEmpty() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM borrowers');
    final count = Sqflite.firstIntValue(result) ?? 0;
    return count == 0;
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
        await db.query('borrowers', where: 'phone = ? AND COALESCE(is_deleted, 0) = 0', whereArgs: [phone]);
    if (maps.isEmpty) return null;
    return Borrower.fromMap(maps.first);
  }

  Future<List<Borrower>> searchBorrowers(String query) async {
    final db = await database;
    final maps = await db.query(
      'borrowers',
      where: '(name LIKE ? OR phone LIKE ? OR borrower_code LIKE ?) AND COALESCE(is_deleted, 0) = 0',
      whereArgs: ['%$query%', '%$query%', '%$query%'],
      orderBy: 'CAST(borrower_code AS INTEGER) ASC',
    );
    return maps.map((m) => Borrower.fromMap(m)).toList();
  }

  Future<int> updateBorrower(Borrower borrower) async {
    await _onMutation();
    final db = await database;
    borrower.updatedAt = DateTime.now().millisecondsSinceEpoch;
    return await db.update(
      'borrowers',
      borrower.toMap(),
      where: 'id = ?',
      whereArgs: [borrower.id],
    );
  }

  Future<void> deleteBorrower(int id) async {
    await _onMutation();
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    
    await db.transaction((txn) async {
      await txn.update('loans', 
        {'is_deleted': 1, 'updated_at': now},
        where: 'borrower_id = ?', whereArgs: [id]);
      
      await txn.rawUpdate('''
        UPDATE payments SET is_deleted = 1, updated_at = ?
        WHERE loan_id IN (SELECT id FROM loans WHERE borrower_id = ?)
      ''', [now, id]);
      
      await txn.rawUpdate('''
        UPDATE borrowers 
        SET is_deleted = 1, updated_at = ?,
            borrower_code = borrower_code || '_del_' || ?
        WHERE id = ?
      ''', [now, now, id]);
    });
  }

  Future<bool> moveToDummyBorrower(int borrowerId) async {
    await _onMutation();
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    
    try {
      final timestampSecs = (now ~/ 1000).toString();
      debugPrint('DBHelper: Moving borrower to dummy...');
      await db.transaction((txn) async {
        // 1. Fetch current code
        final result = await txn.query('borrowers', columns: ['borrower_code'], where: 'id = ?', whereArgs: [borrowerId]);
        if (result.isEmpty) {
          debugPrint('DBHelper: Borrower not found with id $borrowerId');
          return;
        }
        
        final currentCode = result.first['borrower_code'] as String;
        debugPrint('Current borrower code: $currentCode');
        
        // 2. Generate new code (strip existing _del_ if present to prevent multiple suffixes)
        final baseCode = currentCode.split('_del_').first;
        final newCode = '${baseCode}_del_$timestampSecs';
        debugPrint('New borrower code: $newCode');

        // 3. Update BOTH fields
        final count = await txn.rawUpdate('''
          UPDATE borrowers 
          SET borrower_code = ?, is_dummy = 1, updated_at = ?
          WHERE id = ?
        ''', [newCode, now, borrowerId]);
        debugPrint('DBHelper: Rows affected: $count');
        
        // 4. Verify post-update
        final verifyResult = await txn.query('borrowers', columns: ['borrower_code', 'is_dummy'], where: 'id = ?', whereArgs: [borrowerId]);
        if (verifyResult.isNotEmpty) {
          debugPrint('Borrower code after update: ${verifyResult.first['borrower_code']}');
          debugPrint('is_dummy after update: ${verifyResult.first['is_dummy']}');
        }
      });
      return true;
    } catch (e) {
      debugPrint('DBHelper: Error in moveToDummyBorrower: $e');
      return false;
    }
  }

  Future<bool> moveToActiveBorrower(int borrowerId) async {
    await _onMutation();
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    
    try {
      debugPrint('DBHelper: Restoring borrower to active...');
      await db.transaction((txn) async {
        final result = await txn.query('borrowers', columns: ['borrower_code'], where: 'id = ?', whereArgs: [borrowerId]);
        if (result.isEmpty) return;
        
        final currentCode = result.first['borrower_code'] as String;
        final newCode = currentCode.split('_del_').first;

        final count = await txn.rawUpdate('''
          UPDATE borrowers 
          SET borrower_code = ?, is_dummy = 0, updated_at = ?
          WHERE id = ?
        ''', [newCode, now, borrowerId]);
        debugPrint('DBHelper: Restore rows affected: $count');
      });
      return true;
    } catch (e) {
      debugPrint('DBHelper: Error in moveToActiveBorrower: $e');
      return false;
    }
  }

  Future<void> clearAllUserData() async {
    await _onMutation();
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('payments');
      await txn.delete('loans');
      await txn.delete('borrowers');
      await txn.delete('expenses');
      await txn.delete('investments');
      await txn.delete('service_costs');
    });
  }

  Future<void> clearCurrentUserLocalData() async {
    await clearAllUserData();
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
    await _onMutation();
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    loan.updatedAt = now;
    loan.createdAt = now;
    final map = loan.toMap()..remove('id');
    return await db.insert('loans', map);
  }

  Future<List<Loan>> getLoansForBorrower(int borrowerId) async {
    final db = await database;
    final maps = await db.query(
      'loans',
      where: 'borrower_id = ? AND COALESCE(is_deleted, 0) = 0',
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
    await _onMutation();
    final db = await database;
    loan.updatedAt = DateTime.now().millisecondsSinceEpoch;
    return await db.update(
      'loans',
      loan.toMap(),
      where: 'id = ?',
      whereArgs: [loan.id],
    );
  }

  Future<void> deleteLoan(int id) async {
    await _onMutation();
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      await txn.update('loans', 
        {'is_deleted': 1, 'updated_at': now},
        where: 'id = ?', whereArgs: [id]);
      await txn.update('payments', 
        {'is_deleted': 1, 'updated_at': now},
        where: 'loan_id = ?', whereArgs: [id]);
    });
  }

  // ─────────────────────────────────────────────────────────────
  // Payment Operations
  // ─────────────────────────────────────────────────────────────

  Future<int> insertPayment(Payment payment) async {
    await _onMutation();
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    payment.updatedAt = now;
    payment.createdAt = now;
    final map = payment.toMap()..remove('id');
    return await db.insert('payments', map);
  }

  Future<List<Payment>> getPaymentsForLoan(int loanId) async {
    final db = await database;
    final maps = await db.query(
      'payments',
      where: 'loan_id = ? AND COALESCE(is_deleted, 0) = 0',
      whereArgs: [loanId],
      orderBy: 'payment_date DESC',
    );
    return maps.map((m) => Payment.fromMap(m)).toList();
  }

  Future<double> getTotalPaidByLoan(int loanId) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT SUM(amount) as total FROM payments WHERE loan_id = ? AND COALESCE(is_deleted, 0) = 0',
      [loanId],
    );
    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  Future<void> deletePayment(int id) async {
    await _onMutation();
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.update('payments', 
      {'is_deleted': 1, 'updated_at': now},
      where: 'id = ?', whereArgs: [id]);
  }

  // ── Atomic Payment Transactions ───────────────────────────────

  Future<void> executePaymentTransaction(Payment payment) async {
    await _onMutation();
    final db = await database;
    await db.transaction((txn) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      
      // 1. Insert payment
      payment.updatedAt = now;
      payment.createdAt = now;
      final paymentMap = payment.toMap()..remove('id');
      await txn.insert('payments', paymentMap);
      
      // 2. Query loan
      final loanMaps = await txn.query(
        'loans',
        where: 'id = ?',
        whereArgs: [payment.loanId],
      );
      if (loanMaps.isNotEmpty) {
        final loanMap = Map<String, dynamic>.from(loanMaps.first);
        final loanAmount = (loanMap['loan_amount'] as num).toDouble();
        final interestAmount = (loanMap['interest_amount'] as num).toDouble();
        final totalDue = loanAmount + interestAmount;
        
        // 3. Calculate total paid
        final paidRes = await txn.rawQuery(
          'SELECT SUM(amount) as total FROM payments WHERE loan_id = ? AND COALESCE(is_deleted, 0) = 0',
          [payment.loanId],
        );
        final totalPaid = (paidRes.first['total'] as num?)?.toDouble() ?? 0.0;
        
        // 4. Update status and end date if fully paid
        if (totalPaid >= totalDue) {
          await txn.update(
            'loans',
            {
              'status': 'cleared',
              'end_date': payment.paymentDate.toIso8601String(),
              'updated_at': now,
            },
            where: 'id = ?',
            whereArgs: [payment.loanId],
          );
        } else {
          await txn.update(
            'loans',
            {
              'status': 'active',
              'end_date': null,
              'updated_at': now,
            },
            where: 'id = ?',
            whereArgs: [payment.loanId],
          );
        }
      }
    });
  }

  Future<void> executeDeletePaymentTransaction(int paymentId, int loanId) async {
    await _onMutation();
    final db = await database;
    await db.transaction((txn) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      
      // 1. Soft delete the payment
      await txn.update(
        'payments',
        {
          'is_deleted': 1,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [paymentId],
      );
      
      // 2. Query loan
      final loanMaps = await txn.query(
        'loans',
        where: 'id = ?',
        whereArgs: [loanId],
      );
      if (loanMaps.isNotEmpty) {
        final loanMap = Map<String, dynamic>.from(loanMaps.first);
        final loanAmount = (loanMap['loan_amount'] as num).toDouble();
        final interestAmount = (loanMap['interest_amount'] as num).toDouble();
        final totalDue = loanAmount + interestAmount;
        
        // 3. Recalculate total paid
        final paidRes = await txn.rawQuery(
          'SELECT SUM(amount) as total FROM payments WHERE loan_id = ? AND COALESCE(is_deleted, 0) = 0',
          [loanId],
        );
        final totalPaid = (paidRes.first['total'] as num?)?.toDouble() ?? 0.0;
        
        // 4. Update status and end date
        if (totalPaid < totalDue) {
          await txn.update(
            'loans',
            {
              'status': 'active',
              'end_date': null,
              'updated_at': now,
            },
            where: 'id = ?',
            whereArgs: [loanId],
          );
        } else {
          await txn.update(
            'loans',
            {
              'status': 'cleared',
              'updated_at': now,
            },
            where: 'id = ?',
            whereArgs: [loanId],
          );
        }
      }
    });
  }

  Future<void> executeQuickPayFlexibleTransaction(int borrowerId, double totalAmount, {DateTime? paymentDate}) async {
    await _onMutation();
    final db = await database;
    await db.transaction((txn) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      
      // 1. Get active loans
      final loanMaps = await txn.query(
        'loans',
        where: 'borrower_id = ? AND status = "active" AND COALESCE(is_deleted, 0) = 0',
        whereArgs: [borrowerId],
        orderBy: 'loan_date ASC', // pay oldest loan first
      );
      
      double remaining = totalAmount;
      
      for (final lMap in loanMaps) {
        if (remaining <= 0) break;
        
        final loanId = lMap['id'] as int;
        final loanAmount = (lMap['loan_amount'] as num).toDouble();
        final interestAmount = (lMap['interest_amount'] as num).toDouble();
        final totalDue = loanAmount + interestAmount;
        
        // Calculate total paid for this loan so far
        final paidRes = await txn.rawQuery(
          'SELECT SUM(amount) as total FROM payments WHERE loan_id = ? AND COALESCE(is_deleted, 0) = 0',
          [loanId],
        );
        final totalPaid = (paidRes.first['total'] as num?)?.toDouble() ?? 0.0;
        final balance = totalDue - totalPaid;
        
        final payForThisLoan = remaining > balance ? balance : remaining;
        
        if (payForThisLoan > 0) {
          // Insert payment
          final payment = Payment(
            loanId: loanId,
            amount: payForThisLoan,
            paymentDate: paymentDate ?? DateTime.now(),
            notes: 'Quick Pay',
          );
          payment.updatedAt = now;
          payment.createdAt = now;
          final paymentMap = payment.toMap()..remove('id');
          await txn.insert('payments', paymentMap);
          
          final newPaid = totalPaid + payForThisLoan;
          
          // Update loan status
          if (newPaid >= totalDue) {
            await txn.update(
              'loans',
              {
                'status': 'cleared',
                'end_date': (paymentDate ?? DateTime.now()).toIso8601String(),
                'updated_at': now,
              },
              where: 'id = ?',
              whereArgs: [loanId],
            );
          }
          
          remaining -= payForThisLoan;
        }
      }
    });
  }

  // ─────────────────────────────────────────────────────────────
  // Reports
  // ─────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getReportsBreakdown() async {
    final db = await database;
    return await db.rawQuery('''
      SELECT 
        b.id,
        b.borrower_code,
        b.name,
        b.phone,
        b.address,
        b.notes,
        b.updated_at,
        b.created_at,
        b.last_modified_device,
        b.is_deleted,
        COALESCE(lbs.total_loan_amount, 0.0) as total_loan_amount,
        COALESCE(lbs.total_interest_amount, 0.0) as total_interest_amount,
        COALESCE(lbs.total_due, 0.0) as total_due,
        COALESCE(lbs.total_paid, 0.0) as total_paid
      FROM borrowers b
      LEFT JOIN (
        SELECT 
          l.borrower_id,
          SUM(l.loan_amount) as total_loan_amount,
          SUM(l.interest_amount) as total_interest_amount,
          SUM(l.loan_amount + l.interest_amount) as total_due,
          SUM(COALESCE((SELECT SUM(amount) FROM payments WHERE loan_id = l.id AND COALESCE(is_deleted, 0) = 0), 0.0)) as total_paid
        FROM loans l
        WHERE l.status = 'active' AND COALESCE(l.is_deleted, 0) = 0
        GROUP BY l.borrower_id
      ) lbs ON b.id = lbs.borrower_id
      WHERE COALESCE(b.is_deleted, 0) = 0
    ''');
  }

  Future<Map<String, dynamic>> getGlobalSummary() async {
    final db = await database;

    final activeLoanRes = await db.rawQuery(
        "SELECT SUM(loan_amount) as principal, SUM(interest_amount) as interest FROM loans WHERE status = 'active' AND COALESCE(is_deleted, 0) = 0");
    final activePaidRes = await db.rawQuery(
        "SELECT SUM(p.amount) as total FROM payments p JOIN loans l ON p.loan_id = l.id WHERE l.status = 'active' AND COALESCE(p.is_deleted, 0) = 0 AND COALESCE(l.is_deleted, 0) = 0");

    final allLoanRes =
        await db.rawQuery("SELECT SUM(loan_amount) as principal FROM loans WHERE COALESCE(is_deleted, 0) = 0");
    final allPaidRes =
        await db.rawQuery("SELECT SUM(amount) as total FROM payments WHERE COALESCE(is_deleted, 0) = 0");

    final countRes = await db.rawQuery('SELECT COUNT(*) as cnt FROM borrowers WHERE COALESCE(is_deleted, 0) = 0 AND COALESCE(is_dummy, 0) = 0');

    final activePrincipal =
        (activeLoanRes.first['principal'] as num?)?.toDouble() ?? 0.0;
    final activeInterest =
        (activeLoanRes.first['interest'] as num?)?.toDouble() ?? 0.0;
    final activeCollected =
        (activePaidRes.first['total'] as num?)?.toDouble() ?? 0.0;
    final activeDue = activePrincipal + activeInterest;

    final totalLoanedEver =
        (allLoanRes.first['principal'] as num?)?.toDouble() ?? 0.0;
    final totalCollectedEver =
        (allPaidRes.first['total'] as num?)?.toDouble() ?? 0.0;

    return {
      'totalLoaned': totalLoanedEver,
      'totalCollected': totalCollectedEver,
      'activeLoaned': activePrincipal,
      'totalInterest': activeInterest,
      'totalDue': activeDue,
      'activePending': activeDue - activeCollected,
      'totalPending': activeDue - activeCollected,
      'totalBorrowers': (countRes.first['cnt'] as int?) ?? 0,
    };
  }

  Future<void> validateDataIntegrity() async {
    final db = await database;
    try {
      final paymentsRes = await db.rawQuery('SELECT SUM(amount) as total FROM payments WHERE COALESCE(is_deleted, 0) = 0');
      final totalCollected = (paymentsRes.first['total'] as num?)?.toDouble() ?? 0.0;
      
      final activeLoansRes = await db.rawQuery("SELECT SUM(loan_amount + interest_amount) as total FROM loans WHERE status = 'active' AND COALESCE(is_deleted, 0) = 0");
      final totalOutstanding = (activeLoansRes.first['total'] as num?)?.toDouble() ?? 0.0;

      final activePaidRes = await db.rawQuery("SELECT SUM(p.amount) as total FROM payments p JOIN loans l ON p.loan_id = l.id WHERE l.status = 'active' AND COALESCE(p.is_deleted, 0) = 0 AND COALESCE(l.is_deleted, 0) = 0");
      final activeCollected = (activePaidRes.first['total'] as num?)?.toDouble() ?? 0.0;
      
      final pending = totalOutstanding - activeCollected;

      debugPrint('--- Database Integrity Validation ---');
      debugPrint('Total Collected (all payments): $totalCollected');
      debugPrint('Total Outstanding (active loans): $totalOutstanding');
      debugPrint('Active Collected (payments on active loans): $activeCollected');
      debugPrint('Total Pending: $pending');
      
      if (pending < 0) {
        debugPrint('DB Mismatch! Pending amount is negative ($pending). Auto-repairing...');
        await db.rawUpdate('''
          UPDATE loans 
          SET status = 'cleared', updated_at = ? 
          WHERE id IN (
            SELECT l.id FROM loans l
            LEFT JOIN (SELECT loan_id, SUM(amount) as paid FROM payments WHERE COALESCE(is_deleted, 0) = 0 GROUP BY loan_id) p ON p.loan_id = l.id
            WHERE l.status = 'active' AND COALESCE(l.is_deleted, 0) = 0 
            AND COALESCE(p.paid, 0) >= (l.loan_amount + l.interest_amount)
          )
        ''', [DateTime.now().millisecondsSinceEpoch]);
        debugPrint('Auto-repaired overpaid loans by marking them as cleared.');
      }
      
      await db.rawUpdate('''
        UPDATE payments SET is_deleted = 1, updated_at = ?
        WHERE COALESCE(is_deleted, 0) = 0 AND loan_id IN (
          SELECT id FROM loans WHERE COALESCE(is_deleted, 0) = 1
        )
      ''', [DateTime.now().millisecondsSinceEpoch]);
      
      debugPrint('---------------------------------');
    } catch (e) {
      debugPrint('Error during integrity validation: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Investment Operations
  // ─────────────────────────────────────────────────────────────

  Future<int> insertInvestment(Map<String, dynamic> data) async {
    await _onMutation();
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final map = Map<String, dynamic>.from(data);
    map['updated_at'] = now;
    map['created_at'] = now;
    map['is_deleted'] = 0;
    return await db.insert('investments', map);
  }

  Future<List<Map<String, dynamic>>> getAllInvestments() async {
    final db = await database;
    return await db.query(
      'investments',
      where: 'COALESCE(is_deleted, 0) = 0',
      orderBy: 'inv_date DESC',
    );
  }

  Future<void> deleteInvestment(int id) async {
    await _onMutation();
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.update('investments', 
      {'is_deleted': 1, 'updated_at': now},
      where: 'id = ?', whereArgs: [id]);
  }

  Future<double> getTotalInvested() async {
    final db = await database;
    final result = await db.rawQuery(
        'SELECT SUM(amount) as total FROM investments WHERE COALESCE(is_deleted, 0) = 0');
    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  // ───────────────────────────────────────────────────────────────
  // Home Screen Tab Helpers
  // ───────────────────────────────────────────────────────────────

  List<String> _getTodayRangeBounds() {
    final now = DateTime.now();
    final ymd = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    return ['$ymd 00:00:00', '$ymd 23:59:59'];
  }

  List<String> _getMonthRangeBounds() {
    final now = DateTime.now();
    final ymdStart = '${now.year}-${now.month.toString().padLeft(2, '0')}-01';
    
    // Calculate the last day of the current month
    final nextMonth = (now.month == 12) ? 1 : now.month + 1;
    final nextMonthYear = (now.month == 12) ? now.year + 1 : now.year;
    final lastDay = DateTime(nextMonthYear, nextMonth, 0).day;
    final ymdEnd = '${now.year}-${now.month.toString().padLeft(2, '0')}-${lastDay.toString().padLeft(2, '0')}';
    
    return ['$ymdStart 00:00:00', '$ymdEnd 23:59:59'];
  }

  Future<Set<int>> getBorrowersPaidToday() async {
    final db = await database;
    final bounds = _getTodayRangeBounds();

    final result = await db.rawQuery('''
      SELECT b.id
      FROM borrowers b
      WHERE
        COALESCE(b.is_deleted, 0) = 0
        AND EXISTS (
          SELECT 1
          FROM loans active_l
          WHERE active_l.borrower_id = b.id
            AND active_l.status = 'active'
            AND COALESCE(active_l.is_deleted, 0) = 0
        )
        AND NOT EXISTS (
          SELECT 1
          FROM loans unpaid_l
          WHERE unpaid_l.borrower_id = b.id
            AND unpaid_l.status = 'active'
            AND COALESCE(unpaid_l.is_deleted, 0) = 0
            AND NOT EXISTS (
              SELECT 1
              FROM payments p
              WHERE p.loan_id = unpaid_l.id
                AND REPLACE(p.payment_date, 'T', ' ') BETWEEN ? AND ?
                AND COALESCE(p.is_deleted, 0) = 0
            )
        )
    ''', [bounds[0], bounds[1]]);
    return result.map((r) => r['id'] as int).toSet();
  }

  Future<Map<int, int>> getPaidLoanCountsToday() async {
    final db = await database;
    final bounds = _getTodayRangeBounds();

    final result = await db.rawQuery('''
      SELECT l.borrower_id, COUNT(DISTINCT l.id) AS paid_count
      FROM loans l
      JOIN payments p ON p.loan_id = l.id
      WHERE REPLACE(p.payment_date, 'T', ' ') BETWEEN ? AND ?
        AND COALESCE(p.is_deleted, 0) = 0
        AND COALESCE(l.is_deleted, 0) = 0
      GROUP BY l.borrower_id
    ''', [bounds[0], bounds[1]]);
    return {
      for (final row in result)
        row['borrower_id'] as int: (row['paid_count'] as num).toInt()
    };
  }

  Future<Map<int, int>> getClearedPaidLoanCountsToday() async {
    final db = await database;
    final bounds = _getTodayRangeBounds();

    final result = await db.rawQuery('''
      SELECT l.borrower_id, COUNT(DISTINCT l.id) AS paid_count
      FROM loans l
      JOIN payments p ON p.loan_id = l.id
      WHERE l.status != 'active'
        AND REPLACE(p.payment_date, 'T', ' ') BETWEEN ? AND ?
        AND COALESCE(p.is_deleted, 0) = 0
        AND COALESCE(l.is_deleted, 0) = 0
      GROUP BY l.borrower_id
    ''', [bounds[0], bounds[1]]);
    return {
      for (final row in result)
        row['borrower_id'] as int: (row['paid_count'] as num).toInt()
    };
  }

  Future<Set<int>> getLoanIdsPaidTodayForBorrower(int borrowerId) async {
    final db = await database;
    final bounds = _getTodayRangeBounds();

    final result = await db.rawQuery('''
      SELECT DISTINCT l.id
      FROM loans l
      JOIN payments p ON p.loan_id = l.id
      WHERE l.borrower_id = ?
        AND REPLACE(p.payment_date, 'T', ' ') BETWEEN ? AND ?
        AND COALESCE(p.is_deleted, 0) = 0
        AND COALESCE(l.is_deleted, 0) = 0
    ''', [borrowerId, bounds[0], bounds[1]]);
    return result.map((r) => r['id'] as int).toSet();
  }

  Future<Set<int>> getCompletedBorrowerIds() async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT b.id
      FROM borrowers b
      WHERE
        COALESCE(b.is_deleted, 0) = 0
        AND
        (SELECT COUNT(*) FROM loans l WHERE l.borrower_id = b.id AND l.status = 'active' AND COALESCE(l.is_deleted, 0) = 0) = 0
    ''');
    return result.map((r) => r['id'] as int).toSet();
  }

  // ─────────────────────────────────────────────────────────────
  // Expense Operations
  // ─────────────────────────────────────────────────────────────

  Future<int> insertExpense(Map<String, dynamic> data) async {
    await _onMutation();
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final map = Map<String, dynamic>.from(data);
    map['updated_at'] = now;
    map['created_at'] = now;
    map['is_deleted'] = 0;
    return await db.insert('expenses', map);
  }

  Future<List<Map<String, dynamic>>> getAllExpenses() async {
    final db = await database;
    return await db.query(
      'expenses',
      where: 'COALESCE(is_deleted, 0) = 0',
      orderBy: 'expense_date DESC',
    );
  }

  Future<void> deleteExpense(int id) async {
    await _onMutation();
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.update('expenses', 
      {'is_deleted': 1, 'updated_at': now},
      where: 'id = ?', whereArgs: [id]);
  }

  Future<double> getTotalExpenses() async {
    final db = await database;
    final result = await db.rawQuery(
        'SELECT SUM(amount) as total FROM expenses WHERE COALESCE(is_deleted, 0) = 0');
    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  Future<double> getMonthExpenses() async {
    final db = await database;
    final bounds = _getMonthRangeBounds();
    final result = await db.rawQuery('''
      SELECT SUM(amount) as total 
      FROM expenses 
      WHERE REPLACE(expense_date, 'T', ' ') BETWEEN ? AND ?
        AND COALESCE(is_deleted, 0) = 0
    ''', [bounds[0], bounds[1]]);
    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  Future<double> getTodayCollection() async {
    final db = await database;
    final bounds = _getTodayRangeBounds();

    final result = await db.rawQuery('''
      SELECT SUM(amount) as total 
      FROM payments 
      WHERE REPLACE(payment_date, 'T', ' ') BETWEEN ? AND ?
        AND COALESCE(is_deleted, 0) = 0
    ''', [bounds[0], bounds[1]]);
    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  // ─────────────────────────────────────────────────────────────
  // Service Cost Operations
  // ─────────────────────────────────────────────────────────────

  Future<int> insertServiceCost(Map<String, dynamic> data) async {
    await _onMutation();
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final map = Map<String, dynamic>.from(data);
    map['timestamp'] = now;
    map['is_deleted'] = 0;
    return await db.insert('service_costs', map);
  }

  Future<List<Map<String, dynamic>>> getAllServiceCosts() async {
    final db = await database;
    return await db.query(
      'service_costs',
      where: 'COALESCE(is_deleted, 0) = 0',
      orderBy: 'dateCreated DESC',
    );
  }

  Future<void> deleteServiceCost(int id) async {
    await _onMutation();
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.update('service_costs', 
      {'is_deleted': 1, 'timestamp': now},
      where: 'id = ?', whereArgs: [id]);
  }

  Future<double> getTotalServiceCosts() async {
    final db = await database;
    final result = await db.rawQuery(
        'SELECT SUM(amount) as total FROM service_costs WHERE COALESCE(is_deleted, 0) = 0');
    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  Future<double> getTodayServiceCosts() async {
    final db = await database;
    final bounds = _getTodayRangeBounds();
    final result = await db.rawQuery('''
      SELECT SUM(amount) as total 
      FROM service_costs 
      WHERE REPLACE(dateCreated, 'T', ' ') BETWEEN ? AND ?
        AND COALESCE(is_deleted, 0) = 0
    ''', [bounds[0], bounds[1]]);
    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  Future<double> getMonthServiceCosts() async {
    final db = await database;
    final bounds = _getMonthRangeBounds();
    final result = await db.rawQuery('''
      SELECT SUM(amount) as total 
      FROM service_costs 
      WHERE REPLACE(dateCreated, 'T', ' ') BETWEEN ? AND ?
        AND COALESCE(is_deleted, 0) = 0
    ''', [bounds[0], bounds[1]]);
    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  // ─────────────────────────────────────────────────────────────
  // Startup Repair & Restore Metadata Helpers
  // ─────────────────────────────────────────────────────────────

  Future<void> repairDatabaseIfNeeded() async {
    try {
      final dbPath = await getDatabasesPath();
      final path = join(dbPath, 'loan_manager.db');
      final file = File(path);
      if (await file.exists()) {
        final db = await database;
        final restoreMetaExists = Sqflite.firstIntValue(await db.rawQuery(
          "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='restore_meta'"
        )) ?? 0;
        if (restoreMetaExists == 0) {
          print('restore_meta missing - repairing');
          await db.execute('''
            CREATE TABLE IF NOT EXISTS restore_meta (
              key TEXT PRIMARY KEY,
              value TEXT
            )
          ''');
        }
      }
    } catch (e) {
      debugPrint('DBHelper: repairDatabaseIfNeeded silent error: $e');
    }
  }

  Future<void> setRestoreMeta(String key, String value) async {
    final db = await database;
    await db.insert('restore_meta', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String?> getRestoreMeta(String key) async {
    final db = await database;
    final res =
        await db.query('restore_meta', where: 'key = ?', whereArgs: [key]);
    if (res.isEmpty) return null;
    return res.first['value'] as String?;
  }

  Future<void> deleteRestoreMeta(String key) async {
    final db = await database;
    await db.delete('restore_meta', where: 'key = ?', whereArgs: [key]);
  }
}

