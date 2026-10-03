import 'package:flutter/widgets.dart';

// IconData is final in modern Flutter SDKs.
// LucideIconData is provided as a utility helper.
class LucideIconData {
  static IconData create(int codePoint) => IconData(
        codePoint,
        fontFamily: 'Lucide',
        fontPackage: 'lucide_icons',
      );
}
