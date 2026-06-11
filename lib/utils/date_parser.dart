import 'package:flutter/foundation.dart';

/// Centralized utility to safely parse dates from various formats (SQLite, Excel, Firestore)
/// without ever throwing format exceptions.
class DateParser {
  /// Safely parses a dynamic value into a DateTime object.
  /// Handles:
  /// - ISO8601, yyyy-MM-dd HH:mm:ss, yyyy-MM-dd
  /// - dd/MM/yyyy, dd/MM/yyyy HH:mm:ss
  /// - Excel serial numbers (doubles like 44230.5)
  /// - Epoch milliseconds/seconds
  /// - Firestore "Timestamp(seconds=..., nanoseconds=...)" strings
  /// - null or empty strings
  /// Returns a valid DateTime or the provided [fallback] (defaults to current time).
  static DateTime safeParse(dynamic value, {DateTime? fallback}) {
    final defaultFallback = fallback ?? DateTime.now();
    if (value == null) return defaultFallback;

    // 1. If it's already a DateTime
    if (value is DateTime) return value;

    // 2. If it's a number (Epoch or Excel serial double)
    if (value is num) {
      return _parseNum(value, defaultFallback);
    }

    // 3. String representations
    final strVal = value.toString().trim();
    if (strVal.isEmpty) return defaultFallback;

    // Try parsing as a raw number first (in case it is "44230.5" or Epoch in string form)
    final parsedNum = num.tryParse(strVal);
    if (parsedNum != null) {
      return _parseNum(parsedNum, defaultFallback);
    }

    try {
      // Direct ISO-8601 parsing
      final direct = DateTime.tryParse(strVal);
      if (direct != null) return direct;

      // Handle dd/MM/yyyy formats
      if (strVal.contains('/')) {
        final parts = strVal.split('/');
        if (parts.length >= 3) {
          final day = int.tryParse(parts[0]);
          final month = int.tryParse(parts[1]);
          final yearAndTime = parts[2].trim().split(RegExp(r'\s+'));
          final year = int.tryParse(yearAndTime[0]);
          if (day != null && month != null && year != null) {
            int hour = 0, minute = 0, second = 0;
            if (yearAndTime.length > 1) {
              final timeParts = yearAndTime[1].split(':');
              if (timeParts.isNotEmpty) hour = int.tryParse(timeParts[0]) ?? 0;
              if (timeParts.length > 1) minute = int.tryParse(timeParts[1]) ?? 0;
              if (timeParts.length > 2) second = int.tryParse(timeParts[2]) ?? 0;
            }
            return DateTime(year, month, day, hour, minute, second);
          }
        }
      }

      // Handle yyyy-M-d non-padded formats
      if (strVal.contains('-')) {
        final parts = strVal.split('-');
        if (parts.length >= 3) {
          final year = int.tryParse(parts[0]);
          final month = int.tryParse(parts[1]);
          final dayAndTime = parts[2].trim().split(RegExp(r'\s+'));
          final day = int.tryParse(dayAndTime[0]);
          if (year != null && month != null && day != null) {
            int hour = 0, minute = 0, second = 0;
            if (dayAndTime.length > 1) {
              final timeParts = dayAndTime[1].split(':');
              if (timeParts.isNotEmpty) hour = int.tryParse(timeParts[0]) ?? 0;
              if (timeParts.length > 1) minute = int.tryParse(timeParts[1]) ?? 0;
              if (timeParts.length > 2) second = int.tryParse(timeParts[2]) ?? 0;
            }
            return DateTime(year, month, day, hour, minute, second);
          }
        }
      }

      // Handle Firestore Timestamp serialization: Timestamp(seconds=1715833333, nanoseconds=0)
      final secMatch = RegExp(r'seconds=(\d+)').firstMatch(strVal);
      if (secMatch != null) {
        final sec = int.tryParse(secMatch.group(1) ?? '');
        if (sec != null) {
          return DateTime.fromMillisecondsSinceEpoch(sec * 1000);
        }
      }
    } catch (e) {
      debugPrint('DateParser ▶ Exception while parsing "$value": $e');
    }

    debugPrint('DateParser ▶ Invalid date detected: $value. Using fallback: $defaultFallback');
    return defaultFallback;
  }

  /// Helper to parse num representations (Excel double or epoch)
  static DateTime _parseNum(num val, DateTime fallback) {
    if (val > 1000000000) {
      // Unix epoch representation
      if (val > 1000000000000) {
        return DateTime.fromMillisecondsSinceEpoch(val.toInt());
      } else {
        return DateTime.fromMillisecondsSinceEpoch((val * 1000).toInt());
      }
    } else {
      // Excel serial date representation
      // Excel base date: Dec 30, 1899 (accounting for leap year bug in Excel base)
      final baseDate = DateTime(1899, 12, 30);
      final days = val.toDouble();
      final milliseconds = (days * 24 * 60 * 60 * 1000).round();
      return baseDate.add(Duration(milliseconds: milliseconds));
    }
  }
}

