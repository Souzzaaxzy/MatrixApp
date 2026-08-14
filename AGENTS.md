# MATRIX App — Repository Notes

## Project
MATRIX 💤 — cyberpunk futuristic social platform. Monorepo:
- `app/` — Flutter app (presentation layer; calls backend API).
- `server/` — Node/TypeScript backend (Fastify + Prisma + PostgreSQL).
- `.github/workflows/android.yml` — CI.

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

### Server (run inside `server/`)
- deps: `npm install`
- generate Prisma client: `npm run prisma:generate`
- migrate: `npm run prisma:migrate` (dev) / `npm run prisma:deploy` (CI)
- seed: `npm run db:seed`
- typecheck: `npm run typecheck`
- test: `npm test` (64 tests, vitest)
- dev: `npm run dev`

## Architecture — Flutter (`app/lib/`)
- `app/` — entry, routes, theme tokens. Fonts bundled (Inter + JetBrainsMono).
- `core/` — widgets, animations, utils, services (AppState ChangeNotifier).
- `data/` — ApiClient (Dio), TokenStore, Repositories, DTOs. All HTTP in this
  layer; widgets never call HTTP directly.
- `features/` — splash, auth/{login,register,recover}, home, feed, search,
  akame, create_post, profile.
- `models/` — Post, MatrixUser, Comment, AkameMessage.
- State: `AppState` (ChangeNotifier) via `AppStateScope` (InheritedNotifier).

## Architecture — Server (`server/src/`)
- `config/` — env, prisma client.
- `gamification/` — xp.service (append-only ledger), coin.service (ledger).
- `modules/` — auth, posts, comments, likes, users, search, uploads,
  gamification, customization, music, games, calls, akame, config, admin.
- `middleware/authenticate.ts` — JWT auth + `requireRole` RBAC
  (USER/MODERATOR/ADMIN/OWNER).
- `utils/` — auth (Argon2id, recovery code), recovery_guard (brute-force),
  errors, dto, normalize.
- All routes mounted under `/api` prefix in `app.ts`.

## Auth (Phase 3)
- Username-only (NO email, phone, Google, Firebase).
- Password hashing: Argon2id (`src/utils/auth.ts`).
- One-time numeric recovery code (12 digits): shown at registration, only its
  SHA-256 hash is stored. Recovery requires username + code + new password.
- Brute-force guard: `src/utils/recovery_guard.ts` — 5 attempts / 15min lockout,
  constant-time-ish checks that never leak user existence.
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
