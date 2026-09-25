# EnXcci Server

App Flutter Android em Dart puro que consome o API Gateway enxOS, processa
dados no motor enxOS e grava no Dataniverse local.

## Run & Operate

- `cd enxcci && flutter pub get` — instalar dependências Dart
- `cd enxcci && flutter analyze` — verificar o código Flutter
- `cd enxcci && flutter test` — executar os testes unitários
- `cd enxcci && flutter build apk --release` — gerar o APK Android

## Stack

- Flutter stable, Dart 3+
- API Gateway Python via HTTP autenticado
- Dataniverse local via REST 8080 ou TCP 8081
- Persistência local via `shared_preferences`

## Where things live

- `enxcci/lib/config/` — modelos e persistência das conexões/jobs
- `enxcci/lib/database/` — provedor HTTP do gateway
- `enxcci/lib/dataniverse/` — cliente REST/TCP local
- `bridge/` — API Gateway Python para o MySQL local
- `enxcci/lib/engine/` — processamento EnX
- `enxcci/lib/jobs/` — scheduler
- `enxcci/lib/ui/` — telas e estado do app
- `.github/workflows/android_build.yml` — CI do APK

## Architecture decisions

- O projeto Flutter fica em `enxcci/` para manter o app Dart separado do
  scaffold auxiliar existente.
- Queries de jobs são enviadas ao gateway HTTP em isolate para não bloquear a UI.
- O retry do Dataniverse é em memória e preserva comandos enquanto o serviço
  local estiver offline.

## Product

Dashboard dark com status do Dataniverse, conexões MySQL, jobs recorrentes e
log filtrável/copiável.

## User preferences

- Comentários e textos do produto em português brasileiro.
- Sem Node.js, npm ou JavaScript no app Flutter.

## Gotchas

- O CI gera a pasta Android com `flutter create` porque o SDK não está
  disponível no ambiente de desenvolvimento atual.
- O Dataniverse REST precisa estar rodando no mesmo dispositivo em
  `http://127.0.0.1:8080`, ou o modo TCP deve usar `127.0.0.1:8081`.
- O gateway exige `ENX_API_TOKEN` e as variáveis `MYSQL_*` no servidor.
