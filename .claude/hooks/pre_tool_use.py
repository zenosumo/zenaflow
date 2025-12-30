#!/usr/bin/env python3
"""
PreToolUse hook to prevent Claude Code from reading sensitive files and environment variables.

This hook blocks:
1. Read tool calls that attempt to access .env files
2. Bash commands that attempt to echo/print sensitive environment variables
"""
import json
import sys
import os
import re

# Sensitive environment variables that should not be exposed
SENSITIVE_ENV_VARS = {
    "POSTGRES_PASSWORD",
    "CLOUDFLARE_API_TOKEN",
    "CLOUDFLARE_ACCOUNT_ID",
    "N8N_ENCRYPTION_KEY",
    "API_KEY",
    "API_SECRET",
    "SECRET_KEY",
    "PASSWORD",
    "TOKEN",
    "PRIVATE_KEY",
}

def check_bash_command(command):
    """
    Check if a bash command attempts to read sensitive environment variables.
    Returns (is_blocked, reason) tuple.
    """
    # Patterns that attempt to echo/print environment variables
    echo_patterns = [
        r'echo\s+\$(\w+)',           # echo $VAR
        r'echo\s+"?\$\{(\w+)\}',     # echo ${VAR} or echo "${VAR}"
        r'printf.*\$(\w+)',          # printf with $VAR
        r'printenv\s+(\w+)',         # printenv VAR
        r'env\s*\|\s*grep',          # env | grep (lists all vars)
        r'export.*\$(\w+)',          # export with variable reference
        r'set\s*\|\s*grep',          # set | grep (lists all vars)
    ]

    # Check for cat .env or similar
    if re.search(r'\bcat\s+.*\.env', command):
        return True, "Cannot read .env files using cat command"

    # Check for source .env or similar
    if re.search(r'\bsource\s+.*\.env', command) or re.search(r'\.\s+.*\.env', command):
        return True, "Cannot source .env files"

    # Check for printenv or env without arguments (lists all vars)
    if re.search(r'\b(printenv|env)\s*$', command) or re.search(r'\b(printenv|env)\s*\|', command):
        return True, "Cannot list all environment variables"

    # Check each pattern
    for pattern in echo_patterns:
        matches = re.finditer(pattern, command, re.IGNORECASE)
        for match in matches:
            # Extract variable name (from first capture group)
            if match.groups():
                var_name = match.group(1).upper()

                # Check if it's a sensitive variable (exact match or contains sensitive keywords)
                if var_name in SENSITIVE_ENV_VARS:
                    return True, f"Cannot access sensitive environment variable: {var_name}"

                # Check if variable name contains sensitive keywords
                for sensitive in ["PASSWORD", "SECRET", "TOKEN", "KEY", "API"]:
                    if sensitive in var_name:
                        return True, f"Cannot access sensitive environment variable: {var_name}"

    return False, None

def main():
    try:
        # Load hook input from stdin
        input_data = json.load(sys.stdin)
    except json.JSONDecodeError as e:
        print(f"Error: Invalid JSON input: {e}", file=sys.stderr)
        sys.exit(1)

    tool_name = input_data.get("tool_name", "")
    tool_input = input_data.get("tool_input", {})

    # Block Read tool calls for .env files
    if tool_name == "Read":
        file_path = tool_input.get("file_path", "")

        # Normalize the path for comparison
        normalized_path = os.path.normpath(file_path)
        file_name = os.path.basename(normalized_path)

        # Check if this is an .env file (various common names)
        blocked_files = {
            ".env",
            ".env.local",
            ".env.production",
            ".env.development",
            ".env.test",
            ".env.staging",
        }

        if file_name in blocked_files or file_name.startswith(".env."):
            output = {
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "permissionDecision": "deny",
                    "permissionDecisionReason": (
                        f"Blocked: Cannot read {file_name} as it contains sensitive credentials. "
                        "MCP servers have direct access to required environment variables."
                    )
                }
            }
            print(json.dumps(output))
            sys.exit(0)

    # Block Bash commands that attempt to read sensitive environment variables
    elif tool_name == "Bash":
        command = tool_input.get("command", "")

        is_blocked, reason = check_bash_command(command)
        if is_blocked:
            output = {
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "permissionDecision": "deny",
                    "permissionDecisionReason": (
                        f"Blocked: {reason}. "
                        "Sensitive credentials should not be exposed. "
                        "MCP servers have direct access to required environment variables."
                    )
                }
            }
            print(json.dumps(output))
            sys.exit(0)

    # Allow all other tool calls
    sys.exit(0)

if __name__ == "__main__":
    main()
