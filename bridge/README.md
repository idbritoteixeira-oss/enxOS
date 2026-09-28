# EnX API Gateway

Ponte HTTP Python entre o EnXcci Android e o MySQL local do servidor. O
gateway não expõe a porta 3306; ele aceita apenas consultas de leitura via
HTTP autenticado.

## Configuração

```bash
export ENX_API_TOKEN='um-token-forte'
export MYSQL_HOST='127.0.0.1'
export MYSQL_PORT='3306'
export MYSQL_USER='...'
export MYSQL_PASSWORD='...'
export MYSQL_DATABASE='...'
python3 -m pip install -r bridge/requirements.txt
python3 bridge/server.py
```

O serviço usa `PORT` quando fornecida pelo ambiente e `8099` por padrão.

Para perfis adicionais, use variáveis como `MYSQL_REPORTING_HOST`,
`MYSQL_REPORTING_USER`, `MYSQL_REPORTING_DATABASE`, e envie
`{"profile":"reporting"}` na consulta.

A tabela externa precisa expor pelo menos a coluna `dtts`:

```sql
CREATE TABLE dtts (
  dtts VARCHAR(255) NOT NULL
);
```

## Rotas

- `GET /health`
- `POST /query`
- `POST /execute` (alias compatível)
- `POST /dtts/update` (rota principal)
- `POST /dtts` (alias compatível)

Todas exigem `X-EnX-Token`. Consultas em `/query` e `/execute` também exigem
o último DTTS salvo na tabela `dtts`, enviado no header HTTP `X-DTTS`. Em
servidores CGI/PHP, esse mesmo header pode aparecer no ambiente como
`HTTP_X_DTTS`; `HTTP_X_DTTS` não deve ser enviado literalmente pelo cliente.

`/dtts/update` recebe `{"dtts":"..."}`. Na primeira gravação basta o
`X-EnX-Token`; nas seguintes, o cliente deve enviar o DTTS anterior em
`X-DTTS`. Isso permite a rotação automática sem colocar DTTS fixo na conexão.

O gateway bloqueia comandos que não começam com `SELECT`, `SHOW`, `DESCRIBE`,
`DESC` ou `EXPLAIN`, e rejeita múltiplas instruções na mesma requisição.