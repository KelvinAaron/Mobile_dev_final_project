# Finmo

Finmo is an Android-first personal finance application built with Flutter for
MTN Mobile Money users. It turns transaction SMS messages into a searchable,
categorized spending history, provides budget warnings, and backs local data up
to Firebase.


Demo video: [youtu.be/mouEgvzG3sU](https://youtu.be/mouEgvzG3sU)

## Features

- Email/password and Google authentication through Firebase Authentication
- Email verification gate with status refresh and resend controls
- Normalized local phone-number handling
- Automatic MTN Mobile Money SMS import on Android
- SQLite-first storage for fast offline access
- Firestore backup and restore, including manual and daily synchronization
- Transaction history with search, weekly/monthly filters, and cloud-aware delete
- Spending summaries by category and configurable budget limits
- Budget alerts when overall or category limits are exceeded
- Persistent light/dark appearance and default reporting period
- Send-money shortcut through the device dialer/USSD flow

## Architecture

The project separates UI, state, persistence, and external integrations:

```text
lib/
├── components/          Reusable UI and budget alert overlay
├── database/            SQLite schema and database lifecycle
├── screens/             Authentication, dashboard, history, spending, settings
├── services/            Firebase auth, SMS ingestion, and cloud synchronization
├── state/               Provider/ChangeNotifier root application state
├── styles/              Shared colors
├── utils/               SMS parsing, balance extraction, and budget calculations
├── firebase_options.dart
└── main.dart            Bootstrap, session flow, and dependency wiring
```

`AppState` is a `ChangeNotifier` supplied at the application root with Provider.
It owns the theme and reporting-period preferences and persists both with
SharedPreferences. Transaction data remains offline-first in SQLite.
`SyncService` mirrors records to user-scoped Firestore subcollections.

## Technology

- Flutter and Dart
- Provider / ChangeNotifier
- Firebase Core, Authentication, and Cloud Firestore
- Google Sign-In
- SQLite (`sqflite`)
- SharedPreferences
- Android SMS and phone permissions

## Prerequisites

- Flutter SDK compatible with Dart `^3.12.1`
- Android Studio or an Android SDK/device
- A Firebase project with Android app registration
- Firebase Authentication providers enabled:
  - Email/Password
  - Google
- A SHA-1 and SHA-256 fingerprint registered for the Android app in Firebase

The current Android application ID is `com.example.finmo`. It must match the
Android app registered in Firebase and the client entry in `google-services.json`.

## Firebase setup

1. Open Firebase Console and create or select the Finmo project.
2. Register an Android application with package name `com.example.finmo`.
3. Add the debug and release SHA-1/SHA-256 certificate fingerprints.
4. Enable Email/Password and Google in **Authentication → Sign-in method**.
5. Create a Cloud Firestore database.
6. Download `google-services.json` and place it at:

   ```text
   android/app/google-services.json
   ```
7. Confirm the Google Services Gradle plugin is enabled in the Android project.

Do not publish production Firebase credentials or unrestricted Firestore rules.
Use authenticated, user-scoped rules before release.

## Install and run

```bash
flutter doctor
flutter pub get
flutter run
```

Use a physical Android phone for the complete experience. SMS import and the
send-money shortcut are Android/device features and cannot be fully demonstrated
on every emulator.

On first launch:

1. Create an account or sign in.
2. For email/password registration, open the Firebase verification link and
   select **I've verified my email** in Finmo.
3. Complete onboarding and set a monthly limit.
4. Grant SMS and phone permissions.
5. Finmo imports supported Mobile Money messages into SQLite.
6. Use **Settings → Sync now** to back up records to Firestore.

Google Sign-In restores an existing cloud profile when one is available. On a
first Google sign-in, enter a phone number in the prompt; Finmo creates the local
and cloud profile and continues to onboarding.

Phone numbers are normalized locally across common Rwanda formats (`07...`,
`2507...`, and `+2507...`).

## Persistent setting demo

Open **Settings**, switch **Light mode** off or on, close the application fully,
and reopen it. The selection is restored from SharedPreferences. Changing the
Weekly/Monthly selector is also persisted as the default reporting period.

Dark mode uses Finmo's reference palette: a near-black page background,
blue-black cards and inputs, white primary text, muted grey labels, and MTN
yellow actions. Light mode retains the cream page background and white cards.
Only colors change between modes; screen structure and control placement remain
the same.

## CRUD and synchronization demo

- **Create:** SMS ingestion creates parsed transaction rows in SQLite.
- **Read:** Overview, Spending, and History query and display local rows.
- **Update:** Budget limits are edited and saved from Settings.
- **Delete:** Tap the red delete icon on a History item and confirm. Finmo deletes
  the matching Firestore document and then its SQLite row, refreshes History, and
  recalculates budget alerts. A failed cloud operation leaves the local row in
  place so deletion can be retried safely.

For a video demonstration, keep the authenticated user's Firestore document open
in Firebase Console and show the corresponding document disappear after confirmation.

## Testing and coverage

Run all tests and create LCOV coverage data:

```bash
flutter test --coverage
```

Calculate the line percentage from `coverage/lcov.info` with any LCOV-compatible
viewer, or use:

```powershell
$lines = Select-String -Path coverage/lcov.info -Pattern '^LF:' |
  ForEach-Object { [int]($_.Line.Split(':')[1]) } |
  Measure-Object -Sum
$hits = Select-String -Path coverage/lcov.info -Pattern '^LH:' |
  ForEach-Object { [int]($_.Line.Split(':')[1]) } |
  Measure-Object -Sum
"{0:N1}%" -f (100 * $hits.Sum / $lines.Sum)
```

The generated LCOV file should be archived with the assessment evidence. Take a
screenshot of the passing test output and the calculated coverage percentage for
the final report.

## Quality checks

```bash
flutter analyze
flutter test
dart format --output=none --set-exit-if-changed lib test
```

## Troubleshooting

- **Google Sign-In configuration error:** verify the package name, SHA fingerprints,
  enabled Google provider, and latest `google-services.json`.
- **Verification email is missing:** check the spam folder, confirm the address is
  correct, and use **Resend verification email**. Firebase may temporarily rate-limit
  repeated resend requests.
- **No transactions imported:** use a physical Android phone, grant SMS permission,
  and confirm supported MTN Mobile Money messages exist.
- **Balance remains zero:** grant SMS permission when prompted. If it was previously
  blocked permanently, Finmo offers to open Android app settings. Returning to the
  app triggers a full balance scan before incremental syncing resumes.
- **Cloud sync fails:** check connectivity, Firebase Authentication state, Firestore
  rules, and the authenticated user's document.
- **Theme does not persist:** make a selection in Settings, fully stop the app, and
  relaunch rather than hot restarting.
- **Database contains old development data:** uninstalling the application removes
  its local SQLite database; cloud data remains available for restore.

## Platform scope and privacy

Finmo currently targets Android for SMS and phone functionality. Financial SMS
content is sensitive. The application stores parsed data locally and synchronizes
it only under the authenticated Firebase user's document. Production deployments
should use least-privilege Firestore rules, disclose data handling clearly, and
request permissions only when needed.

## Contributors

- Peter
- Garang

Keep Git `user.name` and `user.email` configured consistently before committing so
contribution statistics accurately represent each contributor.
