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

## Stickers (figurinhas) — tamanho, transições e importação
- **Render do chat:** `ChatMediaBubble._StickerBubble` (`features/chat/`
  `chat_media_bubble.dart`) — usado por DM e grupo. Tamanho COMPACTO:
  `~27%` da largura limitado a 118px e a `22%` da altura útil, sempre
  `BoxFit.contain` (proporção, transparência e APNG intactos; sem corte/
  deformação). O placeholder tem a MESMA caixa — sem salto de layout.
- **Grade do painel:** `StickerPicker` (`features/chat/sticker_picker.dart`)
  — `LayoutBuilder` + célula alvo de 62px → ~5–8 colunas, espaçamento `xs`
  (compacta e responsiva). Altura do painel em `StickerPicker.panelHeight`.
  Toque dá um "punch" de escala curto (`_StickerTile`) que NÃO atrasa o envio.
- **Confirmação de importação (share):** o lote compartilhado abre SEMPRE a
  `StickerImportScreen`, que mostra prévia + "Adicionar este pacote ao
  Matrix?" com CANCELAR/ADICIONAR — nada entra na coleção antes do toque.
  `app.dart` só SEGURA a abertura enquanto as rotas de BOOT (splash/login/
  register/recover) estão no topo; NÃO usar allowlist de rotas "permitidas"
  (isso já bloqueou a confirmação quando o usuário estava numa conversa).
- **Excluir pacote:** lixeira (`_DeletePackageButton`) no LADO DIREITO da
  faixa de pacotes, visível só quando o usuário está DENTRO de um pacote
  (nunca por figurinha). Confirma via dialog e chama
  `AppState.deleteStickerPackage` → `DELETE /api/stickers/packages/:id`.
  Ao excluir, o painel volta para "Recentes" (nunca fica um pacote
  selecionado inexistente). Só o DONO de um pacote importado pode excluir.
- **Favoritas:** toque-longo numa figurinha do painel abre o mini menu
  (`_StickerTileMenu`) e, na mensagem, o menu existente ganhou
  "Adicionar às favoritas" (DM e grupo) — ambos usam
  `AppState.isStickerFavorited` (fonte única) e a persistência do servidor
  (upsert, nunca duplica). Favoritas SOBREVIVEM à exclusão do pacote: o
  servidor recria cada favorita como figurinha autônoma num pacote-arquivo
  oculto do usuário.
- **Transições (leves, sem blur/partículas/loops):**
  `AnimatedStickerPanel` (`features/chat/sticker_panel.dart`) faz a morte/
  nascimento do painel (AnimatedSize + fade/slide de 200ms) e só monta o
  filho quando visível; `StickerEntrance` anima a figurinha que chega no
  chat; a troca de aba/pacote é um fade de 180ms (`_switchCtrl`); o modal
  usa o `showModalBottomSheet` padrão. Toque no campo de mensagem continua
  fechando o painel (`_onInputFocusChanged`).
- **Import por código do Sticker.ly:** botão `+ Adicionar` no painel →
  `StickerlyImportSheet` (`features/chat/stickerly_import_sheet.dart`):
  código/link → BUSCAR → prévia (nome/autor/capa/figurinhas) →
  `ADICIONAR AO MATRIX` (com confirmação; pacote já existente informado).
  Reutiliza o sistema atual (`StickerRepository` → `AppState` →
  `POST /api/stickers/stickerly/{preview,import}`). O APK NUNCA fala com o
  Sticker.ly nem guarda credenciais — quem consulta/baixa é o SERVIDOR.
- **Servidor:** `modules/stickers/stickerly.service.ts` + 2 rotas em
  `sticker.routes.ts`. `StickerPackage.authorId/source/sourceId` identificam
  pacotes do usuário (privados ao dono; dedupe por código). O import baixa
  com concorrência limitada, valida magic bytes, guarda no /static e
  deduplica por SHA-256. Base da fonte configurável por `STICKERLY_API_BASE`.
  **URLs salvas** vêm de `publicBase()` (`utils/storage.ts`): STORAGE_PUBLIC_
  BASE_URL → PUBLIC_API_URL → caminho RELATIVO `/static/...` (nunca
  `localhost` — era o que deixava as figurinhas importadas VAZIAS no app).
- **Import via compartilhamento Android:** ver seção "Stickers — compartilhar
  Android" abaixo (fluxo `.wastickers`, inalterado).

## Stickers — compartilhar Android (importação)
- O app recebe figuritas via `ACTION_SEND` / `ACTION_SEND_MULTIPLE` / `VIEW`.
  O `MainActivity` (Kotlin) copia/extrai o conteúdo para o cache e entrega ao
  Flutter pelo MethodChannel `matrix.share/stickers`
  (`data/share_sticker_service.dart`). Não criar um segundo fluxo de entrada.

### Formato REAL do WhatsApp (importante)
- Compartilhar um PACOTE de figurinhas NÃO envia várias imagens: o WhatsApp
  manda UM arquivo `.wastickers` — um **ZIP** com os `.webp`/`.png`, um
  ícone de bandeja e um `contents.json` (título/autor). MIME típico:
  `application/vnd.wastickers`, `application/octet-stream` ou `application/*`.
  Por isso o `AndroidManifest.xml` registra os filtros com `image/*`,
  `application/*` e `*/*` (e `VIEW` p/ os MIME `*wastickers`).
- `WastickersParser.kt` (Kotlin PURO de JVM) abre o ZIP: valida path
  traversal, limita a 60 figurinhas / 5 MB por arquivo / 30 MB total, lê
  título/autor e separa capa. Testes JVM: `android/app/src/test/...` →
  `./gradlew :app:testDebugUnitTest` (8 testes). Lógica pura para poder
  testar sem emulador.
- Figurinha única continua sendo `image/*` (copiada direto).

### Instância única (o bug das janelas infinitas)
- `launchMode="singleTask"` + **SEM** `android:taskAffinity` (ausência =
  afinidade padrão do pacote = UMA task).
  - `singleTop` (usado antes) só reaproveita a Activity se ela estiver NO TOPO
    da própria task: o Sharesheet entrega com `FLAG_ACTIVITY_NEW_TASK` e, com
    o MATRIX em segundo plano/em outra rota, cada share criava uma NOVA
    instância/task — a cascata "MatrixApp → MatrixApp → …".
  - `singleTask` garante no máximo UMA instância no sistema: qualquer novo
    share traz a task existente para a frente e entrega via `onNewIntent`.
  - `taskAffinity=""` (mitigação StrandHogg antiga) NÃO deve voltar: dá à
    Activity nenhuma afinidade e cada launch passa a criar uma task vazia.
  - Não usar `singleInstance`: proíbe outras atividades na task e pode
    quebrar PendingIntents/notificações.
- Notificações: `flutter_local_notifications` monta o PendingIntent com
  `PackageManager.getLaunchIntentForPackage` (ACTION_MAIN/LAUNCHER). Com
  singleTask isso cai no `onNewIntent` da MESMA instância — o plugin lê o
  intent no `FlutterActivity.onNewIntent` (por isso chamamos `super` antes).
- Share com app aberto/em segundo plano chega por `onNewIntent` (mesma
  instância); processo frio por `onCreate` + consulta `initialSharedBatch`.
- Dedupe: assinatura do intent + `consumeIntent` (limpa `EXTRA_STREAM`/
  `ClipData`) no nativo; `batchId` monotônico no Dart
  (`ShareStickerService`) evita reentrega. O `initialSharedBatch` responde
  DEPOIS do lote ficar pronto (deferred result) quando o share chega antes
  do Flutter.
- `app.dart`: um share NUNCA apila a tela de importação — se ela já está
  aberta o lote novo a **substitui** (`pushReplacementNamed`), então o Back
  não revela uma pilha de telas/instâncias.
- Diagnóstico: `MainActivity` loga `onCreate`/`onNewIntent` com
  `instance` (contador no processo, deve ficar em 1) e `taskId` — o teste
  `android/app/src/test/.../MainActivityManifestTest.kt` guarda o invariante
  do manifesto (singleTask, sem taskAffinity) sem precisar de emulador.

### Validação / UI / limpeza
- `EXTRA_STREAM` E `ClipData` são lidos; a validação dos bytes continua em
  `core/utils/sticker_import_validator.dart` (magic bytes + dimensões +
  SHA-256). Arquivos inválidos → mensagem amigável (nunca silêncio).
- A importação é SEMPRE confirmada na `StickerImportScreen`
  (`AppRoutes.stickerImport`): mostra capa/nome/autor/quantidade quando o
  pacote os traz e usa defaults quando não. O upload
  (`AppState.importSharedStickers`) envia o MIME/extensão REAIS (validados)
  porque o servidor só aceita PNG/JPG/WebP — sem isso um temp sem extensão
  iria como `application/octet-stream` e seria recusado.
- Temporários: o nativo limpa `<cacheDir>/shared_stickers` no início do
  processo; o Dart (`ShareStickerService.cleanupTemporaries`) limpa no
  import/cancelar. Nunca toca a coleção do usuário.
- O resultado é criado com `POST /api/stickers/import` (dedupe por hash no
  servidor) — servidor NÃO precisou mudar.

## Stories (24h) — foto, vídeo e texto + curtidas e respostas
- **Modelo/DTO/repo:** `models/story.dart` (`Story` com `type`
  image|video|text, `text`, `liked`, `likeCount`; `StoryGroup`),
  `data/dtos/dtos.dart` (`StoryDto`, `StoryGroupsDto`),
  `data/repositories/story_repository.dart` (`create` cobre os 3 tipos,
  `toggleLike`, `reply`) — registrado em `Services`/`Repositories` como
  `stories`.
- **Estado:** `AppState` expõe `storyGroups`/`myStories` + `loadStories`,
  `createStory` (type/text), `toggleStoryLike` (flip OTIMISTA + rollback),
  `replyToStory`, `markStoryViewed`, `deleteStory`.
- **Card (`features/feed/stories_header.dart`):** o AVATAR fica no TOPO
  (centralizado, nunca sobre a mídia) e a mídia do Story ocupa o corpo
  central — claramente visível; nickname abaixo com ellipsis. Story NÃO
  VISTO = **borda branca**; visto = borda neutra (some na hora, via
  AppState). A faixa termina com **canto arredondado** e SEM `Divider` entre
  Stories e feed (transição contínua). Story de TEXTO mostra o texto no
  card.
- **Viewer (`features/feed/story_viewer.dart`):** fullscreen `BoxFit.contain`,
  navegação por toque/arrastar/✕/Back, UM vídeo por vez. Ouve o `AppState`
  (curtida/visto repintam na hora). Barra inferior com
  **"Responda a esse stories"** (bordas pill, teclado nativo) + **coração**
  no MESMO padrão do feed (♡/♥); não aparece no próprio Story.
- **Resposta → MENSAGEM REAL:** `replyToStory` chama
  `POST /api/stories/:id/reply`; o servidor cria uma DM para o AUTOR com
  `type='story_reply'` + `story` (referência + snapshot). Renderizada por
  `features/chat/story_reply_reference.dart` ("respondeu ao seu stories" +
  thumb/texto) na bolha de DM E de grupo; a snapshot garante que a
  referência continue legível após o Story expirar.
- **Criação:** `CreateStoryScreen` tem o seletor **Foto/Vídeo | Texto**
  (mesma tela; sem fluxo paralelo), preview obrigatório e reusa
  `pickGalleryMedia` + `/api/uploads`.
- **Feed:** o header entra como primeiro sliver ANTES dos posts e só quando
  autenticado; `loadFeed`/`_refresh` também chamam `loadStories`.
- **Rotas:** `AppRoutes.createStory` (`/home/create-story`); registrada
  também no `test_app.dart`.
- **Foto de PERFIL (perfil):** o avatar tem DOIS gestos distintos —
  `onTap` → abre o Story ATIVO do usuário (`_openUserStory`; no-op se não
  houver Story, nunca abre viewer vazio) e `onLongPress` → a foto ampliada
  (`_showProfilePhotoZoom`, implementação existente). Um long press cancela
  o tap, então as duas ações nunca disparam juntas. A moldura antiga
  (`UserAvatar(ring: true)`) foi trocada por `_StoryRingAvatar`: **borda
  BRANCA** quando `AppState.hasUnseenStory(user.id)` (Story ativo não
  visto) e SEM borda quando visto/sem Story — mesmo sistema de visto do
  feed, persistido no servidor.
- **Viewer — progresso e identidade:** `_ProgressBars` tem uma barra por
  Story: a ATUAL anima 0→1 em sincronia (`AnimationController`; 5s fixos
  para foto/texto, duração REAL do vídeo) e auto-avança ao completar; as
  anteriores ficam cheias e as próximas vazias. `_StoryIdentity` mostra
  **FOTO centralizada ACIMA do NOME** (`FramedAvatar`/`UserAvatar`/
  `NicknameRenderer` — mesmo visual de grupos/DM), com o ✕ e (no próprio
  Story) a lixeira.
- **Limite de vídeo (2 min):** `kMaxStoryVideoDuration` no app bloqueia
  ANTES do upload (duração real via `video_player`); o app envia
  `durationMs` no multipart de `/api/uploads/video` e no body do
  `/api/stories`; o SERVIDOR revalida (`validateVideoDurationMs`).

## Stickers — painel, Android Back, favoritar e recentes
- **Android Back fecha o painel, não a conversa:** DM
  (`conversation_screen.dart`) e grupo (`group_conversation_screen.dart`)
  embrulham o `Scaffold` em `PopScope(canPop: !_stickerPickerOpen)`: com o
  painel aberto o Back apenas fecha o painel (e devolve o foco/teclado ao
  campo), permanecendo na MESMA conversa; sem painel, o Back segue a rota.
- **Máquina de estados única:** `_openStickerPanel()` /
  `_closeStickerPanel({refocus})` são o ÚNICO caminho de abrir/fechar —
  usados pelo botão do composer, pelo toque no campo e pelo Back. Abrir
  sempre tira o foco (teclado cede lugar); fechar com `refocus: true`
  devolve o foco (teclado volta). Evita "teclado + painel" ao mesmo tempo.
- **Favoritar no chat = TOQUE na figurinha** (`ChatMediaBubble.onStickerTap`,
  ligado a `_toggleStickerFavorite`): o long press NÃO favorita mais — ele
  continua abrindo o menu normal da mensagem (responder/excluir/…), que
  perdeu a opção de favoritar. Upsert no servidor (nunca duplica).
- **Popup do painel (toque-longo numa figurinha):** ordem fixa —
  "Remover das recentes" (só quando ela ESTÁ nos recentes, via
  `AppState.isStickerRecent`) e depois "Favoritar"/"Remover das favoritas".
- **Remover das recentes:** `AppState.removeStickerRecent` →
  `DELETE /api/stickers/:id/recent`. Escopo estrito: remove APENAS a linha
  de recentes do usuário — pacote, favorito, mensagem e arquivo intactos.
  Atualização imediata no painel; persistido no servidor.
- **Ícone do botão de figurinhas:** `core/widgets/puzzle_icon.dart`
  (`PuzzleIcon`) — peça de quebra-cabeça MONOCROMÁTICA desenhada em
  `CustomPainter` (nunca um emoji colorido), colorida pelo estado do botão.
  O botão de clipe (`ChatAttachButton`) permanece inalterado.

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

