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
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    content: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => openSavedFile(path, messenger: messenger),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 2),
          const Text('Tap OPEN to view the file',
              style: TextStyle(fontSize: 12)),
        ],
      ),
    ),
    action: SnackBarAction(
      label: 'OPEN',
      textColor: Colors.white,
      onPressed: () => openSavedFile(path, messenger: messenger),
    ),
    backgroundColor: Colors.green,
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

