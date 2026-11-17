# Vendor Troubleshooting

Recovery patterns for the `/yen-zip` vendor phase. Each entry names the symptom, the cause, and the smallest fix.

**Upstream status UNKNOWN or rate limited** — `14-vendor.sh` counts it as its own outcome and exits non-zero in update mode. Authenticate (`GITHUB_TOKEN=$(gh auth token)`) and rerun; do not set `YEN_VENDOR_ALLOW_UNKNOWN_STATUS=1` to make it green.

**`apply-overlays.sh` anchor not found** — upstream rewrote the block a `patch_file` call anchors on. `10-update-ghostty.sh` restores the previous tree. Read upstream's change from the forge compare range, then re-anchor or retire per `vendor-audit.md` Layer 1, and rerun only the update phase.

**`[3a/5]` pair tripwire fired** — upstream edited a file a whole-file overlay replaces. Port the change into `yen-terminal/overlays/` (including symbols upstream's tests need), rerun with `YEN_VENDOR_ACCEPT_OVERLAY_CONTENT_DRIFT=1` so the manifest re-pins, and confirm the port survived with `git status --porcelain -- yen-terminal/overlays` before the build. A missing overlay or counterpart is structural and not waivable.

**Zig build flake (`uucode_build_tables: FileNotFound`)** — a shared or half-cleaned `.zig-cache`. Do a full `trash yen-terminal/ghostty/.zig-cache` (keep `.yen-zig-global-cache`), then rebuild from the canonical checkout.

**Ghostty build hangs or the xcframework is stale after an update** — `trash yen-terminal/ghostty/macos/*.xcframework` and rebuild with `bash $HOME/Documents/yenchat/scripts/native/01-macos-smoke.sh --local`. Never run `zig build` directly after a vendor update.

**Binary not found during build** — run `bash $HOME/Documents/yenchat/scripts/14-vendor.sh <vendor>` (add `--force` to re-download).

**Swift concurrency errors after a Ghostty update** — upstream tightened isolation. Add `@MainActor` or `nonisolated` in the overlay source, never in the build tree. See `vendor-audit-decision-matrix.md`.

**`'YEN' is ambiguous` after a Ghostty update** — upstream split, merged, or moved types and a whole-file overlay now duplicates one. Diff the overlay against upstream's new layout and retire or re-base the overlay.

**Ad-hoc signature on a new embedded bundle** — upstream added an Xcode target that emits into `Contents/PlugIns/`. Add a signing step in `finalize-build.sh` before main-app signing.

**Yazi shows "Yazi:" instead of "YEN:" in the title** — check the `ind-app-title` subscriber in `yen-terminal/customizations/yazi-config/init.lua`; it writes `YEN: <cwd>`. The static `title_format` key is obsolete; rebuild to bundle the current config.

**Branding gate fails on a symbol that moved** — `04-verify-branding.sh` greps for named symbols; a YEN refactor can move one without upstream dropping it. Confirm whether the symbol moved before treating it as a vendor regression.

**Stale lock** — the error names the lock path and PID. Confirm the PID is dead with `command ps -p <pid>` (the aliased `ps` rejects the flags and looks like "dead"), then remove the reported path and rerun.

**Integrity bypass left exported** — `YEN_VENDOR_ALLOW_UNVERIFIED_DOWNLOADS` is read live on every call. `unset YEN_VENDOR_ALLOW_UNVERIFIED_DOWNLOADS YEN_VENDOR_INTEGRITY_BYPASS_REASON` after a deliberate bump; the summary warning tells you it was active.
