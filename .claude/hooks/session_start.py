#!/usr/bin/env python3
"""
Zenaflow Environment Detection Hook

Runs at Claude Code session start to detect whether running on VPS or local machine.
Sets environment variables and displays environment information.
"""

import json
import os
import sys
from pathlib import Path


def detect_environment():
    """Detect environment based on working directory."""
    cwd = Path.cwd()
    platform = os.uname().sysname.lower()

    # Determine environment type: VPS production or local development
    if str(cwd).startswith('/opt/core') or str(cwd).startswith('/opt/zenaflow'):
        return {
            'type': 'VPS_PRODUCTION',
            'name': '🖥️  VPS Production (core.zenaflow.com)',
            'capabilities': [
                '✅ Full Docker stack running',
                '✅ System-level access (UFW, Fail2Ban, systemctl)',
                '✅ Production domains (workflow.zenaflow.com, webhook.zenaflow.com)',
                '✅ Direct access to all services',
                '⚠️  sudo commands require explicit user permission',
            ]
        }
    else:
        return {
            'type': 'LOCAL_DEVELOPMENT',
            'name': f'💻 Local Development ({platform})',
            'capabilities': [
                '✅ Local Docker stack available',
                '❌ No system-level access (no UFW, Fail2Ban)',
                '❌ No production domains',
                '💡 Use SSH tunnels for VPS database access:',
                '   ssh -L 5432:localhost:5432 root@core.zenaflow.com  # PostgreSQL',
                '   ssh -L 8889:localhost:8889 root@core.zenaflow.com  # pgAdmin',
                '   ssh -L 5555:localhost:5540 root@core.zenaflow.com  # RedisInsight',
            ]
        }


def main():
    """Main hook entry point."""
    # Read hook input from stdin
    try:
        hook_input = json.load(sys.stdin)
    except json.JSONDecodeError:
        hook_input = {}

    # Detect environment
    cwd = Path.cwd()
    platform = os.uname().sysname.lower()
    env = detect_environment()

    # Display environment information (goes to Claude as context)
    print('╔════════════════════════════════════════════════════════════════╗')
    print('║ ZENAFLOW ENVIRONMENT DETECTED                                  ║')
    print('╚════════════════════════════════════════════════════════════════╝')
    print()
    print(f"Environment: {env['name']}")
    print(f"Type: {env['type']}")
    print(f"Working Directory: {cwd}")
    print(f"Platform: {platform}")
    print()
    print("Capabilities:")
    for capability in env['capabilities']:
        print(f"  {capability}")
    print()
    print('────────────────────────────────────────────────────────────────')
    print()

    # Export environment variables for Claude Code session
    env_file = os.environ.get('CLAUDE_ENV_FILE')
    if env_file:
        with open(env_file, 'a') as f:
            f.write(f'export ZENAFLOW_ENV="{env["type"]}"\n')
            f.write(f'export ZENAFLOW_CWD="{cwd}"\n')
            f.write(f'export ZENAFLOW_PLATFORM="{platform}"\n')

    # Exit successfully
    sys.exit(0)


if __name__ == '__main__':
    main()
