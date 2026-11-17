# shellcheck shell=bash
# Source-time pure declarations for phased IDE CLI modularization.
# Future extraction phases can source additional modules through the
# top-level ide router without changing the public yen ide entrypoint.

IDE_BOOTSTRAP_MODULE_API_VERSION="1"
IDE_BOOTSTRAP_MODULE_NAME="bootstrap"

ide_bootstrap_assert_compatible() {
    local expected="${1:-1}"
    if [[ "${IDE_BOOTSTRAP_MODULE_API_VERSION:-}" != "${expected}" ]]; then
        yen_error "IDE bootstrap module API mismatch: expected ${expected}, got ${IDE_BOOTSTRAP_MODULE_API_VERSION:-missing}"
        exit 1
    fi
}
