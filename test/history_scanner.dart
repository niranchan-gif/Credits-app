import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('Scan Local History for Today\'s Edits', () async {
    print('==================================================');
    print('VS CODE LOCAL HISTORY SCANNER');
    print('==================================================');

    final historyDir = Directory('C:\\Users\\gpk00\\AppData\\Roaming\\Code\\User\\History');
    if (!historyDir.existsSync()) {
      print('History directory not found!');
      return;
    }

    final todayStart = DateTime(2026, 6, 9).millisecondsSinceEpoch;
    print('Scanning edits since ${DateTime(2026, 6, 9)} (timestamp: $todayStart)');

    final List<Map<String, dynamic>> results = [];

    final subdirs = historyDir.listSync().whereType<Directory>();
    for (final dir in subdirs) {
      final entriesFile = File(p.join(dir.path, 'entries.json'));
      if (!entriesFile.existsSync()) continue;

      try {
        final content = entriesFile.readAsStringSync();
        final map = jsonDecode(content);
        final resource = map['resource'] as String?;
        if (resource == null) continue;

        // Decode URL encoding
        var decodedPath = Uri.decodeFull(resource);
        // Normalize paths (Windows style)
        decodedPath = decodedPath.replaceFirst('file:///', '').replaceAll('/', '\\');
        if (decodedPath.startsWith('d:\\vscode\\credit')) {
          final entries = map['entries'] as List<dynamic>? ?? [];
          final todayEntries = <Map<String, dynamic>>[];
          final priorEntries = <Map<String, dynamic>>[];

          for (final entry in entries) {
            final id = entry['id'] as String?;
            final timestamp = entry['timestamp'] as int?;
            if (id == null || timestamp == null) continue;

            final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
            final info = {
              'id': id,
              'timestamp': timestamp,
              'time': dt,
              'historyFile': File(p.join(dir.path, id)),
            };

            if (timestamp >= todayStart) {
              todayEntries.add(info);
            } else {
              priorEntries.add(info);
            }
          }

          if (todayEntries.isNotEmpty) {
            // Sort entries
            todayEntries.sort((a, b) => (a['timestamp'] as int).compareTo(b['timestamp'] as int));
            priorEntries.sort((a, b) => (a['timestamp'] as int).compareTo(b['timestamp'] as int));

            results.add({
              'filePath': decodedPath,
              'historyDir': dir.path,
              'todayEditsCount': todayEntries.length,
              'firstTodayEdit': todayEntries.first,
              'lastPriorEdit': priorEntries.isNotEmpty ? priorEntries.last : null,
              'allToday': todayEntries,
              'allPrior': priorEntries,
            });
          }
        }
      } catch (e) {
        // Skip invalid JSON or read errors
      }
    }

    print('\nFound ${results.length} files modified today:');
    for (final fileInfo in results) {
      print('\nFile: ${fileInfo['filePath']}');
      print('  History Folder: ${fileInfo['historyDir']}');
      print('  Today\'s Edits: ${fileInfo['todayEditsCount']}');
      
      final firstToday = fileInfo['firstTodayEdit'];
      print('  First Edit Today: ${firstToday['time']} (File ID: ${firstToday['id']})');

      final lastPrior = fileInfo['lastPriorEdit'];
      if (lastPrior != null) {
        print('  Last Edit Before Today: ${lastPrior['time']} (File ID: ${lastPrior['id']})');
      } else {
        print('  No edits found in history before today.');
      }
    }

    // Write results to a temporary JSON report for parsing later
    final reportFile = File(p.join(Directory.current.path, 'scratch', 'history_scan_report.json'));
    final reportData = results.map((r) => {
      'filePath': r['filePath'],
      'historyDir': r['historyDir'],
      'lastPriorEditId': r['lastPriorEdit']?['id'],
      'lastPriorEditPath': r['lastPriorEdit']?['historyFile']?.path,
      'lastPriorEditTime': r['lastPriorEdit']?['time']?.toIso8601String(),
      'firstTodayEditTime': r['firstTodayEdit']['time'].toIso8601String(),
    }).toList();

    reportFile.writeAsStringSync(jsonEncode(reportData));
    print('\nReport written to: ${reportFile.path}');
    print('==================================================');
  });
}
