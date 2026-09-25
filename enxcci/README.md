# EnXcci Server

Motor central do ecossistema enxOS para Android. O app consome o enxOS API
Gateway por HTTP, transforma os resultados nos módulos EnX e grava blocos no
Dataniverse local via REST (`127.0.0.1:8080`) ou TCP (`127.0.0.1:8081`).

## Dev

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

- `lib/dataniverse/` — cliente REST/TCP, autenticação e fila de retry.
- `lib/database/` — `EnXApiProvider`, ping e queries HTTP em isolate.
- `lib/engine/` — OttsVision, OttsChain e transformações EnX.
- `lib/jobs/` — scheduler baseado em `cron`.
- `lib/ui/` — dashboard, conexões, jobs e log exportável.

O workflow `.github/workflows/android_build.yml` gera os arquivos Android,
executa análise/testes e publica o APK release como artefato do GitHub Actions.

## API Gateway

O serviço Python em `bridge/` substitui conexões diretas do Android à porta
3306. Ele escuta HTTP no `PORT` configurado (8099 por padrão), exige
`X-EnX-Token` e consulta o MySQL local do servidor. A camada Flutter permite
cadastrar URL, token e perfil do gateway sem armazenar credenciais MySQL no
dispositivo.

```bash
python3 -m pip install -r bridge/requirements.txt
ENX_API_TOKEN='um-token-forte' python3 bridge/server.py
```