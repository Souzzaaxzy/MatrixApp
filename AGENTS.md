# MATRIX App — Repository Notes

## Project
MATRIX 💤 — cyberpunk futuristic social platform Flutter app (Phase 1: full
visual interface and navigation, offline-capable, no real backend).

## Environment
- Flutter: 3.27.x (stable). SDK at `$HOME/flutter/bin`.
- JDK 21 at `/usr/lib/jvm/java-21-openjdk-amd64`. Always export before building:
  `export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64 && export PATH=$HOME/flutter/bin:$JAVA_HOME/bin:$PATH`
- Android: AGP 8.11.1, Gradle 8.14.3, Kotlin 2.2.20, NDK 27.0.12077973,
  Java/Kotlin compile target 17. `android/app/build.gradle` pins NDK version
  explicitly to satisfy plugin requirements.

## Commands
- deps: `flutter pub get`
- analyze: `flutter analyze` (must pass with no issues)
- test: `flutter test` (66 tests)
- build APK: `flutter build apk --release` →
  `build/app/outputs/flutter-apk/app-release.apk` (~22MB)

## Architecture
- `lib/app/` — app entry, routes, theme tokens (colors, text styles,
  dimensions). Fonts bundled as assets (Inter + JetBrainsMono); NO
  google_fonts dependency.
- `lib/core/` — reusable widgets (MatrixButton, MatrixTextField, MatrixCard,
  PostCard, UserAvatar, GlowContainer, etc.), animations, utils, services.
- `lib/features/` — feature folders: splash, auth/{login,register}, home,
  feed, search, akame, create_post, profile.
- `lib/models/` — Post, MatrixUser, Comment, AkameMessage.
- State: `AppState` (ChangeNotifier) exposed via `AppStateScope` (InheritedNotifier).
  All data is in-memory mock; the AppState class is the seam for a future backend.

## Conventions / gotchas
- MatrixButton is NOT an ElevatedButton (uses GlowContainer + GestureDetector).
  In tests, locate it via `find.descendant(of: find.byType(MatrixButton), matching: find.text('LABEL'))`.
- MatrixTextField uppercases its label (`label!.toUpperCase()`). Tests must use
  uppercase label text (e.g. "NOME", not "Nome").
- Screens with simulated async (login/register/create-post/akame) use
  `Future.delayed`. In widget tests, advance the fake clock with
  `tester.pump(Duration(...))` to fire pending timers and avoid
  "Timer is still pending" failures.
- AppState uses a `_disposed` flag (NOT `hasListeners`) to guard the delayed
  Akame reply, so unit tests without listeners still receive the reply.
- CreatePostScreen pops the navigator on publish; tests must pump it from the
  HomeScreen (proper route stack), not as the MaterialApp root.
- Git identity is set locally: openhands / openhands@all-hands.dev.

## CI
`.github/workflows/android.yml` — on push/PR to main/master: checkout, JDK 21,
Flutter, `pub get`, `analyze`, `test`, `build apk --release`, upload APK artifact.

## Phase 1 status
Complete: compiles, analyze clean, 66 tests pass, APK builds. No Phase 2/3
features (followers, real auth, Akame AI API, backend, etc.).
