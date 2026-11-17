#!/bin/bash
# YEN Common Utilities
# Shared colors, formatting, and prompts

# Brand color: #ff5100 (RGB: 255, 81, 0)
ORANGE='\033[38;2;255;81;0m'
GREEN='\033[38;2;34;197;94m'
RED='\033[38;2;239;68;68m'
YELLOW='\033[38;2;234;179;8m'
GRAY='\033[38;5;245m'
BOLD='\033[1m'
RESET='\033[0m'

# Print success message
yen_success() {
    printf "${GREEN}%s${RESET}\n" "$1"
}

# Print error message
yen_error() {
    printf "${RED}%s${RESET}\n" "$1" >&2
}

# Print warning message
yen_warn() {
    printf "${YELLOW}%s${RESET}\n" "$1"
}

# Print info message
yen_info() {
    printf "${GRAY}%s${RESET}\n" "$1"
}

# Print brand-colored header
yen_header() {
    printf "\n${ORANGE}${BOLD}%s${RESET}\n\n" "$1"
}

# Prompt for input
yen_prompt() {
    local prompt="$1"
    local var_name="$2"
    printf "${ORANGE}%s${RESET} " "$prompt"
    read -r "$var_name"
}

# Check if command exists
yen_command_exists() {
    command -v "$1" &> /dev/null
}
