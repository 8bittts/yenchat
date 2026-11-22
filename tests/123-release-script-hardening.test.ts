import { describe, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import {
	copyFileSync,
	mkdirSync,
	mkdtempSync,
	readdirSync,
	readFileSync,
	rmSync,
	writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const repoRoot = process.cwd();
const generateAppcastPath = join(
	repoRoot,
	"yen-terminal/customizations/generate-appcast.sh",
);
const finalizeBuildPath = join(
	repoRoot,
	"yen-terminal/customizations/finalize-build.sh",
);
const buildReleasePath = join(
	repoRoot,
	"yen-terminal/customizations/build-release.sh",
);
const detectFailuresPath = join(repoRoot, "scripts/05-detect-failures.sh");
const sparkleVerifyPath = join(
	repoRoot,
	"scripts/manual/11-verify-sparkle-signing.sh",
);
const workflowLockPath = join(repoRoot, "scripts/lib/workflow-lock.sh");
const vendorScriptPath = join(repoRoot, "scripts/14-vendor.sh");
const ghosttyVendorPath = join(repoRoot, "scripts/10-update-ghostty.sh");
const applyOverlaysPath = join(repoRoot, "yen-terminal/apply-overlays.sh");
const sparkleRuntimeFloorLibPath = join(
	repoRoot,
	"scripts/lib/sparkle-runtime-floor.sh",
);
const brandingVerifyPath = join(repoRoot, "scripts/04-verify-branding.sh");
const versionUtilsPath = join(repoRoot, "scripts/lib/version-utils.sh");
const vendorAuditPath = join(repoRoot, "_docs/04-security.md");

describe("release script hardening", () => {
	test("in-app docs branding rejects lineage while public plaintext may credit Ghostty", () => {
		const script = readFileSync(brandingVerifyPath, "utf8");
		const start = script.indexOf("LINEAGE_PATTERN=");
		const end = script.indexOf("# Check 9:", start);
		expect(start).toBeGreaterThan(0);
		expect(end).toBeGreaterThan(start);
		const root = mkdtempSync(join(tmpdir(), "yen-doc-branding-"));
		try {
			mkdirSync(join(root, "app/docs"), { recursive: true });
			mkdirSync(join(root, "public"));
			// YEN is open source, so the public plaintext credits Ghostty and must not fail the gate.
			writeFileSync(join(root, "public/llms.txt"), "YEN is built on Ghostty");
			writeFileSync(join(root, "public/README.md"), "Built using libghostty");
			for (const [copy, expected] of [
				["YEN terminal guide", 0],
				["Built using libghostty", 1],
			] as const) {
				writeFileSync(join(root, "app/docs/docs-client.tsx"), copy);
				const result = spawnSync(
					"bash",
					[
						"-c",
						`
REPO_ROOT="$1"
ISSUES=0
subject_present() { test -e "$2"; }
add_issue() { ISSUES=$((ISSUES+1)); }
${script.slice(start, end)}
printf 'issues=%s\\n' "$ISSUES"
exit "$ISSUES"
`,
						"fixture",
						root,
					],
					{ encoding: "utf8" },
				);
				expect(result.status, result.stderr).toBe(expected);
				expect(result.stdout).toContain(`issues=${expected}`);
			}
		} finally {
			rmSync(root, { recursive: true, force: true });
		}
	});

	test("native component selection follows extracted overlay implementation and data", () => {
		const helper = join(repoRoot, "scripts/lib/native-component-paths.sh");
		for (const path of [
			"yen-terminal/apply-overlays.sh",
			"scripts/lib/overlay-phases/02-renames.sh",
			"scripts/lib/overlay-data/retired-paths.tsv",
			"scripts/lib/overlay-branding.sh",
			"scripts/lib/patches/shift-enter.new",
			"scripts/lib/patch-file.py",
		]) {
			const result = spawnSync("bash", [
				"-c",
				'source "$1"; is_component_xcode_relevant_path "$2"',
				"fixture",
				helper,
				path,
			]);
			expect(result.status, path).toBe(0);
		}
		const unrelated = spawnSync("bash", [
			"-c",
			'source "$1"; is_component_xcode_relevant_path "$2"',
			"fixture",
			helper,
			"_docs/todos.md",
		]);
		expect(unrelated.status).toBe(1);
		const gate = readFileSync(
			join(repoRoot, "scripts/03-verify-components.sh"),
			"utf8",
		);
		expect(gate).toContain(
			'source "$REPO_ROOT/scripts/lib/native-component-paths.sh"',
		);
	});

	test("standalone YEN commands enforce the same macOS minimum outside Finder", () => {
		const root = mkdtempSync(join(tmpdir(), "yen-host-version-"));
		const env = { ...process.env, PATH: `${root}:${process.env.PATH}` };
		const cli = join(repoRoot, "yen-cli/bin/yen");
		try {
			writeFileSync(
				join(root, "sw_vers"),
				'#!/bin/sh\nprintf "%s\\n" "$YEN_TEST_OS"\n',
				{ mode: 0o755 },
			);
			for (const version of ["13.6.9", "26.9.9", "", "unknown"]) {
				for (const command of [
					cli,
					...["browse", "yen-quicklook", "yen-yazi-edit"].map((name) =>
						join(repoRoot, "yen-terminal/customizations/bin", name),
					),
				]) {
					const result = spawnSync(command, ["version"], {
						env: { ...env, YEN_TEST_OS: version },
						encoding: "utf8",
					});
					expect(result.status).toBe(1);
					expect(result.stderr).toContain("YEN requires macOS 27.0 or later");
				}
			}
			for (const version of ["27.0", "27.2.1", "28.0"]) {
				const result = spawnSync(cli, ["version"], {
					env: { ...env, YEN_TEST_OS: version },
					encoding: "utf8",
				});
				expect(result.status, result.stderr).toBe(0);
				expect(result.stdout).toContain("YEN");
			}
		} finally {
			rmSync(root, { recursive: true, force: true });
		}
	});

	test.skipIf(process.platform !== "darwin")(
		"native direct launch refuses a deployment target newer than the host",
		() => {
			const root = mkdtempSync(join(tmpdir(), "yen-native-minimum-"));
			try {
				const host = spawnSync("sw_vers", ["-productVersion"], {
					encoding: "utf8",
				});
				expect(host.status).toBe(0);
				const nextMajor = Number.parseInt(host.stdout, 10) + 1;
				const probe = join(root, "probe");
				const guard = join(
					repoRoot,
					"yen-terminal/overlays/macos/Sources/App/YENMinimumSystemVersion.m",
				);
				const target = `${process.arch === "arm64" ? "arm64" : "x86_64"}-apple-macos${nextMajor}.0`;
				const build = spawnSync(
					"xcrun",
					[
						"clang",
						"-target",
						target,
						"-framework",
						"Foundation",
						guard,
						"-x",
						"c",
						"-",
						"-o",
						probe,
					],
					{
						encoding: "utf8",
						input: "int main(void) { return 42; }",
					},
				);
				expect(build.status, build.stderr).toBe(0);
				const launch = spawnSync(probe, { encoding: "utf8" });
				expect(launch.status).toBe(1);
				expect(launch.stderr).toContain(
					`YEN requires macOS ${nextMajor}.0 or later`,
				);
			} finally {
				rmSync(root, { recursive: true, force: true });
			}
		},
	);

	test.skipIf(process.platform !== "darwin")(
		"release gate inspects the minimum in each packaged YEN binary",
		() => {
			const root = mkdtempSync(join(tmpdir(), "yen-artifact-floor-"));
			const contents = join(root, "Contents");
			const dock = join(contents, "PlugIns/DockTilePlugin.plugin/Contents");
			const app = join(contents, "MacOS/yen");
			const helpers = [
				join(dock, "MacOS/DockTilePlugin"),
				...["pdf", "svg", "vid"].map((name) =>
					join(contents, "Resources/bin", `yen-${name}thumb`),
				),
			];
			const verify = () =>
				spawnSync(
					"bash",
					[join(repoRoot, "scripts/lib/verify-macos-floor.sh"), root],
					{ encoding: "utf8" },
				);
			try {
				for (const dir of [
					join(contents, "MacOS"),
					join(contents, "Resources/bin"),
					join(dock, "MacOS"),
				])
					mkdirSync(dir, { recursive: true });
				for (const dir of [contents, dock]) {
					writeFileSync(
						join(dir, "Info.plist"),
						'<plist version="1.0"><dict><key>LSMinimumSystemVersion</key><string>27.0</string></dict></plist>',
					);
				}
				const compile = (path: string, target: string) => {
					const result = spawnSync(
						"xcrun",
						["clang", "-target", target, "-x", "c", "-", "-o", path],
						{ input: "int main(void) { return 0; }", encoding: "utf8" },
					);
					expect(result.status, result.stderr).toBe(0);
				};
				compile(app, "arm64-apple-macos27.0");
				for (const path of helpers) copyFileSync(app, path);
				const valid = verify();
				expect(valid.status, valid.stderr).toBe(0);
				const pdf = join(contents, "Resources/bin/yen-pdfthumb");
				const ios = spawnSync(
					"xcrun",
					[
						"vtool",
						"-set-build-version",
						"ios",
						"27.0",
						"27.0",
						"-replace",
						"-output",
						pdf,
						app,
					],
					{ encoding: "utf8" },
				);
				expect(ios.status, ios.stderr).toBe(0);
				const wrongPlatform = verify();
				expect(wrongPlatform.status).toBe(1);
				expect(wrongPlatform.stderr).toContain("IOS");
				const otherSlice = join(root, "old");
				compile(otherSlice, "x86_64-apple-macos26.0");
				const mixed = spawnSync(
					"lipo",
					[
						"-create",
						app,
						otherSlice,
						"-output",
						join(contents, "Resources/bin/yen-pdfthumb"),
					],
					{ encoding: "utf8" },
				);
				expect(mixed.status, mixed.stderr).toBe(0);
				const mismatch = verify();
				expect(mismatch.status).toBe(1);
				expect(mismatch.stderr).toContain(
					"yen-pdfthumb (x86_64) targets 'MACOS 26.0'",
				);
				rmSync(app);
				expect(verify().status).not.toBe(0);
			} finally {
				rmSync(root, { recursive: true, force: true });
			}
		},
	);

	test("appcast generation validates minOS before writing Sparkle metadata", () => {
		const script = readFileSync(generateAppcastPath, "utf8");
		const validationIndex = script.indexOf(
			'if [ "$MIN_OS" != "$YEN_MIN_MACOS" ]; then',
		);
		const appcastWriteIndex = script.indexOf(
			"<sparkle:minimumSystemVersion>$MIN_OS</sparkle:minimumSystemVersion>",
		);

		expect(script).toContain('verify-macos-floor.sh" "$MOUNT_POINT/YEN.app"');
		expect(validationIndex).toBeGreaterThan(0);
		expect(appcastWriteIndex).toBeGreaterThan(0);
		expect(validationIndex).toBeLessThan(appcastWriteIndex);
	});

	test("the informational git-state unit cannot abort the gate on a clean tree", () => {
		// git-state is documented and commented as informational, but the receipt
		// framework rejects a unit recording RAN with a bare zero quantity. A clean
		// worktree has zero tracked changes, so reporting RAN there aborted the whole
		// gate before any RECEIPT and discarded every real check above it.
		const script = readFileSync(detectFailuresPath, "utf8");

		expect(script).toContain("gate_unit_skipped git-state");
		expect(script).not.toMatch(
			/gate_unit_ran git-state "tracked_changes=\$\(git /,
		);

		const ranIndex = script.indexOf("gate_unit_ran git-state");
		const skippedIndex = script.indexOf("gate_unit_skipped git-state");
		expect(ranIndex).toBeGreaterThan(-1);
		expect(skippedIndex).toBeGreaterThan(ranIndex);
	});

	test("retired sound artifact release hooks stay removed", () => {
		const phaseDir = join(repoRoot, "scripts/lib/finalize-build-phases");
		const paths = [
			finalizeBuildPath,
			...readdirSync(phaseDir).map((name) => join(phaseDir, name)),
		];
		expect(paths.length).toBe(8);
		const detector = readFileSync(detectFailuresPath, "utf8");

		for (const path of paths) {
			const script = readFileSync(path, "utf8");
			expect(script).not.toContain("verify_sound_remote_release_artifacts");
			expect(script).not.toContain("verify_sound_archive_url_is_canonical");
			expect(script).not.toContain("Sound-pack artifacts already current");
		}

		expect(detector).not.toContain("EXPECTED_SOUND_ARCHIVE_URL");
		expect(detector).not.toContain("Sound manifest archive URL mismatch");
		expect(detector).not.toContain(
			"Sound manifest archive filename is unexpected",
		);
	});

	test("build and finalize locks use shared stale-lock helper", () => {
		const buildScript = readFileSync(buildReleasePath, "utf8");
		const finalizeScript = readFileSync(finalizeBuildPath, "utf8");
		const workflowLock = readFileSync(workflowLockPath, "utf8");

		expect(workflowLock).toContain("acquire_yen_process_lock()");
		expect(workflowLock).toContain(
			'busy_message="${busy_message//\\{pid\\}/$existing_pid}"',
		);
		expect(workflowLock).toContain('echo "$$" > "$lock_dir/pid" || {');
		expect(workflowLock).toContain(
			'echo "$$" > "$YEN_SHARED_WORKFLOW_LOCK_DIR/pid" || {',
		);
		expect(buildScript).toContain("acquire_yen_process_lock \\");
		expect(buildScript).toContain("BUILD_LOCK_ACQUIRED");
		expect(buildScript).toContain(
			"ERROR: Another build-release.sh process is running (pid {pid})",
		);
		expect(buildScript).not.toContain("local existing_cmd");
		expect(finalizeScript).toContain("acquire_yen_process_lock \\");
		expect(finalizeScript).toContain("FINALIZE_LOCK_ACQUIRED");
		expect(finalizeScript).toContain(
			"ERROR: Another finalize-build.sh process is running (pid {pid})",
		);
		expect(finalizeScript).not.toContain("local existing_cmd");
	});

	test("vendor and ghostty-vendor locks use shared stale-lock helper", () => {
		const vendorScript = readFileSync(vendorScriptPath, "utf8");
		const ghosttyScript = readFileSync(ghosttyVendorPath, "utf8");

		expect(vendorScript).toContain("acquire_yen_process_lock \\");
		expect(vendorScript).toContain("VENDOR_LOCK_ACQUIRED");
		expect(vendorScript).toContain(
			"ERROR: Another vendor run is in progress (pid {pid})",
		);
		expect(vendorScript).not.toContain("local existing_cmd");

		expect(ghosttyScript).toContain("acquire_yen_process_lock \\");
		expect(ghosttyScript).toContain("GHOSTTY_VENDOR_LOCK_ACQUIRED");
		expect(ghosttyScript).toContain(
			"ERROR: Another Ghostty vendor update is already running (pid {pid})",
		);
		expect(ghosttyScript).not.toContain("local existing_cmd");
	});

	test("appcast deltas are a sibling of the enclosure, never nested inside it", () => {
		const appcastScript = readFileSync(generateAppcastPath, "utf8");

		// Sparkle reads <sparkle:deltas> from the <item>'s children. Nesting it inside
		// <enclosure> is well-formed XML that Sparkle silently ignores, so every client
		// downloads the full DMG (~103 MB) instead of its delta (~1 MB). Pin the shape:
		// the main enclosure must self-close BEFORE the delta fragment is spliced in.
		const deltaBranch = appcastScript.slice(
			appcastScript.indexOf('if [ -n "$DELTA_FRAGMENT" ]; then'),
			appcastScript.indexOf("# Convert release date"),
		);
		expect(deltaBranch).toContain('sparkle:edSignature=\\"$ED_SIGNATURE\\" />');
		expect(deltaBranch).not.toContain("</enclosure>");
		// The self-closing enclosure must come immediately before the spliced fragment.
		expect(deltaBranch).toMatch(
			/sparkle:edSignature=\\"\$ED_SIGNATURE\\" \/>\n\$DELTA_FRAGMENT/,
		);

		// And the shipped artifact must match the shape the script now emits.
		const appcast = readFileSync(
			join(repoRoot, "public/stable/appcast.xml"),
			"utf8",
		);
		if (appcast.includes("<sparkle:deltas>")) {
			// `[^>]*>` alone also matches a correct self-closing ` />`, so require the
			// character before the `>` to not be `/` — that is the nested-and-broken shape.
			expect(appcast).not.toMatch(/<enclosure[^>]*[^/]>\s*<sparkle:deltas>/);
		}
	});

	test("Sparkle signature and version metadata parsing stay shared", () => {
		const appcastScript = readFileSync(generateAppcastPath, "utf8");
		const buildScript = readFileSync(
			join(repoRoot, "scripts/lib/build-release-phases/02-prepare.sh"),
			"utf8",
		);
		const finalizeScript = readFileSync(
			join(repoRoot, "scripts/lib/finalize-build-phases/05-metadata.sh"),
			"utf8",
		);
		const sparkleVerifyScript = readFileSync(sparkleVerifyPath, "utf8");
		const versionUtils = readFileSync(versionUtilsPath, "utf8");

		expect(versionUtils).toContain("get_version_json_string()");
		expect(versionUtils).toContain("extract_sparkle_ed_signature()");
		expect(appcastScript).toContain('VERSION=$(get_version "$VERSION_JSON")');
		expect(appcastScript).toContain(
			'RELEASE_DATE=$(get_version_json_string "$VERSION_JSON" "releaseDate")',
		);
		expect(appcastScript).toContain(
			'ED_SIGNATURE=$(extract_sparkle_ed_signature "$SIGN_OUTPUT")',
		);
		expect(buildScript).toContain('VERSION=$(get_version "$VERSION_JSON")');
		expect(sparkleVerifyScript).toContain(
			'VERSION=$(get_version "$VERSION_JSON")',
		);
		expect(sparkleVerifyScript).toContain(
			'APPCAST_SIG=$(extract_sparkle_ed_signature "$(cat "$APPCAST_FILE")")',
		);
		expect(sparkleVerifyScript).toContain(
			'CURRENT_SIG=$(extract_sparkle_ed_signature "$CURRENT_SIG_OUTPUT")',
		);
		expect(appcastScript).not.toContain("jq -r '.version'");
		expect(appcastScript).not.toContain("grep '\"releaseDate\"'");
		expect(buildScript).not.toContain("jq -r '.version'");
		expect(sparkleVerifyScript).not.toContain("jq -r '.version'");
		expect(sparkleVerifyScript).not.toContain("grep -o 'sparkle:edSignature");
		expect(finalizeScript).toContain(
			'VERSION_SIGNATURE=$(extract_sparkle_ed_signature "$VERSION_SIGN_OUTPUT")',
		);
		expect(finalizeScript).not.toContain("extract_sparkle_signature()");
	});

	test("Sparkle runtime floor is asserted at vendor time and at release time", () => {
		const lib = readFileSync(sparkleRuntimeFloorLibPath, "utf8");
		const applyOverlays = readFileSync(applyOverlaysPath, "utf8");
		const brandingGate = readFileSync(brandingVerifyPath, "utf8");

		// One constant, one parser. Sparkle 2.9.5 and 2.9.6 were security
		// releases, and upstream ghostty e8aa0986 (#14082) pins exactVersion
		// 2.9.6, so the audited floor is 2.9.6. Raise it here and in the lib
		// together.
		expect(lib).toContain('SPARKLE_RUNTIME_FLOOR="2.9.6"');
		const overlayBranding = readFileSync(
			join(repoRoot, "scripts/lib/overlay-branding.sh"),
			"utf8",
		);
		expect(
			readFileSync(
				join(repoRoot, "scripts/lib/overlay-phases/01-branding.sh"),
				"utf8",
			),
		).toContain("\nrestore_overlay_project_paths\n");
		for (const script of [applyOverlays, brandingGate]) {
			expect(script).toContain(
				'source "$REPO_ROOT/scripts/lib/sparkle-runtime-floor.sh"',
			);
			expect(script === applyOverlays ? overlayBranding : script).toContain(
				'assert_sparkle_runtime_floor "$PBXPROJ_PATH" "$SPARKLE_RUNTIME_FLOOR"',
			);
		}
		// Vendor time aborts the run before any tracking file is written;
		// release time flows into the branding issue list and exit code.
		expect(overlayBranding).toContain(
			'assert_sparkle_runtime_floor "$PBXPROJ_PATH" "$SPARKLE_RUNTIME_FLOOR" || exit 1',
		);
		expect(brandingGate).toMatch(
			/SPARKLE_FLOOR_RESULT="\$\(assert_sparkle_runtime_floor "\$PBXPROJ_PATH" "\$SPARKLE_RUNTIME_FLOOR" 2>&1\)"[^\n]*\n\s*\|\| add_issue/,
		);
	});

	test("vendor audit names build-system whole-file overlays as watched owners", () => {
		const doc = readFileSync(vendorAuditPath, "utf8");

		expect(doc).toContain("yen-terminal/overlays/build.zig");
		expect(doc).toContain("yen-terminal/overlays/src/build/main.zig");
		expect(doc).toContain("whole-file build-system overlays");
	});
});

// ---------------------------------------------------------------------------
// Branding gate cannot report a green run against a relocated upstream tree.
//
// 04-verify-branding.sh wraps most checks in `if [ -f "ghostty/..." ]` while
// check() increments unconditionally, so before scripts/lib/ghostty-paths.sh a
// single relocated source file produced "Branding verified (52 checks)" and
// exit 0 out of a shipping gate (build-release.sh step 7).
// ---------------------------------------------------------------------------
describe("branding gate upstream-path coverage", () => {
	const brandingPath = join(repoRoot, "scripts/04-verify-branding.sh");
	const ghosttyPathsPath = join(repoRoot, "scripts/lib/ghostty-paths.sh");

	function declaredRequiredPaths(): Set<string> {
		const source = readFileSync(ghosttyPathsPath, "utf8");
		const body = source.match(/GHOSTTY_REQUIRED_PATHS=\(\n([\s\S]*?)\n\)/)?.[1];
		if (!body) throw new Error("GHOSTTY_REQUIRED_PATHS array not found");
		return new Set(
			[...body.matchAll(/"[fd]\|([^"]+)"/g)]
				.map((m) => m[1])
				.filter((v): v is string => v !== undefined),
		);
	}

	// Paths the branding script asserts are ABSENT (retirement checks) or that
	// are pre-rename alternates resolved by an explicit either/or. Requiring
	// these would invert their meaning.
	const NOT_REQUIRED = new Set([
		"ghostty/macos/Ghostty.sdef",
		"ghostty/macos/Ghostty.xcodeproj/project.pbxproj",
		"ghostty/macos/Sources/App/AppDelegate+Layout.swift",
		"ghostty/macos/Sources/Features/Layout/LayoutManager.swift",
		"ghostty/macos/Sources/Features/Layout/LayoutTemplate.swift",
		// One arm of the AppleScript compound guard
		// `[ -d DIR ] || [ -f YEN.sdef ] || [ -f Ghostty.sdef ]` — an OR, so no
		// single arm is individually required. The directory arm IS required and
		// is declared.
		"ghostty/macos/YEN.sdef",
	]);

	test("branding script sources the shared path module and runs the gate", () => {
		const source = readFileSync(brandingPath, "utf8");
		expect(source).toContain(
			'source "$REPO_ROOT/scripts/lib/ghostty-paths.sh"',
		);
		expect(source).toContain("ghostty_paths_verify");
		// The result must flow into the existing issue/exit-code path.
		expect(source).toMatch(
			/MISSING_UPSTREAM_PATHS[\s\S]{0,400}add_issue "upstream path missing/,
		);
	});

	test("every path the branding script guards on is declared required", () => {
		// Comment lines are prose about the mechanism (they contain literal
		// `ghostty/...` placeholders); only real guards count.
		const code = readFileSync(brandingPath, "utf8")
			.split("\n")
			.filter((line) => !line.trimStart().startsWith("#"))
			.join("\n");
		// Both guard forms. The literal `[ -f "ghostty/..." ]` AND the indirect
		// `[ -f "$VAR" ]`, resolved through the VAR="ghostty/..." assignments.
		// Matching literals only let 12 variable-guarded files escape the
		// manifest while ghostty-paths.sh claimed they could not.
		const assignments = new Map<string, string>();
		for (const m of code.matchAll(/^([A-Z_]+)="(ghostty\/[^"]+)"$/gm)) {
			const [, name, path] = m;
			if (name && path) assignments.set(name, path);
		}
		// Three guard forms now. `subject_present f "..."` replaced the bare
		// `[ -f "..." ]` when 04 adopted the receipt contract so the gate could
		// COUNT how many of its checks had subjects; if this extractor is not
		// taught that form, every converted guard silently escapes the manifest
		// and this coverage assertion enforces nothing.
		const guarded = new Set(
			[
				...code.matchAll(/\[ -[fd] "(ghostty\/[^"]+)" \]/g),
				...code.matchAll(/subject_present [fd] "(ghostty\/[^"]+)"/g),
			]
				.map((m) => m[1])
				.filter((v): v is string => v !== undefined),
		);
		for (const m of [
			...code.matchAll(/\[ -[fd] "\$([A-Z_]+)" \]/g),
			...code.matchAll(/subject_present [fd] "\$([A-Z_]+)"/g),
		]) {
			const resolved = assignments.get(m[1] ?? "");
			if (resolved) guarded.add(resolved);
		}
		const required = declaredRequiredPaths();

		expect(guarded.size).toBeGreaterThan(30);
		const uncovered = [...guarded].filter(
			(p) => !required.has(p) && !NOT_REQUIRED.has(p),
		);
		expect(uncovered).toEqual([]);
	});

	test("the required-path manifest has no stale entries", () => {
		const source = readFileSync(brandingPath, "utf8");
		const referenced = new Set(
			[...source.matchAll(/(ghostty\/[A-Za-z0-9_./ +-]+)/g)]
				.map((m) => m[1])
				.filter((v): v is string => v !== undefined),
		);
		const stale = [...declaredRequiredPaths()].filter(
			(p) => !referenced.has(p),
		);
		expect(stale).toEqual([]);
	});

	test("ghostty_paths_verify fails closed on an empty manifest", () => {
		// An empty array must never read as "everything resolved" — that is the
		// exact false-green an empty loop produces.
		const source = readFileSync(ghosttyPathsPath, "utf8");
		expect(source).toMatch(
			/if \[ "\$\{#GHOSTTY_REQUIRED_PATHS\[@\]\}" -eq 0 \]; then[\s\S]*?return 1/,
		);
	});
});

// ---------------------------------------------------------------------------
// The guardrail suites must stay wired into a gate that actually runs.
//
// Before this, tests/46, 47, 53, 119, 120, 124 and 127 were invoked by no
// script, no /update-yen step and no hook — the fingerprint scanner shipped
// release-wired while the test proving it fails closed only ran if somebody
// typed `bun test` by hand. A test nothing runs is documentation.
// ---------------------------------------------------------------------------
describe("guardrail suites are wired into the release path", () => {
	const componentsPath = join(repoRoot, "scripts/03-verify-components.sh");

	test("every process/gate suite is in the pre-build regression list", () => {
		const script = readFileSync(componentsPath, "utf8");
		const block = script.match(/REGRESSION_TESTS=\(\n([\s\S]*?)\n\s*\)/)?.[1];
		if (!block) throw new Error("REGRESSION_TESTS array not found");

		for (const suite of [
			"tests/46-artifact-fingerprint-gate.test.ts",
			"tests/47-update-signature-gate.test.ts",
			"tests/119-vendor-process-guardrails.test.ts",
			"tests/120-zip-process-guardrails.test.ts",
			"tests/123-release-script-hardening.test.ts",
			"tests/124-upstream-lib-contract.test.ts",
			"tests/127-overlay-recurrence-gates.test.ts",
		]) {
			expect(block).toContain(suite);
		}
		// The originals must survive the rewrite too.
		expect(block).toContain("$YAZI_CONFIG_TEST");
		expect(block).toContain("$OVERLAY_PATCH_TEST");
		expect(block).toContain("$CLI_ALIAS_PARITY_TEST");
	});

	test("the xcodebuild regression slice emits positive evidence, not a missing string", () => {
		const script = readFileSync(componentsPath, "utf8");

		// This replaces a source-text guardrail that asserted the SKIP marker
		// existed. That guardrail was green on the very run that produced an
		// evidence-free success line, because a skip marker says nothing about the
		// RAN path -- and a reader with no positive signal to check will reach for
		// the absence of the negative one. Which is exactly what happened.
		//
		// The requirement is now the inverse: the slice must report what it
		// executed. Behavioural coverage of the mechanism lives in
		// tests/145-gate-receipt-contract.test.ts.
		expect(script).toContain("gate_unit_ran xcode-regression");
		expect(script).toMatch(/executed=\$XCODE_EXECUTED/);

		// The measurement has to come from xcodebuild's own output, so it cannot be
		// satisfied by a constant. Both invocations previously sent everything to
		// /dev/null, which is what left the RAN path silent.
		expect(script).toContain("Executed [0-9]+ test");
		expect(script).not.toMatch(/test-without-building >\/dev\/null/);

		// A slice that builds and reports success while executing zero tests has
		// covered nothing -- the -only-testing identifiers no longer resolving to
		// any suite must fail, not record a hollow RAN.
		expect(script).toMatch(/if \[ "\$XCODE_EXECUTED" -eq 0 \]; then\n\s*fail /);

		// mode=always means "force"; it cannot be satisfied by skipping.
		const forcedBlock = script.match(
			/if \[ "\$\{YEN_COMPONENT_XCODE_REGRESSION_MODE:-auto\}" = "always" \]; then\n\s*fail /,
		);
		expect(forcedBlock).not.toBeNull();
	});

	test("auto-mode change detection anchors on the last release, not any [deploy]", () => {
		const script = readFileSync(componentsPath, "utf8");

		// [deploy] rides web-only deploys too — most reliably the
		// "docs: publish v<version> release notes [deploy]" commit that every /update-yen
		// pushes right AFTER the release, plus routine "chore: update packages
		// [deploy]" bumps. Anchoring on it moved the comparison window past native
		// work, so the gate reported "no native macOS changes" for code the native
		// slice had never covered. Measured on real history: v1.164 shipped with 8
		// native files shadowed, including command-palette sources AND their tests,
		// which are precisely what the native slice runs.
		expect(script).toMatch(
			/--grep='\^v\[0-9\]\+\\\.\[0-9\]\+: '|--grep='\^v\[0-9\]\+\.\[0-9\]\+: '/,
		);

		// The bare [deploy] anchor must not come back.
		expect(script).not.toContain("--grep='\\[deploy\\]'");

		// Extended regex is required for the +/() syntax above to mean anything;
		// without -E the pattern silently matches nothing and the gate would fall
		// back to "no release found".
		const anchorLine = script
			.split("\n")
			.find((line) => line.includes("last_deploy_ref=$("));
		expect(anchorLine).toBeDefined();
		expect(anchorLine).toContain(" -E ");
	});

	test("a missing or failing suite aborts rather than shrinking the set", () => {
		const script = readFileSync(componentsPath, "utf8");
		// Missing file -> fail(), counted, and the run is not attempted.
		expect(script).toContain('fail "Missing regression test:');
		expect(script).toMatch(
			/REGRESSION_TESTS_MISSING=\$\(\(REGRESSION_TESTS_MISSING \+ 1\)\)/,
		);
		expect(script).toMatch(
			/if \[ "\$REGRESSION_TESTS_MISSING" -eq 0 \]; then[\s\S]*?bun test "\$\{REGRESSION_TESTS\[@\]\}"/,
		);
		expect(script).toContain('fail "Regression tests failed');
	});

	test("the vendor roster claim in the docs is actually true", () => {
		// vendor.md states all three consumers iterate the manifest. Phase 4
		// originally converted only some of them; this pins the rest.
		for (const rel of [
			"scripts/14-vendor.sh",
			"scripts/11-sync-vendor-audit.sh",
			"scripts/12-verify-vendor-audit.sh",
		]) {
			const script = readFileSync(join(repoRoot, rel), "utf8");
			expect(script).toContain("vendor_manifest_keys");
			// No hand-written per-vendor registration blocks.
			expect(script).not.toMatch(
				/queue_status_prefetch prefetch_binary_latest_tag "[a-z]+"/,
			);
			expect(script).not.toMatch(/^check_vendor_version "[a-z]+_version"/m);
		}
	});
});

// ---------------------------------------------------------------------------
// A gate that dies must not report success.
//
// An EXIT trap swallows a `set -euo pipefail` fatal abort in bash 3.2 — $? is
// already 0 when the trap fires. 05-detect-failures.sh hit exactly that: with
// version.json absent it printed one "unbound variable" line and exited 0,
// which /update-yen Step 6 reads as PASS on a shipping gate.
// ---------------------------------------------------------------------------
describe("post-build gate cannot exit 0 without completing", () => {
	const detectPath = join(repoRoot, "scripts/05-detect-failures.sh");

	test("the completion sentinel is the shared one, not a fourth hand-written copy", () => {
		const s = readFileSync(detectPath, "utf8");
		// The sentinel was hand-copied into 05, 10 and 13; the third copy's
		// comment named the first two and still copy-pasted. It is now one
		// implementation in scripts/lib/gate-receipt.sh, which every gate on the
		// roster inherits by sourcing -- so it cannot be forgotten by the next
		// author. Behavioural coverage: tests/145.
		expect(s).toContain("scripts/lib/gate-receipt.sh");
		expect(s).toContain(
			"gate_begin 05-detect-failures cleanup_parallel_gate_dir",
		);
		expect(s).toContain("gate_end");
		expect(s).not.toContain("DETECT_COMPLETED");
		// bash 3.2 traps are single-slot: a second EXIT trap here would silently
		// replace the abort handler.
		expect(s).not.toMatch(/^trap .* EXIT/m);
	});

	test("the variables whose absence caused the abort are defaulted", () => {
		const s = readFileSync(detectPath, "utf8");
		expect(s).toMatch(/^VERSION_FILENAME=""$/m);
		expect(s).toMatch(/^DMG_FILENAME=""$/m);
	});

	test("a mid-run abort exits non-zero, proven by execution", () => {
		// The script derives REPO_ROOT from its own path and sources scripts/lib,
		// so mirror that layout in the sandbox or it dies before the trap is even
		// installed — which would pass this test for the wrong reason.
		const dir = mkdtempSync(join(tmpdir(), "yen-detect-abort-"));
		mkdirSync(join(dir, "scripts/lib/units"), { recursive: true });
		for (const lib of readdirSync(join(repoRoot, "scripts/lib"))) {
			if (lib.endsWith(".sh")) {
				copyFileSync(
					join(repoRoot, "scripts/lib", lib),
					join(dir, "scripts/lib", lib),
				);
			}
		}
		// The unit declarations must come along, or the gate fails at gate_begin
		// for a MISSING ROSTER rather than at the deliberate mid-run abort -- which
		// would pass this test for the wrong reason.
		for (const u of readdirSync(join(repoRoot, "scripts/lib/units"))) {
			copyFileSync(
				join(repoRoot, "scripts/lib/units", u),
				join(dir, "scripts/lib/units", u),
			);
		}
		const probe = join(dir, "scripts/probe.sh");
		writeFileSync(
			probe,
			readFileSync(detectPath, "utf8").replace(
				"summarize_output() {",
				'echo "$DELIBERATELY_UNSET_FOR_TEST"\nsummarize_output() {',
			),
			"utf8",
		);
		const res = spawnSync("bash", [probe], { encoding: "utf8" });
		expect(res.status).not.toBe(0);
		expect(`${res.stdout}${res.stderr}`).toContain(
			"aborted before emitting a RECEIPT",
		);
		rmSync(dir, { recursive: true, force: true });
	});
});

// ---------------------------------------------------------------------------
// Remaining fail-opens from the audit: empty scan sets, unverified signatures,
// unasserted frameworks, and a universality predicate the repo's own code
// documents as insufficient.
// ---------------------------------------------------------------------------
describe("release gate completeness", () => {
	const fingerprintPath = join(
		repoRoot,
		"scripts/13-scan-artifact-fingerprints.sh",
	);
	const detectPath = join(repoRoot, "scripts/05-detect-failures.sh");
	const parityPath = join(repoRoot, "scripts/40-vendor-parity-snapshot.sh");
	const sigUtils = join(repoRoot, "scripts/lib/signature-utils.sh");

	test("fingerprint scan reports coverage and fails on an empty scan set", () => {
		const s = readFileSync(fingerprintPath, "utf8");
		expect(s).toContain("SCANNED_PAYLOADS=0");
		expect(s).toContain("scanned=$SCANNED_PAYLOADS");
		expect(s).toMatch(
			/if \[ "\$SCANNED_PAYLOADS" -eq 0 \][\s\S]*?GATE_MODE" = "enforce"[\s\S]*?gate_end 1 2/,
		);
		// A missing `file` binary would silently empty the Mach-O pre-filter.
		expect(s).toContain("command -v file >/dev/null 2>&1");
		// Same trap-swallows-abort shape as 05, now covered by the shared sentinel.
		expect(s).toContain("scripts/lib/gate-receipt.sh");
		expect(s).toContain("gate_begin 13-scan-artifact-fingerprints cleanup");
		expect(s).not.toContain("SCAN_COMPLETED");
	});

	test("empty bundle is rejected in enforce mode, proven by execution", () => {
		const dir = mkdtempSync(join(tmpdir(), "yen-fp-empty-"));
		mkdirSync(join(dir, "YEN.app/Contents/Resources"), { recursive: true });
		writeFileSync(
			join(dir, "YEN.app/Contents/Resources/readme.txt"),
			"hi",
			"utf8",
		);
		const res = spawnSync(
			"bash",
			[
				fingerprintPath,
				"--app",
				join(dir, "YEN.app"),
				"--gate-mode",
				"enforce",
				"--skip-codesig",
			],
			{ encoding: "utf8" },
		);
		expect(res.status).not.toBe(0);
		expect(res.stdout).toContain("scanned=0");
		expect(res.stdout).toContain("ZERO payloads");
		rmSync(dir, { recursive: true, force: true });
	});

	test("appcast signature is cryptographically verified, not grepped", () => {
		const s = readFileSync(detectPath, "utf8");
		expect(s).toContain("extract_sparkle_ed_signature");
		expect(s).toMatch(
			/verify_signed_file_with_public_key "\$RELEASE_DMG" "\$APPCAST_SIG" "\$PUB_KEY"/,
		);
		expect(s).toContain("Appcast EdDSA signature does not verify");
	});

	test("Sparkle.framework absence is a failure, not a skip", () => {
		const s = readFileSync(detectPath, "utf8");
		expect(s).toMatch(
			/if \[ -d "\$SPARKLE_FRAMEWORK" \]; then[\s\S]*?else\n\s*fail "Sparkle\.framework missing/,
		);
	});

	test("universality uses lipo -archs everywhere, not file | grep universal", () => {
		const helper = readFileSync(sigUtils, "utf8");
		expect(helper).toContain("assert_universal_binary()");
		expect(helper).toContain("lipo -archs");
		expect(helper).toMatch(/grep -q " arm64 "/);
		expect(helper).toMatch(/grep -q " x86_64 "/);

		for (const rel of [
			"scripts/05-detect-failures.sh",
			"scripts/12-verify-vendor-audit.sh",
		]) {
			const s = readFileSync(join(repoRoot, rel), "utf8");
			expect(s).toContain("assert_universal_binary");
			expect(s).not.toMatch(/file "[^"]+" \| grep -q "universal"/);
			expect(s).not.toMatch(/grep -q "universal"/);
		}
	});

	test("assert_universal_binary rejects arm64e-only fat binaries", () => {
		// /bin/ls is x86_64 + arm64e — no arm64 slice. `file | grep universal`
		// passes it; the sound check must not.
		const probe = `source ${sigUtils}
assert_universal_binary /bin/ls && echo WEAK || echo STRONG`;
		const res = spawnSync("bash", ["-c", probe], { encoding: "utf8" });
		expect(res.stdout.trim()).toBe("STRONG");
	});

	test("parity snapshot refuses a non-vendor-run as a baseline", () => {
		const s = readFileSync(parityPath, "utf8");
		expect(s).not.toContain("--check 2>&1 || true");
		expect(s).toContain("vendor_status=$?");
		expect(s).toContain("no Summary section");
		expect(s).toContain("manifest vendors");
	});
});

describe("Sparkle runtime floor assertion", () => {
	// Mirrors the live pbxproj shape: the reference DEFINITION (opens `= {`)
	// followed by the product-dependency entry, which also names
	// `XCRemoteSwiftPackageReference "Sparkle"` but ends in `;` and carries no
	// requirement. The parser must anchor on the definition.
	const productDependencySection = `/* Begin XCSwiftPackageProductDependency section */
\t\tA51BFC262B30F1B800E92F16 /* Sparkle */ = {
\t\t\tisa = XCSwiftPackageProductDependency;
\t\t\tpackage = A51BFC252B30F1B700E92F16 /* XCRemoteSwiftPackageReference "Sparkle" */;
\t\t\tproductName = Sparkle;
\t\t};
/* End XCSwiftPackageProductDependency section */
`;

	function pbxprojWith(requirementLines: string[]): string {
		return `// !$*UTF8*$!
{
\tobjects = {
/* Begin XCRemoteSwiftPackageReference section */
\t\tA51BFC252B30F1B700E92F16 /* XCRemoteSwiftPackageReference "Sparkle" */ = {
\t\t\tisa = XCRemoteSwiftPackageReference;
\t\t\trepositoryURL = "https://github.com/sparkle-project/Sparkle";
\t\t\trequirement = {
${requirementLines.map((line) => `\t\t\t\t${line}`).join("\n")}
\t\t\t};
\t\t};
/* End XCRemoteSwiftPackageReference section */

${productDependencySection}\t};
}
`;
	}

	function assertFloor(
		content: string | null,
		floor?: string,
	): { status: number | null; output: string } {
		const dir = mkdtempSync(join(tmpdir(), "yen-sparkle-floor-"));
		const pbxproj = join(dir, "project.pbxproj");
		if (content !== null) writeFileSync(pbxproj, content);
		const floorArg = floor === undefined ? "" : ` "${floor}"`;
		const res = spawnSync(
			"bash",
			[
				"-c",
				`set -euo pipefail
source "${sparkleRuntimeFloorLibPath}"
assert_sparkle_runtime_floor "$1"${floorArg}`,
				"sparkle-floor",
				pbxproj,
			],
			{ encoding: "utf8" },
		);
		rmSync(dir, { recursive: true, force: true });
		return { status: res.status, output: `${res.stdout}${res.stderr}` };
	}

	test("accepts upstream's exact pin at the audited floor", () => {
		const res = assertFloor(
			pbxprojWith(["kind = exactVersion;", "version = 2.9.6;"]),
		);
		expect(res.status).toBe(0);
		expect(res.output).toContain("exactVersion 2.9.6 >= 2.9.6");
	});

	test("compares numerically, not lexically", () => {
		// "2.10.0" sorts below "2.9.6" as text. A lexical compare would reject
		// a legitimately newer minor release.
		const res = assertFloor(
			pbxprojWith(["kind = upToNextMajorVersion;", "minimumVersion = 2.10.0;"]),
		);
		expect(res.status).toBe(0);
		expect(res.output).toContain("upToNextMajorVersion 2.10.0 >= 2.9.6");
	});

	test("rejects an exact pin below the floor", () => {
		const res = assertFloor(
			pbxprojWith(["kind = exactVersion;", "version = 2.9.5;"]),
		);
		expect(res.status).not.toBe(0);
		expect(res.output).toContain(
			"resolves Sparkle exactVersion 2.9.5, below the audited floor 2.9.6",
		);
	});

	test("rejects upstream's former broad 2.5.1 floor", () => {
		// The shape the retired content patch used to rewrite. If upstream ever
		// loosens back to it, the vendor run must stop here.
		const res = assertFloor(
			pbxprojWith(["kind = upToNextMajorVersion;", "minimumVersion = 2.5.1;"]),
		);
		expect(res.status).not.toBe(0);
		expect(res.output).toContain("below the audited floor 2.9.6");
	});

	test("rejects a branch pin, which carries no comparable version", () => {
		const res = assertFloor(pbxprojWith(["kind = branch;", "branch = main;"]));
		expect(res.status).not.toBe(0);
		expect(res.output).toContain(
			"requirement kind 'branch' has no comparable version",
		);
	});

	test("fails closed when only the product dependency names Sparkle", () => {
		// No definition block: the `package = ... /* ... "Sparkle" */;` line
		// must not satisfy the parser, or a removed reference would pass.
		const content = `// !$*UTF8*$!
{
\tobjects = {
${productDependencySection}\t};
}
`;
		const res = assertFloor(content);
		expect(res.status).not.toBe(0);
		expect(res.output).toContain(
			'no XCRemoteSwiftPackageReference "Sparkle" block',
		);
	});

	test("fails closed when the project file is missing", () => {
		const res = assertFloor(null);
		expect(res.status).not.toBe(0);
		expect(res.output).toContain("project file missing");
	});

	test("honors an explicit floor argument", () => {
		const res = assertFloor(
			pbxprojWith(["kind = exactVersion;", "version = 2.9.4;"]),
			"2.9.4",
		);
		expect(res.status).toBe(0);
	});

	test("version_ge orders dotted versions numerically", () => {
		const cases: Array<[string, string, number]> = [
			["2.9.6", "2.9.6", 0],
			["2.10.0", "2.9.6", 0],
			["3", "2.9.6", 0],
			["2.9.6.0", "2.9.6", 0],
			["2.9", "2.9.6", 1],
			["2.9.6", "2.9.6.1", 1],
			["2.9.5", "2.9.6", 1],
		];
		for (const [a, b, expected] of cases) {
			const res = spawnSync(
				"bash",
				[
					"-c",
					`source "${sparkleRuntimeFloorLibPath}"
version_ge "$1" "$2"`,
					"version-ge",
					a,
					b,
				],
				{ encoding: "utf8" },
			);
			expect(res.status, `version_ge ${a} ${b}`).toBe(expected);
		}
	});
});
