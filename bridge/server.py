#!/usr/bin/env python3
"""API Gateway HTTP do EnXcci para o MySQL local."""

from __future__ import annotations

import hmac
import json
import os
import re
import sys
from datetime import date, datetime
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any
from urllib.parse import urlparse

try:
    import mysql.connector
    from mysql.connector import Error as MySqlError
except ImportError as error:  # pragma: no cover - mensagem de inicialização
    print(
        "Dependência ausente: instale mysql-connector-python antes de iniciar o gateway.",
        file=sys.stderr,
    )
    raise SystemExit(1) from error


READ_ONLY_SQL = re.compile(r"^\s*(SELECT|SHOW|DESCRIBE|DESC|EXPLAIN)\b", re.IGNORECASE)
MAX_BODY_BYTES = 2 * 1024 * 1024


def env(name: str, default: str = "") -> str:
    return os.environ.get(name, default).strip()


def profile_key(profile: str) -> str:
    normalized = re.sub(r"[^A-Za-z0-9]", "_", profile or "default").upper()
    return "" if normalized in {"", "DEFAULT"} else f"_{normalized}"


def db_config(profile: str) -> dict[str, Any]:
    suffix = profile_key(profile)

    def setting(name: str, default: str = "") -> str:
        return env(f"MYSQL_{name}{suffix}", env(f"MYSQL_{name}", default))

    return {
        "host": setting("HOST", "127.0.0.1"),
        "port": int(setting("PORT", "3306")),
        "user": setting("USER"),
        "password": setting("PASSWORD"),
        "database": setting("DATABASE"),
        "connection_timeout": int(setting("TIMEOUT", "5")),
    }


def json_default(value: Any) -> str:
    if isinstance(value, (datetime, date)):
        return value.isoformat()
    return str(value)


class GatewayHandler(BaseHTTPRequestHandler):
    server_version = "EnXApiGateway/1.0"

    def log_message(self, format: str, *args: Any) -> None:
        print(f"[gateway] {self.address_string()} - {format % args}")

    def _send_json(self, status: HTTPStatus, payload: dict[str, Any]) -> None:
        encoded = json.dumps(payload, default=json_default).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def _authorized(self) -> bool:
        configured = env("ENX_API_TOKEN")
        received = self.headers.get("X-EnX-Token", "")
        return bool(configured) and hmac.compare_digest(received, configured)

    def _read_payload(self) -> dict[str, Any] | None:
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            return None
        if length <= 0 or length > MAX_BODY_BYTES:
            return None
        try:
            payload = json.loads(self.rfile.read(length))
        except (UnicodeDecodeError, json.JSONDecodeError):
            return None
        return payload if isinstance(payload, dict) else None

    def do_GET(self) -> None:
        path = urlparse(self.path).path
        if path != "/health":
            self._send_json(HTTPStatus.NOT_FOUND, {"status": "error", "message": "Rota não encontrada"})
            return
        if not self._authorized():
            self._send_json(HTTPStatus.UNAUTHORIZED, {"status": "error", "message": "Token inválido"})
            return
        self._send_json(
            HTTPStatus.OK,
            {"status": "success", "data": {"service": "enx-api-gateway", "mysql": "ready"}},
        )

    def do_POST(self) -> None:
        path = urlparse(self.path).path
        if path not in {"/query", "/execute"}:
            self._send_json(HTTPStatus.NOT_FOUND, {"status": "error", "message": "Rota não encontrada"})
            return
        if not self._authorized():
            self._send_json(HTTPStatus.UNAUTHORIZED, {"status": "error", "message": "Token inválido"})
            return

        payload = self._read_payload()
        if payload is None:
            self._send_json(HTTPStatus.BAD_REQUEST, {"status": "error", "message": "JSON inválido ou grande demais"})
            return

        query = payload.get("query")
        profile = str(payload.get("profile", "default"))
        params = payload.get("params", [])
        if not isinstance(query, str) or not query.strip():
            self._send_json(HTTPStatus.BAD_REQUEST, {"status": "error", "message": "query é obrigatória"})
            return
        if not isinstance(params, list):
            self._send_json(HTTPStatus.BAD_REQUEST, {"status": "error", "message": "params deve ser uma lista"})
            return
        if not READ_ONLY_SQL.match(query) or ";" in query.rstrip(";"):
            self._send_json(
                HTTPStatus.FORBIDDEN,
                {"status": "error", "message": "Apenas consultas de leitura são permitidas"},
            )
            return

        connection = None
        cursor = None
        try:
            connection = mysql.connector.connect(**db_config(profile))
            cursor = connection.cursor(dictionary=True)
            cursor.execute(query, tuple(params))
            rows = cursor.fetchall() if cursor.with_rows else []
            self._send_json(
                HTTPStatus.OK,
                {
                    "status": "success",
                    "data": rows,
                    "meta": {"count": len(rows), "profile": profile},
                },
            )
        except (MySqlError, ValueError) as error:
            self._send_json(
                HTTPStatus.BAD_GATEWAY,
                {"status": "error", "message": f"Falha no MySQL local: {error}"},
            )
        finally:
            if cursor is not None:
                cursor.close()
            if connection is not None and connection.is_connected():
                connection.close()


def main() -> None:
    token = env("ENX_API_TOKEN")
    if not token:
        raise SystemExit("ENX_API_TOKEN precisa ser configurado para iniciar o gateway.")

    host = env("HOST", "0.0.0.0")
    port = int(env("PORT", "8099"))
    server = ThreadingHTTPServer((host, port), GatewayHandler)
    print(f"EnX API Gateway ouvindo em {host}:{port}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()