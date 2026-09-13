import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:credit/database/db_helper.dart';
import 'package:credit/services/excel_backup_service.dart';

void main() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  SharedPreferences.setMockInitialValues({});

  final path = r'C:\Users\gpk00\Downloads\CreditBackup_20260610_121129.xlsx';
  print('Testing import on $path (merge: false)...');
  try {
    await ExcelBackupService.importBackup(path, merge: false);
    print('Import SUCCESS (merge: false)!');
  } catch (e, stack) {
    print('Import FAILED (merge: false): $e');
    print(stack);
  }

  print('\nTesting import on $path (merge: true)...');
  try {
    await ExcelBackupService.importBackup(path, merge: true);
    print('Import SUCCESS (merge: true)!');
  } catch (e, stack) {
    print('Import FAILED (merge: true): $e');
    print(stack);
  }
}
