# Firebase user/version monitoring setup

This is an optional monitoring layer. It reuses the Google account already connected through Credits' existing Google Drive sign-in. It does not add a second sign-in screen, replace Drive authentication, or change the existing backup/restore/local database flows.

## What is recorded

One document per Firebase user in `credits_app_users/{uid}` stores:
- Firebase UID and Google account email/display name
- Installed app version and build number
- Platform
- First-seen, last-seen, and updated timestamps

No borrower, loan, payment, backup, or local database contents are sent to Firebase. Monitoring is best-effort: failures are logged and ignored so the existing app flow can continue.

## Firebase Console setup

1. Create or select the Firebase project for Credits.
2. Add an Android app using the exact application ID from `android/app/build.gradle.kts` (currently `com.example.credit`).
3. In **Authentication → Sign-in method**, enable **Google**.
4. In **Firestore Database**, create the database.
5. Download that app's `google-services.json` and place it at `android/app/google-services.json`. Do not use a config file from a different Firebase project.
6. Run `flutter pub get`, then rebuild the app. The Google Services Gradle plugin is applied only when this config file exists, so an unconfigured checkout remains buildable with monitoring disabled.

## Firestore security rules

Set these rules in **Firestore Database → Rules**. They allow each signed-in user to write only their own monitoring document; app clients cannot list all users or read other users' documents. The project owner can inspect all documents in the Firebase Console.

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /credits_app_users/{uid} {
      allow create, update: if request.auth != null
        && request.auth.uid == uid
        && request.resource.data.uid == request.auth.uid
        && request.resource.data.keys().hasOnly([
          'uid',
          'email',
          'displayName',
          'provider',
          'appVersion',
          'buildNumber',
          'platform',
          'firstSeenAt',
          'lastSeenAt',
          'updatedAt',
          'createdAt'
        ]);
      allow read: if request.auth != null && request.auth.uid == uid;
      allow delete: if false;
    }
  }
}
```

These are new Firestore rules for the monitoring collection only; they do not modify any existing API/backend or Drive configuration. If this Firebase project already has Firestore rules for other collections, merge this match block into those rules rather than replacing unrelated rules.

## How it works

- At app startup, Credits tries to silently reuse the existing Google Drive account and update its Firebase user/version record.
- When the user completes the existing Drive sign-in screen, Credits records the account from that same sign-in.
- Firebase configuration or network failures do not prevent the user from entering Credits or using Google Drive.
- The existing GitHub `update.json` update-check behavior is unchanged.

The repository intentionally does not contain a Firebase project's config file. Until the Firebase Console setup above is completed, monitoring stays disabled.
