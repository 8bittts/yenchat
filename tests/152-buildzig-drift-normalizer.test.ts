import { describe, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const repoRoot = join(import.meta.dir, "..");
const normalizer = join(repoRoot, "scripts/lib/normalize-overlay-buildzig.py");
const updateScript = join(repoRoot, "scripts/10-update-ghostty.sh");
const overlayBuildZig = join(repoRoot, "yen-terminal/overlays/build.zig");

const upstream = [
	"pub fn build(b: *std.Build) !void {",
	"        // If we're not a dependency, we rename the static lib.",
	"        const static_lib_name = if (windows)",
	'            "ghostty-vt-static.lib"',
	"        else",
	'            "libghostty-vt.a";',
	'            .source_dir = b.path("include/ghostty"),',
	'            .install_subdir = "ghostty",',
	"        if (config.emit_macos_app) {",
	"            macos_app.install();",
	"        }",
	'        const c_src = wf.add("vt_h_test.c", "#include <ghostty/vt.h>\\n");',
	'        try c_deps.add(b, .@"ghostty-vt-h", mod, &config, .{});',
	'        try c_deps.add(b, .@"ghostty-h", mod, &config, .{});',
	'            _ = wf.addCopyFile(b.path("include/ghostty/vt/version.h"), "version.h");',
	"}",
	"",
].join("\n");

const overlay = [
	"pub fn build(b: *std.Build) !void {",
	"        // If we're not a dependency, we rename the static lib.",
	"        // YEN: match the branded names YENLibVt writes.",
	"        // This overlay is excluded from branding.",
	"        const static_lib_name = if (windows)",
	'            "yen-vt-static.lib"',
	"        else",
	'            "libyen-vt.a";',
	"            // YEN: apply-overlays.sh renames include/ghostty to include/yen.",
	'            .source_dir = b.path("include/yen"),',
	'            .install_subdir = "yen",',
	"        if (config.emit_macos_app) {",
	"            macos_app.install();",
	"",
	"            // YEN Custom Resources - bundle config into YEN.app",
	"            const yen_custom = try buildpkg.YENCustomResources.init(b);",
	"            yen_custom.install();",
	"        }",
	'        const c_src = wf.add("vt_h_test.c", "#include <yen/vt.h>\\n");',
	"        // YEN: c_deps.zig is branded, so its header keys are yen-h / yen-vt-h.",
	'        try c_deps.add(b, .@"yen-vt-h", mod, &config, .{});',
	'        try c_deps.add(b, .@"yen-h", mod, &config, .{});',
	'            _ = wf.addCopyFile(b.path("include/yen/vt/version.h"), "version.h");',
	"}",
	"",
].join("\n");

function normalize(text: string): string {
	const dir = mkdtempSync(join(tmpdir(), "yen-buildzig-"));
	const file = join(dir, "build.zig");
	writeFileSync(file, text);
	const res = spawnSync("python3", [normalizer, file], { encoding: "utf8" });
	expect(res.status).toBe(0);
	return res.stdout;
}

function blankless(text: string): string {
	return text
		.split("\n")
		.filter((l) => l.trim() !== "")
		.join("\n");
}

describe("[3a/5] build.zig drift normalizer", () => {
	test("reverses every documented YEN customization", () => {
		expect(blankless(normalize(overlay))).toBe(blankless(upstream));
	});

	test("still surfaces upstream drift (fails closed)", () => {
		const drifted = upstream.replace(
			"macos_app.install();",
			"macos_app.install();\n            new_upstream_step();",
		);
		expect(blankless(normalize(overlay))).not.toBe(blankless(drifted));
	});

	test("does not hide non-YEN comments or code", () => {
		const extra = overlay.replace(
			"macos_app.install();",
			"macos_app.install();\n            // unrelated comment\n            extra();",
		);
		const out = normalize(extra);
		expect(out).toContain("// unrelated comment");
		expect(out).toContain("extra();");
	});

	test("the real overlay normalizes to an unbranded build.zig", () => {
		const out = normalize(readFileSync(overlayBuildZig, "utf8"));
		expect(out).not.toMatch(/yen/i);
	});

	test("10-update-ghostty.sh uses the normalizer and keeps the fail-closed exit", () => {
		const src = readFileSync(updateScript, "utf8");
		expect(src).toContain("scripts/lib/normalize-overlay-buildzig.py");
		expect(src).toContain(
			"ERROR: upstream build.zig changed outside the documented YEN customizations.",
		);
		expect(src).toContain(
			"build.zig: only YEN customization diverges (no upstream drift).",
		);
	});
});
