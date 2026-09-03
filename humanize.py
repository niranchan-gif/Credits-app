import os

replacements = {
    # General Prompts & Warnings
    "Export failed:": "Oops! Couldn't export the report:",
    "Error:": "Something went wrong:",
    "Confirm Deletion": "Are you sure?",
    "This action cannot be undone.": "You won't be able to undo this later.",
    "Confirm Payment": "Save Payment",
    
    # Settings Screen
    "Developer Mode Enabled": "You're now a developer! 🛠️",
    "Clear Local Database": "Start Fresh (Clear Data)",
    "Factory Reset App": "Reset Everything",
    "This will permanently delete all local borrowers, loans, payments, expenses, and investments from this device.": "This will erase all your local records on this device. Be sure you have a backup!",
    "Wipes local DB and settings": "Erases everything and starts from scratch.",
    "Sign Out": "See you later!",
    "Deletes all local records permanently": "Say goodbye to all your records forever. There's no undo!",
    
    # Home & Navigation
    "Credits Dashboard": "Your Dashboard",
    "Backup Before Exit": "Wait, want to save before leaving?",
    "Exit Without Backup": "Leave without saving",
    "No borrowers found": "Looks like you haven't added anyone yet!",
    "Welcome back,": "Hey there,",
    "Today's Collection": "Collected Today",
    "Quick Add": "Quick Action",
    "Add Borrower": "New Borrower",
    
    # Backup & Restore
    "Choose import mode:": "How would you like to import?",
    "Replace Local Data?": "Replace all local data?",
    "Restore Successful!": "All done! Data restored.",
    "Awesome!": "Got it!",
    
    # Borrower & Loan Details
    "No loans found.\\nTap + to start a new loan.": "No loans here yet.\\nTap + to start one!",
    "Move to Inactive?": "Hide this borrower?",
    "Move to Active?": "Bring this borrower back?",
    "No payments recorded yet": "No payments recorded yet. Let's add one!",
    
    # Date Range & Reports
    "No transactions recorded in this period": "It's quiet... no transactions in this period.",
    "No deletable transactions in this period": "Nothing to delete here right now."
}

directory = 'd:/vscode/credit/lib'

for root, _, files in os.walk(directory):
    for file in files:
        if file.endswith('.dart'):
            path = os.path.join(root, file)
            with open(path, 'r', encoding='utf-8') as f:
                content = f.read()
            
            new_content = content
            for old_text, new_text in replacements.items():
                new_content = new_content.replace(old_text, new_text)
            
            if new_content != content:
                with open(path, 'w', encoding='utf-8') as f:
                    f.write(new_content)
                print(f'Updated {path}')
