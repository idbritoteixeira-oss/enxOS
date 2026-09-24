# EnXcci Server

Motor central do ecossistema enxOS para Android. O app conecta em múltiplos
bancos MySQL, transforma os resultados nos módulos EnX e grava blocos no
Dataniverse local (`127.0.0.1:8081`).

## Desenvolvimento

```bash
flutter create --platforms=android --project-name enxcci .
flutter pub get
flutter analyze
flutter test
flutter run
```

O projeto não usa Node.js, npm ou JavaScript. As regras EnX estão em
`lib/engine/modules/enx_math.dart` como placeholders até a lógica oficial ser
fornecida.

## Estrutura

- `lib/dataniverse/` — cliente REST, autenticação e fila de retry.
- `lib/database/` — pool em memória, ping e queries em isolate.
- `lib/engine/` — OttsVision, OttsChain e transformações EnX.
- `lib/jobs/` — scheduler baseado em `cron`.
- `lib/ui/` — dashboard, conexões, jobs e log exportável.

O workflow `.github/workflows/android_build.yml` gera os arquivos Android,
executa análise/testes e publica o APK release como artefato do GitHub Actions.