#!/bin/bash
# install-companions.sh
# Installs or uninstalls recommended companion tools for DevFileTypes.
#
# Quick Look providers (pick one):
#   - Syntax Highlight + QLMarkdown: deep coverage, configurable, two focused apps
#   - Glance: single app covering source code, Markdown, archives, notebooks
#
# Also installs duti for setting default "open with" handlers.
#
# Usage:
#   ./install-companions.sh                    Interactive — prompts for Quick Look choice
#   ./install-companions.sh --syntax-highlight  Syntax Highlight + QLMarkdown + duti
#   ./install-companions.sh --glance            Glance + duti
#   ./install-companions.sh --uninstall         Remove all companion tools
#   ./install-companions.sh --help              Show usage
#
# Compatible with macOS system bash (3.2+). No associative arrays.

# Don't use set -e globally — each tool installs independently so one failure
# shouldn't prevent the others from installing.
set -u

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

FAILURES=0

usage() {
    echo "Usage: $0 [--syntax-highlight | --glance | --uninstall | --help]"
    echo ""
    echo "  (no args)            Prompt for Quick Look provider, then install"
    echo "  --syntax-highlight   Install Syntax Highlight + QLMarkdown + duti"
    echo "  --glance             Install Glance + duti"
    echo "  --uninstall          Remove all companion tools"
    echo "  --help, -h           Show this help message"
}

check_macos() {
    if [ "$(uname -s)" != "Darwin" ]; then
        echo "Error: This tool is macOS-only. Detected OS: $(uname -s)"
        exit 1
    fi
}

check_homebrew() {
    if ! command -v brew &>/dev/null; then
        echo "Error: Homebrew is not installed."
        echo ""
        echo "Homebrew is required to install the companion tools. Install it with:"
        echo ""
        echo '  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
        echo ""
        echo "Then re-run this script."
        exit 1
    fi
}

is_cask_installed() {
    brew list --cask "$1" &>/dev/null
}

is_formula_installed() {
    brew list --formula "$1" &>/dev/null
}

resolve_app_path() {
    local cask="$1"
    local app_name="$2"
    local candidate=""

    for candidate in "/Applications/$app_name" "$HOME/Applications/$app_name"; do
        if [ -d "$candidate" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    while IFS= read -r candidate; do
        case "$candidate" in
            *.app)
                if [ "$(basename "$candidate")" = "$app_name" ] && [ -d "$candidate" ]; then
                    printf '%s\n' "$candidate"
                    return 0
                fi
                ;;
        esac
    done <<EOF
$(brew list --cask "$cask" 2>/dev/null)
EOF

    return 1
}

# ---------------------------------------------------------------------------
# Cask / formula operations
# ---------------------------------------------------------------------------

install_cask() {
    local cask="$1"
    local app_name="$2"

    if is_cask_installed "$cask"; then
        echo "  $cask: already installed, refreshing registration"
        register_cask_app "$cask" "$app_name"
        return
    fi

    echo "  Installing $cask..."
    if brew install --cask "$cask"; then
        register_cask_app "$cask" "$app_name"
    else
        echo "  Warning: Failed to install $cask"
        FAILURES=$((FAILURES + 1))
    fi
}

register_cask_app() {
    local cask="$1"
    local app_name="$2"
    local app_path=""

    app_path="$(resolve_app_path "$cask" "$app_name" || true)"

    if [ -z "$app_path" ] || [ ! -d "$app_path" ]; then
        echo "  Warning: Could not locate $app_name to launch it"
        FAILURES=$((FAILURES + 1))
        return
    fi

    # Clear quarantine flag (may not be present — suppress errors).
    xattr -rd com.apple.quarantine "$app_path" 2>/dev/null || true

    # Launch once so macOS discovers the Quick Look extension.
    echo "  Launching $cask to register Quick Look extension..."
    if ! open "$app_path"; then
        echo "  Warning: Failed to launch $app_path"
        FAILURES=$((FAILURES + 1))
    fi
}

install_formula() {
    local formula="$1"

    if is_formula_installed "$formula"; then
        echo "  $formula: already installed, skipping"
        return
    fi

    echo "  Installing $formula..."
    if ! brew install "$formula"; then
        echo "  Warning: Failed to install $formula"
        FAILURES=$((FAILURES + 1))
    fi
}

uninstall_cask() {
    local cask="$1"

    if ! is_cask_installed "$cask"; then
        return
    fi

    echo "  Removing $cask..."
    if ! brew uninstall --cask "$cask"; then
        echo "  Warning: Failed to remove $cask"
        FAILURES=$((FAILURES + 1))
    fi
}

uninstall_formula() {
    local formula="$1"

    if ! is_formula_installed "$formula"; then
        return
    fi

    echo "  Removing $formula..."
    if ! brew uninstall "$formula"; then
        echo "  Warning: Failed to remove $formula"
        FAILURES=$((FAILURES + 1))
    fi
}

# ---------------------------------------------------------------------------
# Conflict removal
# ---------------------------------------------------------------------------

remove_conflicting_glance() {
    if is_cask_installed "glance-chamburr"; then
        echo "  Removing glance (conflicts with Syntax Highlight)..."
        brew uninstall --cask "glance-chamburr" || true
    fi
}

remove_conflicting_syntax_highlight() {
    if is_cask_installed "syntax-highlight"; then
        echo "  Removing syntax-highlight (conflicts with Glance)..."
        brew uninstall --cask "syntax-highlight" || true
    fi
    if is_cask_installed "qlmarkdown"; then
        echo "  Removing qlmarkdown (conflicts with Glance)..."
        brew uninstall --cask "qlmarkdown" || true
    fi
}

# ---------------------------------------------------------------------------
# Install modes
# ---------------------------------------------------------------------------

do_install_syntax_highlight() {
    echo "Installing: Syntax Highlight + QLMarkdown + duti"
    echo ""

    remove_conflicting_glance

    install_cask "syntax-highlight" "Syntax Highlight.app"
    install_cask "qlmarkdown" "QLMarkdown.app"
    install_formula "duti"

    print_install_summary
}

do_install_glance() {
    echo "Installing: Glance + duti"
    echo ""

    remove_conflicting_syntax_highlight

    install_cask "glance-chamburr" "Glance.app"
    install_formula "duti"

    print_install_summary
}

print_install_summary() {
    echo ""
    if [ $FAILURES -gt 0 ]; then
        echo "Some tools failed to install. Check the output above for details."
        echo "You can retry individual installs with: brew install <name>"
        echo ""
        echo "If Quick Look previews are not active yet, open the Quick Look app"
        echo "manually once after resolving the warnings above."
        echo ""
    else
        echo "Quick Look helper apps were launched to register their extensions."
        echo "Press Space on a source file in Finder to verify previews are active."
        echo ""
    fi

    echo "To set your editor as the default for all developer file extensions, run:"
    echo "  ./set-default-editor.sh"

    if [ $FAILURES -gt 0 ]; then
        exit 1
    fi
}

# ---------------------------------------------------------------------------
# Interactive prompt
# ---------------------------------------------------------------------------

do_install_interactive() {
    echo "=== DevFileTypes Companion Tools Installer ==="
    echo ""
    echo "Choose a Quick Look provider:"
    echo ""
    echo "  1) Syntax Highlight + QLMarkdown"
    echo "     Deep language coverage, configurable themes, rich Markdown rendering."
    echo "     Two apps from the same developer, each focused on one job."
    echo ""
    echo "  2) Glance"
    echo "     Single app covering source code, Markdown, archives, and notebooks."
    echo "     Simpler setup, less configurable."
    echo ""
    printf "Enter choice [1]: "
    read -r choice

    case "${choice:-1}" in
        1)
            echo ""
            do_install_syntax_highlight
            ;;
        2)
            echo ""
            do_install_glance
            ;;
        *)
            echo ""
            echo "Error: Invalid choice '$choice'. Enter 1 or 2."
            exit 1
            ;;
    esac
}

# ---------------------------------------------------------------------------
# Uninstall
# ---------------------------------------------------------------------------

do_uninstall() {
    echo "=== DevFileTypes Companion Tools Uninstaller ==="
    echo ""

    local found=0
    for cask in syntax-highlight qlmarkdown glance-chamburr; do
        if is_cask_installed "$cask"; then
            found=1
            uninstall_cask "$cask"
        fi
    done
    if is_formula_installed "duti"; then
        found=1
        uninstall_formula "duti"
    fi

    if [ $found -eq 0 ]; then
        echo "  No companion tools installed. Nothing to do."
        echo ""
        return
    fi

    echo ""
    if [ $FAILURES -gt 0 ]; then
        echo "Some tools failed to uninstall. Try removing them manually with:"
        echo "  brew uninstall --cask <name>  or  brew uninstall <name>"
        exit 1
    else
        echo "Done! Companion tools have been removed."
    fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

case "${1:-}" in
    --syntax-highlight)
        check_macos
        check_homebrew
        echo "=== DevFileTypes Companion Tools Installer ==="
        echo ""
        do_install_syntax_highlight
        ;;
    --glance)
        check_macos
        check_homebrew
        echo "=== DevFileTypes Companion Tools Installer ==="
        echo ""
        do_install_glance
        ;;
    --uninstall)
        check_macos
        check_homebrew
        do_uninstall
        ;;
    --help|-h)
        usage
        ;;
    "")
        check_macos
        check_homebrew
        do_install_interactive
        ;;
    *)
        check_macos
        echo "Error: Unknown option '$1'"
        echo ""
        usage
        exit 1
        ;;
esac
