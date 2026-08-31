import os
import re

path = r'd:\vscode\credit\lib\screens\borrower_loans_screen.dart'
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

end_str = 'icon: const Icon(LucideIcons.share2, color: AppColors.accent, size: 20),'
end_idx = content.find(end_str)
if end_idx == -1:
    print('End not found')
    exit()

start_str = 'IconButton(\n                  onPressed: () async {\n                    final messenger = ScaffoldMessenger.of(context);\n                    final provider = context.read<LoanProvider>();'
start_idx = content.rfind(start_str, 0, end_idx)
if start_idx == -1:
    print('Start not found')
    exit()

old_block = content[start_idx:end_idx + len(end_str)]

new_block = r"""IconButton(
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    final provider = context.read<LoanProvider>();
                    final allBorrowerLoans = await provider.getLoans(b.id ?? 0);
                    
                    if (allBorrowerLoans.isEmpty) {
                      messenger.showSnackBar(const SnackBar(content: Text('No loans available to share.')));
                      return;
                    }

                    List<Loan>? targetLoans = allBorrowerLoans;

                    if (allBorrowerLoans.length > 1) {
                      targetLoans = await showDialog<List<Loan>>(
                        context: context,
                        builder: (BuildContext context) {
                          return AlertDialog(
                            title: const Text('Select Loan to Share', style: TextStyle(fontWeight: FontWeight.bold)),
                            backgroundColor: Theme.of(context).colorScheme.surface,
                            content: SizedBox(
                              width: double.maxFinite,
                              child: ListView.builder(
                                shrinkWrap: true,
                                itemCount: allBorrowerLoans.length + 1,
                                itemBuilder: (context, index) {
                                  if (index == 0) {
                                    return ListTile(
                                      leading: const Icon(LucideIcons.copyAll, color: AppColors.accent),
                                      title: const Text('All Loans (Combined)', style: TextStyle(fontWeight: FontWeight.bold)),
                                      onTap: () => Navigator.of(context).pop(allBorrowerLoans),
                                    );
                                  }
                                  final loan = allBorrowerLoans[index - 1];
                                  final dateStr = DateFormat('dd MMM yyyy').format(loan.loanDate);
                                  return ListTile(
                                    leading: const Icon(LucideIcons.fileText, color: AppColors.accentLight),
                                    title: Text('Loan - $dateStr'),
                                    subtitle: Text('₹${loan.loanAmount.toStringAsFixed(0)}'),
                                    onTap: () => Navigator.of(context).pop([loan]),
                                  );
                                },
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(context).pop(null),
                                child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
                              ),
                            ],
                          );
                        },
                      );
                      
                      if (targetLoans == null) return; // User canceled
                    }

                    double loanAmount = 0.0;
                    double totalPaid = 0.0;
                    final List<Map<String, dynamic>> allPayments = [];

                    for (final loan in targetLoans) {
                      loanAmount += loan.loanAmount;
                      final payments = await provider.getPayments(loan.id ?? 0);
                      for (final p in payments) {
                        totalPaid += p.amount;
                        allPayments.add({
                          'date': p.paymentDate,
                          'amount': p.amount,
                        });
                      }
                    }

                    // 2. Sort payments by date ascending
                    allPayments.sort((a, b) => (a['date'] as DateTime).compareTo(b['date'] as DateTime));

                    // 3. Generate payment history string
                    double balanceToPay = 0.0;
                    if (targetLoans.length == 1) {
                      balanceToPay = targetLoans.first.balanceAmount ?? (loanAmount - totalPaid);
                    } else {
                      balanceToPay = (b.totalBalance as num?)?.toDouble() ?? (loanAmount - totalPaid);
                    }
                    
                    final todayStr = DateFormat('dd-MM-yyyy').format(DateTime.now());

                    try {
                      // Show loading snackbar
                      messenger.showSnackBar(
                        const SnackBar(content: Text('Generating PDF report...')),
                      );
                      
                      final pdfBytes = await BorrowerPdfService.generate(
                        context: context,
                        borrower: b,
                        totalPaid: totalPaid,
                        balanceToPay: balanceToPay,
                        allPayments: allPayments,
                      );

                      messenger.hideCurrentSnackBar();

                      // Save PDF only to temporary cache
                      final tempDir = await getTemporaryDirectory();
                      final filePath = '${tempDir.path}${Platform.pathSeparator}Report.pdf';
                      final file = File(filePath);
                      await file.writeAsBytes(pdfBytes);

                      // Format phone number for WhatsApp
                      String digits = b.phone.replaceAll(RegExp(r'\D'), '');
                      if (digits.length == 10) {
                        digits = '91$digits';
                      }

                      final summaryMsg =
                          'வணக்கம்,\n'
                          'பெயர்: ${b.name} (${b.displayBorrowerCode})\n'
                          'இதுவரை செலுத்திய தொகை: ₹${totalPaid.toStringAsFixed(0)}\\n'
                          'செலுத்த வேண்டிய தொகை: ₹${balanceToPay.toStringAsFixed(0)}\\n'
                          'உங்கள் கட்டண விபரங்கள் அடங்கிய ரசீது இத்துடன் இணைக்கப்பட்டுள்ளது.\n'
                          'தேதி: $todayStr\n'
                          'நன்றி';

                      if (Platform.isAndroid) {
                        bool nativeSuccess = false;
                        try {
                          await _whatsappChannel.invokeMethod('shareToWhatsApp', {
                            'filePath': filePath,
                            'phone': digits,
                            'text': summaryMsg,
                          });
                          nativeSuccess = true;
                        } on PlatformException catch (_) {
                          nativeSuccess = false;
                        }

                        if (!nativeSuccess) {
                          await SharePlus.instance.share(
                            ShareParams(
                              files: [XFile(filePath, mimeType: 'application/pdf')],
                              text: summaryMsg,
                              subject: 'கடன் அறிக்கை - ${b.name}',
                            ),
                          );
                        }
                      } else if (Platform.isIOS) {
                        await SharePlus.instance.share(
                          ShareParams(
                            files: [XFile(filePath, mimeType: 'application/pdf')],
                            text: summaryMsg,
                            subject: 'கடன் அறிக்கை - ${b.name}',
                          ),
                        );
                      } else {
                        final webUrl = 'https://web.whatsapp.com/send?phone=$digits&text=${Uri.encodeComponent(summaryMsg)}';
                        final uri = Uri.parse(webUrl);
                        if (await canLaunchUrl(uri)) {
                          await launchUrl(uri, mode: LaunchMode.externalApplication);
                        } else {
                          final fallbackUri = Uri.parse('https://wa.me/$digits?text=${Uri.encodeComponent(summaryMsg)}');
                          await launchUrl(fallbackUri, mode: LaunchMode.externalApplication);
                        }
                        if (Platform.isWindows) {
                          try {
                            await Process.run('powershell.exe', ['-NoProfile', '-Command', "Set-Clipboard -Path '" + filePath + "'"]);
                          } catch (_) {}
                          messenger.showSnackBar(
                            SnackBar(
                              behavior: SnackBarBehavior.floating,
                              backgroundColor: AppColors.accent,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              content: const Text(
                                'WhatsApp Web opened! Press Ctrl + V in the chat to attach & send the PDF.',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              duration: const Duration(seconds: 5),
                            ),
                          );
                        }
                      }
                    } catch (e) {
                      messenger.hideCurrentSnackBar();
                      messenger.showSnackBar(
                        SnackBar(content: Text('Failed to generate PDF: $e'), backgroundColor: AppColors.error),
                      );
                    }
                  },
                  icon: const Icon(LucideIcons.share2, color: AppColors.accent, size: 20),"""

content = content.replace(old_block, new_block)

with open(path, 'w', encoding='utf-8') as f:
    f.write(content)
print("Replaced successfully")
