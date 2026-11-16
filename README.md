# Kona Share

An Android app for a household sharing a Hyundai Kona. Borrowers request a time, owners approve or decline, and each trip records two odometer readings. The app calculates the agreed price and can add it to the household's existing Spliit group.

**Backend: Firebase Authentication + Cloud Firestore. No Cloud Functions, custom server, billing account, or payment processor is required.** The unconfigured build opens an explicitly labelled, device-only preview with sample data.

## What works

- Email/password and Google sign-in; create a group as owner or join using a role-specific invitation.
- Separate owner and borrower invitations. Borrowers cannot promote themselves, approve requests, change the Spliit connection, or view owner invitations.
- Date/time requests with estimated kilometres and a live price breakdown. Select other household borrowers under **Invite borrowers** to share one ride, with a live equal split. The requester starts and finishes it; the selected borrowers share its final cost automatically.
- **Approve** reserves the car immediately. **Fine by me** records only that owner’s response and leaves the request pending until every current owner agrees, or any one owner approves directly. Cards show who has responded and who is still waiting. Approval still checks for overlapping reservations; simultaneous responses are merged in a transaction. Declines, optional decline notes, cancellations, and shared booking history remain available.
- Transactional approval checks to prevent simultaneous owners approving overlapping reservations.
- Add any approved booking to an Android calendar through its normal event editor. This exports a copy; later booking changes do not automatically update an exported event.
- Start an approved trip with a typed or photo-assisted odometer reading. The start time is recorded automatically. One active trip is allowed per vehicle group, and it can start up to one hour before the booked start and before the booked return. Pricing uses the actual start time, including any early time. Starting odometer readings are independent of previous trips; only an ending reading below that same trip’s start is rejected.
- Finish with the ending odometer and a confirmed return time, with an itemized fare.
- Android arrival-home reminders using a 200 m geofence, an active-trip notification, and an approximate four-hour fallback reminder. Location is optional for trip logging.
- On-device odometer photo recognition, with explicit selection/confirmation of a candidate number. Dashboard photos are not uploaded.
- Recovery of a saved ending reading/time after an interrupted or offline finish.
- Owner corrections in **Activity → Edit trip**: adjust actual times and odometer readings with an updated price preview, or finish a forgotten active trip. **Delete trip** removes it from totals and releases an active car; owners can restore the saved record. Each change keeps an immutable history record. Linked Spliit expenses are updated or removed, with uncertain corrections shown for checking.
- Automatic Spliit expense creation when a completed trip and participant mappings are available; safe pending sends are retried when the app resumes. Uncertain sends are reconciled by their trip marker instead of blindly resubmitted.
- Monthly recorded-cost totals (each borrower sees only their own share; owners see the full house total), payable on the first of the following month. These are costs, not payment-status tracking.

## Agreed pricing

All amounts are Canadian dollars. The agreement's 20% discount is already reflected in these rates; it is not applied again.

| Item | Rate |
| --- | --- |
| Base fee | $1 once per trip, always included |
| Time | $5/hour, prorated; monetary components rounded to cents |
| Distance | $0.28/km |
| Minimum total | $6 per trip |
| Daily option | $80 for the time within one calendar day, with 250 km included |

For a trip touching several calendar days, the calculator considers the daily option on each day and chooses the cheapest combination of daily and hourly rates. **Every day charged at the daily rate contributes 250 included km to the whole trip.** Remaining distance costs $0.28/km. No midnight odometer reading is needed. Ending exactly at midnight does not consume another day.

Calendar days use `America/Vancouver`, with the bundled current timezone database, independently of the phone's travel timezone. This includes B.C.'s permanent UTC−7 Pacific time from March 2026 and historical daylight-saving changes.

Examples:

| Trip | Total |
| --- | --- |
| 2 hours, 30 km | $19.40 |
| 12 hours in one calendar day, 100 km | $81.00 |
| 12 hours in one calendar day, 300 km | $95.00 |
| 23:00–01:00, 100 km | $39.00 |
| 08:00–08:00 the following day, 300 km | $135.00 |
| Two full calendar days, 500 km | $161.00 |

Charging at home and at external fast chargers is included. Ferries and parking are separate. Ordinary daily outings with the owners are free; longer shared outings are agreed separately. Shared borrowed rides divide the calculated trip total equally, including the single base fee and any minimum adjustment. Extra cents are assigned in the displayed borrower order so shares add up exactly.

The agreement also lists a discretionary $20 late fee; lost keys at $20 plus replacement/reprogramming; and damage and tickets paid by the responsible person. These are not automatically added by the app. Plug in below 30% and return the car as found.

## Android testing release

Download [Kona Share 0.2.1](https://github.com/CobeyH/Kona-Car-Share/releases/tag/v0.2.1) and open the ARM64 APK on an Android 8+ phone. When prompted, allow **Install unknown apps → Allow from this source** for the browser or file app opening it, then return to install. Root and USB debugging are not required. You can disable that source permission after installation. See [Android’s installation guidance](https://developer.android.com/distribute/marketing-tools/alternative-distribution?hl=en).

Updates use the same signing certificate and a higher version code. Install over the existing app to keep its account and phone settings; do not uninstall first. Each borrower on a shared ride must have linked their own Spliit participant. This is a household testing build distributed through GitHub, not Google Play.

## Run the preview

Use Flutter 3.47.8 / Dart 3.13 or newer compatible versions and Android SDK 36+.

```sh
flutter pub get
flutter run
```

No Firebase configuration is needed for the sample-data preview. In **House**, switch between borrower and owner to explore both flows. The web target is a UI preview; native camera recognition, Android location reminders, calendar export, and unrestricted Spliit HTTP access target Android.

## Connected household project

A dedicated project has been provisioned: **`kona-car-share-cobey`**, with a free-tier Standard Firestore database in **Toronto (`northamerica-northeast2`)**. The tested access rules are deployed, Email/Password and Google providers are enabled, and billing is unlinked. The `production` Firebase CLI alias selects it. Local `firebase-config.json` holds the Android client configuration; it is ignored by Git. Use the following steps when setting up another checkout or project.

## Connect Firebase on the Spark plan

1. Create a Firebase project with billing unlinked (Spark).
2. Enable **Authentication → Email/Password** and, optionally, **Google**.
3. Create the default **Cloud Firestore Standard** database. Start with production/locked rules, then deploy this repository's rules. Pick the database region before creation; that choice is permanent for that database.
4. Register an Android app with package name `ca.konashare.kona_share`.
5. Copy `firebase-config.example.json` to `firebase-config.json`, and fill the Firebase values from the Android app's Firebase SDK configuration (`current_key`, `mobilesdk_app_id`, `project_id`, and `project_number`).
6. Install/sign in to the Firebase CLI, then deploy only Firestore:

```sh
firebase deploy --only firestore --project YOUR_PROJECT_ID
flutter run --dart-define-from-file=firebase-config.json
```

For Google sign-in, also set `FIREBASE_GOOGLE_CLIENT_ID` to the web OAuth client ID (`oauth_client` entry with `client_type: 3` in the SDK config). Add the SHA-1 and SHA-256 fingerprints of each build’s signing certificate in Firebase’s Android app settings. The test build created in this workspace has its fingerprints registered; a build on another machine uses a different debug certificate unless configured otherwise.

No Functions deployment, Storage bucket, messaging service, Analytics, or service-account key is used. Android Firebase initialization uses the supplied options, so no Google Services Gradle plugin or committed `google-services.json` is needed. Client Firebase identifiers are public application configuration; rules and Authentication provide access control. `firebase-config.json` is nevertheless ignored to keep local environment configuration out of source control.

Create your own account and house, then invite the co-owner using the owner code and other roommates using the borrower code. Each account belongs to one group in this version.

## Spliit setup

An owner opens **House → Configure Spliit**, loads the existing group link, selects the participant to credit for car use, and confirms the group uses CAD. Each borrower links their own Spliit participant. For shared rides, all selected borrowers must be linked before the expense is sent; incomplete mappings leave it pending without charging only some riders. One Spliit expense credits the owner and assigns the exact equal shares to those borrowers. A participant can be claimed by only one household account, and the payer cannot be selected as the borrower.

The app calls Spliit's existing tRPC endpoints directly over HTTPS. The group link already grants editing access in Spliit's capability-based model and is available to signed-in members of this household. It is not embedded in the repository or APK. Spliit's API is an application API, so compatibility should be rechecked when Spliit changes it.

Before a send, the app freezes the destination group and all borrower participant IDs on the trip, checks for an existing expense bearing `[Kona:TRIP_ID]`, and persists `sending` before the mutation. If a response is lost or the app is interrupted, **Check Spliit** reconciles the existing expense. An uncertain mutation is never automatically recreated. This favors avoiding duplicate charges over unattended retries. A network connection and an open/resumed app are required for synchronization; no server runs while all phones are closed.

Spliit balances are an accounting ledger. The app does not collect money, mark a trip paid, or handle reimbursements automatically. Choose the shared owners' participant if both owners want one common credit balance.

## Location and calendar setup

On each borrower's Android phone, while at home:

1. **House → Set home location**; allow precise location.
2. **Enable notifications**.
3. In Android app permissions, enable **Location → Allow all the time**, keeping precise location on.

Google Play services is required for the geofence. The app registers it only for an active trip and removes it after finishing. It waits for an exit followed by an entry so starting a trip at home does not immediately trigger an arrival reminder. It restores an active geofence after a reboot. Only the home point and a return-time hint are saved on that phone; no route history is recorded or sent to Firebase. Android can delay arrival events, so the return time is editable and reminders never automatically finalize a bill.

Enabled notification and home buttons turn green with a check mark. Tap **Notifications enabled** to open notification settings, or **Home location set** to review the saved address or replace the point. The House page shows only the address; the set-home dialog explains the reminder area. **View in Maps** opens the saved pin. Address lookup uses Android’s geocoder when available and caches the result only on that phone; the saved pin can still be opened in Maps if lookup fails. Tapping a trip or arrival notification opens the Trip screen, including after a cold start.

Calendar export uses Android's event insertion intent, so the user chooses a calendar and confirms saving. The app does not require access to read their calendar. Exported copies do not constitute a live calendar subscription.

## Offline behavior and boundaries

- A connection is required to create/join a group, approve requests, and start a shared trip transaction.
- Firebase caches shared data on Android. An ending reading and its actual return time are saved locally before the finish transaction. If offline, retry the saved finish when online; the shared vehicle remains active until that succeeds.
- A completed but safely unsent Spliit expense retries on app resume. Uncertain sends require reconciliation, never a blind retry.
- This is a household trust model. Firestore rules enforce roles, membership, borrower trip-start boundaries, audited owner corrections, sane odometer/time ranges, and field-level write boundaries. The actual reading is supplied by the borrower and the fare is calculated on the device. This is not a tamper-proof billing meter.
- The shared schedule transaction prevents conflicting approvals in the official app. Owners are trusted managers and can change reservations using their authorized access.
- The latest 200 bookings and 200 trips are loaded in this first version. Add paginated history before long-term use exceeds that window. Trip duration is limited to 31 days.
- Approval changes appear through Firestore while the app is open; there are no remote push notifications for approvals in this version.
- Confirm camera accuracy, background arrival behavior, and the chosen calendar app on the actual phones before relying on them daily.

## Local Firebase testing

```sh
firebase emulators:start --only auth,firestore --project demo-kona-share
flutter run --dart-define=USE_EMULATORS=true
```

The Android emulator uses `10.0.2.2` to reach the host. Override `EMULATOR_HOST` for another development device. Emulator cleartext access is permitted only in the debug manifest. For a browser preview, pass `--dart-define=EMULATOR_HOST=127.0.0.1` and use `-d chrome`.

Run the rules tests against the emulator:

```sh
npm ci --prefix tools
node --test tools/rules.test.mjs
```

Do not point the rules-unit-test harness at production. It clears only the `demo-kona-share` emulator project.

## Checks and APK

```sh
flutter analyze
flutter test
flutter build apk --debug
# Configured Android APK:
flutter build apk --debug --dart-define-from-file=firebase-config.json
```

The APK is in `build/app/outputs/flutter-apk/app-debug.apk`. The initial household test APK is release-mode ARM64 signed with this workspace’s Android test certificate. It is not a Play Store release. A debug APK can also be built for development. For the smaller test build, use `flutter build apk --release --target-platform android-arm64 --split-per-abi --dart-define-from-file=firebase-config.json`; its output is `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`.

Before store distribution, configure your own release signing key and review permissions/distribution requirements. No signing key is stored in this repository.

Structure: domain pricing in `lib/domain`; data access and device services in `lib/data`; app state in `lib/ui/app_model.dart`; feature screens in `lib/ui`; Android geofence/OCR/calendar bindings under `android/app/src/main/kotlin`; Firebase authorization in `firestore.rules`.
