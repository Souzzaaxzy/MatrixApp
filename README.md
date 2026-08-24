# MATRIX 💤 — Flutter App

Cyberpunk futuristic social platform — **app (cliente Flutter)**.

> **Backend separado**: o servidor agora está em
> [Souzzaaxzy/ServidorMtx](https://github.com/Souzzaaxzy/ServidorMtx).
> Para rodar o backend localmente em container, clone aquele repositório
> e execute `docker compose up -d --build`.

## O que é este repositório

Apenas o app Flutter (camada de apresentação). Ele consome a API do
backend MATRIX e **não** contém código de servidor.

## Configurar o endereço do backend

O app fala com **UMA única API**: o ServidorMtx hospedado na
Bronxys/Pterodactyl. A URL oficial é resolvida em
`app/lib/data/api_config.dart`:

| Modo | Endereço |
|------|----------|
| Release (APK) | `--dart-define=API_BASE_URL=...` (o CI injeta a partir do secret `API_BASE_URL`) |
| Debug (emulador Android) | `http://10.0.2.2:3000` |

A URL de produção é o endereço público REAL da alocação do servidor no
painel da Bronxys — IP/host do node + porta alocada (ex.:
`http://123.45.67.89:4316`). HTTPS somente se o painel fornecer um
domínio com SSL válido. **Nunca** localhost, 127.0.0.1, 0.0.0.0 ou URLs de
túneis/serviços externos. Passos completos:
[CONEXAO_APP.md no ServidorMtx](https://github.com/Souzzaaxzy/ServidorMtx/blob/main/CONEXAO_APP.md).

Para apontar para um servidor diferente (dev):
```bash
flutter run --dart-define=API_BASE_URL=http://192.168.0.10:3000
```

## Comandos (dentro de `app/`)

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

## CI

`.github/workflows/android.yml` — usa `working-directory: app`.
Pipeline: checkout → JDK 21 → Flutter → pub get → analyze → test → build apk.
