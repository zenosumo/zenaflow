#!/bin/bash

# Load environment variables from .env file
if [ -f "/opt/zenaflow/.env" ]; then
    set -a
    source /opt/zenaflow/.env
    set +a
fi

# URL-encode the password using Python
PASSWORD_ENCODED=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${ZENAFLOW_DB_PASSWORD}', safe=''))")

# Construct the database URL with encoded password
DATABASE_URL="postgresql://zenaflow_user:${PASSWORD_ENCODED}@localhost:5432/zenaflow"

# Start the postgres MCP server
exec npx -y @modelcontextprotocol/server-postgres "$DATABASE_URL"
