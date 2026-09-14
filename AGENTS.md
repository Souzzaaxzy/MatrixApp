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
- test: `flutter test` (259 tests)
- build APK: `flutter build apk --release` →
  `build/app/outputs/flutter-apk/app-release.apk` (~70MB)

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

## Conversa em grupo — menção em negrito no composer
- O composer de grupo usa `MentionComposerController`
  (`core/widgets/mention_composer_controller.dart`) — um
  `TextEditingController` cujo `buildTextSpan` renderiza EM NEGRITO apenas os
  tokens de menção ainda válidos (`@Nickname`/`@todos`), enquanto o valor
  subjacente continua TEXTO PLANO (parsing/ranges/envio/servidor intactos). O
  texto ao redor da menção nunca fica em negrito.
- Hook: `getMentions` aponta para `_mentionTracker.drafts`; chamar
  `_input.refresh()` SEMPRE que o tracker mudar sem mudança de texto
  (`applyEdit`, `_insertMention`, `_restoreMentions`).

## Vídeos antigos — capa gerada sob demanda
- Vídeos NOVOS já geram capa no create_post (`video_thumbnail`) e persistem
  `thumbnailUrl` (server). Vídeos ANTIGOS (sem `thumbnailUrl`) recebem a capa
  via `core/services/video_cover_service.dart`: extrai 1 frame da URL com o
  MESMO plugin `video_thumbnail`, UMA vez por URL (cache em memória + disco em
  `getTemporaryDirectory()`), extrações SERIALIZADAS (uma por vez), falha vira
  "sem capa" na sessão. O tile do perfil (`_VideoThumb`) mostra placeholder
  VÍDEO + badge de play enquanto não há capa.

## Stickers — compartilhar Android (importação)
- O app recebe figuritas via `ACTION_SEND` / `ACTION_SEND_MULTIPLE` de imagens
  (PNG/WebP/JPEG). O `MainActivity` (Kotlin) copia os `content://` para o
  cache e entrega ao Flutter pelo MethodChannel `matrix.share/stickers`
  (`data/share_sticker_service.dart`). Não criar um segundo fluxo de entrada.
- A validação real dos bytes acontece em
  `core/utils/sticker_import_validator.dart` (magic bytes + dimensões +
  SHA-256). Arquivos inválidos são descartados com mensagem amigável.
- A importação é SEMPRE confirmada pelo usuário na `StickerImportScreen`
  (rota `AppRoutes.stickerImport`, em `features/stickers/`). Só depois os
  arquivos são enviados pelo sistema de uploads existente e criados com
  `POST /api/stickers/import` (o servidor deduplica por hash).
- Navegação: app aberto → listener em `app/app.dart`; processo frio →
  consulta `initialFiles()` no arranque. Após importar/cancelar,
  `ShareStickerService.clearCurrent()` evita reprocessamento.

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

