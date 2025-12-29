#!/bin/bash

# Load environment variables from .env file
if [ -f "/opt/zenaflow/.env" ]; then
    set -a
    source /opt/zenaflow/.env
    set +a
fi

# Start the MCP server
exec node /opt/zenaflow/mcp-cloudflare-dns/index.js
