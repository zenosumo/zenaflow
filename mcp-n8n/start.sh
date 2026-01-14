#!/bin/bash
# MCP server for n8n workflow automation
# Provides Claude Code with n8n node docs, templates, and workflow management

set -a
source /opt/zenaflow/.env
set +a

exec npx -y n8n-mcp
