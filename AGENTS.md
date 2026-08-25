# MATRIX App — Repository Notes

## Project
MATRIX 💤 — cyberpunk futuristic social platform. Split across two repos:
- **This repo (`MatrixApp`)** — Flutter app (presentation layer; calls backend API).
  Only `app/` (Flutter) + `.github/`. The server was moved out.
- **`Souzzaaxzy/ServidorMtx`** — Node/TypeScript backend (Fastify + Prisma +
  **SQLite** `data/matrix.db`). Hospedado na Bronxys/Pterodactyl via
  `npm start` (self-provisions). Container-ready: `docker compose up -d --build`.
  See https://github.com/Souzzaaxzy/ServidorMtx

## Environment
- Flutter: 3.27.x (stable). SDK at `$HOME/flutter/bin`.
- JDK 21 at `/usr/lib/jvm/java-21-openjdk-amd64`. Always export before building:
  `export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64 && export PATH=$HOME/flutter/bin:$JAVA_HOME/bin:$PATH`
- Android SDK: `ANDROID_HOME=$HOME/Android/Sdk` (cmdline-tools, platform-34/36,
  build-tools 34.0.0). Needed for `flutter build apk`.
- Android: AGP 8.11.1, Gradle 8.14.3, Kotlin 2.2.20, NDK 27.0.12077973,
  Java/Kotlin compile target 17. `android/app/build.gradle` pins NDK version.

## Commands
### Flutter (run inside `app/`)
- deps: `flutter pub get`
- analyze: `flutter analyze` (must pass with no issues)
- test: `flutter test` (70 tests)
- build APK: `flutter build apk --release` →
  `build/app/outputs/flutter-apk/app-release.apk` (~54MB)

### Server
The server is in `Souzzaaxzy/ServidorMtx`. Commands there:
`npm install`, `npx prisma generate`, `npx prisma migrate deploy`,
`npm run db:seed`, `npm test` (64 tests, vitest), `npm run dev`.
Or just `docker compose up -d --build`.

## Architecture — Flutter (`app/lib/`)
- `app/` — entry, routes, theme tokens. Fonts bundled (Inter + JetBrainsMono).
- `core/` — widgets, animations, utils, services (AppState ChangeNotifier).
- `data/` — ApiClient (Dio), TokenStore, Repositories, DTOs. All HTTP in this
  layer; widgets never call HTTP directly.
- `features/` — splash, auth/{login,register,recover}, home, feed, search,
  akame, create_post, profile.
- `models/` — Post, MatrixUser, Comment, AkameMessage.
- State: `AppState` (ChangeNotifier) via `AppStateScope` (InheritedNotifier).

## Architecture — Server
The backend lives in the separate repo `Souzzaaxzy/ServidorMtx`. Key points
for reference when working on the app's data layer:
- All routes under `/api` prefix. Base URL resolved in `lib/data/api_config.dart`.
- Auth: username-only, Argon2id, recovery code (hash only), JWT sessions.
- userId (UUID) is the internal key for ALL relations; username is mutable.
- Modules: auth, posts, comments, likes, users, search, uploads, gamification,
  customization, music, games, calls, akame, config, admin.
- RBAC: USER/MODERATOR/ADMIN/OWNER.
- AI (Akame): AIProvider abstraction; AI_API_KEY only on the server.

## Auth (Phase 3)
- Username-only (NO email, phone, Google, Firebase).
- Password hashing: Argon2id (server, `ServidorMtx`).
- One-time numeric recovery code (12 digits): shown at registration, only its
  hash is stored server-side. Recovery requires username + code + new password.
- Brute-force guard: 5 attempts / 15min lockout, never leaks user existence.
- Identity: userId (UUID) is the internal key for ALL relations; username is
  mutable. displayName is separate from username.

## Conventions / gotchas
- MatrixButton is NOT an ElevatedButton (GlowContainer + GestureDetector).
  Locate in tests: `find.ancestor(of: find.byType(MatrixButton), matching: find.text('LABEL'))`.
- MatrixTextField uppercases its label. Tests must use uppercase label text.
- Screens with simulated async use `Future.delayed`. In widget tests use
  `tester.pump(Duration(...))` (not `pumpAndSettle`, which times out on the
  continuous glow animation) to fire pending timers.
- AppState uses `_disposed` (NOT `hasListeners`) to guard the delayed Akame reply.
- CreatePostScreen pops on publish; pump from HomeScreen, not as root.
- Server tests load `.env.test` via dotenv in `tests/setup.ts` (vitest does
  not auto-load it). Test DB is reset (truncated) before each run.
- Git identity: openhands / openhands@all-hands.dev.

## CI
`.github/workflows/android.yml` — on push/PR to main/master. Uses
`working-directory: app` (Flutter project root is `app/`, not repo root).
Verifies `pubspec.yaml` exists before running pub get. Pipeline: checkout →
JDK 21 → Flutter → verify structure → pub get → analyze → test → build apk →
upload APK artifact.

## Phase 3 status
Complete. Server: 64 tests pass, typecheck clean. Flutter: 70 tests pass,
analyze clean, APK builds (~54MB). CI green on main.

## Phase 4 — Social (friendships + notifications)
- Server: `friend_requests`, `friendships`, `notifications` Prisma models
  (SQLite). Modules `src/modules/friends/` and `src/modules/notifications/`.
  Endpoints: `POST /api/friend-requests/:userId`, `GET /api/friend-requests`,
  `POST /api/friend-requests/:id/accept|reject`, `GET /api/users/:id/friendship`,
  `GET /api/notifications`, `PATCH /api/notifications/:id/read`, `PATCH /api/notifications/read-all`.
  Notification types: LIKE / COMMENT / FRIEND_REQUEST / FRIEND_ACCEPTED.
  Friendship states: NONE / OUTGOING_PENDING / INCOMING_PENDING / FRIENDS.
  No self-notifications; unlike deletes the pending LIKE notification.
  Server: 96 tests pass.
- App: profile redesigned (big avatar, glowing @username, friendship button,
  floating `+` on own profile only). Bottom bar: "Criar" tab replaced by
  "Notificações" with unread badge. Search results open the user profile.
  NotificationsScreen has actionable FRIEND_REQUEST cards (ACEITAR/RECUSAR).
  Flutter: 97 tests pass, analyze clean.
- Gotcha: widget tests that navigate to PostDetailScreen/ProfileScreen need
  TWO `tester.pump()` after the tap (route transition + async data load).

## Phase 5 — Activities, profile stats, friends sheet, push
- **Profile bug fix**: `AppState` now caches profiles per username
  (`_profiles[username]` + `profileFor(username)`); `currentUser` (session)
  and the viewed profile are fully separate slots. Viewing a profile NEVER
  overwrites the session user. Tests: `app_state_test.dart`
  "profile isolation" group + `profile_screen_test.dart` regression group.
- **Profile stats**: server `GET /api/users/:username/profile` returns
  `postsCount` (own posts only) + `friendsCount` (accepted friendships only)
  in the user DTO; app renders the "Amigos / Posts" counter row
  (`_ProfileStats` in profile_screen.dart) for the VIEWED user.
- **Friends list**: `GET /api/friends/:userId?page=&pageSize=` (paginated).
  App: `FriendsSheet` (modal bottom sheet, drag handle, infinite scroll) from
  tapping the Amigos counter. Tapping a friend pops the sheet and pushes
  `/profile/:username`.
- **FRIEND_ACCEPTED**: server notifies BOTH sender and acceptor (each entry
  carries the other user as actor). Accept removes the actionable
  FRIEND_REQUEST notification. App area renamed to "Atividades" (labels only;
  endpoints/models unchanged).
- **Push (no FCM, self-contained)**: server holds a `Device` table
  (`platform`, unique `token`, `lastSeenAt`) + `POST/DELETE /api/devices`
  + WebSocket `/api/ws` (token auth via `Sec-WebSocket-Protocol`) broadcasting
  notification payloads. App `PushService` (web_socket_channel +
  flutter_local_notifications) registers an RFC4122 device id (stored via
  TokenStore), shows heads-up notifications and routes taps:
  postId → post detail, else actor profile. Android 13+ permission
  (POST_NOTIFICATIONS) requested once. Logout unregisters the device.
- **Android gotcha**: flutter_local_notifications requires core library
  desugaring — `android/app/build.gradle` enables it
  (`coreLibraryDesugaringEnabled = true` + `desugar_jdk_libs:2.1.4`).
- **Flutter gotcha**: never call `AppStateScope.of()` (or any
  dependOnInheritedWidgetOfExactType) inside `initState` — capture it in
  `didChangeDependencies` (bug hit in FriendsSheet).
- Status: server 114 tests pass; app 105 tests pass, analyze clean,
  APK builds (~24MB).
