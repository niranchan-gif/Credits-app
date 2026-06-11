import 'package:intl/intl.dart';

/// Indian-locale currency formatter — e.g. ₹1,00,000
final _inrFmt = NumberFormat.currency(
  locale: 'en_IN',
  symbol: '₹',
  decimalDigits: 0,
);

/// Format a [double] as Indian Rupees with commas, no decimals.
/// e.g. fmtINR(100000) → "₹1,00,000"
String fmtINR(double amount) => _inrFmt.format(amount);

