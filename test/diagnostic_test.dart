import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:excel/excel.dart';

void main() {
  test('Analyze Excel Backup Files for Developer/Test Data', () async {
    print('==================================================');
    print('EXCEL BACKUP DIAGNOSTICS & DATA ANALYSIS');
    print('==================================================');

    final backupDir = Directory(p.join(Directory.current.path, 'scratch'));
    if (!backupDir.existsSync()) {
      print('Scratch directory does not exist! Run adb pull first.');
      return;
    }

    final files = backupDir.listSync().whereType<File>().where((f) => f.path.endsWith('.xlsx')).toList();
    print('Found ${files.length} Excel backup files in scratch/');

    for (final file in files) {
      print('\n--------------------------------------------------');
      print('Analyzing File: ${p.basename(file.path)}');
      print('Size: ${file.lengthSync()} bytes');
      print('--------------------------------------------------');

      final bytes = file.readAsBytesSync();
      final excel = Excel.decodeBytes(bytes);

      print('Excel Sheets: ${excel.tables.keys.toList()}');

      // 1. Parse Metadata Sheet if available
      final metaSheet = excel.tables['Metadata'];
      if (metaSheet != null) {
        print('\n[Metadata Sheet Contents]');
        for (var i = 0; i < metaSheet.maxRows; i++) {
          final row = metaSheet.rows[i];
          if (row.length >= 2 && row[0] != null && row[1] != null) {
            print('  ${row[0]?.value} : ${row[1]?.value}');
          }
        }
      }

      // 2. Parse Summary Sheet if available
      final summarySheet = excel.tables['Summary'];
      if (summarySheet != null) {
        print('\n[Summary Sheet Contents]');
        for (var i = 0; i < summarySheet.maxRows; i++) {
          final row = summarySheet.rows[i];
          if (row.length >= 2 && row[0] != null && row[1] != null) {
            print('  ${row[0]?.value} : ${row[1]?.value}');
          }
        }
      }

      // 3. Scan Borrowers
      final borrowersSheet = excel.tables['Borrowers'];
      if (borrowersSheet == null) {
        print('\nWarning: Borrowers sheet not found!');
        continue;
      }

      final bHeaders = borrowersSheet.rows.first.map((c) => c?.value?.toString().toLowerCase() ?? '').toList();
      print('\nBorrowers Table Headers: $bHeaders');

      final idIndex = bHeaders.indexOf('id');
      final codeIndex = bHeaders.indexOf('borrower_code');
      final nameIndex = bHeaders.indexOf('name');
      final phoneIndex = bHeaders.indexOf('phone');
      final addressIndex = bHeaders.indexOf('address');
      final notesIndex = bHeaders.indexOf('notes');
      final isDeletedIndex = bHeaders.indexOf('is_deleted');

      int totalBorrowers = 0;
      int testBorrowersCount = 0;
      int activeBorrowersCount = 0;
      int deletedBorrowersCount = 0;

      final testBorrowersList = [];
      final normalBorrowersList = [];

      for (var i = 1; i < borrowersSheet.maxRows; i++) {
        final row = borrowersSheet.rows[i];
        if (row.isEmpty || row.length <= nameIndex) continue;

        totalBorrowers++;
        final id = idIndex != -1 ? row[idIndex]?.value?.toString() : '';
        final code = codeIndex != -1 ? row[codeIndex]?.value?.toString() : '';
        final name = nameIndex != -1 ? row[nameIndex]?.value?.toString() ?? '' : '';
        final phone = phoneIndex != -1 ? row[phoneIndex]?.value?.toString() : '';
        final address = addressIndex != -1 ? row[addressIndex]?.value?.toString() : '';
        final notes = notesIndex != -1 ? row[notesIndex]?.value?.toString() : '';
        final isDeletedStr = isDeletedIndex != -1 ? row[isDeletedIndex]?.value?.toString() ?? '0' : '0';
        final isDeleted = isDeletedStr == '1' || isDeletedStr.toLowerCase() == 'true';

        if (isDeleted) {
          deletedBorrowersCount++;
        } else {
          activeBorrowersCount++;
        }

        final bInfo = {
          'id': id,
          'code': code,
          'name': name,
          'phone': phone,
          'address': address,
          'notes': notes,
          'is_deleted': isDeleted,
        };

        // Classify if it's test/developer-created
        final isTest = name.startsWith('Test Borrower') || 
                       (address?.startsWith('Test Address') ?? false) ||
                       (notes?.toLowerCase().contains('test') ?? false);

        if (isTest) {
          testBorrowersCount++;
          testBorrowersList.add(bInfo);
        } else {
          normalBorrowersList.add(bInfo);
        }
      }

      print('  Total Borrowers: $totalBorrowers');
      print('  Active Borrowers: $activeBorrowersCount');
      print('  Deleted Borrowers: $deletedBorrowersCount');
      print('  Test/Developer Borrowers: $testBorrowersCount');
      print('  Normal Production Borrowers: ${totalBorrowers - testBorrowersCount}');

      print('\n[Developer/Test Borrowers Samples (first 10)]');
      for (var i = 0; i < testBorrowersList.length && i < 10; i++) {
        final b = testBorrowersList[i];
        print('  - ID: ${b['id']}, Code: ${b['code']}, Name: "${b['name']}", Phone: ${b['phone']}, Deleted: ${b['is_deleted']}');
      }

      print('\n[Normal Production Borrowers Samples (first 10)]');
      for (var i = 0; i < normalBorrowersList.length && i < 10; i++) {
        final b = normalBorrowersList[i];
        print('  - ID: ${b['id']}, Code: ${b['code']}, Name: "${b['name']}", Phone: ${b['phone']}, Deleted: ${b['is_deleted']}');
      }

      // Check if there are any specific custom attributes on the worksheets
      print('\n[Checking other tables for custom flags or validations]');
      for (final tableName in ['Loans', 'Payments', 'Expenses', 'Investments', 'SERVICE_COSTS']) {
        final sheet = excel.tables[tableName];
        if (sheet == null) continue;
        final headers = sheet.rows.first.map((c) => c?.value?.toString() ?? '').toList();
        print('  Sheet "$tableName" Headers: $headers');
      }
    }
    print('==================================================');
  });
}
