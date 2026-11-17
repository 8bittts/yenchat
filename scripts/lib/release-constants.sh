#!/bin/bash
# release-constants.sh - shared GitHub Releases constants for release scripts.
#
# Every desktop release is a GitHub Release on the public repository, tagged
# v<version> (v1.272). The DMG, its .sha256 and the Sparkle deltas are assets of
# that release, so one release URL prefix serves all of them.

GITHUB_RELEASES_REPO="8bittts/yenchat"
GITHUB_RELEASES_HOSTNAME="github.com"
GITHUB_RELEASES_DOWNLOAD_BASE_URL="https://${GITHUB_RELEASES_HOSTNAME}/${GITHUB_RELEASES_REPO}/releases/download"

github_release_tag() {
    local version="$1"
    if [ -z "$version" ]; then
        echo "ERROR: github_release_tag requires a version" >&2
        return 1
    fi
    echo "v${version}"
}

# Prefix for every asset of one release, with a trailing slash; Sparkle's
# generate_appcast takes it as --download-url-prefix.
github_release_download_prefix() {
    local version="$1"
    local tag
    tag="$(github_release_tag "$version")" || return 1
    echo "${GITHUB_RELEASES_DOWNLOAD_BASE_URL}/${tag}/"
}

github_release_asset_url() {
    local version="$1"
    local artifact_name="$2"
    if [ -z "$artifact_name" ]; then
        echo "ERROR: github_release_asset_url requires an artifact filename" >&2
        return 1
    fi
    local prefix
    prefix="$(github_release_download_prefix "$version")" || return 1
    echo "${prefix}${artifact_name}"
}
