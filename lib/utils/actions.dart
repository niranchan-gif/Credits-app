import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';

Future<void> openSavedFile(
  String path, {
  ScaffoldMessengerState? messenger,
}) async {
  final result = await OpenFilex.open(path);
  if (result.type != ResultType.done) {
    messenger?.showSnackBar(SnackBar(
      content: Text('Could not open file: ${result.message}'),
      backgroundColor: Colors.redAccent,
    ));
  }
}

void showOpenFileSnackBar({
  required ScaffoldMessengerState messenger,
  required String path,
  String label = 'Downloaded successfully',
}) {
  messenger.showSnackBar(SnackBar(
    behavior: SnackBarBehavior.floating,
    margin: const EdgeInsets.all(14),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    content: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => openSavedFile(path, messenger: messenger),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: const BoxDecoration(
              color: Colors.white24,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check, color: Colors.white, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: Colors.white),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Tap OPEN to view the file',
                  style: TextStyle(fontSize: 11.5, color: Colors.white70),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
    action: SnackBarAction(
      label: 'OPEN',
      textColor: Colors.amberAccent,
      onPressed: () => openSavedFile(path, messenger: messenger),
    ),
    backgroundColor: const Color(0xFF059669),
    duration: const Duration(seconds: 8),
  ));
}

Future<void> openPhoneDialer(
  String phone, {
  required ScaffoldMessengerState messenger,
}) async {
  final cleaned = phone.replaceAll(RegExp(r'\s+'), '');
  final uri = Uri(scheme: 'tel', path: cleaned);

  if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
    messenger.showSnackBar(const SnackBar(
      content: Text('Could not open phone dialer.'),
      backgroundColor: Colors.redAccent,
    ));
  }
}

