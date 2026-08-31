import re

path = r'd:\vscode\Credits-app\lib\screens\borrower_loans_screen.dart'
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

# Add import
content = content.replace("import '../services/backup_freshness_service.dart';", "import '../services/backup_freshness_service.dart';\nimport '../services/borrower_pdf_service.dart';")

# Replace function call
old_call = """                      final pdfBytes = await _buildFlawlessTamilPdf(
                        b: b,
                        totalPaid: totalPaid,
                        balanceToPay: balanceToPay,
                        todayStr: todayStr,
                        allPayments: allPayments,
                      );"""
                      
new_call = """                      final pdfBytes = await BorrowerPdfService.generate(
                        borrower: b,
                        totalPaid: totalPaid,
                        balanceToPay: balanceToPay,
                        todayStr: todayStr,
                        allPayments: allPayments,
                      );"""
                      
content = content.replace(old_call, new_call)

with open(path, 'w', encoding='utf-8') as f:
    f.write(content)
