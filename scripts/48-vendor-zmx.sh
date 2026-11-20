#!/bin/bash
# Vendor zmx Binary (Universal, built against YEN's vendored engine)
#
# zmx keeps each terminal pane's process alive in its own daemon and replays the
# screen on reattach (_docs/00-foundation.md -> Decisions). It renders that
# replay with libghostty-vt, so this script compiles it against YEN's own
# vendored engine instead of the upstream commit zmx pins. Replay and rendering
# then share one engine, and the binary carries no upstream engine name.
#
# Source edits, each fail-closed when its anchor is missing:
#   build.zig.zon  the engine dependency points at an in-tree clone (yen-engine)
#   build.zig      the version banner reads the engine id, not the upstream hash
#   build.zig      the vt module is looked up by YEN's branded name (yen-vt)
#   build.zig      the executable is built without debug info (.strip = true)
#   src/main.zig   the version banner label says "engine"
#   src/daemonize.zig  the daemon records its session tty in <ZMX_DIR>/<name>.tty,
#                  so YEN can read the inner pty's termios (password detection);
#                  zmx ls skips that non-socket file
#
# Reproducible output, so the baseline output pin can hold across rebuilds:
# - Debug info carries a timestamped object map, and the linker derives the
#   Mach-O UUID from it, so the binary is built stripped.
# - Zig's cache hash embeds the absolute build path, and a C++ dependency
#   compiles a cache path into a string, so every build runs from one fixed
#   path ($ZMX_BUILD_ROOT), guarded by a lock directory.
#
# The engine id (upstream commit plus a digest of the tracked YEN inputs that
# shape the engine's Zig sources) is passed as VENDOR_BUILD_INPUT_ID, so an
# engine bump or an engine patch rebuilds zmx and re-records its pin.
#
# Stores at yen-terminal/customizations/vendor/zmx/
#
# Usage: ./scripts/48-vendor-zmx.sh
#        ./scripts/48-vendor-zmx.sh --force
#        ./scripts/48-vendor-zmx.sh --print-input-id   (what 14-vendor.sh compares)
#        VENDOR_LATEST_TAG=vX.Y.Z ./scripts/48-vendor-zmx.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib/vendor-binary.sh"

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    echo "Usage: ./scripts/48-vendor-zmx.sh [--force | --print-input-id]"
    exit 0
fi
PRINT_INPUT_ID=false
[ "${1:-}" = "--print-input-id" ] && PRINT_INPUT_ID=true
FORCE=false
[ "$PRINT_INPUT_ID" = true ] || FORCE=$(parse_force_flag "$@")

require_tool "shasum"

ENGINE_DIR="$REPO_ROOT/yen-terminal/ghostty"
ENGINE_BASELINE="$REPO_ROOT/yen-terminal/.ghostty-baseline"
for required in "$ENGINE_DIR/build.zig" "$ENGINE_DIR/build.zig.zon" "$ENGINE_DIR/src/lib_vt.zig" "$ENGINE_BASELINE"; do
    if [ ! -f "$required" ]; then
        echo "ERROR: vendored engine file missing: ${required#"$REPO_ROOT"/}"
        echo "Run the Ghostty vendor phase (./scripts/14-vendor.sh ghostty) first."
        exit 1
    fi
done

# Engine identity, from tracked files only so every checkout computes the same
# id whether or not overlays are applied: the pinned upstream commit and its
# archive digest, plus every YEN input that can change engine Zig sources (Zig
# overlays, patch blocks aimed at src/, build.zig or pkg/, and the branding,
# rename and emoji phases), plus this recipe itself.
engine_input_id() {
    python3 - "$REPO_ROOT" "$ENGINE_BASELINE" "$0" <<'PY'
import hashlib, json, os, re, sys
root, baseline_path, recipe = sys.argv[1], sys.argv[2], sys.argv[3]
baseline = dict(l.split("=", 1) for l in open(baseline_path).read().splitlines() if "=" in l and not l.startswith("#"))
commit, archive = baseline.get("upstream_commit", ""), baseline.get("source_archive_sha256", "")
if not re.fullmatch(r"[0-9a-f]{40}", commit) or not re.fullmatch(r"[0-9a-f]{64}", archive):
    sys.exit("ERROR: engine baseline lacks upstream_commit or source_archive_sha256")
files = set()
for top in ["yen-terminal/overlays/src"]:
    for d, _, names in os.walk(os.path.join(root, top)):
        files.update(os.path.relpath(os.path.join(d, n), root) for n in names if n != ".DS_Store")
plan = json.load(open(os.path.join(root, "scripts/lib/overlay-patch-plan.json")))
for entry in plan.values():
    if entry["target"].startswith(("ghostty/src/", "ghostty/build.zig", "ghostty/pkg/")):
        for arg in entry["arguments"]:
            for ref in re.findall(r"@\$PATCHES_DIR/([^:]+)", arg):
                files.add(os.path.join("scripts/lib/patches", ref))
files.update([
    "scripts/lib/overlay-patch-plan.json",
    "scripts/lib/overlay-branding.sh",
    "scripts/lib/overlay-phases/01-branding.sh",
    "scripts/lib/overlay-phases/02-renames.sh",
    "scripts/lib/overlay-phases/05-emoji.sh",
    os.path.relpath(os.path.realpath(recipe), root),
])
h = hashlib.sha256()
h.update(f"{commit}\n{archive}\n".encode())
for rel in sorted(files):
    path = os.path.join(root, rel)
    if not os.path.isfile(path):
        sys.exit(f"ERROR: engine input missing: {rel}")
    h.update(rel.encode() + b"\0" + hashlib.sha256(open(path, "rb").read()).hexdigest().encode() + b"\n")
print(f"engine-{commit[:12]}-{h.hexdigest()[:16]}")
PY
}

ENGINE_ID="$(engine_input_id)"
if [ "$PRINT_INPUT_ID" = true ]; then
    echo "$ENGINE_ID"
    exit 0
fi
echo "  Engine input: $ENGINE_ID"

require_tool "zig"
require_tool "curl"
require_tool "tar"
require_tool "lipo"
require_tool "file"
require_tool "python3"

# Replace exactly the expected anchor in a file; any other count fails closed.
patch_anchor() {
    local file="$1" old="$2" new="$3" min_count="$4"
    python3 - "$file" "$old" "$new" "$min_count" <<'PY'
import sys
path, old, new, min_count = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
text = open(path).read()
count = text.count(old)
if count < min_count:
    sys.exit(f"ERROR: zmx patch anchor not found {count}x (need {min_count}) in {path}: {old!r}")
open(path, "w").write(text.replace(old, new))
PY
}

patch_zmx_source() {
    local source_dir="$1"
    python3 - "$source_dir/build.zig.zon" <<'PY' >&2
import re, sys
path = sys.argv[1]
text = open(path).read()
new, count = re.subn(r"\.ghostty\s*=\s*\.\{[^{}]*\},", '.ghostty = .{ .path = "yen-engine" },', text, flags=re.S)
if count != 1:
    sys.exit(f"ERROR: expected one ghostty dependency in {path}, found {count}")
open(path, "w").write(new)
PY
    patch_anchor "$source_dir/build.zig" \
        "build_zig_zon.dependencies.ghostty.hash" "\"$ENGINE_ID\"" 1 >&2
    patch_anchor "$source_dir/build.zig" '.module("ghostty-vt")' '.module("yen-vt")' 1 >&2
    patch_anchor "$source_dir/build.zig" \
        '.root_source_file = b.path("src/main.zig"),' \
        '.root_source_file = b.path("src/main.zig"),
        .strip = true,' 1 >&2
    patch_anchor "$source_dir/src/main.zig" 'ghostty_vt\t' 'engine\t\t' 1 >&2
    patch_anchor "$source_dir/src/daemonize.zig" \
        'const pid = cross.forkpty(&master_fd, null, null, &ws);' \
        'var yen_tty_name: [1024]u8 = std.mem.zeroes([1024]u8);
    const pid = cross.forkpty(&master_fd, &yen_tty_name, null, &ws);' 1 >&2
    patch_anchor "$source_dir/src/daemonize.zig" \
        '    std.log.info("pty spawned session={s} pid={d}", .{ sesh_name, pid });' \
        '    std.log.info("pty spawned session={s} pid={d}", .{ sesh_name, pid });

    // YEN: record the session tty beside the socket so the app can read the
    // inner pty termios for password detection; zmx ls skips non-socket files.
    yen_tty: {
        const dir = std.c.getenv("ZMX_DIR") orelse break :yen_tty;
        var path_buf: [1024]u8 = undefined;
        const path = std.fmt.bufPrintSentinel(&path_buf, "{s}/{s}.tty", .{ std.mem.span(dir), sesh_name }, 0) catch break :yen_tty;
        const fd = std.c.open(path.ptr, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, @as(c_uint, 0o600));
        if (fd < 0) break :yen_tty;
        defer _ = std.c.close(fd);
        const tty = std.mem.sliceTo(&yen_tty_name, 0);
        _ = std.c.write(fd, tty.ptr, tty.len);
    }' 1 >&2
}

ZMX_BUILD_ROOT="/private/tmp/yen-vendor-zmx-build"
ZMX_BUILD_LOCK="$ZMX_BUILD_ROOT.lock"


build_arch_binary() {
    local source_dir="$1" zig_target="$2" prefix="$3"
    echo "  Building $zig_target..." >&2
    (cd "$source_dir" && zig build -Doptimize=ReleaseSafe -Dtarget="$zig_target" --prefix "$prefix") >&2 || return 1
    [ -x "$prefix/bin/zmx" ] || { echo "ERROR: zmx not produced for $zig_target" >&2; return 1; }
    echo "$prefix/bin/zmx"
}

# Build callback (see the BUILD_FN contract in lib/vendor-binary.sh): arm64 path
# first, x86_64 second on STDOUT; all progress on STDERR.
build_zmx() {
    local source_dir="$1" temp_dir="$2" arm64 x86
    if ! mkdir "$ZMX_BUILD_LOCK" 2>/dev/null; then
        echo "ERROR: another zmx build holds $ZMX_BUILD_LOCK; remove it only if no build is running" >&2
        return 1
    fi
    # This function runs in a command-substitution subshell, so the trap is local.
    trap 'rm -rf "$ZMX_BUILD_ROOT" "$ZMX_BUILD_LOCK"' EXIT
    rm -rf "$ZMX_BUILD_ROOT"
    cp -Rp "$source_dir" "$ZMX_BUILD_ROOT" || return 1
    echo "  Cloning the vendored engine into the build tree..." >&2
    cp -cRp "$ENGINE_DIR" "$ZMX_BUILD_ROOT/yen-engine" 2>/dev/null || cp -Rp "$ENGINE_DIR" "$ZMX_BUILD_ROOT/yen-engine" || return 1
    rm -rf "$ZMX_BUILD_ROOT/yen-engine/.zig-cache" "$ZMX_BUILD_ROOT/yen-engine/zig-out" "$ZMX_BUILD_ROOT/yen-engine/macos/build"
    patch_zmx_source "$ZMX_BUILD_ROOT" || return 1
    build_arch_binary "$ZMX_BUILD_ROOT" "aarch64-macos" "$ZMX_BUILD_ROOT/out-arm64" >/dev/null || return 1
    build_arch_binary "$ZMX_BUILD_ROOT" "x86_64-macos" "$ZMX_BUILD_ROOT/out-x86_64" >/dev/null || return 1
    mkdir -p "$temp_dir/out" || return 1
    cp "$ZMX_BUILD_ROOT/out-arm64/bin/zmx" "$temp_dir/out/zmx-arm64" || return 1
    cp "$ZMX_BUILD_ROOT/out-x86_64/bin/zmx" "$temp_dir/out/zmx-x86_64" || return 1
    arm64="$temp_dir/out/zmx-arm64"
    x86="$temp_dir/out/zmx-x86_64"
    if strings "$arm64" "$x86" | grep -qi "ghostty"; then
        echo "ERROR: zmx build still carries the upstream engine name" >&2
        return 1
    fi
    echo "$arm64"
    echo "$x86"
}

VENDOR_BUILD_INPUT_ID="$ENGINE_ID" \
    vendor_source_build "zmx" "neurosnap/zmx" "zmx" ".zmx-baseline" "zmx" build_zmx "$FORCE" "zig build against the vendored engine"
