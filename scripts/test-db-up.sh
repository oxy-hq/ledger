#!/usr/bin/env bash
# Brings up Postgres, MySQL, and ClickHouse for integration tests.
# Auto-picks free ports if defaults are occupied; writes them to
# .test-ports.env so the test runner can source them.
set -euo pipefail
cd "$(dirname "$0")/.."

find_free_port() {
  local port=$1
  while lsof -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; do
    echo "  Port $port occupied, trying $((port + 1))..." >&2
    port=$((port + 1))
  done
  echo "$port"
}

PG_PORT=$(find_free_port "${AIRLEDGER_PG_PORT:-15433}")
MYSQL_PORT=$(find_free_port "${AIRLEDGER_MYSQL_PORT:-13307}")
CH_HTTP_PORT=$(find_free_port "${AIRLEDGER_CH_HTTP_PORT:-18124}")

cat > .test-ports.env <<EOF
AIRLEDGER_PG_PORT=$PG_PORT
AIRLEDGER_MYSQL_PORT=$MYSQL_PORT
AIRLEDGER_CH_HTTP_PORT=$CH_HTTP_PORT
EOF

echo "Ports: pg=$PG_PORT mysql=$MYSQL_PORT clickhouse=$CH_HTTP_PORT"
export AIRLEDGER_PG_PORT=$PG_PORT
export AIRLEDGER_MYSQL_PORT=$MYSQL_PORT
export AIRLEDGER_CH_HTTP_PORT=$CH_HTTP_PORT

docker compose -f docker-compose.test.yml up -d "$@"

echo ""
echo "Wait a few seconds for containers to be healthy, then run tests:"
echo "  set -a && source .test-ports.env && set +a"
echo "  flutter test test/integration/"
