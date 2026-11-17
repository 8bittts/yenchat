#!/bin/bash
# Sourced by apply-overlays.sh; inherits its working directory and fail-fast mode.

# ============================================================================
# Verify AppDelegate Overlay Hooks
# ============================================================================
# AppDelegate customizations now ship as a full overlay file
# (overlays/macos/Sources/App/AppDelegate.swift) instead of sed-based
# patch injection. Keep this as a hard fail-fast guard.

verify_overlay_app_hooks
