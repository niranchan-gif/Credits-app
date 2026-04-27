import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../database/db_helper.dart';
import '../models/borrower.dart';
import '../models/loan.dart';
import '../models/payment.dart';

class FirebaseBackupResult {
  final int borrowers;
  final int loans;
  final int payments;
  final int investments;

  const FirebaseBackupResult({
    required this.borrowers,
    required this.loans,
    required this.payments,
    required this.investments,
  });

  int get total => borrowers + loans + payments + investments;
}

class FirebaseBackupService {
  FirebaseBackupService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    DBHelper? db,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _db = db ?? DBHelper();

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final DBHelper _db;

  Future<FirebaseBackupResult> backupAll() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('Please login before backup.');
    }

    final borrowers = await _db.getAllBorrowers();
    final loansByBorrower = <int, List<Loan>>{};
    final paymentsByLoan = <int, List<Payment>>{};
    final allLoans = <Loan>[];
    final allPayments = <Payment>[];
    final investments = await _db.getAllInvestments();

    for (final borrower in borrowers) {
      final borrowerId = borrower.id;
      if (borrowerId == null) continue;
      final loans = await _db.getLoansForBorrower(borrowerId);
      loansByBorrower[borrowerId] = loans;
      allLoans.addAll(loans);

      for (final loan in loans) {
        final loanId = loan.id;
        if (loanId == null) continue;
        final payments = await _db.getPaymentsForLoan(loanId);
        paymentsByLoan[loanId] = payments;
        allPayments.addAll(payments);
      }
    }

    final root = _firestore.collection('users').doc(user.uid);
    await root.set({
      'email': user.email,
      'lastBackupAt': FieldValue.serverTimestamp(),
      'deviceBackupVersion': 1,
    }, SetOptions(merge: true));

    await _syncCollection<Borrower>(
      root: root,
      collectionName: 'borrowers',
      items: borrowers.where((b) => b.id != null).toList(),
      docId: (b) => 'borrower_${b.id}',
      data: (b) => {
        'localId': b.id,
        'borrowerCode': b.borrowerCode,
        'name': b.name,
        'phone': b.phone,
        'address': b.address,
        'notes': b.notes,
        'updatedAt': FieldValue.serverTimestamp(),
      },
    );

    await _syncCollection<Loan>(
      root: root,
      collectionName: 'loans',
      items: allLoans.where((l) => l.id != null).toList(),
      docId: (l) => 'loan_${l.id}',
      data: (l) => {
        'localId': l.id,
        'borrowerId': l.borrowerId,
        'loanAmount': l.loanAmount,
        'interestAmount': l.interestAmount,
        'loanDate': l.loanDate.toIso8601String(),
        'status': l.status,
        'notes': l.notes,
        'updatedAt': FieldValue.serverTimestamp(),
      },
    );

    await _syncCollection<Payment>(
      root: root,
      collectionName: 'payments',
      items: allPayments.where((p) => p.id != null).toList(),
      docId: (p) => 'payment_${p.id}',
      data: (p) => {
        'localId': p.id,
        'loanId': p.loanId,
        'amount': p.amount,
        'paymentDate': p.paymentDate.toIso8601String(),
        'notes': p.notes,
        'updatedAt': FieldValue.serverTimestamp(),
      },
    );

    await _syncCollection<Map<String, dynamic>>(
      root: root,
      collectionName: 'investments',
      items: investments.where((i) => i['id'] != null).toList(),
      docId: (i) => 'investment_${i['id']}',
      data: (i) => {
        'localId': i['id'],
        'amount': i['amount'],
        'investmentDate': i['inv_date'],
        'notes': i['notes'],
        'updatedAt': FieldValue.serverTimestamp(),
      },
    );

    return FirebaseBackupResult(
      borrowers: borrowers.length,
      loans: allLoans.length,
      payments: allPayments.length,
      investments: investments.length,
    );
  }

  Future<void> _syncCollection<T>({
    required DocumentReference<Map<String, dynamic>> root,
    required String collectionName,
    required List<T> items,
    required String Function(T item) docId,
    required Map<String, dynamic> Function(T item) data,
  }) async {
    final collection = root.collection(collectionName);
    final localIds = items.map(docId).toSet();

    var batch = _firestore.batch();
    var opCount = 0;

    Future<void> commitIfNeeded({bool force = false}) async {
      if (opCount == 0 || (!force && opCount < 450)) return;
      await batch.commit();
      batch = _firestore.batch();
      opCount = 0;
    }

    for (final item in items) {
      batch.set(
          collection.doc(docId(item)), data(item), SetOptions(merge: true));
      opCount++;
      await commitIfNeeded();
    }

    final existingDocs = await collection.get();
    for (final doc in existingDocs.docs) {
      if (!localIds.contains(doc.id)) {
        batch.delete(doc.reference);
        opCount++;
        await commitIfNeeded();
      }
    }

    await commitIfNeeded(force: true);
  }
}
