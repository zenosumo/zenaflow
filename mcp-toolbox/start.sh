#!/bin/bash
# MCP Toolbox starter script for Zenaflow PostgreSQL
# Loads environment variables and starts the MCP Toolbox server

# Load main environment variables from project root
if [ -f "/opt/zenaflow/.env" ]; then
    set -a
    source /opt/zenaflow/.env
    set +a
fi

# Set PostgreSQL connection details
export POSTGRES_HOST="${POSTGRES_HOST}"
export POSTGRES_PORT="${POSTGRES_PORT}"
export POSTGRES_DATABASE="${POSTGRES_DATABASE}"
export POSTGRES_USER="${POSTGRES_USER}"
export POSTGRES_PASSWORD="${POSTGRES_PASSWORD}"

# Start MCP Toolbox with prebuilt PostgreSQL tools
exec npx -y @toolbox-sdk/server --prebuilt postgres --stdio
