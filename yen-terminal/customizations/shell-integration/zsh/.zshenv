# Based on (started as) a copy of Kitty's zsh integration. Kitty is
# distributed under GPLv3, so this file is also distributed under GPLv3.
# The license header is reproduced below:
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

# YEN CUSTOMIZATION: Add bundled binaries to PATH and print welcome banner
# This runs FIRST when zsh starts, before any other initialization
if [[ -o 'interactive' ]]; then
    local resources_dir="${YEN_RESOURCES_DIR:-${GHOSTTY_RESOURCES_DIR}}"
    if [[ -n "$resources_dir" ]]; then
        # Add app bundle bin to PATH so bundled tools (yen, browse, etc.) are available
        # resources_dir may be Resources or Resources/yen — bin is at Resources/bin
        local bin_dir="$resources_dir/bin"
        if [[ ! -d "$bin_dir" ]]; then
            bin_dir="${resources_dir%/*}/bin"
        fi
        if [[ -d "$bin_dir" ]] && [[ ":$PATH:" != *":$bin_dir:"* ]]; then
            'builtin' 'export' PATH="$bin_dir:$PATH"
        fi
        # Parse version once here so the welcome banner and yen-integration
        # both reuse the cached value instead of re-parsing version.json
        if [[ -z "$YEN_VERSION" ]]; then
            local version_file="$resources_dir/version.json"
            if [[ -f "$version_file" ]]; then
                local ver_line=""
                while IFS= read -r ver_line; do
                    case "$ver_line" in
                        *'"version"'*)
                            YEN_VERSION="${ver_line#*\"version\"*:*\"}"
                            YEN_VERSION="${YEN_VERSION%%\"*}"
                            break
                            ;;
                    esac
                done < "$version_file"
                if [[ -n "$YEN_VERSION" ]]; then
                    'builtin' 'export' TERM_PROGRAM="yen"
                    'builtin' 'export' TERM_PROGRAM_VERSION="$YEN_VERSION"
                    'builtin' 'export' YEN_VERSION
                fi
            fi
        fi
        if [[ -z "$YEN_WELCOME_SHOWN" ]]; then
            local yen_welcome="$resources_dir/shell-integration/yen-welcome.sh"
            if [[ -f "$yen_welcome" ]]; then
                'builtin' 'source' '--' "$yen_welcome"
            fi
        fi
    fi
fi

# Restore the original ZDOTDIR value if YEN_ZSH_ZDOTDIR is set.
# Otherwise, unset the ZDOTDIR that was set during shell injection.
# CRITICAL: Must match vendor's environment variable name (YEN_ZSH_ZDOTDIR, not GHOSTTY_ZSH_ZDOTDIR)
if [[ -n "${YEN_ZSH_ZDOTDIR+X}" ]]; then
    'builtin' 'export' ZDOTDIR="$YEN_ZSH_ZDOTDIR"
    'builtin' 'unset' 'YEN_ZSH_ZDOTDIR'
else
    'builtin' 'unset' 'ZDOTDIR'
fi

# Use try-always to have the right error code.
{
    # Zsh treats unset ZDOTDIR as if it was HOME. We do the same.
    #
    # Source the user's .zshenv before sourcing yen-integration because the
    # former might set fpath and other things without which yen-integration
    # won't work.
    #
    # Use typeset in case we are in a function with warn_create_global in
    # effect. Unlikely but better safe than sorry.
    'builtin' 'typeset' _yen_file=${ZDOTDIR-$HOME}"/.zshenv"
    # Zsh ignores unreadable rc files. We do the same.
    # Zsh ignores rc files that are directories, and so does source.
    [[ ! -r "$_yen_file" ]] || 'builtin' 'source' '--' "$_yen_file"
} always {
    if [[ -o 'interactive' ]]; then
        # ${(%):-%x} is the path to the current file.
        # On top of it we add :A:h to get the directory.
        'builtin' 'typeset' _yen_file="${${(%):-%x}:A:h}"/yen-integration
        if [[ -r "$_yen_file" ]]; then
            'builtin' 'autoload' '-Uz' '--' "$_yen_file"
            "${_yen_file:t}"
            'builtin' 'unfunction' '--' "${_yen_file:t}"
        fi
    fi
    'builtin' 'unset' '_yen_file'
}

