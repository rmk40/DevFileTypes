#!/bin/bash
# set-default-editor.sh
# Set a default "Open With" editor for developer file extensions managed
# by DevFileTypes. Only overrides extensions that have macOS default handlers
# or clearly wrong handlers — leaves user-configured editors alone.
#
# Usage:
#   ./set-default-editor.sh                       Interactive: scan, prompt, set
#   ./set-default-editor.sh <editor>              Set Apple defaults to <editor>
#   ./set-default-editor.sh --check               Show current state, change nothing
#   ./set-default-editor.sh --revert              Restore from default backup
#   ./set-default-editor.sh --backup <path>       Save current handlers to file
#   ./set-default-editor.sh --restore <path>      Restore handlers from file
#   ./set-default-editor.sh --help                Show usage
#
# <editor> is a shorthand (vscode, cursor, zed, sublime, nova, webstorm,
# intellij) or a raw bundle ID (e.g., com.microsoft.VSCode).
#
# Requires duti. Install via: brew install duti
# Compatible with macOS system bash (3.2+).

set -u

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

BACKUP_FILE="$HOME/.devfiletypes-editor-backup"

# Developer file extensions to manage.
# The first group is from DevFileTypes.app/Contents/Info.plist (UTI fixes).
# The second group has correct macOS UTIs but commonly get assigned to the
# wrong app (Xcode, TextEdit, etc.) instead of a code editor.
EXTENSIONS="ts mts cts r R tsx jsx vue svelte astro rs go zig nim kt kts scala sc groovy gvy cs fs fsi fsx dart lua coffee ex exs elm hs lhs ml mli tf tfvars hcl toml nix dhall graphql gql proto prisma sass scss less styl jade pug ejs hbs handlebars mustache twig jinja jinja2 j2 mdx ipynb json yaml yml xml py rb bash zsh env conf tsv sql lock gitignore gitattributes editorconfig dockerfile makefile gemspec cmake gradle properties patch diff"

# Known code editors — if an extension is handled by one of these, skip it.
KNOWN_EDITORS="
com.microsoft.VSCode
com.microsoft.VSCodeInsiders
com.todesktop.230313mzl4w4u92
dev.zed.Zed
com.sublimetext.4
com.sublimetext.3
com.panic.Nova
com.barebones.bbedit
com.macromates.TextMate
com.github.atom
"

# Prefix matches (covers all JetBrains IDEs)
KNOWN_EDITOR_PREFIXES="com.jetbrains."

# Shorthand names for interactive/non-interactive editor selection.
# Format: shorthand:bundle_id:display_name
EDITOR_SHORTHANDS="
vscode:com.microsoft.VSCode:Visual Studio Code
cursor:com.todesktop.230313mzl4w4u92:Cursor
zed:dev.zed.Zed:Zed
sublime:com.sublimetext.4:Sublime Text
nova:com.panic.Nova:Nova
webstorm:com.jetbrains.WebStorm:WebStorm
intellij:com.jetbrains.intellij:IntelliJ IDEA
"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

usage() {
    echo "Usage: $0 [<editor> | --check | --revert | --backup <path> | --restore <path> | --help]"
    echo ""
    echo "  (no args)          Scan file associations, prompt for editor, set"
    echo "  <editor>           Set Apple defaults to <editor> (no prompt)"
    echo "  --check            Show current handlers, change nothing"
    echo "  --revert           Restore from ~/.devfiletypes-editor-backup"
    echo "  --backup <path>    Save current handlers to a file"
    echo "  --restore <path>   Restore handlers from a file"
    echo "  --help, -h         Show this help message"
    echo ""
    echo "Editors: vscode, cursor, zed, sublime, nova, webstorm, intellij"
    echo "Or pass a raw bundle ID (e.g., com.microsoft.VSCode)."
}

check_macos() {
    if [ "$(uname -s)" != "Darwin" ]; then
        echo "Error: This tool is macOS-only. Detected OS: $(uname -s)"
        exit 1
    fi
}

check_duti() {
    if ! command -v duti &>/dev/null; then
        echo "Error: duti is not installed."
        echo ""
        echo "Install it with:"
        echo "  brew install duti"
        echo ""
        echo "Or run ./install-companions.sh to install all companion tools."
        exit 1
    fi
}

# Resolve a shorthand name or bundle ID to a bundle ID.
# Prints the bundle ID on stdout. Returns 1 on failure (errors to stderr).
resolve_editor() {
    local input="$1"

    # If it contains a dot, treat as a raw bundle ID
    case "$input" in
        *.*)
            printf '%s\n' "$input"
            return 0
            ;;
    esac

    # Look up shorthand
    local line=""
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        local shorthand="${line%%:*}"
        local rest="${line#*:}"
        local bundle_id="${rest%%:*}"
        if [ "$shorthand" = "$input" ]; then
            printf '%s\n' "$bundle_id"
            return 0
        fi
    done <<EOF
$EDITOR_SHORTHANDS
EOF

    echo "Error: Unknown editor '$input'" >&2
    echo "" >&2
    echo "Known shorthands: vscode, cursor, zed, sublime, nova, webstorm, intellij" >&2
    echo "Or pass a raw bundle ID (e.g., com.microsoft.VSCode)." >&2
    return 1
}

# Get the display name for a bundle ID (from shorthand table or the ID itself).
display_name_for_bundle() {
    local bundle_id="$1"
    local line=""
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        local rest="${line#*:}"
        local bid="${rest%%:*}"
        local name="${rest#*:}"
        if [ "$bid" = "$bundle_id" ]; then
            printf '%s\n' "$name"
            return 0
        fi
    done <<EOF
$EDITOR_SHORTHANDS
EOF
    printf '%s\n' "$bundle_id"
}

# Check if a bundle ID is a known code editor.
is_known_editor() {
    local bundle_id="$1"

    # Check exact matches
    local entry=""
    while IFS= read -r entry; do
        [ -z "$entry" ] && continue
        if [ "$entry" = "$bundle_id" ]; then
            return 0
        fi
    done <<EOF
$KNOWN_EDITORS
EOF

    # Check prefix matches
    local prefix=""
    while IFS= read -r prefix; do
        [ -z "$prefix" ] && continue
        case "$bundle_id" in
            "$prefix"*)
                return 0
                ;;
        esac
    done <<EOF
$KNOWN_EDITOR_PREFIXES
EOF

    return 1
}

# Get the current handler for an extension.
# Prints: app_name<TAB>bundle_id
# Returns 1 if no handler found.
get_handler() {
    local ext="$1"
    local output=""

    output="$(duti -x "$ext" 2>/dev/null)" || return 1

    local app_name=""
    local bundle_id=""
    app_name="$(echo "$output" | head -1)"
    bundle_id="$(echo "$output" | tail -1)"

    if [ -z "$bundle_id" ] || [ -z "$app_name" ]; then
        return 1
    fi

    printf '%s\t%s\n' "$app_name" "$bundle_id"
    return 0
}

# ---------------------------------------------------------------------------
# Categorize extensions into three buckets
# ---------------------------------------------------------------------------

# These get populated by categorize_extensions.
# Each entry is: ext<TAB>app_name<TAB>bundle_id
APPLE_DEFAULTS=""
AMBIGUOUS=""
KNOWN_EDITOR_EXTS=""
APPLE_DEFAULT_COUNT=0
AMBIGUOUS_COUNT=0
KNOWN_EDITOR_COUNT=0

categorize_extensions() {
    APPLE_DEFAULTS=""
    AMBIGUOUS=""
    KNOWN_EDITOR_EXTS=""
    APPLE_DEFAULT_COUNT=0
    AMBIGUOUS_COUNT=0
    KNOWN_EDITOR_COUNT=0

    for ext in $EXTENSIONS; do
        local handler=""
        handler="$(get_handler "$ext")" || true

        if [ -z "$handler" ]; then
            # No handler at all — treat as Apple default
            APPLE_DEFAULTS="${APPLE_DEFAULTS}${ext}	(none)	(none)
"
            APPLE_DEFAULT_COUNT=$((APPLE_DEFAULT_COUNT + 1))
            continue
        fi

        local app_name="${handler%%	*}"
        local bundle_id="${handler##*	}"

        case "$bundle_id" in
            com.apple.*)
                APPLE_DEFAULTS="${APPLE_DEFAULTS}${ext}	${app_name}	${bundle_id}
"
                APPLE_DEFAULT_COUNT=$((APPLE_DEFAULT_COUNT + 1))
                ;;
            *)
                if is_known_editor "$bundle_id"; then
                    KNOWN_EDITOR_EXTS="${KNOWN_EDITOR_EXTS}${ext}	${app_name}	${bundle_id}
"
                    KNOWN_EDITOR_COUNT=$((KNOWN_EDITOR_COUNT + 1))
                else
                    AMBIGUOUS="${AMBIGUOUS}${ext}	${app_name}	${bundle_id}
"
                    AMBIGUOUS_COUNT=$((AMBIGUOUS_COUNT + 1))
                fi
                ;;
        esac
    done
}

# Print a bucket of extensions as a formatted table.
print_bucket() {
    local data="$1"
    local line=""
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        local ext="${line%%	*}"
        local rest="${line#*	}"
        local app_name="${rest%%	*}"
        local bundle_id="${rest##*	}"
        printf "  %-15s %-30s %s\n" ".$ext" "$app_name" "$bundle_id"
    done <<EOF
$data
EOF
}

# ---------------------------------------------------------------------------
# Backup / restore
# ---------------------------------------------------------------------------

# Save current handlers for the given extensions to a file.
# Takes: file_path, newline-separated "ext\tapp\tbundle" entries
save_backup() {
    local path="$1"
    local entries="$2"

    {
        echo "# devfiletypes editor backup"
        echo "# Created: $(date -u +%Y-%m-%dT%H:%M:%S)"
        echo "# Restore: ./set-default-editor.sh --restore $path"

        local line=""
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            local ext="${line%%	*}"
            local rest="${line#*	}"
            local bundle_id="${rest##*	}"
            if [ "$bundle_id" != "(none)" ]; then
                echo ".$ext $bundle_id"
            fi
        done <<EOF
$entries
EOF
    } > "$path"
}

do_backup() {
    local path="$1"

    echo "Saving current handlers to $path..."

    local all_entries=""
    for ext in $EXTENSIONS; do
        local handler=""
        handler="$(get_handler "$ext")" || true

        if [ -z "$handler" ]; then
            continue
        fi

        local app_name="${handler%%	*}"
        local bundle_id="${handler##*	}"
        all_entries="${all_entries}${ext}	${app_name}	${bundle_id}
"
    done

    save_backup "$path" "$all_entries"
    echo "Done! Saved handlers for all managed extensions to $path"
}

do_restore() {
    local path="$1"

    if [ ! -f "$path" ]; then
        echo "Error: Backup file not found: $path"
        exit 1
    fi

    echo "Restoring handlers from $path..."

    local count=0
    local failures=0
    local line=""
    while IFS= read -r line; do
        # Skip comments and empty lines
        case "$line" in
            "#"*|"")
                continue
                ;;
        esac

        local ext="${line%% *}"
        local bundle_id="${line#* }"

        if duti -s "$bundle_id" "$ext" all 2>/dev/null; then
            count=$((count + 1))
        else
            echo "  Warning: Failed to restore $ext → $bundle_id"
            failures=$((failures + 1))
        fi
    done < "$path"

    echo "Done! Restored $count extensions."

    return "$failures"
}

do_revert() {
    if [ ! -f "$BACKUP_FILE" ]; then
        echo "Error: No backup found at $BACKUP_FILE"
        echo ""
        echo "Use --restore /path/to/file to restore from a specific file."
        exit 1
    fi

    local restore_failures=0
    do_restore "$BACKUP_FILE" || restore_failures=$?

    if [ "$restore_failures" -gt 0 ]; then
        echo "Backup preserved at $BACKUP_FILE (some restorations failed)."
    else
        rm -f "$BACKUP_FILE"
        echo "Backup file removed."
    fi
}

# ---------------------------------------------------------------------------
# Check (dry run)
# ---------------------------------------------------------------------------

do_check() {
    echo "=== Developer File Extension Handlers ==="
    echo ""

    categorize_extensions

    if [ $APPLE_DEFAULT_COUNT -gt 0 ]; then
        echo "Apple defaults (would be changed):"
        print_bucket "$APPLE_DEFAULTS"
        echo ""
    fi

    if [ $AMBIGUOUS_COUNT -gt 0 ]; then
        echo "Non-editor handlers (may be incorrect, interactive mode will ask):"
        print_bucket "$AMBIGUOUS"
        echo ""
    fi

    if [ $KNOWN_EDITOR_COUNT -gt 0 ]; then
        echo "Already using a code editor (no change needed):"
        print_bucket "$KNOWN_EDITOR_EXTS"
        echo ""
    fi

    if [ $APPLE_DEFAULT_COUNT -gt 0 ]; then
        echo "To fix the $APPLE_DEFAULT_COUNT extensions with Apple defaults, run:"
        echo "  ./set-default-editor.sh vscode"
    else
        echo "All extensions are already using third-party editors."
    fi
}

# ---------------------------------------------------------------------------
# Set (non-interactive)
# ---------------------------------------------------------------------------

do_set() {
    local bundle_id="$1"
    local editor_name=""
    editor_name="$(display_name_for_bundle "$bundle_id")"

    echo "=== Set Default Editor for Developer Files ==="
    echo ""
    echo "Editor: $editor_name ($bundle_id)"
    echo ""

    # Warn if the editor app doesn't appear to be installed
    if ! mdfind "kMDItemCFBundleIdentifier == '$bundle_id'" 2>/dev/null | head -1 | grep -q .; then
        echo "Note: $editor_name does not appear to be installed."
        echo "The preference will be set but won't take effect until the app is installed."
        echo ""
    fi

    categorize_extensions

    if [ $APPLE_DEFAULT_COUNT -eq 0 ] && [ $AMBIGUOUS_COUNT -eq 0 ]; then
        echo "All extensions are already using third-party editors. Nothing to do."
        return
    fi

    # In non-interactive mode, skip ambiguous extensions with a warning
    if [ $AMBIGUOUS_COUNT -gt 0 ]; then
        echo "Skipping (run interactively to override):"
        local line=""
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            local ext="${line%%	*}"
            local rest="${line#*	}"
            local app_name="${rest%%	*}"
            echo "  .$ext (currently $app_name)"
        done <<EOF
$AMBIGUOUS
EOF
        echo ""
    fi

    if [ $APPLE_DEFAULT_COUNT -eq 0 ]; then
        echo "No Apple defaults to update."
        return
    fi

    # Save backup (preserve original if it exists)
    if [ -f "$BACKUP_FILE" ]; then
        echo "Backup already exists at $BACKUP_FILE (preserving original)"
    else
        save_backup "$BACKUP_FILE" "$APPLE_DEFAULTS"
        echo "Saved backup to $BACKUP_FILE"
    fi

    echo "Updating $APPLE_DEFAULT_COUNT extensions..."
    echo ""

    local count=0
    local line=""
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        local ext="${line%%	*}"
        if duti -s "$bundle_id" ".$ext" all 2>/dev/null; then
            printf "  .%-14s → %s\n" "$ext" "$editor_name"
            count=$((count + 1))
        else
            echo "  Warning: Failed to set .$ext"
        fi
    done <<EOF
$APPLE_DEFAULTS
EOF

    echo ""
    echo "Done! Updated $count extensions."
    echo ""
    echo "To undo: ./set-default-editor.sh --revert"
}

# ---------------------------------------------------------------------------
# Set (interactive)
# ---------------------------------------------------------------------------

do_set_interactive() {
    echo "=== Set Default Editor for Developer Files ==="
    echo ""
    echo "Scanning current file associations..."
    echo ""

    categorize_extensions

    # Show Apple defaults
    if [ $APPLE_DEFAULT_COUNT -gt 0 ]; then
        echo "Apple defaults (will be updated):"
        print_bucket "$APPLE_DEFAULTS"
        echo ""
    fi

    # Show and ask about ambiguous handlers
    local ambiguous_to_set=""
    local ambiguous_set_count=0
    if [ $AMBIGUOUS_COUNT -gt 0 ]; then
        echo "Non-editor handlers (may be incorrect):"
        print_bucket "$AMBIGUOUS"
        echo ""

        local line=""
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            local ext="${line%%	*}"
            local rest="${line#*	}"
            local app_name="${rest%%	*}"
            local bundle_id="${rest##*	}"
            printf "  Override .%s (currently %s)? [Y/n]: " "$ext" "$app_name"
            read -r answer < /dev/tty
            case "${answer:-Y}" in
                [Yy]|[Yy]es|"")
                    ambiguous_to_set="${ambiguous_to_set}${line}
"
                    ambiguous_set_count=$((ambiguous_set_count + 1))
                    ;;
                *)
                    echo "  Skipping .$ext"
                    ;;
            esac
        done <<EOF
$AMBIGUOUS
EOF
        echo ""
    fi

    # Show known editors
    if [ $KNOWN_EDITOR_COUNT -gt 0 ]; then
        echo "Already using a code editor (no change):"
        print_bucket "$KNOWN_EDITOR_EXTS"
        echo ""
    fi

    local total_to_set=$((APPLE_DEFAULT_COUNT + ambiguous_set_count))
    if [ $total_to_set -eq 0 ]; then
        echo "Nothing to change."
        return
    fi

    # Detect installed editors and prompt for choice
    local bundle_id=""
    bundle_id="$(prompt_editor_choice)"
    if [ -z "$bundle_id" ]; then
        echo "No editor selected. Aborting."
        exit 1
    fi

    local editor_name=""
    editor_name="$(display_name_for_bundle "$bundle_id")"

    echo ""

    # Save backup (preserve original if it exists)
    local all_to_backup="${APPLE_DEFAULTS}${ambiguous_to_set}"
    if [ -f "$BACKUP_FILE" ]; then
        echo "Backup already exists at $BACKUP_FILE (preserving original)"
    else
        save_backup "$BACKUP_FILE" "$all_to_backup"
        echo "Saved backup to $BACKUP_FILE"
    fi

    echo "Updating $total_to_set extensions..."
    echo ""

    local count=0
    local all_to_set="${APPLE_DEFAULTS}${ambiguous_to_set}"
    local line=""
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        local ext="${line%%	*}"
        if duti -s "$bundle_id" ".$ext" all 2>/dev/null; then
            printf "  .%-14s → %s\n" "$ext" "$editor_name"
            count=$((count + 1))
        else
            echo "  Warning: Failed to set .$ext"
        fi
    done <<EOF
$all_to_set
EOF

    echo ""
    echo "Done! Updated $count extensions."
    echo ""
    echo "To undo: ./set-default-editor.sh --revert"
}

# Scan for installed editors and prompt the user to pick one.
# Prints the chosen bundle ID to stdout.
prompt_editor_choice() {
    local installed_editors=""
    local count=0

    local line=""
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        local rest="${line#*:}"
        local bundle_id="${rest%%:*}"
        local name="${rest#*:}"

        # Check if this editor is installed
        if mdfind "kMDItemCFBundleIdentifier == '$bundle_id'" 2>/dev/null | head -1 | grep -q .; then
            count=$((count + 1))
            installed_editors="${installed_editors}${count}:${bundle_id}:${name}
"
        fi
    done <<EOF
$EDITOR_SHORTHANDS
EOF

    if [ $count -eq 0 ]; then
        echo "No known editors detected in /Applications." >&2
        printf "Enter a bundle ID manually: " >&2
        local manual_id=""
        read -r manual_id < /dev/tty
        printf '%s\n' "$manual_id"
        return
    fi

    echo "Choose a default editor:" >&2
    echo "" >&2
    local entry=""
    while IFS= read -r entry; do
        [ -z "$entry" ] && continue
        local num="${entry%%:*}"
        local rest="${entry#*:}"
        local name="${rest#*:}"
        echo "  $num) $name" >&2
    done <<EOF
$installed_editors
EOF

    echo "" >&2
    printf "Enter choice [1]: " >&2
    local choice=""
    read -r choice < /dev/tty
    choice="${choice:-1}"

    # Find the chosen entry
    while IFS= read -r entry; do
        [ -z "$entry" ] && continue
        local num="${entry%%:*}"
        local rest="${entry#*:}"
        local bundle_id="${rest%%:*}"
        if [ "$num" = "$choice" ]; then
            printf '%s\n' "$bundle_id"
            return 0
        fi
    done <<EOF
$installed_editors
EOF

    echo "Error: Invalid choice '$choice'" >&2
    return 1
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

case "${1:-}" in
    --check)
        check_macos
        check_duti
        do_check
        ;;
    --revert)
        check_macos
        check_duti
        do_revert
        ;;
    --backup)
        check_macos
        check_duti
        if [ -z "${2:-}" ]; then
            echo "Error: --backup requires a file path"
            echo ""
            usage
            exit 1
        fi
        do_backup "$2"
        ;;
    --restore)
        check_macos
        check_duti
        if [ -z "${2:-}" ]; then
            echo "Error: --restore requires a file path"
            echo ""
            usage
            exit 1
        fi
        do_restore "$2"
        ;;
    --help|-h)
        usage
        ;;
    "")
        check_macos
        check_duti
        do_set_interactive
        ;;
    --*)
        check_macos
        echo "Error: Unknown option '$1'"
        echo ""
        usage
        exit 1
        ;;
    *)
        check_macos
        check_duti
        local_bundle_id="$(resolve_editor "$1")" || exit 1
        do_set "$local_bundle_id"
        ;;
esac
