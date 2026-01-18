#!/bin/bash
# Glass Claude - Audit Logger
# Logs Claude Code tool usage outside project directory

AUDIT_DIR="$HOME/.claude/debug"
AUDIT_LOG="$AUDIT_DIR/audit.log"
ERROR_LOG="$AUDIT_DIR/error.log"
JQ_PATH="$HOME/.glass-claude/jq"

# Use system jq or bundled jq
if command -v jq &>/dev/null; then
    JQ="jq"
elif [ -x "$JQ_PATH" ]; then
    JQ="$JQ_PATH"
else
    echo "$(date -u +%Y-%m-%dT%H:%M:%S)|SYSTEM|FATAL|jq not found" >> "$ERROR_LOG"
    exit 2
fi

# --- Spec Validation ---
# CLAUDE_PROJECT_DIR is set by Claude Code - if missing, spec may have changed
if [ -z "$CLAUDE_PROJECT_DIR" ]; then
    echo "$(date -u +%Y-%m-%dT%H:%M:%S)|SYSTEM|FATAL|CLAUDE_PROJECT_DIR not set - Claude Code spec may have changed" >> "$ERROR_LOG"
    echo "GLASS_CLAUDE: CLAUDE_PROJECT_DIR not set. Auditing disabled until fixed." >&2
    exit 2
fi

PROJECT_DIR="$CLAUDE_PROJECT_DIR"
HOME_DIR="$HOME"

mkdir -p "$AUDIT_DIR" 2>/dev/null

# --- Helper Functions ---
is_inside_project() {
    local path="$1"
    [ -n "$PROJECT_DIR" ] && [[ "$path" == "$PROJECT_DIR"* ]]
}

minimize_path() {
    local path="$1"
    path="${path/#$PROJECT_DIR/\{PROJECT\}}"
    echo "${path/#$HOME_DIR/~}"
}

extract_paths() {
    echo "$1" | grep -oE '(/[^ ]+|~[^ ]*)' | head -5
}

# --- Read and Validate Input ---
INPUT=$(cat)

# Validate expected JSON structure
if ! echo "$INPUT" | "$JQ" -e '.tool_name' &>/dev/null; then
    echo "$(date -u +%Y-%m-%dT%H:%M:%S)|SYSTEM|FATAL|Invalid JSON - tool_name missing" >> "$ERROR_LOG"
    exit 2
fi

TOOL_NAME=$("$JQ" -r '.tool_name' <<< "$INPUT")
TOOL_INPUT=$("$JQ" -c '.tool_input // {}' <<< "$INPUT")
TOOL_RESPONSE=$("$JQ" -r '.tool_response // empty' <<< "$INPUT")

# --- Error Logging ---
# Check tool_response for errors
if echo "$TOOL_RESPONSE" | grep -qiE '(error|failed|exception|denied|refused|timeout)'; then
    TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%S)
    SNIPPET=$(echo "$TOOL_RESPONSE" | head -c 300 | tr '\n' ' ')
    echo "${TIMESTAMP}|${TOOL_NAME}|RESULT_ERROR|${SNIPPET}" >> "$ERROR_LOG"
fi

# --- Skip Internal Tools ---
case "$TOOL_NAME" in
    TodoWrite|AskUserQuestion|EnterPlanMode|ExitPlanMode|TaskOutput)
        exit 0
        ;;
esac

# --- Determine Target and Log Decision ---
TARGET=""
SHOULD_LOG=false

case "$TOOL_NAME" in
    Read|Write|Edit|NotebookEdit)
        TARGET=$("$JQ" -r '.file_path // .notebook_path // empty' <<< "$TOOL_INPUT")
        if [ -n "$TARGET" ] && ! is_inside_project "$TARGET"; then
            SHOULD_LOG=true
            TARGET=$(minimize_path "$TARGET")
        fi
        ;;

    Glob)
        TARGET=$("$JQ" -r '.path // "."' <<< "$TOOL_INPUT")
        PATTERN=$("$JQ" -r '.pattern // empty' <<< "$TOOL_INPUT")
        if ! is_inside_project "$TARGET"; then
            SHOULD_LOG=true
            TARGET="$(minimize_path "$TARGET")/$PATTERN"
        fi
        ;;

    Grep)
        TARGET=$("$JQ" -r '.path // "."' <<< "$TOOL_INPUT")
        PATTERN=$("$JQ" -r '.pattern // empty' <<< "$TOOL_INPUT")
        if ! is_inside_project "$TARGET"; then
            SHOULD_LOG=true
            TARGET="$(minimize_path "$TARGET") pattern:${PATTERN:0:50}"
        fi
        ;;

    Bash)
        CMD=$("$JQ" -r '.command // empty' <<< "$TOOL_INPUT" | head -c 300)
        PATHS=$(extract_paths "$CMD")

        if [ -z "$PATHS" ]; then
            SHOULD_LOG=true
        else
            for P in $PATHS; do
                EXPANDED="${P/#\~/$HOME_DIR}"
                if ! is_inside_project "$EXPANDED"; then
                    SHOULD_LOG=true
                    break
                fi
            done
        fi

        if $SHOULD_LOG; then
            TARGET=$(minimize_path "$CMD")
        fi
        ;;

    Task)
        SHOULD_LOG=true
        TARGET=$("$JQ" -r '.description // empty' <<< "$TOOL_INPUT")
        ;;

    WebFetch)
        SHOULD_LOG=true
        TARGET=$("$JQ" -r '.url // empty' <<< "$TOOL_INPUT" | head -c 100)
        ;;

    WebSearch)
        SHOULD_LOG=true
        TARGET=$("$JQ" -r '.query // empty' <<< "$TOOL_INPUT" | head -c 100)
        ;;

    Skill)
        SHOULD_LOG=true
        TARGET=$("$JQ" -r '.skill // empty' <<< "$TOOL_INPUT")
        ;;

    KillShell)
        SHOULD_LOG=true
        TARGET=$("$JQ" -r '.shell_id // empty' <<< "$TOOL_INPUT")
        ;;

    mcp__*)
        SHOULD_LOG=true
        TARGET=$(echo "$TOOL_INPUT" | head -c 150)
        ;;

    *)
        SHOULD_LOG=true
        TARGET=$(echo "$TOOL_INPUT" | head -c 100)
        ;;
esac

# --- Write Audit Log ---
if $SHOULD_LOG && [ -n "$TARGET" ]; then
    TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%S)
    echo "${TIMESTAMP}|${TOOL_NAME}|${TARGET}" >> "$AUDIT_LOG"
fi

exit 0
