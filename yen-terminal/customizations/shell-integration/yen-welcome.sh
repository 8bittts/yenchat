#!/bin/sh
# YEN Welcome Banner
# Shell-agnostic version that works for both bash and zsh
#
# This script prints the YEN welcome banner once per terminal session.
# It reads version AND notes from version.json in the app bundle.
#
# The Dev Note mirrors the "notes" field from version.json — same as
# what users see in Sparkle update notifications. Single source of truth.

# Only show once per session
if [ -n "$YEN_WELCOME_SHOWN" ]; then
    return 0
fi

# Get version and notes from app bundle (unified version system)
# Reads from version.json bundled in app - single source of truth
# Read only the YEN resource root exported by the terminal runtime.
YEN_VERSION="${YEN_VERSION:-}"
DEV_NOTE=""
RESOURCES_DIR="${YEN_RESOURCES_DIR}"
VERSION_FILE=""
if [ -n "$RESOURCES_DIR" ]; then
    VERSION_FILE="$RESOURCES_DIR/version.json"
    if [ -f "$VERSION_FILE" ]; then
        # Extract version only if not already set by .zshenv / bash integration
        if [ -z "$YEN_VERSION" ]; then
            YEN_VERSION=$(grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' "$VERSION_FILE" | sed 's/.*"\([^"]*\)".*/\1/' | head -1)
            if [ -z "$YEN_VERSION" ] || [ "$YEN_VERSION" = "" ]; then
                YEN_VERSION=$(grep '"version"' "$VERSION_FILE" | sed 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' | head -1)
            fi
        fi

        # Always extract notes (not cached by shell integration)
        DEV_NOTE=$(grep -o '"notes"[[:space:]]*:[[:space:]]*"[^"]*"' "$VERSION_FILE" | sed 's/.*"\([^"]*\)".*/\1/' | head -1)
    fi
fi

# Fallbacks
if [ -z "$YEN_VERSION" ] || [ "$YEN_VERSION" = "" ]; then
    YEN_VERSION="dev"
fi
if [ -z "$DEV_NOTE" ] || [ "$DEV_NOTE" = "" ]; then
    DEV_NOTE="Welcome to YEN!"
fi

# Keep the copy theme-aware, but pin the ASCII mark to the brand orange.
printf "\n  \033[38;2;255;81;0m┓┏┏┓┳┓\033[0m\n"
printf "  \033[38;2;255;81;0m┗┫┣ ┃┃\033[0m\n"
printf "  \033[38;2;255;81;0m┗┛┗┛┛┗\033[0m\n\n"
printf "  Welcome to your \033[1mPersonal Terminal Experience.\033[0m\n"
printf "  \033[1mOption + Space\033[0m Voice · \033[1mCmd + ,\033[0m Settings\n"
printf "  \033[1mv%s:\033[0m %s\n\n" "$YEN_VERSION" "$DEV_NOTE"

# Mark banner as shown for this session
export YEN_WELCOME_SHOWN=1
