import os
import re

path = r'd:\vscode\credit\lib\services\borrower_pdf_service.dart'

with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

# Update limits
content = content.replace('static const int _paymentsPerPageFirst = 12;', 'static const int _paymentsPerPageFirst = 9;')
content = content.replace('static const int _paymentsPerPageNext = 18;', 'static const int _paymentsPerPageNext = 14;')

# Remove header from subsequent pages
header_replacement = """                        // Header Row
                        if (isFirstPage) ...[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'STATEMENT',
                                style: TextStyle(color: _brand, fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 1.5),
                              ),
                              Text(
                                'தேதி: $todayStr',
                                style: const TextStyle(color: Color(0xFF475569), fontSize: 24, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                        ],"""

# The existing header is:
existing_header = """                        // Header Row
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'STATEMENT',
                              style: TextStyle(color: _brand, fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 1.5),
                            ),
                            Text(
                              'தேதி: $todayStr',
                              style: const TextStyle(color: Color(0xFF475569), fontSize: 24, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),"""

content = content.replace(existing_header, header_replacement)

with open(path, 'w', encoding='utf-8') as f:
    f.write(content)
