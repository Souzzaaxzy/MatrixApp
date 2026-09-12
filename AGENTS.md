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

## Phase 6 — Back navigation, usernames, themes, account management
- **Back button fix**: `HomeScreen` is wrapped in `PopScope(canPop: false)`
  with `onPopInvokedWithResult` → `_handleBackPress()`: non-feed tab → feed
  tab first; feed tab → 1st press shows "Pressione voltar novamente para
  sair" SnackBar, 2nd press within 2s calls `SystemNavigator.pop()`. The
  pending state auto-resets via a `Timer` (2s) — do NOT use DateTime diffs
  (fake clock mismatch in tests). Pushed routes (post detail, profiles,
  create post) pop normally because they sit above home on the root
  navigator. `createPostScreen` now `pop()`s after publish (was
  `pushReplacementNamed(home)` — broke the back stack). No more
  "Rota não encontrada" on back.
- **Usernames never carry '@'**: stored lowercase w/o '@' everywhere.
  Server `normalizeUsername()` strips leading `@+`; migration
  `20260825123937_strip_username_at_prefix` strips stored '@' (collisions
  get `_legacy` suffix, never merged). App strips in login/register/recover/
  edit-profile inputs; UI adds '@' visually only at display sites
  (`'@$username'`). The login field has NO '@' prefix widget.
- **FCM removed everywhere**: server's external-provider slot
  (`registerExternalProvider`) deleted — push = WebSocket `/api/ws` +
  local Android notifications only. No Firebase deps/configs in either repo.
- **ThemeController** (`lib/core/services/theme_controller.dart`): singleton
  ChangeNotifier + WidgetsBindingObserver; modes dark/light/system;
  persisted via `ThemeStore` (flutter_secure_storage 'matrix_theme_mode');
  `load()` called from `Services.init()`. `MatrixApp` rebuilds on it and
  sets `AppColors.setActive(effectivePalette(mode, platformBrightness))`
  before building ThemeData. Palette: `lib/app/theme/app_palette.dart`
  (dark + light); `AppColors` statics now delegate to the active palette
  — they are NOT compile-time const anymore, so never use `const` with
  them (colorOf light theme is a full redesign, not an inversion).
- **Settings sheet**: `ProfileScreen` shows ☰ (menu_rounded) leading ONLY
  on the own profile (`_isOwn` compares widget.username vs currentUser —
  case-insensitive). Sheet: theme trio (Escuro/Claro/Sistema),
  Sair da conta (AlertDialog confirm → AppState.logout → pushNamedAndRemove
  login), Excluir conta (2-step confirm: dialog + nickname re-entry match
  → AppState.deleteAccount → login). `isScrollControlled: true` +
  SingleChildScrollView or it clips on small/test surfaces.
- **Server**: `DELETE /api/auth/account` (bearer-auth, id from token;
  Prisma cascade removes posts/comments/likes/friendships/notifications/
  devices/sessions). App `AuthRepository.deleteAccount()` +
  `AppState.deleteAccount()` clears session caches like logout.
- **Test gotchas**: bottom sheets/dialogs need an extra `pump(500ms)` after
  the 300ms pump for the slide-in animation to land; SnackBar dismissal
  needs ~3s fake time stepped in 500ms chunks (its display timer is
  created only after the enter animation completes); widget tests must
  `await state.restoreSession()` + `await state.loadFeed()` before
  pumpWidget (see `test/helpers/test_app.dart pumpMatrixApp`).
- Status: server 120 tests pass, typecheck clean; app 123 tests pass,
  analyze clean.

## Phase 7 — Live theme, like-state fix, customization infrastructure
- **Live theme fix**: route pages are built per navigation in
  `app/lib/app/routes.dart` (`_buildPage`) and wrapped in
  `ThemeWatcher` (`lib/core/widgets/theme_watcher.dart`) — a StatefulWidget
  that listens to `ThemeController.instance` and returns FRESH (non-const)
  page instances. Root cause of "theme needs restart": identical const
  widget instances were skipped by the element tree, and screens read
  static `AppColors` at build time so they never repainted. `HomeScreen`
  tab pages are also non-const for the same reason. Bottom sheets
  (settings/comments/friends) are ThemeWatcher-wrapped too.
- **Like-state fix**: `post.liked` (server `likedByMe`, computed from the
  AUTHENTICATED token user — never client-supplied ids) drives the detail
  screen heart. The profile post GRID shows only a neutral
  `favorite_border_rounded` counter — never a filled heart.
- **Customization infra** (assets ship next phase):
  - Server: `Item`/`UserItem`/`EquippedItem` (SQLite), module
    `src/modules/customization/` — `GET /api/customization/catalog`
    (?type=), `GET /inventory`, `GET /equipped`, `POST /equip/:itemId`
    (ownership + expiry validated server-side), `DELETE /equip/:slot`.
    `GET /api/users/:username` embeds `user.customization`
    (slot → {itemId, name, assetUrl, rarity}).
  - App: `CosmeticItem` model + `CosmeticMap` (slot→item),
    `MatrixUser.customization`, `CustomizationRepository`,
    `AppState.myCosmetics` + load/equip/unequip. Renderers:
    `FramedAvatar` / `StyledUsername` / `CosmeticBadgeView` in
    `core/widgets/`; screen `features/customizations/` with
    `ProfileCustomizationPreview`; entry in the profile settings sheet.
- **Gotchas**: never notify listeners from `didChangeDependencies`
  (schedule post-frame); capture `Navigator` BEFORE popping a bottom sheet
  to pushNamed the next route; `setMode` is called WITHOUT await in widget
  tests (platform channel never resolves under fake async).
- Status: server 122 tests pass, typecheck clean; app 133 tests pass,
  analyze clean; CI green (APK built.

## Phase 7b — Group chat (app) e fix de classes aninhadas
- O commit `ddf46e7` (`feat(chat): group chat creation, listing and conversation
  flow`): crio grupo, tile do grupo no Chat tab e `group_conversation_screen`
  reutilizando o sistema de mensagens/voice/realtime — mas quebrou o build do app:
  as classes `_ChatFab` e `_GroupTile` foram inseridas **dentro** da classe
  `_AkameCard` (faltou o `}` que fechava a classe antes delas`, causando
  `undefined_method` e `Classes can't be declared inside other classes`.
- Fix: fechar a classe `_AkameCard` com um `}` dedicado antes do
  `_ChatFab` (commit `b47170c`). `flutter analyze` limpo e `flutter test`
  (237 testes) passando depois da correção.

- Gotcha: ao inserir novas classes no fim dum ficheiro, conferir sempre
  o balanceamento de chaves da classe **imediatamente anterior** — o editor
  `str_replace` nem sempre faz o fecho automático.


## Status atuais
- App: `flutter analyze` limpo e `flutter test` (256 testes, contagem atualizada)
  passando, APK buildável via CI. — o AGENTS.md anterior listava 237; cresceu
  com os fluxos de chats/grupos/voice adicionados entretanto.


- Servidor: `npm test` (212 testes, vitest) passando, `npm run lint` limpo,
  `npm run build` (tsc) OK. Commit de testes das etapas 4-5 em `main`.

## Phase 8 — Correções e melhorias restantes do sistema de grupos (Etapas 1-6)
- **Etapa 1 — Galeria** (commit anterior): `pickGalleryImage()`
  (`core/utils/gallery_picker.dart`) unificado — `READ_MEDIA_IMAGES`/legacy
  storage via permission_handler, resize/compress (1600px/q85), previews e
  rejeição sem travar; usado em foto de perfil, post, grupo.
- **Etapa 2 — Mini menu de edição** (`group_profile_screen.dart`): ícone de
  lápis (`Icons.edit_rounded`) na AppBar SÓ para o owner (`_isOwner` compara
  `_ownerId` do grupo com `currentUser.id`). Abre bottom sheet `_EditGroupMenu`
  com: Editar nome (`_NameEditDialog`, nome obrigatório), Editar foto
  (`_changeAvatar` galeria→upload→`updateGroupAvatar`), Editar descrição
  (`_DescriptionEditDialog`, texto opcional + "Remover descrição"). Persistência
  via `updateGroup` (nome OU descrição isolados) + realtime `chat_group_updated`.
- **Etapa 3 — Membros** (`group_profile_screen.dart` + `group_members_screen.dart`):
  corpo do perfil agora mostra seção "Membros" com prévia inline (avatar+apelido+
  badge Dono) + "Ver todos" navegando para `GroupMembersScreen`. O botão
  "ADICIONAR MEMBRO" (owner-only) fica DENTRO de `GroupMembersScreen` e abre o
  sheet compartilhado `AddMemberSheet` (`features/chat/add_member_sheet.dart`),
  filtrando amigos fora do grupo. `groupInfo`/`addGroupMember` validados no
  servidor — nunca só no APP.
- **Etapa 4 — Exclusão de comentários**: servidor já valida `comment.userId ===
  userId || post.userId === userId` (`deleteComment`). Novo teste no servidor
  cobre o cenário obrigatório: User1 post, User2 comenta 1º, User3 depois —
  User2 NÃO pode apagar o comentário do User3 (403); o autor do post pode (204);
  User2 pode apagar o próprio. Ordem NÃO concede permissão.
- **Etapa 5 — Exclusão de mensagens em grupo**: mesmo sistema do DM reutilizado
  (`deleteGroupMessageForEveryone` valida owner para apagar de terceiro;
  `deleteGroupMessageForMe` idempotente; realtime `chat_message_deleted` para
  todos os membros). Novo teste no servidor: membro comum → 403 ao apagar de
  terceiro; owner OK + broadcast; membro pode apagar a própria para todos.
- **Gotchas test**: bottom sheets/dialogs precisam de `pump(300ms)` após o tap;
  `find.text('Ver todos')` substitui o antigo 'Participantes' no perfil do grupo;
  `seededGroup` aceita `sessionUserId` para simular não-owner. Depois de
  `Navigator.pushNamed`, `_openMembers` faz `_refreshSilent()` ao voltar.

## Phase 7c — Group chat UI improvements (Etapas 1-7)
- **Header da conversa de grupo** (`group_conversation_screen.dart`): seta
  de voltar à esquerda, foto (40px) + nome + contagem de membros centralizados.
  Indicador de atividade (digitando/gravando áudio) fica na `actions` do AppBar
  (direita), truncado via `ConstrainedBox(maxWidth)` — nunca overflow. O
  `_GroupAvatar` usa `UserAvatar` (CachedNetworkImage) — a foto real do grupo.
- **Teclado (Etapa 2)**: `_GroupConversationScreenState` agora usa
  `WidgetsBindingObserver` + `didChangeMetrics()` para re-pinar o scroll ao
  fundo quando o teclado abre/fecha (mesmo comportamento do DM). Nada de
  valores fixos — `resizeToAvoidBottomInset: true` + `SafeArea`.
- **Foto do grupo (Etapa 3)**: a MESMA `avatarUrl` do `GroupHeader` alimenta a
  aba de chats (`_GroupTile`), o cabeçalho da conversa e as configurações —
  sem cópias independentes. O realtime `chat_group_updated` (AppState
  `handleIncomingGroupUpdated`) atualiza os três locais ao vivo.
- **Configurações do grupo (Etapa 4)**: `_AdminActionsGrid` (Wrap de
  `_AdminActionTile` 104px em quadrados) logo abaixo do nome/descrição —
  responsivo, sem overflow horizontal.
- **Participantes (Etapas 5-6)**: nova tela dedicada `GroupMembersScreen`
  (`AppRoutes.groupMembers`, args `GroupMembersRouteArgs`) com seta de voltar.
  A `GroupProfileScreen` mostra um `_ParticipantesTile` que navega até ela.
  Cada membro é clicável → `openProfileById` (id real, guard anti-duplicata).
- **Sem "@" (Etapa 7)**: `displayNickname()` em `core/utils/chat_format.dart`
  remove "@" apenas na apresentação (defesa em profundidade — o servidor já
  normaliza). Aplicado em bolhas, indicadores de atividade, lista de membros,
  add-member sheet e criação de grupo. Identificadores/API inalterados.
- Testes: `test/features/group_chat_feature_test.dart` (9 testes) cobre
  cabeçalho, indicadores, teclado/scroll, foto nos 3 locais, participantes
  clicáveis e ausência de "@". Helper `test_app.dart` ganhou as rotas de
  grupo; `fake_repositories.dart` ganhou `groupMemberIds` no FakeStore.

============================================================
MATRIX — FLUXO OBRIGATÓRIO DE TRABALHO
============================================================

COMO EU TRABALHO

Eu quero que qualquer agente que trabalhe no MATRIX siga um
processo cuidadoso, completo e organizado.

O MATRIX possui dois repositórios conectados:

APP:
https://github.com/Souzzaaxzy/MatrixApp

SERVIDOR:
https://github.com/Souzzaaxzy/ServidorMtx

O APP e o SERVIDOR NÃO devem ser tratados como projetos
independentes.

Eles fazem parte do mesmo sistema e qualquer alteração deve
considerar a comunicação entre os dois.


============================================================
FLUXO OBRIGATÓRIO
============================================================

Antes de começar qualquer alteração, seguir exatamente esta
ordem:

1. ANALISAR O PROMPT

Ler completamente o prompt/tarefa recebido.

Entender todos os requisitos, regras, limitações,
comportamentos esperados, funcionalidades novas e possíveis
impactos no sistema existente.

Não começar a programar antes de entender completamente o
prompt.


2. LER OS AGENTS.MD

Ler o AGENTS.md do APP.

Ler o AGENTS.md do SERVIDOR.

As regras dos dois arquivos são obrigatórias.


3. ANALISAR OS DOIS REPOSITÓRIOS

Antes de modificar qualquer código:

analisar completamente o APP;

analisar completamente o SERVIDOR;

analisar a arquitetura;

analisar as funcionalidades existentes;

analisar APIs;

analisar banco de dados;

analisar autenticação;

analisar realtime;

analisar comunicação APP ↔ SERVIDOR;

analisar os arquivos que serão afetados;

analisar possíveis dependências com funcionalidades antigas.


4. FAZER UMA VARREDURA COMPLETA

Não analisar somente o arquivo que aparentemente precisa ser
alterado.

Pesquisar o projeto para descobrir:

implementações existentes;

componentes reutilizáveis;

serviços existentes;

endpoints;

modelos;

schemas;

tabelas;

eventos realtime;

listeners;

rotas;

estados;

testes;

dependências;

fluxos relacionados.


O objetivo é entender como a funcionalidade realmente funciona
antes de alterá-la.


============================================================
IMPLEMENTAÇÃO
============================================================

Depois da análise completa:

começar a executar o prompt recebido.

Implementar somente o que foi solicitado e o que for
estritamente necessário para que a funcionalidade funcione
corretamente.


============================================================
REGRA PRINCIPAL — PRESERVAR O QUE JÁ EXISTE
============================================================

NÃO modificar funcionalidades antigas sem necessidade.

NÃO substituir sistemas existentes simplesmente para criar uma
nova funcionalidade.

NÃO apagar código funcional sem motivo.

NÃO criar uma segunda implementação quando já existir uma
implementação adequada.

NÃO duplicar serviços, APIs, componentes, estados ou sistemas.

NÃO alterar comportamentos antigos que não fazem parte da
tarefa.


A regra é:

ADICIONAR E INTEGRAR, NÃO DESTRUIR E REFAZER.


Se for realmente necessário modificar uma funcionalidade
existente para implementar a nova:

primeiro analisar o impacto;

preservar o comportamento anterior;

alterar somente o necessário;

testar a funcionalidade antiga;

testar a funcionalidade nova.


============================================================
APP + SERVIDOR
============================================================

Sempre verificar se a tarefa afeta:

APP;

SERVIDOR;

API;

BANCO;

REALTIME;

AUTENTICAÇÃO;

PERSISTÊNCIA.


Quando uma alteração precisar dos dois lados:

implementar os dois lados de forma sincronizada.


Nunca deixar:

APP esperando uma API inexistente;

SERVIDOR esperando dados que o APP não envia;

modelos diferentes;

contratos incompatíveis;

eventos realtime incompatíveis.


O APP e o SERVIDOR devem permanecer conectados e compatíveis.


============================================================
TESTES COMPLETOS
============================================================

Depois da implementação:

testar a funcionalidade nova;

testar as funcionalidades antigas relacionadas;

testar os fluxos existentes;

testar APP + SERVIDOR juntos;

testar persistência;

testar realtime quando aplicável;

testar erros e casos extremos.


Não testar somente o código novo.


É obrigatório verificar se a implementação nova não quebrou
funcionalidades que já existiam.


============================================================
VALIDAÇÃO
============================================================

Executar todas as ferramentas de validação disponíveis no
projeto.

APP:

flutter analyze;

flutter test;

lint, caso exista;

build.


SERVIDOR:

testes;

lint, caso exista;

build.


Corrigir TODOS os erros encontrados.

Depois das correções, executar novamente os testes necessários.


Não considerar uma tarefa concluída somente porque o projeto
compilou.


============================================================
VERIFICAÇÃO FINAL
============================================================

Antes do commit, fazer uma última revisão completa.

Verificar:

o prompt foi executado completamente;

todos os requisitos foram implementados;

APP e SERVIDOR continuam conectados;

nenhuma funcionalidade antiga foi quebrada;

nenhuma implementação duplicada foi criada;

nenhum erro ficou pendente;

testes estão passando;

build está funcionando;

persistência está funcionando;

realtime está funcionando quando aplicável.


============================================================
GIT
============================================================

Depois que tudo estiver funcionando:

fazer commit das alterações do APP;

fazer push para main;

fazer commit das alterações do SERVIDOR;

fazer push para main.


Não deixar alterações importantes somente no ambiente local.


============================================================
REGRA FINAL
============================================================

A ordem obrigatória é:

LER O PROMPT

↓

LER OS DOIS AGENTS.MD

↓

ANALISAR APP + SERVIDOR

↓

FAZER VARREDURA COMPLETA

↓

PLANEJAR

↓

IMPLEMENTAR

↓

TESTAR FUNCIONALIDADE NOVA

↓

TESTAR FUNCIONALIDADES ANTIGAS

↓

TESTAR APP + SERVIDOR

↓

CORRIGIR ERROS

↓

VALIDAR NOVAMENTE

↓

VERIFICAR SE NADA ANTIGO FOI QUEBRADO

↓

COMMIT

↓

PUSH PARA MAIN

↓

FINALIZAR


Não pular etapas.

Não pedir confirmação entre etapas.

Executar o processo de forma autônoma.


============================================================
COMO EU ESPERO QUE O AGENTE TRABALHE
============================================================

Eu prefiro alterações cuidadosas, integradas e completas.

Não quero soluções rápidas que apenas façam o código compilar.

Quero que o agente entenda primeiro como o projeto funciona,
reutilize a arquitetura existente, implemente a nova
funcionalidade sem destruir o que já existe, teste o novo e o
antigo, verifique a comunicação entre APP e SERVIDOR e somente
depois considere a tarefa concluída.

O objetivo não é apenas "fazer funcionar".

O objetivo é fazer funcionar, manter o que já funciona,
integrar corretamente os dois repositórios e entregar tudo
testado e enviado para a main.
============================================================