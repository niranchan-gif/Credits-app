import os
import re

path = r'd:\vscode\credit\lib\services\borrower_pdf_service.dart'

with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

# Add OverflowBox to prevent device screen constraints from squishing the layout
content = content.replace(
    'return Directionality(',
    'return OverflowBox(\n      maxWidth: _pageWidth,\n      maxHeight: _pageHeight,\n      child: Directionality('
)
content = content.replace(
    '      ), // child: Container\n    ); // Directionality',
    '      ),\n    ));'
)
# Wait, let's just do it cleanly by replacing the whole _buildPageWidget return statement.

new_build_page = """  static Widget _buildPageWidget({
    required Borrower borrower,
    required List<Map<String, dynamic>> pagePayments,
    required double totalPaid,
    required double balanceToPay,
    required bool isFirstPage,
    required int pageIndex,
    required int totalPages,
  }) {
    final todayStr = DateFormat('dd-MM-yyyy').format(DateTime.now());

    // OverflowBox ensures the widget is rendered exactly at 800x1131, 
    // overriding any mobile screen constraints that would otherwise squish it.
    return OverflowBox(
      maxWidth: _pageWidth,
      maxHeight: _pageHeight,
      minWidth: _pageWidth,
      minHeight: _pageHeight,
      child: Directionality(
        textDirection: ui.TextDirection.ltr,
        child: Container(
          width: _pageWidth,
          height: _pageHeight,
          color: _bg,
          child: DefaultTextStyle(
            style: const TextStyle(fontFamily: 'Roboto', color: _textDark), // Premium font rendering
            child: Column(
              children: [
                // Top Dark Green Strip
                Container(height: 12, color: _brand),
                
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 30),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Header Row
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

                        if (isFirstPage) ...[
                          // Borrower Details Box
                          _buildBorrowerDetails(borrower, totalPaid, balanceToPay),
                          const SizedBox(height: 32),
                          
                          const Text(
                            'கட்டண விவரம்',
                            style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: _textDark),
                          ),
                          const SizedBox(height: 16),
                        ],

                        // Payment Table
                        _buildPaymentTable(pagePayments),
                        
                        const Spacer(),
                        
                        if (totalPages > 1) ...[
                           const Divider(color: _divider, thickness: 2),
                           const SizedBox(height: 10),
                           Center(
                             child: Text(
                               'Page ${pageIndex + 1} of $totalPages', 
                               style: const TextStyle(color: Colors.grey, fontSize: 18)
                             )
                           ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }"""

# Extract the existing _buildPageWidget and replace it
import re
pattern = r'static Widget _buildPageWidget\(\{.*?return Directionality\([\s\S]*?;\n  \}'
content = re.sub(pattern, new_build_page, content, flags=re.DOTALL)

# Adjust font sizes in details for the premium look (slightly smaller than before so they fit nicely)
content = content.replace('fontSize: 26, fontWeight: FontWeight.bold', 'fontSize: 28, fontWeight: FontWeight.bold') # Name
content = content.replace('fontSize: 20', 'fontSize: 22') # Phone, cell texts

# Table logic
# We removed S.No, but the headers were: 'தேதி', 'தொகை (₹)'
# Let's adjust flex to make it look nicer: flex: 1 and flex: 1 is fine.

with open(path, 'w', encoding='utf-8') as f:
    f.write(content)
