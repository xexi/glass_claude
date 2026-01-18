#!/bin/bash
# Glass Claude - Audit Logger
# Logs Claude Code tool usage

set -euo pipefail

readonly AUDIT_DIR="$HOME/.claude/debug"
readonly AUDIT_LOG="$AUDIT_DIR/audit.log"
readonly ERROR_LOG="$AUDIT_DIR/error.log"
readonly CONFIG_FILE="$HOME/.glass-claude/config"
readonly JQ_PATH="$HOME/.glass-claude/jq"
readonly INTERNAL_TOOLS="TodoWrite|AskUserQuestion|EnterPlanMode|ExitPlanMode|TaskOutput"

# --- Setup ---

init_jq() {
    if command -v jq &>/dev/null; then
        echo "jq"
    elif [[ -x "$JQ_PATH" ]]; then
        echo "$JQ_PATH"
    else
        log_error "SYSTEM" "FATAL" "jq not found"
        exit 2
    fi
}

load_config() {
    [[ -f "$CONFIG_FILE" ]] && grep -q "^exclude_pwd=true" "$CONFIG_FILE" 2>/dev/null
}

# --- Logging ---

log_error() {
    local tool="$1" type="$2" message="$3"
    echo "$(date -u +%Y-%m-%dT%H:%M:%S)|${tool}|${type}|${message}" >> "$ERROR_LOG"
}

log_audit() {
    local tool="$1" target="$2"
    echo "$(date -u +%Y-%m-%dT%H:%M:%S)|${tool}|${target}" >> "$AUDIT_LOG"
}

# --- Path Helpers ---

minimize_path() {
    local path="$1"
    path="${path/#$CLAUDE_PROJECT_DIR/\{PWD\}}"
    echo "${path/#$HOME/~}"
}

is_inside_pwd() {
    local path="$1"
    [[ -n "${CLAUDE_PROJECT_DIR:-}" && "$path" == "$CLAUDE_PROJECT_DIR"* ]]
}

extract_paths() {
    grep -oE '(/[^ ]+|~[^ ]*)' <<< "$1" | head -5
}

has_external_path() {
    local cmd="$1"
    local paths
    paths=$(extract_paths "$cmd")

    [[ -z "$paths" ]] && return 0  # No paths = unknown scope = external

    while IFS= read -r p; do
        local expanded="${p/#\~/$HOME}"
        is_inside_pwd "$expanded" || return 0
    done <<< "$paths"

    return 1
}

# --- Target Extraction ---

extract_target() {
    local tool="$1" input="$2"

    case "$tool" in
        Read|Write|Edit|NotebookEdit)
            $JQ -r '.file_path // .notebook_path // empty' <<< "$input"
            ;;
        Glob)
            local path pattern
            path=$($JQ -r '.path // "."' <<< "$input")
            pattern=$($JQ -r '.pattern // empty' <<< "$input")
            echo "${path}/${pattern}"
            ;;
        Grep)
            local path pattern
            path=$($JQ -r '.path // "."' <<< "$input")
            pattern=$($JQ -r '.pattern // empty' <<< "$input")
            echo "${path} pattern:${pattern:0:50}"
            ;;
        Bash)
            $JQ -r '.command // empty' <<< "$input" | head -c 300
            ;;
        Task)
            $JQ -r '.description // empty' <<< "$input"
            ;;
        WebFetch)
            $JQ -r '.url // empty' <<< "$input" | head -c 100
            ;;
        WebSearch)
            $JQ -r '.query // empty' <<< "$input" | head -c 100
            ;;
        Skill)
            $JQ -r '.skill // empty' <<< "$input"
            ;;
        KillShell)
            $JQ -r '.shell_id // empty' <<< "$input"
            ;;
        mcp__*)
            head -c 150 <<< "$input"
            ;;
        *)
            head -c 100 <<< "$input"
            ;;
    esac
}

should_exclude() {
    local tool="$1" target="$2"

    # Never exclude web/external tools
    case "$tool" in
        Task|WebFetch|WebSearch|Skill|KillShell|mcp__*) return 1 ;;
    esac

    # Exclude if inside PWD (when config enabled)
    case "$tool" in
        Bash)
            ! has_external_path "$target"
            ;;
        *)
            is_inside_pwd "$target"
            ;;
    esac
}

# --- Main ---

main() {
    mkdir -p "$AUDIT_DIR" 2>/dev/null

    JQ=$(init_jq)
    EXCLUDE_PWD=$(load_config && echo true || echo false)

    local input tool_name tool_input tool_response
    input=$(cat)

    # Validate JSON
    if ! $JQ -e '.tool_name' <<< "$input" &>/dev/null; then
        log_error "SYSTEM" "FATAL" "Invalid JSON - tool_name missing"
        exit 2
    fi

    tool_name=$($JQ -r '.tool_name' <<< "$input")
    tool_input=$($JQ -c '.tool_input // {}' <<< "$input")
    tool_response=$($JQ -r '.tool_response // empty' <<< "$input")

    # Log errors from tool response
    if grep -qiE '(error|failed|exception|denied|refused|timeout)' <<< "$tool_response"; then
        local snippet
        snippet=$(head -c 300 <<< "$tool_response" | tr '\n' ' ')
        log_error "$tool_name" "RESULT_ERROR" "$snippet"
    fi

    # Skip internal tools
    [[ "$tool_name" =~ ^($INTERNAL_TOOLS)$ ]] && exit 0

    # Extract target
    local target
    target=$(extract_target "$tool_name" "$tool_input")
    [[ -z "$target" ]] && exit 0

    # Apply exclusion filter
    if [[ "$EXCLUDE_PWD" == "true" ]] && should_exclude "$tool_name" "$target"; then
        exit 0
    fi

    # Log it
    log_audit "$tool_name" "$(minimize_path "$target")"
}

main "$@"
