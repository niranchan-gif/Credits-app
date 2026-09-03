import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:excel/excel.dart' show Excel;
import 'package:googleapis/drive/v3.dart' as drive;

import '../services/excel_backup_service.dart';
import '../services/backup_freshness_service.dart';
import '../services/google_drive_service.dart';
import '../services/auto_backup_manager.dart';
import '../services/google_drive_excel_backup_service.dart';
import '../utils/app_colors.dart';
import '../utils/date_parser.dart';
import '../widgets/premium_card.dart';
import '../widgets/progress_dialog.dart';
import '../widgets/sync_status_indicator.dart';
import '../providers/loan_provider.dart';

class BackupRestoreScreen extends StatefulWidget {
  const BackupRestoreScreen({super.key});

  @override
  State<BackupRestoreScreen> createState() => _BackupRestoreScreenState();
}

class _BackupRestoreScreenState extends State<BackupRestoreScreen> {
  // Services
  final _driveService = GoogleDriveService();
  final _autoBackupManager = AutoBackupManager();

  // Excel states
  bool _isExporting = false;
  bool _isImporting = false;
  String? _lastExcelBackupDate;

  // Google Drive states
  bool _isDriveConnected = false;
  String? _driveEmail;
  bool _isDriveLoading = false;
  bool _isDriveSyncing = false;
  bool _backupPending = false;
  String? _lastGDriveBackupDate;
  String? _lastGDriveBackupSize;
  String? _lastGDriveBackupHealth;
  bool _areBackupsBlocked = false;

  @override
  void initState() {
    super.initState();
    _loadBackupInfo();
    _checkDriveConnection();
    
    // Register callback on AutoBackupManager so if background sync completes, we update UI
    _autoBackupManager.onBackupCompleted = () {
      if (mounted) {
        _loadBackupInfo();
      }
    };
  }

  @override
  void dispose() {
    _autoBackupManager.onBackupCompleted = null;
    super.dispose();
  }

  Future<void> _loadBackupInfo() async {
    final prefs = await SharedPreferences.getInstance();
    final blocked = await BackupFreshnessService().areBackupsBlocked();
    setState(() {
      _areBackupsBlocked = blocked;
      // Excel
      _lastExcelBackupDate = prefs.getString('last_excel_backup_date');
      
      // Google Drive
      _driveEmail = prefs.getString('google_drive_account_email');
      _lastGDriveBackupDate = prefs.getString('last_gdrive_backup_date');
      _lastGDriveBackupSize = prefs.getString('last_gdrive_backup_size');
      _lastGDriveBackupHealth = prefs.getString('last_gdrive_backup_health');
      _backupPending = prefs.getBool('backup_pending') ?? false;
    });
  }

  Future<void> _checkDriveConnection() async {
    setState(() => _isDriveLoading = true);
    try {
      final connected = await _driveService.isConnected();
      setState(() {
        _isDriveConnected = connected;
        if (connected && _driveService.currentUser != null) {
          _driveEmail = _driveService.currentUser!.email;
        }
      });
    } catch (e) {
      debugPrint('BackupRestoreScreen: Drive check failed: $e');
    } finally {
      setState(() => _isDriveLoading = false);
    }
  }

  // ==========================================
  // GOOGLE DRIVE BACKUP & RESTORE ACTIONS
  // ==========================================

  Future<void> _connectGoogleDrive() async {
    setState(() => _isDriveLoading = true);
    try {
      final account = await _driveService.connectAccount();
      if (account != null) {
        setState(() {
          _isDriveConnected = true;
          _driveEmail = account.email;
        });
        _showSuccessSnackbar('Connected to Google Account: ${account.email}');
        try {
          await GoogleDriveExcelBackupService().initializeOnStartup();
        } catch (e) {
          debugPrint('BackupRestoreScreen: Drive Excel backup init failed: $e');
        }
        await _loadBackupInfo();
      }
    } catch (e) {
      _showErrorSnackbar('Google sign-in failed: $e');
    } finally {
      setState(() => _isDriveLoading = false);
    }
  }

  Future<void> _disconnectGoogleDrive() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Disconnect Google Drive?'),
        content: const Text('You will no longer perform automatic cloud backups to Google Drive. Local data is unaffected.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isDriveLoading = true);
    try {
      await _driveService.disconnectAccount();
      setState(() {
        _isDriveConnected = false;
        _driveEmail = null;
        _lastGDriveBackupDate = null;
        _lastGDriveBackupSize = null;
        _lastGDriveBackupHealth = null;
        _backupPending = false;
      });
      _showSuccessSnackbar('Google Drive account disconnected.');
    } catch (e) {
      _showErrorSnackbar('Disconnect failed: $e');
    } finally {
      setState(() => _isDriveLoading = false);
    }
  }

  Future<void> _triggerManualGDriveBackup() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ProgressDialog(
        title: 'Backup',
        successMessage: '✓ Backup Completed',
        errorMessage: 'Backup Failed',
        action: (updateProgress) async {
          // Force manual run of backup manager
          await _autoBackupManager.checkAndPerformBackup(
            forceManual: true,
            onProgress: (p) => updateProgress(p, ''),
          );
          await _loadBackupInfo();
        },
      ),
    );
  }

  List<String> _restoreLogs = [];
  StateSetter? _dialogStateSetter;

  void _addRestoreLog(String message) {
    debugPrint(message);
    if (mounted) {
      setState(() {
        _restoreLogs.add(message);
      });
      _dialogStateSetter?.call(() {});
    }
  }

  String _mapDriveError(Object e) {
    if (e is drive.DetailedApiRequestError) {
      if (e.status == 401) {
        return 'Access denied: Google Drive authentication has expired or is invalid. Please reconnect your account.';
      } else if (e.status == 403) {
        return 'Access denied: Insufficient permissions to access the backup file on Google Drive.';
      } else if (e.status == 404) {
        return 'Backup not found: The backup file does not exist on Google Drive.';
      }
      return 'Google Drive API Error (${e.status}): ${e.message}';
    }
    final errorStr = e.toString();
    if (errorStr.contains('401') || errorStr.contains('auth') || errorStr.contains('token')) {
      return 'Access denied: Google Drive authentication is invalid or expired. Please disconnect and reconnect your account.';
    }
    if (errorStr.contains('403') || errorStr.contains('permission')) {
      return 'Access denied: Permission denied when accessing Google Drive.';
    }
    if (errorStr.contains('404')) {
      return 'Backup not found: The backup file does not exist on Google Drive.';
    }
    return errorStr;
  }

  String _cleanErrorMessage(String errorMsg) {
    if (errorMsg.startsWith('Exception: ')) {
      return errorMsg.substring('Exception: '.length);
    }
    return errorMsg;
  }

  Future<void> _clearStaleGDriveMetadata() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('google_drive_excel_backup_file_id');
    await prefs.remove('google_drive_excel_backup_file_name');
    await prefs.remove('google_drive_excel_backup_timestamp');
    await prefs.remove('google_drive_excel_backup_metadata_json');
    await prefs.remove('last_gdrive_backup_date');
    await prefs.remove('last_gdrive_backup_size');
    await prefs.remove('last_gdrive_backup_health');
    await prefs.remove('last_successful_backup_checksum');
    await _loadBackupInfo();
  }

  /// Downloads the single Excel file, validates it, and shows a premium restore preview dialog.
  Future<void> _initiateGDriveExcelRestore() async {
    File? tempFile;
    drive.File? fileMetadata;
    Map<String, int>? previewData;
    String? sizeString;
    DateTime? backupTime;
    bool success = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ProgressDialog(
        title: 'Downloading Backup',
        successMessage: '✓ Download Completed',
        errorMessage: 'Download Failed',
        action: (updateProgress) async {
          updateProgress(0.1, '');
          final connected = await _driveService.isConnected();
          if (!connected) {
            throw Exception('Access denied: Google Drive is not connected.');
          }

          updateProgress(0.2, '');
          final authClient = await _driveService.getAuthClient();
          final driveApi = drive.DriveApi(authClient);

          updateProgress(0.3, '');
          final folderId = await _driveService.findOrCreateBackupsFolder(driveApi);

          final prefs = await SharedPreferences.getInstance();
          String? storedFileId = prefs.getString('google_drive_excel_backup_file_id');

          if (storedFileId != null && storedFileId.isNotEmpty) {
            updateProgress(0.4, '');
            try {
              final fetchedFile = await driveApi.files.get(
                storedFileId,
                $fields: 'id, name, size, createdTime, parents, trashed',
              ) as drive.File;
              if (fetchedFile.parents != null && fetchedFile.parents!.contains(folderId) && fetchedFile.trashed != true) {
                fileMetadata = fetchedFile;
              }
            } catch (_) {}
          }

          if (fileMetadata == null) {
            updateProgress(0.5, '');
            final listResult = await driveApi.files.list(
              q: "'$folderId' in parents and trashed = false",
              spaces: 'drive',
              $fields: 'files(id, name, size, createdTime)',
            );
            final files = listResult.files ?? [];
            for (final f in files) {
              if (f.name == 'credits_backup.xlsx') {
                fileMetadata = f;
                break;
              }
            }
            if (fileMetadata == null) {
              await _clearStaleGDriveMetadata();
              throw Exception('Backup not found: No persistent Excel backup file exists on Google Drive.');
            }
          }

          final actualFileId = fileMetadata!.id!;
          if (storedFileId != actualFileId) {
            await prefs.setString('google_drive_excel_backup_file_id', actualFileId);
          }

          updateProgress(0.6, '');
          await driveApi.files.get(actualFileId);

          final bytes = await _driveService.downloadBackup(
            actualFileId,
            onProgress: (p) => updateProgress(0.6 + p * 0.2, ''),
          );

          updateProgress(0.8, '');
          final tempDir = await getTemporaryDirectory();
          tempFile = File('${tempDir.path}/restore_temp.xlsx');
          await tempFile!.writeAsBytes(bytes, flush: true);

          updateProgress(0.9, '');
          final isValid = await _validateRestoreWorkbook(tempFile!);
          if (!isValid) {
            throw Exception('Corrupted Excel file: Workbook validation failed.');
          }

          previewData = await ExcelBackupService.previewImport(tempFile!.path);
          sizeString = _formatSize(tempFile!.lengthSync());
          backupTime = fileMetadata!.createdTime != null
              ? DateTime.parse(fileMetadata!.createdTime.toString()).toLocal()
              : DateTime.now();
          success = true;
          updateProgress(1.0, '');
        },
      ),
    );

    if (success && tempFile != null && previewData != null && sizeString != null && backupTime != null && mounted) {
      _showGDriveExcelRestorePreviewDialog(tempFile!.path, previewData!, sizeString!, backupTime!);
    }
  }

  String _formatSize(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB'];
    double size = bytes.toDouble();
    int suffixIndex = 0;
    while (size >= 1024 && suffixIndex < suffixes.length - 1) {
      size /= 1024;
      suffixIndex++;
    }
    return '${size.toStringAsFixed(1)} ${suffixes[suffixIndex]}';
  }

  /// Strict workbook format validator prior to import
  Future<bool> _validateRestoreWorkbook(File file) async {
    try {
      if (!await file.exists()) {
        debugPrint('[Restore] Validation failed: file does not exist.');
        return false;
      }
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        debugPrint('[Restore] Validation failed: file bytes are empty.');
        return false;
      }
      final excel = Excel.decodeBytes(bytes);
      if (excel.tables.isEmpty) {
        debugPrint('[Restore] Validation failed: Excel tables are empty.');
        return false;
      }
      final requiredSheets = ['borrowers', 'loans', 'payments', 'expenses', 'investments'];
      final tableKeysLower = excel.tables.keys.map((k) => k.toLowerCase()).toList();
      for (final sheet in requiredSheets) {
        if (!tableKeysLower.contains(sheet)) {
          debugPrint('[Restore] Validation failed: Missing required sheet "$sheet".');
          return false;
        }
      }
      return true;
    } catch (e) {
      debugPrint('[Restore] Workbook validation failed: $e');
      return false;
    }
  }

  /// Shows the premium modal preview dialog from Drive Excel file with Merge or Replace choices.
  void _showGDriveExcelRestorePreviewDialog(String tempPath, Map<String, int> preview, String sizeStr, DateTime timestamp) {
    final fmt = NumberFormat('#,##0');
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(LucideIcons.fileSpreadsheet, color: Colors.white),
            SizedBox(width: 12),
            Text('Cloud Restore Preview'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Restore',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
            ),
            const SizedBox(height: 8),
            Text('Last Backup: ${DateFormat('dd MMM yyyy, hh:mm a').format(timestamp)}', style: const TextStyle(fontSize: 12)),
            Text('Backup Size: $sizeStr', style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity( 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  _previewRow(LucideIcons.users, 'Borrowers', fmt.format(preview['borrowers'] ?? 0), AppColors.accent),
                  const SizedBox(height: 8),
                  _previewRow(LucideIcons.creditCard, 'Loans', fmt.format(preview['loans'] ?? 0), AppColors.info),
                  const SizedBox(height: 8),
                  _previewRow(LucideIcons.wallet, 'Payments', fmt.format(preview['payments'] ?? 0), AppColors.success),
                  const SizedBox(height: 8),
                  _previewRow(LucideIcons.receipt, 'Expenses', fmt.format(preview['expenses'] ?? 0), AppColors.warning),
                  const SizedBox(height: 8),
                  _previewRow(LucideIcons.trendingUp, 'Investments', fmt.format(preview['investments'] ?? 0), AppColors.secondary),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Text('Choose restore mode:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 4),
            const Text(
              'Merge: Adds new records and updates existing safely without wiping.\nReplace: Wipes existing local data and restores a fresh state.',
              style: TextStyle(fontSize: 11, height: 1.4),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              File(tempPath).delete().catchError((_) => File(tempPath));
            }, 
            child: const Text('Cancel')
          ),
          OutlinedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _executeGDriveExcelRestore(tempPath, merge: true);
            },
            child: const Text('Merge Restore'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _confirmGDriveExcelReplace(tempPath);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Replace Local DB'),
          ),
        ],
      ),
    );
  }

  void _confirmGDriveExcelReplace(String tempPath) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(LucideIcons.alertTriangle, color: AppColors.error),
            SizedBox(width: 12),
            Text('Wipe & Replace Database?'),
          ],
        ),
        content: const Text(
          'This will permanently delete ALL local borrowers, loans, payments, expenses, and investments, replacing them with the cloud backup.\n\nThis action CANNOT be undone. Are you sure?',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              File(tempPath).delete().catchError((_) => File(tempPath));
            }, 
            child: const Text('Cancel')
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _executeGDriveExcelRestore(tempPath, merge: false);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Replace Data'),
          ),
        ],
      ),
    );
  }

  /// Performs the actual transaction restore from Excel workbook and shows a scrolling log dialog.
  Future<void> _executeGDriveExcelRestore(String tempPath, {required bool merge}) async {
    final tempFile = File(tempPath);
    Map<String, int>? previewData;
    bool success = false;
    
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ProgressDialog(
        title: 'Restoring Backup',
        successMessage: '✓ Restore Completed',
        errorMessage: 'Restore Failed',
        action: (updateProgress) async {
          final preview = await ExcelBackupService.previewImport(tempPath);
          previewData = preview;
          
          await ExcelBackupService.importBackup(
            tempPath,
            merge: merge,
            onProgress: (p) => updateProgress(p, ''),
          );
          
          if (mounted) {
            await Provider.of<LoanProvider>(context, listen: false).loadBorrowers();
          }
          success = true;
        },
      ),
    );
    
    if (await tempFile.exists()) {
      try {
        await tempFile.delete();
      } catch (_) {}
    }
    
    if (success && previewData != null && mounted) {
      _showRestoreSuccessExcelDialog(previewData!, merge);
    }
  }

  void _showRestoreSuccessExcelDialog(Map<String, int> preview, bool merge) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(LucideIcons.checkCircle, color: Colors.white),
            SizedBox(width: 12),
            Text('Restore Successful!'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(merge 
                ? 'Your local database was successfully merged with the cloud backup.'
                : 'Your local database has been fully replaced with the cloud backup.'
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity( 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  _previewRow(LucideIcons.users, 'Borrowers', (preview['borrowers'] ?? 0).toString(), AppColors.accent),
                  const SizedBox(height: 8),
                  _previewRow(LucideIcons.creditCard, 'Loans', (preview['loans'] ?? 0).toString(), AppColors.info),
                  const SizedBox(height: 8),
                  _previewRow(LucideIcons.wallet, 'Payments', (preview['payments'] ?? 0).toString(), AppColors.success),
                  const SizedBox(height: 8),
                  _previewRow(LucideIcons.receipt, 'Expenses', (preview['expenses'] ?? 0).toString(), AppColors.warning),
                  const SizedBox(height: 8),
                  _previewRow(LucideIcons.trendingUp, 'Investments', (preview['investments'] ?? 0).toString(), AppColors.secondary),
                ],
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Awesome!'),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // PORTABLE EXCEL IMPORT/EXPORT ACTIONS
  // ==========================================

  Future<void> _exportExcelBackup() async {
    String? exportedPath;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ProgressDialog(
        title: 'Export',
        successMessage: '✓ Export Completed',
        errorMessage: 'Export Failed',
        action: (updateProgress) async {
          final path = await ExcelBackupService.exportFullBackup(
            onProgress: (p) => updateProgress(p, ''),
          );
          exportedPath = path;
          
          final prefs = await SharedPreferences.getInstance();
          final now = DateTime.now().toIso8601String();
          await prefs.setString('last_excel_backup_date', now);
          await prefs.setString('last_excel_backup_path', path);
          
          if (mounted) {
            setState(() {
              _lastExcelBackupDate = now;
            });
          }
        },
      ),
    );
    
    if (exportedPath != null && mounted) {
      _showExportSuccessDialog(exportedPath!);
    }
  }

  Future<void> _pickAndImportExcel() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      dialogTitle: 'Select Excel Backup File',
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.first.path;
    if (path == null) return;

    setState(() => _isImporting = true);
    try {
      final preview = await ExcelBackupService.previewImport(path);
      if (mounted) {
        setState(() => _isImporting = false);
        _showExcelImportPreviewDialog(path, preview);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isImporting = false);
        _showErrorSnackbar('Invalid Excel file: $e');
      }
    }
  }

  void _showExcelImportPreviewDialog(String path, Map<String, int> preview) {
    final fmt = NumberFormat('#,##0');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(LucideIcons.fileSpreadsheet, color: Colors.white),
            SizedBox(width: 12),
            Text('Excel Import Preview'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity( 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  _previewRow(LucideIcons.users, 'Borrowers', fmt.format(preview['borrowers'] ?? 0), AppColors.accent),
                  const SizedBox(height: 8),
                  _previewRow(LucideIcons.creditCard, 'Loans', fmt.format(preview['loans'] ?? 0), AppColors.info),
                  const SizedBox(height: 8),
                  _previewRow(LucideIcons.wallet, 'Payments', fmt.format(preview['payments'] ?? 0), AppColors.success),
                  const SizedBox(height: 8),
                  _previewRow(LucideIcons.receipt, 'Expenses', fmt.format(preview['expenses'] ?? 0), AppColors.warning),
                  const SizedBox(height: 8),
                  _previewRow(LucideIcons.trendingUp, 'Investments', fmt.format(preview['investments'] ?? 0), AppColors.secondary),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Text('Choose import mode:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 4),
            const Text(
              'Merge: Adds new records, updates existing (safe).\nReplace: Wipes your local data and imports fresh.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          OutlinedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _confirmExcelImport(path, merge: true);
            },
            child: const Text('Merge'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _confirmExcelImport(path, merge: false);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Replace'),
          ),
        ],
      ),
    );
  }

  void _confirmExcelImport(String path, {required bool merge}) {
    if (!merge) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(LucideIcons.alertTriangle, color: AppColors.error),
              SizedBox(width: 12),
              Text('Replace Local Data?'),
            ],
          ),
          content: const Text(
            'This will permanently delete your current local data and replace it with the Excel backup. '
            'This action cannot be undone.\n\nAre you sure?',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                _doExcelImport(path, merge: false);
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
              child: const Text('Replace'),
            ),
          ],
        ),
      );
    } else {
      _doExcelImport(path, merge: true);
    }
  }

  Future<void> _doExcelImport(String path, {required bool merge}) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ProgressDialog(
        title: 'Import',
        successMessage: '✓ Import Completed',
        errorMessage: 'Import Failed',
        action: (updateProgress) async {
          await ExcelBackupService.importBackup(
            path,
            merge: merge,
            onProgress: (p) => updateProgress(p, ''),
          );
          
          if (mounted) {
            await context.read<LoanProvider>().loadBorrowers();
          }
        },
      ),
    );
  }

  void _showExportSuccessDialog(String path) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(LucideIcons.checkCircle, color: Colors.white),
            SizedBox(width: 12),
            Text('Backup Saved!'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Your portable Excel report has been exported.'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity( 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(LucideIcons.fileSpreadsheet, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      File(path).uri.pathSegments.last,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Text('Location: Downloads/LoanReports/', style: TextStyle(fontSize: 12, color: AppColors.textTertiary)),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Great!'),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // SHARED UI ELEMENTS
  // ==========================================

  Widget _previewRow(IconData icon, String label, String value, Color color) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
        Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }

  void _showSuccessSnackbar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: AppColors.success));
  }

  void _showErrorSnackbar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: AppColors.error));
  }

  String _formatDate(String? isoDate) {
    if (isoDate == null || isoDate.isEmpty) return 'Never';
    final dt = DateParser.safeParse(isoDate);
    return DateFormat('dd MMM yyyy, hh:mm a').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final onSurfaceVariant = Theme.of(context).colorScheme.onSurfaceVariant;
    
    final isGlobalLoading = _isExporting || _isImporting || _isDriveLoading || _isDriveSyncing;

    return ValueListenableBuilder<bool>(
      valueListenable: BackupFreshnessService.isReadOnlyMode,
      builder: (context, isReadOnly, _) {
        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          appBar: AppBar(
            title: const Text('Backup & Restore'),
            leading: IconButton(
              icon: const Icon(LucideIcons.arrowLeft),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          body: Stack(
            children: [
              ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
                children: [
                  if (isReadOnly || _areBackupsBlocked) ...[
                    Padding(
                      padding: const EdgeInsets.only(bottom: 20),
                      child: PremiumCard(
                        color: isReadOnly ? AppColors.warning.withOpacity(0.1) : AppColors.error.withOpacity(0.1),
                        border: Border.all(
                          color: isReadOnly ? AppColors.warning.withOpacity(0.3) : AppColors.error.withOpacity(0.3),
                        ),
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Icon(
                              isReadOnly ? LucideIcons.wifiOff : LucideIcons.cloudOff,
                              color: isReadOnly ? AppColors.warning : AppColors.error,
                              size: 24,
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    isReadOnly ? "Read Only Mode" : "Backups Suspended",
                                    style: TextStyle(
                                      color: isReadOnly ? AppColors.warning : AppColors.error,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    isReadOnly
                                        ? "Internet Required"
                                        : "A newer backup is available. Please restore to continue.",
                                    style: TextStyle(
                                      color: onSurfaceVariant.withOpacity(0.8),
                                      fontSize: 12,
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
              // ==========================================
              // 1. PREMIUM GOOGLE DRIVE BACKUP CARD
              // ==========================================
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 12),
                child: Text('Cloud Backup', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: onSurfaceVariant)),
              ),
              PremiumCard(
                padding: const EdgeInsets.all(20),
                gradient: Theme.of(context).brightness == Brightness.dark
                    ? AppColors.surfaceGradientDark
                    : AppColors.surfaceGradient,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(colors: [Color(0xFF4285F4), Color(0xFF34A853)]),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(LucideIcons.cloud, color: Colors.white, size: 24),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Backup', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                              const SizedBox(height: 2),
                              Text(
                                _isDriveConnected && _driveEmail != null
                                    ? _driveEmail!
                                    : 'Not Connected',
                                style: TextStyle(color: onSurfaceVariant.withOpacity( 0.8), fontSize: 12),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        _isDriveConnected
                            ? Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity( 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  'Connected',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              )
                            : Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: AppColors.error.withOpacity( 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  'Not Connected',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.error,
                                  ),
                                ),
                              ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Divider(height: 1),
                    const SizedBox(height: 16),
                    
                    if (_isDriveConnected) ...[
                      // Cloud sync parameters
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Last Backup', style: TextStyle(fontSize: 12, color: onSurfaceVariant.withOpacity( 0.6))),
                              const SizedBox(height: 2),
                              Text(_formatDate(_lastGDriveBackupDate), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('Backup Size', style: TextStyle(fontSize: 12, color: onSurfaceVariant.withOpacity( 0.6))),
                              const SizedBox(height: 2),
                              Text(_lastGDriveBackupSize ?? 'N/A', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Icon(LucideIcons.shieldCheck, size: 14, color: Colors.white),
                           const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _lastGDriveBackupHealth ?? 'Health: N/A',
                              style: const TextStyle(fontSize: 11, color: AppColors.textTertiary),
                            ),
                          ),
                        ],
                      ),
                      
                      // Settings are backed up and status is shown in indicator above
 
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: (isGlobalLoading || isReadOnly || _areBackupsBlocked) ? null : _triggerManualGDriveBackup,
                              icon: const Icon(LucideIcons.refreshCw, size: 16),
                              label: const Text('Backup Now'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Theme.of(context).colorScheme.primary,
                                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: isGlobalLoading ? null : _initiateGDriveExcelRestore,
                              icon: const Icon(LucideIcons.downloadCloud, size: 16),
                              label: const Text('Restore'),
                              style: OutlinedButton.styleFrom(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: TextButton.icon(
                          onPressed: isGlobalLoading ? null : _disconnectGoogleDrive,
                          icon: const Icon(LucideIcons.logOut, size: 14),
                          label: const Text('Disconnect', style: TextStyle(fontSize: 12)),
                          style: TextButton.styleFrom(foregroundColor: AppColors.error),
                        ),
                      ),
                    ] else ...[
                      // Disconnected state
                      Text(
                        'Backup data to cloud storage. Backups are encrypted for privacy.',
                        style: TextStyle(fontSize: 12, height: 1.5, color: onSurfaceVariant.withOpacity( 0.8)),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: isGlobalLoading ? null : _connectGoogleDrive,
                          icon: const Icon(LucideIcons.logIn, size: 18),
                          label: const Text('Connect', style: TextStyle(fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(context).colorScheme.primary,
                            foregroundColor: Theme.of(context).colorScheme.onPrimary,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.05, end: 0),
 
              const SizedBox(height: 28),
 
              // ==========================================
              // 2. EXCEL PORTABLE BACKUP CARD
              // ==========================================
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 12),
                child: Text('Local Backup', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: onSurfaceVariant)),
              ),
              PremiumCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      leading: _isExporting
                          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(LucideIcons.fileSpreadsheet, color: Colors.white),
                      title: Text('Export', style: TextStyle(fontWeight: FontWeight.bold, color: onSurface)),
                      subtitle: Text(
                        'Export data to device storage.',
                        style: TextStyle(color: onSurfaceVariant.withOpacity( 0.7), fontSize: 12),
                      ),
                      trailing: _isExporting
                          ? null
                          : Icon(LucideIcons.chevronRight, size: 18, color: onSurfaceVariant.withOpacity( 0.5)),
                      onTap: (isGlobalLoading || isReadOnly || _areBackupsBlocked) ? null : _exportExcelBackup,
                    ),
                    Divider(height: 1, color: Theme.of(context).dividerColor.withOpacity( 0.1)),
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      leading: _isImporting
                          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.info))
                          : const Icon(LucideIcons.uploadCloud, color: AppColors.info),
                      title: Text('Import', style: TextStyle(fontWeight: FontWeight.bold, color: onSurface)),
                      subtitle: Text(
                        'Import data from device storage.',
                        style: TextStyle(color: onSurfaceVariant.withOpacity( 0.7), fontSize: 12),
                      ),
                      trailing: _isImporting
                          ? null
                          : Icon(LucideIcons.chevronRight, size: 18, color: onSurfaceVariant.withOpacity( 0.5)),
                      onTap: isGlobalLoading ? null : _pickAndImportExcel,
                    ),
                  ],
                ),
              ).animate().fadeIn(duration: 400.ms, delay: 100.ms).slideY(begin: 0.05, end: 0),
 
              if (_lastExcelBackupDate != null) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    'Last Backup: ${_formatDate(_lastExcelBackupDate)}',
                    style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity( 0.6)),
                  ),
                ),
              ],
 
              const SizedBox(height: 28),
 
              // ==========================================
              // 3. SECURITY & PRIVACY NOTE
              // ==========================================
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
                child: Center(
                  child: Text(
                    'All backups are encrypted and stored securely.',
                    style: TextStyle(fontSize: 11, color: onSurfaceVariant.withOpacity(0.5)),
                  ),
                ),
              ),
                ],
              ),
          // Global loading spinner overlays
          if (isGlobalLoading)
            Container(
              color: Colors.black.withOpacity( 0.25),
              child: Center(
                child: PremiumCard(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: Colors.white),
                      const SizedBox(height: 16),
                      Text(
                        _isExporting
                            ? 'Exporting...'
                            : _isImporting
                                ? 'Importing...'
                                : _isDriveSyncing
                                    ? 'Backing up...'
                                    : 'Restoring...',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            ],
          ),
        );
      },
    );
  }

  Widget _infoRow(String emoji, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12, color: AppColors.textTertiary))),
        ],
      ),
    );
  }
}

