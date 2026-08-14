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

O app aponta para o backend definido em `lib/data/api_config.dart`:

| Modo | Endereço |
|------|----------|
| Debug (emulador Android) | `http://10.0.2.2:3000` |
| Release | `--dart-define=API_BASE_URL=https://seu-host` |

Para apontar para um servidor diferente:
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
