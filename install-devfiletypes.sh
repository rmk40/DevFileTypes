#!/bin/bash
# install-devfiletypes.sh
# Installs or uninstalls DevFileTypes.app and rebuilds the Launch Services
# database so macOS treats developer file extensions as source code / plain text.
#
# Usage:
#   ./install-devfiletypes.sh              Install DevFileTypes
#   ./install-devfiletypes.sh --uninstall  Remove DevFileTypes
#   ./install-devfiletypes.sh --help       Show usage

set -euo pipefail

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

APP_NAME="DevFileTypes.app"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE="$SCRIPT_DIR/$APP_NAME"
DEST="/Applications/$APP_NAME"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

usage() {
    echo "Usage: $0 [--uninstall | --help]"
    echo ""
    echo "  (no args)     Install DevFileTypes.app to /Applications"
    echo "  --uninstall   Remove DevFileTypes.app from /Applications"
    echo "  --help, -h    Show this help message"
}

check_macos() {
    if [ "$(uname -s)" != "Darwin" ]; then
        echo "Error: This tool is macOS-only. Detected OS: $(uname -s)"
        exit 1
    fi
}

check_lsregister() {
    if [ ! -x "$LSREGISTER" ]; then
        echo "Error: lsregister not found at expected path:"
        echo "  $LSREGISTER"
        echo ""
        echo "This is a core macOS system binary. If it's missing, your macOS"
        echo "installation may be incomplete or the path may have changed in"
        echo "a future macOS version."
        exit 1
    fi
}

rebuild_launchservices() {
    echo "Rebuilding Launch Services database (this may take a moment)..."
    "$LSREGISTER" -r -domain local -domain user
}

# ---------------------------------------------------------------------------
# Uninstall
# ---------------------------------------------------------------------------

do_uninstall() {
    echo "=== DevFileTypes Uninstaller ==="
    echo ""

    if [ ! -d "$DEST" ]; then
        echo "$APP_NAME is not installed in /Applications. Nothing to do."
        exit 0
    fi

    echo "Removing $DEST..."
    rm -rf "$DEST"

    rebuild_launchservices

    echo ""
    echo "Done! macOS default file type mappings have been restored."
    echo "You may need to restart apps or log out and back in for changes to take effect."
    echo ""
    echo "Note: Companion tools (Syntax Highlight, QLMarkdown, duti) are managed"
    echo "separately. Use ./install-companions.sh --uninstall to remove them."
}

# ---------------------------------------------------------------------------
# Install
# ---------------------------------------------------------------------------

do_install() {
    if [ ! -d "$SOURCE" ]; then
        echo "Error: $APP_NAME not found in $SCRIPT_DIR"
        echo ""
        echo "If you're building from source, run 'make' first to create the app bundle."
        exit 1
    fi

    echo "=== DevFileTypes Installer ==="
    echo ""
    echo "This will:"
    echo "  1. Copy $APP_NAME to /Applications"
    echo "  2. Register it with Launch Services"
    echo "  3. Rebuild the Launch Services database"
    echo ""
    echo "This fixes file type classification for dozens of developer file"
    echo "extensions,"
    echo "including .ts (incorrectly classified as MPEG-2 video by macOS)."
    echo ""

    # Copy app
    if [ -d "$DEST" ]; then
        echo "Removing existing installation..."
        rm -rf "$DEST"
    fi

    echo "Copying $APP_NAME to /Applications..."
    cp -R "$SOURCE" "$DEST"

    # Register with Launch Services
    echo "Registering with Launch Services..."
    "$LSREGISTER" -f "$DEST"

    rebuild_launchservices

    echo ""
    echo "Done! Changes should take effect immediately for most apps."
    echo "If some apps still show old file types, restart them or log out and back in."
    echo ""
    echo "To verify, run:"
    echo "  mdls -name kMDItemContentType /path/to/some/file.rs"
    echo ""
    echo "You should see a source-code UTI such as 'dev.devfiletypes.rust-source'."
    echo ""
    echo "For Quick Look previews and default app handlers, run:"
    echo "  ./install-companions.sh"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

check_macos
check_lsregister

case "${1:-}" in
    --uninstall)
        do_uninstall
        ;;
    --help|-h)
        usage
        ;;
    "")
        do_install
        ;;
    *)
        echo "Error: Unknown option '$1'"
        echo ""
        usage
        exit 1
        ;;
esac
