# Credits — Loan Manager

A professional Flutter app for managing personal micro-lending.

## Features

- **Borrower Management** — Add, edit, and delete borrowers with unique codes
- **Multi-Loan Support** — Each borrower can have multiple active loans
- **Daily Collection Tracking** — Tabbed view: Collect / Paid / Completed
- **Swipe-to-Pay** — Quickly record payments by swiping a borrower card
- **Partial Payment Indicator** — Shows `X/Y` badge with amber colour when only some loans are paid today
- **Indian Currency Formatting** — All amounts displayed in ₹ Indian format
- **Reports Screen** — Global financial summary (Total Due, Collected, Pending, On-Hand)
- **Excel Export** — Export borrower and loan data to `.xlsx`
- **App Lock** — Biometric / PIN security via `local_auth` + `flutter_secure_storage`
- **Expense Tracking** — Deduct on-hand expenses with full history

## Tech Stack

- Flutter (Dart)
- SQLite (`sqflite`) — local database, no cloud dependency
- Provider — state management
- `local_auth` — biometric authentication
- `flutter_secure_storage` — secure PIN storage
- `excel` — Excel export

## Getting Started

```bash
flutter pub get
flutter run
```

> Requires Android SDK / Xcode for device deployment.
