import { describe, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import {
	chmodSync,
	existsSync,
	mkdirSync,
	mkdtempSync,
	readdirSync,
	readFileSync,
	rmSync,
	symlinkSync,
	writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const repoRoot = process.cwd();
const vendorSkillPath = join(repoRoot, ".agents/skills/update-yen/SKILL.md");
const vendorBuildRefPath = join(
	repoRoot,
	".agents/skills/update-yen/references/vendor-build.md",
);
const vendorCommitRefPath = join(
	repoRoot,
	".agents/skills/update-yen/references/vendor-commit.md",
);
const scriptsReadmePath = join(repoRoot, "scripts/00-scripts-readme.md");
const vendorScriptPath = join(repoRoot, "scripts/14-vendor.sh");
const vendorBinaryHelperPath = join(repoRoot, "scripts/lib/vendor-binary.sh");
const smokeScriptPath = join(repoRoot, "scripts/native/01-macos-smoke.sh");
const xcodePolicyPath = join(repoRoot, "scripts/lib/xcode-policy.sh");

describe("vendor process guardrails", () => {
	test("pre-release Xcode fails closed unless explicitly acknowledged", () => {
		const fakeBin = mkdtempSync(join(tmpdir(), "yen-xcode-policy-"));
		try {
			writeFileSync(
				join(fakeBin, "xcodebuild"),
				'#!/bin/bash\nprintf "Xcode 27.0\\nBuild version 27A5228h\\n"\n',
				{ mode: 0o755 },
			);
			writeFileSync(
				join(fakeBin, "xcode-select"),
				'#!/bin/bash\nprintf "/Applications/Xcode-beta.app/Contents/Developer\\n"\n',
				{ mode: 0o755 },
			);
			const command = `source ${JSON.stringify(xcodePolicyPath)}; validate_selected_xcode_release_policy`;
			const blocked = spawnSync("/bin/bash", ["-c", command], {
				env: { ...process.env, PATH: `${fakeBin}:${process.env.PATH}` },
				encoding: "utf8",
			});
			expect(blocked.status).not.toBe(0);
			expect(`${blocked.stdout}${blocked.stderr}`).toContain(
				"Refusing pre-release Xcode",
			);

			const allowed = spawnSync("/bin/bash", ["-c", command], {
				env: {
					...process.env,
					PATH: `${fakeBin}:${process.env.PATH}`,
					YEN_ALLOW_PRERELEASE_XCODE: "1",
				},
				encoding: "utf8",
			});
			expect(allowed.status).toBe(0);
			expect(allowed.stdout).toContain("Pre-release Xcode explicitly allowed");
		} finally {
			rmSync(fakeBin, { recursive: true, force: true });
		}
	});

	test("stable Xcode.app GM builds with letter-suffix ids are accepted", () => {
		const fakeBin = mkdtempSync(join(tmpdir(), "yen-xcode-policy-gm-"));
		try {
			writeFileSync(
				join(fakeBin, "xcodebuild"),
				'#!/bin/bash\nprintf "Xcode 27.0\\nBuild version 27A266a\\n"\n',
				{ mode: 0o755 },
			);
			writeFileSync(
				join(fakeBin, "xcode-select"),
				'#!/bin/bash\nprintf "/Applications/Xcode.app/Contents/Developer\\n"\n',
				{ mode: 0o755 },
			);
			const command = `source ${JSON.stringify(xcodePolicyPath)}; validate_selected_xcode_release_policy`;
			const accepted = spawnSync("/bin/bash", ["-c", command], {
				env: { ...process.env, PATH: `${fakeBin}:${process.env.PATH}` },
				encoding: "utf8",
			});
			expect(accepted.status).toBe(0);
			expect(accepted.stdout).toContain("Stable Xcode selected");
			expect(accepted.stdout).toContain("27A266a");
		} finally {
			rmSync(fakeBin, { recursive: true, force: true });
		}
	});

	test("Xcode.app whose version line names beta still fails closed", () => {
		const fakeBin = mkdtempSync(join(tmpdir(), "yen-xcode-policy-named-beta-"));
		try {
			writeFileSync(
				join(fakeBin, "xcodebuild"),
				'#!/bin/bash\nprintf "Xcode 27.0 beta\\nBuild version 27A5194q\\n"\n',
				{ mode: 0o755 },
			);
			writeFileSync(
				join(fakeBin, "xcode-select"),
				'#!/bin/bash\nprintf "/Applications/Xcode.app/Contents/Developer\\n"\n',
				{ mode: 0o755 },
			);
			const command = `source ${JSON.stringify(xcodePolicyPath)}; validate_selected_xcode_release_policy`;
			const blocked = spawnSync("/bin/bash", ["-c", command], {
				env: { ...process.env, PATH: `${fakeBin}:${process.env.PATH}` },
				encoding: "utf8",
			});
			expect(blocked.status).not.toBe(0);
			expect(`${blocked.stdout}${blocked.stderr}`).toContain(
				"Refusing pre-release Xcode",
			);
		} finally {
			rmSync(fakeBin, { recursive: true, force: true });
		}
	});

	test("vendor provenance uses provider digests and immutable source commits", () => {
		const helper = readFileSync(vendorBinaryHelperPath, "utf8");
		const ghostty = readFileSync(
			join(repoRoot, "scripts/10-update-ghostty.sh"),
			"utf8",
		);
		const vendorGate = readFileSync(vendorScriptPath, "utf8");
		expect(helper).toContain("github-release-asset-digests");
		expect(helper).toContain("source_api_sha256_arm64");
		expect(helper).toContain("vendor_resolve_tag_commit");
		expect(helper).toContain("github-commit-bound-archive");
		expect(ghostty).toContain("upstream_verified_commit_sha");
		expect(ghostty).toContain("github-verified-commit");
		expect(vendorGate).toContain("source_api_sha256_arm64");
		expect(vendorGate).toContain("github-commit-bound-archive");
		expect(vendorGate).toContain(
			"Ghostty baseline lacks verified forge commit provenance",
		);

		for (const name of [
			".ghostty-baseline",
			".btop-baseline",
			".fastfetch-baseline",
			".lazygit-baseline",
			".ripgrep-baseline",
			".yazi-baseline",
		]) {
			const baseline = readFileSync(
				join(repoRoot, "yen-terminal", name),
				"utf8",
			);
			expect(baseline).not.toMatch(/provenance_verification=override-/);
		}
	});
	test("the retired /yen-vendor skill leaves no skill, pointer or backup copy in the repo", () => {
		// /yen-vendor was folded into /update-yen as its vendor phase. A leftover skill
		// directory would list a second entry point in the picker, and a repo-local
		// pointer would shadow the global /update-yen command inside this repo.
		for (const rel of [
			".agents/skills/yen-vendor",
			".claude/commands/vendor.md",
			".claude/commands/yen-vendor.md",
			"claude-commands",
		]) {
			expect(existsSync(join(repoRoot, rel)), `${rel} must not exist`).toBe(
				false,
			);
		}
	});

	test("the retired /yen-zip name leaves no skill directory in the repo", () => {
		// /yen-zip was renamed /update-yen when it took over yenchat's dependency
		// updates from /update-projs. A leftover directory would list a second,
		// stale entry point in the picker.
		expect(existsSync(join(repoRoot, ".agents/skills/yen-zip"))).toBe(false);
		expect(existsSync(join(repoRoot, ".agents/skills/update-yen"))).toBe(true);
	});

	test("the /update-yen deps phase runs first and owns yenchat's package updates", () => {
		const skill = readFileSync(vendorSkillPath, "utf8");
		const deps = readFileSync(
			join(repoRoot, ".agents/skills/update-yen/references/deps-update.md"),
			"utf8",
		);
		// The deps phase precedes the vendor phase in the phase map and in full mode.
		const map = skill.slice(skill.indexOf("## Phase Map"));
		expect(map.indexOf("references/deps-update.md")).toBeGreaterThan(-1);
		expect(map.indexOf("references/deps-update.md")).toBeLessThan(
			map.indexOf("references/vendor-check.md"),
		);
		expect(skill).toContain("Before Step D1, `cd $HOME/Documents/yenchat`");
		expect(skill).toContain("`/update-projs` does not cover yenchat");
		// The phase covers every updater /update-projs used to run here.
		for (const needle of [
			"bunx npm-check-updates",
			"bun audit",
			"tools/sparkle/VERSION",
			"releases/latest",
			"bun run check:full",
			"`deps: ",
			"eval-phase.sh begin yen-deps",
		]) {
			expect(deps).toContain(needle);
		}
		// Every deps eval ID in the table matches the namespace contract.
		const ids = [...deps.matchAll(/^\| (DP-\d\d) \|/gm)].map((m) => m[1]);
		expect(ids).toEqual(["DP-01", "DP-02", "DP-03", "DP-04", "DP-05", "DP-06"]);
	});

	test("the /update-yen skill carries the vendor phase and its mirror rule", () => {
		const skill = readFileSync(vendorSkillPath, "utf8").toLowerCase();

		for (const needle of [
			"name: update-yen",
			"mirror update rule",
			"vendor phase",
			"steps v1 to v5",
			"references/vendor-check.md",
			"references/vendor-update.md",
			"references/vendor-audit.md",
			"references/vendor-build.md",
			"references/vendor-commit.md",
			"runs from any directory",
			"cd $home/documents/yenchat",
			"same commit",
			"tests/119-vendor-process-guardrails.test.ts",
		]) {
			expect(skill).toContain(needle);
		}
		for (const retired of [
			".claude/commands/vendor.md",
			"claude-commands/vendor.md",
			"~/.codex/skills/vendor",
			"~/.claude/commands/yen-vendor.md",
			"~/.codex/skills/yen-vendor",
			"claude-commands/yen-vendor.md",
			"name: yen-vendor",
		]) {
			expect(skill).not.toContain(retired);
		}
	});

	test("skill documents the current Ghostty preflight gates", () => {
		const skill = readFileSync(vendorSkillPath, "utf8").toLowerCase();

		for (const needle of [
			"toolchain preflight",
			"rollback-history check",
			"ghostty rollback history",
			"yen_vendor_block_on_rollback=1",
			"pre-overlay structural diff",
			"baseline snapshot/revert hint",
			"sdk linker probe",
			"scripts/lib/upstream.sh",
			"scripts/40-vendor-parity-snapshot.sh",
			"stable xcode policy",
			"yen_allow_prerelease_xcode=1",
			"upstream provenance",
		]) {
			expect(skill).toContain(needle);
		}
	});

	test("skill documents the upstream-relocation gates", () => {
		const skill = readFileSync(vendorSkillPath, "utf8").toLowerCase();

		// These gates only help if an operator knows the bypass exists and what
		// it does and does not cover; an undocumented waiver env gets used wrong.
		for (const needle of [
			"yen_vendor_accept_overlay_content_drift=1",
			"yen-terminal/.overlay-upstream-pairs.txt",
			"src/build/libtoolstep.zig",
			"ghostty_patch_targets",
		]) {
			expect(skill).toContain(needle);
		}
		// The structural-vs-drift distinction is the load-bearing part.
		expect(skill).toMatch(/structural[\s\S]{0,120}(not|never)\b/);
	});

	test("upstream content pins cover every paired overlay", () => {
		// The three-entry .build-overlay-upstream.sha256 tripwire was retired:
		// its entries were a strict subset of the pair manifest, which now pins
		// upstream content for every paired overlay, not just the Zig build
		// files. That generalization is what catches for Swift what the Zig
		// tripwire caught for src/build/LibtoolStep.zig.
		const manifest = readFileSync(
			join(repoRoot, "yen-terminal/.overlay-upstream-pairs.txt"),
			"utf8",
		);
		const rows = manifest
			.split("\n")
			.filter((l) => l.trim() && !l.startsWith("#"))
			.map((l) => l.split("\t"));

		expect(rows.length).toBeGreaterThan(20);
		for (const [rel, sha] of rows) {
			expect(rel).toBeTruthy();
			expect(sha).toMatch(/^[0-9a-f]{64}$/);
			expect(
				existsSync(join(repoRoot, "yen-terminal/overlays", rel as string)),
			).toBe(true);
		}
		// The formerly separately-pinned build files must still be covered.
		const paths = rows.map((r) => r[0]);
		for (const rel of [
			"build.zig",
			"src/build/main.zig",
			"src/build/LibtoolStep.zig",
		]) {
			expect(paths).toContain(rel);
		}
		// The retired three-entry tripwire must be gone, not merely unused.
		expect(
			existsSync(join(repoRoot, "yen-terminal/.build-overlay-upstream.sha256")),
		).toBe(false);
	});

	test("skip-build default for non-code bumps documents its classification + zip-follows guards", () => {
		const skill = readFileSync(vendorSkillPath, "utf8").toLowerCase();
		const buildRef = readFileSync(vendorBuildRefPath, "utf8").toLowerCase();

		for (const doc of [skill, buildRef]) {
			// Promoted from optional shortcut to the documented default...
			expect(doc).toContain("skip-build default for non-code bumps");
			// ...with the non-code classification (code bumps must NOT skip the gate)...
			expect(doc).toContain("build.zig");
			expect(doc).toContain("overlay");
			// ...and the standalone-bump guard (no /update-yen following → still build).
			expect(doc).toContain("not following immediately");
		}
	});

	test("VB-05 runs the native slice once from VB-01's saved receipt", () => {
		// After a Ghostty refresh VB-01 skips the xcodebuild slice (no
		// xcframework), and nothing in the vendor run executed the native suites
		// before the commit; agents compensated by re-running all 17 component
		// units after the build (measured 345-375s per run). The vendor build
		// reference now tees VB-01 and hands the decision to the shared decider.
		const buildRef = readFileSync(vendorBuildRefPath, "utf8");
		const skill = readFileSync(vendorSkillPath, "utf8");
		expect(buildRef).toContain(
			"03-verify-components.sh 2>&1 \\| tee $HOME/Documents/yenchat/tmp/skill-telemetry/yen-vendor-components.out",
		);
		expect(buildRef).toContain("| VB-05 |");
		expect(buildRef).toContain(
			"bash $HOME/Documents/yenchat/.agents/skills/update-yen/scripts/run-native-slice-if-needed.sh yen-vendor",
		);
		expect(buildRef).toContain("SKIP|native-slice-vb05|");
		expect(buildRef).toContain("RAN|native-slice-vb05|forcing the slice:");
		expect(skill).toContain("run-native-slice-if-needed.sh yen-vendor");
		expect(buildRef).not.toContain("Components verified (post-build");
	});

	test("saved-output eval checks reject a file from an earlier run", () => {
		// VB-02 passed on a smoke log at a fixed path, so a run that never
		// started the build (or whose nohup never launched) could pass on
		// yesterday's SMOKE_EXIT_CODE=0. Every saved-file check now tests -nt
		// against the run id file that `begin` writes.
		const checks: Array<[string, string]> = [
			[".agents/skills/update-yen/references/vendor-check.md", "| VC-01 |"],
			[".agents/skills/update-yen/references/vendor-update.md", "| VU-01 |"],
			[".agents/skills/update-yen/references/vendor-build.md", "| VB-02 |"],
			[".agents/skills/update-yen/references/zip-build.md", "| BD-03 |"],
		];
		for (const [rel, rowId] of checks) {
			const doc = readFileSync(join(repoRoot, rel), "utf8");
			const row = doc.split("\n").find((l) => l.startsWith(rowId));
			expect(row, `${rel} has no ${rowId} row`).toBeDefined();
			expect(row, `${rel} ${rowId} must test -nt the run id file`).toMatch(
				/-nt .*-eval-run\.id|-eval-run\.id.* -nt|-nt "\$RUN"/,
			);
		}
	});

	test("the Zig toolchain pin is compared in one shared function", () => {
		// 14-vendor.sh and validate-environment.sh each carried their own
		// grep/sed of `.minimum_zig_version`; a pin-format change had two places
		// to miss. Both now call scripts/lib/zig-toolchain.sh with their own
		// bypass variables, which stay distinct because they guard different moments.
		const lib = readFileSync(
			join(repoRoot, "scripts/lib/zig-toolchain.sh"),
			"utf8",
		);
		const vendor = readFileSync(vendorScriptPath, "utf8");
		const validate = readFileSync(
			join(repoRoot, "yen-terminal/customizations/validate-environment.sh"),
			"utf8",
		);
		expect(lib).toContain("zig_toolchain_check() {");
		expect(
			lib
				.split("\n")
				.filter(
					(l) =>
						!l.trimStart().startsWith("#") && /minimum_zig_version/.test(l),
				).length,
		).toBe(1);
		for (const [name, body] of [
			["14-vendor.sh", vendor],
			["validate-environment.sh", validate],
		] as const) {
			expect(body, `${name} must source the shared lib`).toContain(
				"scripts/lib/zig-toolchain.sh",
			);
			expect(body, `${name} must call the shared check`).toContain(
				"zig_toolchain_check",
			);
			expect(
				body
					.split("\n")
					.filter(
						(l) =>
							!l.trimStart().startsWith("#") &&
							/grep .*minimum_zig_version/.test(l),
					),
				`${name} must not grep the pin itself`,
			).toEqual([]);
		}
		expect(vendor).toContain("YEN_VENDOR_SKIP_TOOLCHAIN_PREFLIGHT");
		expect(validate).toContain("YEN_SKIP_ZIG_VERSION_CHECK");
	});

	test("VB-04 saves the AppleScript receipt it tells the agent to read", () => {
		// eval-phase.sh deletes a passing check's log, so a bare VB-04 left no
		// RAN|verifier| or SKIP|verifier| line to judge and forced a second run.
		const buildRef = readFileSync(vendorBuildRefPath, "utf8");
		expect(buildRef).toContain(
			"16-verify-applescript-if-needed.sh 2>&1 \\| tee $HOME/Documents/yenchat/tmp/skill-telemetry/yen-vendor-applescript.out",
		);
		expect(buildRef).toContain("in that saved receipt, not by exit 0");
	});

	test("vendor rollback preflight reads the rollback ledger against the compare range", () => {
		const script = readFileSync(vendorScriptPath, "utf8");

		expect(script).toContain("_docs/04-security.md");
		expect(script).toContain("Ghostty Rollback History");
		// Phase 0 of the Ghostty-leaving-GitHub migration centralizes upstream
		// URL plumbing in scripts/lib/upstream.sh. The compare URL is now built
		// via upstream_compare_url; we assert the abstraction is wired in, and
		// validate the produced URL shape in the dedicated lib/upstream test.
		expect(script).toContain('source "$REPO_ROOT/scripts/lib/upstream.sh"');
		expect(script).toContain('upstream_compare_url "$current_commit" main');
		expect(script).toContain("sha.startswith(start) or sha.startswith(end)");
	});

	test("vendor rollback preflight survives a compare body past ARG_MAX and fails closed on a bad body", () => {
		// The compare body embeds every file patch. Passed through the
		// environment, a 61-commit range hit E2BIG and the check silently passed.
		const script = readFileSync(vendorScriptPath, "utf8");
		const fn = script.match(
			/^preflight_check_rollback_history\(\) \{\n[\s\S]*?\n\}\n/m,
		)?.[0];
		expect(fn).toBeDefined();
		const sandbox = mkdtempSync(join(tmpdir(), "yen-vendor-rollback-"));
		try {
			mkdirSync(join(sandbox, "_docs"));
			writeFileSync(
				join(sandbox, "_docs/04-security.md"),
				"| Rollback commit | Date | Vendor | Rolled-back range | Reason |\n|---|---|---|---|---|\n| `abc1234` | 2026-01-01 | Ghostty | `deadbeef..cafef00d` | broke splits |\n",
			);
			const runWithBody = (body: string) => {
				const bodyPath = join(sandbox, "compare.json");
				writeFileSync(bodyPath, body);
				const harness = [
					`REPO_ROOT=${JSON.stringify(sandbox)}`,
					"upstream_compare_url() { echo compare; }",
					`github_api_get() { GITHUB_API_RESPONSE_HTTP_CODE=200; GITHUB_API_RESPONSE_BODY=$(/bin/cat ${JSON.stringify(bodyPath)}); }`,
					fn,
					"YEN_VENDOR_BLOCK_ON_ROLLBACK=1 preflight_check_rollback_history deadbeef",
				].join("\n");
				return spawnSync("/bin/bash", ["-c", harness], { encoding: "utf8" });
			};

			const large = runWithBody(
				JSON.stringify({
					commits: [{ sha: `deadbeef${"0".repeat(32)}` }],
					files: [{ patch: "x".repeat(2 * 1024 * 1024) }],
				}),
			);
			expect(`${large.stdout}${large.stderr}`).toContain(
				"Re-landing a previously-reverted Ghostty range",
			);
			expect(large.status).toBe(1);

			const malformed = runWithBody("not json");
			expect(malformed.stdout).toContain(
				"Rollback-history check failed (python3 exit 1); ledger not checked",
			);
			expect(malformed.status).toBe(1);
		} finally {
			rmSync(sandbox, { recursive: true, force: true });
		}
	});

	test("Yazi audit uses a supported non-interactive liveness command", () => {
		const auditReference = readFileSync(
			join(repoRoot, ".agents/skills/update-yen/references/vendor-audit.md"),
			"utf8",
		);
		const fileBrowserDoc = readFileSync(
			join(repoRoot, "_docs/14-file-browser.md"),
			"utf8",
		);

		expect(auditReference).toContain("yazi --version");
		expect(fileBrowserDoc).toContain("yazi --version");
		expect(auditReference).not.toContain("yazi --debug");
		expect(fileBrowserDoc).not.toContain("yazi --debug");
	});

	test("local smoke build suggests rollback when the build introduces vendor drift", () => {
		const script = readFileSync(smokeScriptPath, "utf8");

		expect(script).toContain("SMOKE_VENDOR_DIRTY_BEFORE");
		expect(script).toContain("SMOKE_VENDOR_DIRTY_AFTER");
		expect(script).toContain(
			'[ "$SMOKE_VENDOR_DIRTY_AFTER" != "$SMOKE_VENDOR_DIRTY_BEFORE" ]',
		);
		expect(script).toContain(
			'git -C \\"$REPO_ROOT\\" checkout -- ${SMOKE_VENDOR_SNAPSHOT_PATHS[*]}',
		);
	});

	test("source-build no-op path revalidates the pinned output digest before returning current", () => {
		// The fd/btop/zmx source-build scripts share vendor_source_build() in
		// lib/vendor-binary.sh. Its no-op path must fail closed on a tampered or
		// stale bundled binary BEFORE printing "Already current" — a guardrail on
		// ordering, since the message must never precede the digest revalidation.
		const fullHelper = readFileSync(vendorBinaryHelperPath, "utf8");
		// Scope to vendor_source_build(): vendor_binary() also prints an "Already
		// current ... and universal" line, so an unscoped indexOf would compare
		// against the wrong function.
		const fnStart = fullHelper.indexOf("vendor_source_build() {");
		expect(fnStart).toBeGreaterThanOrEqual(0);
		const script = fullHelper.slice(fnStart);
		const digestMismatchIndex = script.indexOf(
			"current output digest mismatch vs baseline pin",
		);
		const missingPinIndex = script.indexOf(
			"missing baseline output_sha256 for current version",
		);
		const currentExitIndex = script.indexOf(
			"Already current ($CURRENT_VERSION) and universal",
		);

		expect(digestMismatchIndex).toBeGreaterThanOrEqual(0);
		expect(missingPinIndex).toBeGreaterThanOrEqual(0);
		expect(currentExitIndex).toBeGreaterThanOrEqual(0);
		expect(digestMismatchIndex).toBeLessThan(currentExitIndex);
		expect(missingPinIndex).toBeLessThan(currentExitIndex);
	});

	test("source-build rebuild path rejects a missing output pin before persistence", () => {
		const fullHelper = readFileSync(vendorBinaryHelperPath, "utf8");
		const fnStart = fullHelper.indexOf("vendor_source_build() {");
		expect(fnStart).toBeGreaterThanOrEqual(0);
		const script = fullHelper.slice(fnStart);
		const missingPinIndex = script.indexOf(
			"missing baseline output_sha256 before source-build baseline rewrite",
		);
		const versionWriteIndex = script.indexOf(
			'echo "$LATEST_TAG" > "$VERSION_FILE"',
		);
		const baselineWriteIndex = script.indexOf('} > "$BASELINE_FILE"');

		expect(missingPinIndex).toBeGreaterThanOrEqual(0);
		expect(script).toContain(
			'PROVENANCE_VERIFICATION="override-missing-output-pin"',
		);
		expect(versionWriteIndex).toBeGreaterThanOrEqual(0);
		expect(baselineWriteIndex).toBeGreaterThanOrEqual(0);
		expect(missingPinIndex).toBeLessThan(versionWriteIndex);
		expect(missingPinIndex).toBeLessThan(baselineWriteIndex);
	});

	test("integrity bypass fails closed when its audit log cannot be written", () => {
		const fixtureRoot = mkdtempSync(join(tmpdir(), "yen-vendor-audit-"));
		const notDirectory = join(fixtureRoot, "regular-file");
		writeFileSync(notDirectory, "blocks mkdir", "utf8");

		try {
			const auditLog = join(notDirectory, "audit.log");
			const result = spawnSync(
				"/bin/bash",
				[
					"-c",
					[
						`source ${JSON.stringify(vendorBinaryHelperPath)}`,
						`YEN_VENDOR_ALLOW_UNVERIFIED_DOWNLOADS=1 YEN_VENDOR_INTEGRITY_AUDIT_LOG=${JSON.stringify(auditLog)} YEN_VENDOR_INTEGRITY_BYPASS_REASON=test vendor_fail_or_bypass_integrity ${JSON.stringify(fixtureRoot)} test-context test-detail`,
					].join("\n"),
				],
				{ encoding: "utf8" },
			);

			expect(result.status).not.toBe(0);
			expect(`${result.stdout}${result.stderr}`).toContain(
				"Refusing unaudited integrity-gate bypass",
			);
		} finally {
			rmSync(fixtureRoot, { recursive: true, force: true });
		}
	});

	test("integrity bypass refuses a malformed audit-log path instead of mkdir -p'ing it", () => {
		// Regression: a caller that captures the helper's stdout into the audit-log
		// path (or into $repo_root) hands over a multi-line, non-absolute string.
		// The old code ran `mkdir -p "$(dirname "$log_path")"` on it, silently
		// building the whole bogus tree relative to the current directory.
		const sandbox = mkdtempSync(join(tmpdir(), "yen-vendor-audit-malformed-"));

		try {
			// Passed through the environment, not the command string: a real newline
			// survives here, whereas shell-quoting it would collapse to a literal
			// backslash-n and exercise the absolute-path guard instead.
			const malformed = `  WARNING: Integrity gate bypassed\n${join(sandbox, "nested", "audit.log")}`;
			const result = spawnSync(
				"/bin/bash",
				[
					"-c",
					[
						`source ${JSON.stringify(vendorBinaryHelperPath)}`,
						`vendor_fail_or_bypass_integrity ${JSON.stringify(sandbox)} test-context test-detail`,
					].join("\n"),
				],
				{
					cwd: sandbox,
					encoding: "utf8",
					env: {
						...process.env,
						YEN_VENDOR_ALLOW_UNVERIFIED_DOWNLOADS: "1",
						YEN_VENDOR_INTEGRITY_AUDIT_LOG: malformed,
						YEN_VENDOR_INTEGRITY_BYPASS_REASON: "test",
					},
				},
			);

			const output = `${result.stdout}${result.stderr}`;
			expect(result.status).not.toBe(0);
			expect(output).toContain(
				"Malformed integrity audit-log path (empty or multi-line)",
			);
			expect(output).toContain("Refusing unaudited integrity-gate bypass");
			// The bypass must not have littered the working directory.
			expect(readdirSync(sandbox)).toEqual([]);
		} finally {
			rmSync(sandbox, { recursive: true, force: true });
		}
	});

	test("integrity bypass refuses a relative audit-log path", () => {
		const sandbox = mkdtempSync(join(tmpdir(), "yen-vendor-audit-relative-"));

		try {
			const result = spawnSync(
				"/bin/bash",
				[
					"-c",
					[
						`source ${JSON.stringify(vendorBinaryHelperPath)}`,
						`YEN_VENDOR_ALLOW_UNVERIFIED_DOWNLOADS=1 YEN_VENDOR_INTEGRITY_AUDIT_LOG=relative/dir/audit.log YEN_VENDOR_INTEGRITY_BYPASS_REASON=test vendor_fail_or_bypass_integrity ${JSON.stringify(sandbox)} test-context test-detail`,
					].join("\n"),
				],
				{ cwd: sandbox, encoding: "utf8" },
			);

			const output = `${result.stdout}${result.stderr}`;
			expect(result.status).not.toBe(0);
			expect(output).toContain(
				"Integrity audit-log path must be absolute: relative/dir/audit.log",
			);
			expect(readdirSync(sandbox)).toEqual([]);
		} finally {
			rmSync(sandbox, { recursive: true, force: true });
		}
	});

	test("scripts readme stays aligned with underscore checksum discovery", () => {
		const readme = readFileSync(scriptsReadmePath, "utf8");
		const helper = readFileSync(
			join(repoRoot, "scripts/lib/vendor-binary.sh"),
			"utf8",
		);

		expect(readme).toContain(
			"Published checksum verification (8 filename patterns tried, including underscore variants)",
		);

		expect(helper).toContain('"${DISPLAY_NAME}_${LATEST_TAG}_checksums.txt"');
		expect(helper).toContain('"${DISPLAY_NAME}_${VERSION_NUM}_checksums.txt"');
	});

	test("ghostty vendor run neutralizes upstream agent instructions before overlays", () => {
		const script = readFileSync(
			join(repoRoot, "scripts/10-update-ghostty.sh"),
			"utf8",
		);

		expect(script).toContain("neutralize_vendored_agent_files() {");

		const callIndex = script.indexOf("if ! neutralize_vendored_agent_files;");
		const overlayIndex = script.indexOf('echo "[3/5] Applying overlays..."');

		expect(callIndex).toBeGreaterThan(0);
		expect(overlayIndex).toBeGreaterThan(0);
		expect(callIndex).toBeLessThan(overlayIndex);

		// Fail-closed: a stub that was not written is a live upstream booby trap.
		expect(script).toContain(
			"ERROR: failed to write vendored agent instruction stub",
		);
		expect(script).toContain(
			"upstream agent instruction file(s) survived neutralization",
		);
	});
});

// ---------------------------------------------------------------------------
// Unknown-status and audit-completeness gates.
//
// "We could not determine the status" is a distinct outcome from "there is
// nothing new". Folding the former into the latter is a false green, and it is
// the failure mode that gets likelier as upstream cadence rises.
// ---------------------------------------------------------------------------
describe("unknown-status fail-closed gates", () => {
	const upstreamLibPath = join(repoRoot, "scripts/lib/upstream.sh");
	const checkUpstreamPath = join(repoRoot, "scripts/08-check-upstream.sh");
	const analyzeImpactPath = join(repoRoot, "scripts/09-analyze-impact.sh");
	const auditLayersPath = join(
		repoRoot,
		".agents/skills/update-yen/scripts/verify-audit-layers.sh",
	);

	test("forge auth header is centralized and used by every API caller", () => {
		const lib = readFileSync(upstreamLibPath, "utf8");
		expect(lib).toContain("upstream_auth_header()");
		expect(lib).toContain("forge_github_auth_header()");
		// Dispatch through the forge indirection like every other verb.
		expect(lib).toContain('"forge_${UPSTREAM_FORGE}_auth_header"');

		for (const p of [checkUpstreamPath, analyzeImpactPath]) {
			expect(readFileSync(p, "utf8")).toContain("upstream_auth_header");
		}
	});

	test("08-check-upstream reports UNKNOWN instead of 'up to date' on API failure", () => {
		const script = readFileSync(checkUpstreamPath, "utf8");
		// A non-200 must not fall through to the up-to-date branch.
		expect(script).not.toMatch(
			/HTTP_CODE" = "403"[\s\S]{0,120}TOTAL_COMMITS=0/,
		);
		expect(script).toContain("Upstream: UNKNOWN");
		// Every UNKNOWN branch exits non-zero.
		const unknownBranches = [
			...script.matchAll(/Upstream: UNKNOWN"\n\s*exit 1/g),
		];
		expect(unknownBranches.length).toBeGreaterThanOrEqual(3);
	});

	test("14-vendor counts unknown status separately and fails update mode", () => {
		const script = readFileSync(vendorScriptPath, "utf8");
		expect(script).toContain("UNKNOWN_COUNT=0");
		expect(script).toContain("record_unknown_status()");
		// Unknown must no longer be folded into CURRENT_COUNT.
		expect(script).not.toMatch(
			/status unknown"\n\s*if \[ "\$CHECK_ONLY" = true \][\s\S]{0,120}CURRENT_COUNT/,
		);
		expect(script).toContain('echo "  Unknown:         $UNKNOWN_COUNT"');
		expect(script).toMatch(
			/if \[ "\$UNKNOWN_COUNT" -gt 0 \]; then[\s\S]*?YEN_VENDOR_ALLOW_UNKNOWN_STATUS[\s\S]*?gate_end 1/,
		);
	});

	test("verify-audit-layers accepts every vendor in the manifest", () => {
		// 14-vendor.sh now accepts any manifest key (the hand-written arg-parse
		// arms were replaced in Phase 4), so the manifest is the target list.
		const manifestBody = readFileSync(
			join(repoRoot, "scripts/lib/vendor-manifest.sh"),
			"utf8",
		).match(/YEN_VENDOR_MANIFEST=\(\n([\s\S]*?)\n\)/)?.[1];
		if (!manifestBody) throw new Error("YEN_VENDOR_MANIFEST array not found");
		const auditScript = readFileSync(auditLayersPath, "utf8");

		const targets = new Set(
			[...manifestBody.matchAll(/"([a-z0-9-]+)\|/g)]
				.map((m) => m[1])
				.filter((v): v is string => v !== undefined),
		);
		// Floor against a short parse: the roster holds eight vendors.
		expect(targets.size).toBeGreaterThanOrEqual(8);

		// The case arms list accepted vendors pipe-separated.
		const armed = new Set<string>();
		for (const m of auditScript.matchAll(/^\s{4}([a-z0-9|-]+)\)$/gm)) {
			for (const name of (m[1] ?? "").split("|")) {
				if (name && name !== "*") armed.add(name);
			}
		}
		const unsupported = [...targets].filter((t) => !armed.has(t));
		expect(unsupported).toEqual([]);
	});

	test("verify-audit-layers fails closed without a real audit log", () => {
		const dir = mkdtempSync(join(tmpdir(), "yen-audit-layers-"));
		const emptyLog = join(dir, "empty.log");
		writeFileSync(emptyLog, "", "utf8");
		const partialLog = join(dir, "partial.log");
		writeFileSync(
			partialLog,
			"LAYER 1: overlays applied clean, 0 patched\nLAYER 3: no branding residue found\n",
			"utf8",
		);
		const fullLog = join(dir, "full.log");
		writeFileSync(
			fullLog,
			[1, 2, 3, 4, 5, 6]
				.map((n) => `LAYER ${n}: recorded finding for layer ${n}`)
				.join("\n"),
			"utf8",
		);

		// No log at all — this is the case the old script always passed.
		const noLog = spawnSync("bash", [auditLayersPath, "ghostty"], {
			encoding: "utf8",
		});
		expect(noLog.status).not.toBe(0);

		const empty = spawnSync("bash", [auditLayersPath, "ghostty", emptyLog], {
			encoding: "utf8",
		});
		expect(empty.status).not.toBe(0);

		const partial = spawnSync(
			"bash",
			[auditLayersPath, "ghostty", partialLog],
			{
				encoding: "utf8",
			},
		);
		expect(partial.status).not.toBe(0);
		expect(partial.stdout).toContain("Layer 2");

		const full = spawnSync("bash", [auditLayersPath, "ghostty", fullLog], {
			encoding: "utf8",
		});
		expect(full.status).toBe(0);

		rmSync(dir, { recursive: true, force: true });
	});

	test("zip preflight keychain check exercises signing, not a negated grep", () => {
		for (const rel of [
			".agents/skills/update-yen/references/zip-preflight.md",
		]) {
			const doc = readFileSync(join(repoRoot, rel), "utf8");
			// `security show-keychain-info | grep -qv locked` passes on the locked
			// error string, and the non-negated variant blocks on an unlock prompt.
			expect(doc).not.toContain("show-keychain-info");
			expect(doc).toContain("codesign --sign");
		}
	});
});

// ---------------------------------------------------------------------------
// One vendor roster.
//
// The roster used to live in eleven-plus independent enumerations. Missing a
// copy degraded silently: a vendor absent from 12-verify-vendor-audit.sh was
// simply never verified, and one absent from the status prefetch fell back to
// a synchronous fetch with no warning.
// ---------------------------------------------------------------------------
describe("vendor manifest is the single roster", () => {
	const manifestPath = join(repoRoot, "scripts/lib/vendor-manifest.sh");

	type VendorRecord = {
		key: string;
		type: string;
		title: string;
		subtitle: string;
		repo: string;
		binary: string;
		script: string;
		companion: string;
		requireCompanion: string;
	};

	function manifest(): VendorRecord[] {
		const body = readFileSync(manifestPath, "utf8").match(
			/YEN_VENDOR_MANIFEST=\(\n([\s\S]*?)\n\)/,
		)?.[1];
		if (!body) throw new Error("YEN_VENDOR_MANIFEST array not found");
		return [...body.matchAll(/"([^"]*)"/g)]
			.map((m) => (m[1] ?? "").split("|"))
			.map((f) => ({
				key: f[0] ?? "",
				type: f[1] ?? "",
				title: f[2] ?? "",
				subtitle: f[3] ?? "",
				repo: f[4] ?? "",
				binary: f[5] ?? "",
				script: f[6] ?? "",
				companion: f[7] ?? "",
				requireCompanion: f[8] ?? "",
			}));
	}

	test("every manifest record resolves to real files", () => {
		const records = manifest();
		expect(records.length).toBeGreaterThanOrEqual(8);

		for (const r of records) {
			expect(r.key).not.toBe("");
			expect(["source", "binary", "source-built"]).toContain(r.type);
			expect(
				existsSync(join(repoRoot, `yen-terminal/.${r.key}-baseline`)),
			).toBe(true);

			if (r.type === "source") continue;

			// Non-source vendors need an upstream repo, an updater and a binary.
			expect(r.repo).toMatch(/^[^/]+\/[^/]+$/);
			expect(existsSync(join(repoRoot, "scripts", r.script))).toBe(true);
			expect(r.binary).not.toBe("");
			if (r.companion) {
				expect(["true", "false"]).toContain(r.requireCompanion);
			}
		}
	});

	test("baseline files on disk match the manifest exactly", () => {
		const declared = new Set(manifest().map((r) => r.key));
		const onDisk = new Set(
			readdirSync(join(repoRoot, "yen-terminal"))
				.filter((f) => /^\.[a-z0-9-]+-baseline$/.test(f))
				.map((f) => f.replace(/^\./, "").replace(/-baseline$/, "")),
		);
		expect([...onDisk].sort()).toEqual([...declared].sort());
	});

	test("roster consumers derive from the manifest, not their own copies", () => {
		for (const rel of [
			"scripts/14-vendor.sh",
			"scripts/11-sync-vendor-audit.sh",
			"scripts/12-verify-vendor-audit.sh",
		]) {
			const script = readFileSync(join(repoRoot, rel), "utf8");
			expect(script).toContain("scripts/lib/vendor-manifest.sh");
			// No hand-listed baseline block should survive.
			expect(script).not.toMatch(
				/"\$REPO_ROOT\/yen-terminal\/\.ghostty-baseline"\n\s*"\$REPO_ROOT\/yen-terminal\/\.yazi-baseline"/,
			);
		}

		// 14-vendor.sh should invoke process_binary_vendor exactly once, from
		// the loop — twelve hand-written call sites is what this replaced.
		const vendorScript = readFileSync(vendorScriptPath, "utf8");
		expect(
			[...vendorScript.matchAll(/^\s*process_binary_vendor \\$/gm)].length,
		).toBe(1);
	});

	// Headings can repeat in a doc, so anchor on the LAST occurrence and stop at
	// the next `## ` heading. A bare `toContain(key)` passes on any incidental
	// mention, which is how a summary template once fell three vendors behind
	// the manifest; assert placement (a table row), not mere presence.
	function section(body: string, heading: string): string {
		const parts = body.split(`\n${heading}\n`);
		const tail = parts.length > 1 ? (parts[parts.length - 1] ?? "") : "";
		return tail.split(/\n## /)[0] ?? "";
	}

	function expectRowPerVendor(doc: string, heading: string): void {
		const body = section(doc, heading);
		expect(body).not.toBe("");
		for (const row of manifest()) {
			// Table rows are `| <title> | ... |`; match the leading cell.
			const hasRow = new RegExp(`^\\|\\s*${row.title}\\s*\\|`, "im").test(body);
			expect(hasRow, `${heading} lacks a row for ${row.title}`).toBe(true);
		}
	}

	test("a recorded build input matches the inputs its vendor script computes now", () => {
		// zmx compiles the vendored engine. Its tag can stay current while an
		// engine bump makes the bundled binary stale, so 14-vendor.sh compares
		// build_input_id with `<script> --print-input-id`. This fails when a
		// committed baseline names inputs the tree no longer has.
		const withInputs = manifest().filter((r) => {
			const baselinePath = join(repoRoot, `yen-terminal/.${r.key}-baseline`);
			return (
				existsSync(baselinePath) &&
				/^build_input_id=/m.test(readFileSync(baselinePath, "utf8"))
			);
		});
		expect(withInputs.map((r) => r.key)).toContain("zmx");

		const engineConfig = join(
			repoRoot,
			"yen-terminal/ghostty/src/config/Config.zig",
		);
		if (!existsSync(engineConfig)) {
			expect(
				process.env.YEN_ALLOW_MISSING_VENDOR_TREE,
				"vendored engine missing — run scripts/10-update-ghostty.sh, or set YEN_ALLOW_MISSING_VENDOR_TREE=1 to acknowledge this check did not run",
			).toBe("1");
			return;
		}

		for (const record of withInputs) {
			const recorded = readFileSync(
				join(repoRoot, `yen-terminal/.${record.key}-baseline`),
				"utf8",
			).match(/^build_input_id=(.+)$/m)?.[1];
			const result = spawnSync(
				join(repoRoot, "scripts", record.script),
				["--print-input-id"],
				{ encoding: "utf8" },
			);
			expect(result.status, result.stderr).toBe(0);
			expect(result.stdout.trim(), `${record.key} build inputs drifted`).toBe(
				recorded ?? "",
			);
		}

		const vendorScript = readFileSync(vendorScriptPath, "utf8");
		expect(vendorScript).toContain('baseline_value "build_input_id"');
		expect(vendorScript).toContain('"$script_path" --print-input-id');
	});

	test("scripts readme registry has a row for every manifest vendor", () => {
		const readme = readFileSync(scriptsReadmePath, "utf8");
		expectRowPerVendor(readme, "### Vendor Registry");
		for (const row of manifest()) {
			if (row.script) expect(readme).toContain(row.script);
		}
	});

	test("vendor summary template has a row for every manifest vendor", () => {
		const commitRef = readFileSync(vendorCommitRefPath, "utf8");
		expectRowPerVendor(commitRef, "## Vendor Summary");
		// The doc claims a vendor count; keep it honest.
		expect(commitRef).toContain(`${manifest().length} vendors`);
	});
});

// ---------------------------------------------------------------------------
// eval-phase.sh must fail closed.
//
// The summary counts only check IDs matching a per-skill pattern, then reports
// a verdict. Before this gate it printed "Result: PASS" over an EMPTY set, so a
// run whose IDs were all malformed reported zero checks and still read green —
// the natural control flow of an empty loop producing the worst outcome for a
// verification tool. These tests drive the real script in a sandboxed repo root
// so the assertions are behavioral, not textual.
// ---------------------------------------------------------------------------
describe("eval-phase.sh fails closed", () => {
	const evalScriptPath = join(
		repoRoot,
		".agents/skills/update-yen/scripts/eval-phase.sh",
	);

	// eval-phase.sh derives REPO_ROOT four levels up from its own directory and
	// writes under <root>/tmp/skill-telemetry. Reproduce that depth inside a temp
	// dir so a test run never writes into the real telemetry log.
	function sandbox(): { root: string; script: string } {
		const root = mkdtempSync(join(tmpdir(), "yen-evalphase-"));
		const scriptDir = join(root, ".agents/skills/update-yen/scripts");
		mkdirSync(scriptDir, { recursive: true });
		const script = join(scriptDir, "eval-phase.sh");
		writeFileSync(script, readFileSync(evalScriptPath, "utf8"));
		chmodSync(script, 0o755);
		return { root, script };
	}

	function run(script: string, args: string[]) {
		return spawnSync("bash", [script, ...args], {
			encoding: "utf8",
			env: { ...process.env, YEN_SKILL_EVAL_HEARTBEAT_SECONDS: "0" },
		});
	}

	// eval-phase.sh names its file from the SHELL's local date. Bun's test runner
	// evaluates JS in UTC, so a JS-derived tag disagrees with the script whenever
	// UTC and local time fall on different days -- every evening in a negative-UTC
	// zone. That mismatch made these fixtures land in a file the script never reads:
	// the carry-forward tests failed, and the existence assertions passed for the
	// wrong reason. Derive the tag with the same command the script uses.
	function dateTag(offsetDays: number): string {
		const args =
			offsetDays === 0 ? ["+%Y%m%d"] : [`-v${offsetDays}d`, "+%Y%m%d"];
		const r = spawnSync("date", args, { encoding: "utf8" });
		const tag = r.stdout?.trim();
		if (!tag || !/^\d{8}$/.test(tag)) {
			throw new Error(
				`could not derive date tag (offset ${offsetDays}): ${r.stdout}`,
			);
		}
		return tag;
	}

	function evalFileForOffset(
		root: string,
		skill: string,
		offsetDays: number,
	): string {
		return join(
			root,
			`tmp/skill-telemetry/${skill}-eval-${dateTag(offsetDays)}.jsonl`,
		);
	}

	function evalFileFor(root: string, skill: string): string {
		return evalFileForOffset(root, skill, 0);
	}

	test("summary over an empty check set reports FAIL, not PASS", () => {
		const { root, script } = sandbox();
		try {
			// A log whose every ID is non-conforming: the exact shape produced by a
			// run that used IDs like "VC1" instead of "VC-01".
			const file = evalFileFor(root, "yen-vendor");
			mkdirSync(join(root, "tmp/skill-telemetry"), { recursive: true });
			writeFileSync(
				file,
				`${[
					'{"ts":"x","check_id":"VC1","desc":"malformed","pass":true}',
					'{"ts":"x","check_id":"VG1","desc":"malformed","pass":true}',
				].join("\n")}\n`,
			);

			const r = run(script, ["summary", "yen-vendor"]);
			expect(r.stdout).toContain("Result: FAIL");
			expect(r.stdout).not.toContain("Result: PASS");
			expect(r.status).toBe(1);
		} finally {
			rmSync(root, { recursive: true, force: true });
		}
	});

	test("summary with no eval file at all reports FAIL, not PASS", () => {
		const { root, script } = sandbox();
		try {
			const r = run(script, ["summary", "update-yen"]);
			expect(r.stdout).toContain("Result: FAIL");
			expect(r.stdout).not.toContain("Result: PASS");
			expect(r.status).toBe(1);
		} finally {
			rmSync(root, { recursive: true, force: true });
		}
	});

	test("a malformed check ID is rejected at write time", () => {
		const { root, script } = sandbox();
		try {
			const cases: Array<[string, string]> = [
				["yen-vendor", "VG1"],
				["update-yen", "SMOKE-01"],
				["yen-deps", "VC-01"],
				["yen-deps", "DP1"],
			];
			for (const [skill, badId] of cases) {
				const r = run(script, ["check", skill, badId, "desc", "true"]);
				expect(r.status).toBe(2);
				expect(r.stderr).toContain(badId);
				// Nothing may be recorded, or the summary count and the run would
				// disagree about which checks exist.
				expect(existsSync(evalFileFor(root, skill))).toBe(false);
			}
		} finally {
			rmSync(root, { recursive: true, force: true });
		}
	});

	test("conforming check IDs are still accepted and summarized", () => {
		const { root, script } = sandbox();
		try {
			expect(
				run(script, ["check", "yen-vendor", "VC-01", "ok", "true"]).status,
			).toBe(0);
			expect(
				run(script, ["check", "update-yen", "PF-01", "ok", "true"]).status,
			).toBe(0);
			expect(
				run(script, ["check", "yen-deps", "DP-01", "ok", "true"]).status,
			).toBe(0);
			const deps = run(script, ["summary", "yen-deps"]);
			expect(deps.stdout).toContain("Result: PASS");
			expect(deps.status).toBe(0);

			const r = run(script, ["summary", "yen-vendor"]);
			expect(r.stdout).toContain("Result: PASS");
			expect(r.status).toBe(0);
		} finally {
			rmSync(root, { recursive: true, force: true });
		}
	});

	test("a genuine failing check still reports FAIL", () => {
		const { root, script } = sandbox();
		try {
			run(script, ["check", "yen-vendor", "VC-01", "passing", "true"]);
			run(script, ["check", "yen-vendor", "VU-01", "failing", "false"]);

			const r = run(script, ["summary", "yen-vendor"]);
			expect(r.stdout).toContain("Result: FAIL");
			expect(r.stdout).toContain("VU-01");
			expect(r.status).toBe(1);
		} finally {
			rmSync(root, { recursive: true, force: true });
		}
	});

	// The check runs in the background so the script can print heartbeats. Under
	// macOS /bin/bash 3.2 a bare `eval "$cmd" &` lets the `command` builtin exec
	// its external target in place of the subshell, so every step after the first
	// `command <tool>` was skipped and the check took that tool's exit code.
	// Measured on a /yen-vendor run: a `command grep -qx EXIT=0` loop over six gate
	// logs stopped after the first file and recorded PASS over a missing receipt.
	test("steps after `command <external>` still run", () => {
		const { root, script } = sandbox();
		try {
			const r = run(script, [
				"check",
				"yen-vendor",
				"VB-03",
				"later step fails",
				"command env true; exit 7",
			]);
			expect(r.status).toBe(7);
			expect(r.stdout).toContain("[FAIL] VB-03");
		} finally {
			rmSync(root, { recursive: true, force: true });
		}
	});

	// A check whose command argument was simply forgotten used to run `eval ""`,
	// which exits 0 — so the check was written as {"pass":true} having verified
	// nothing. That is the empty-scan-set false green one layer earlier than the
	// summary gate above, and the ID contract does not catch it.
	test("a check with no command is rejected, not recorded as a pass", () => {
		const { root, script } = sandbox();
		try {
			for (const args of [
				["check", "yen-vendor", "VC-01", "no command at all"],
				["check", "yen-vendor", "VC-02", "blank command", "   "],
			]) {
				const r = run(script, args);
				expect(r.status).toBe(2);
				expect(r.stderr).toContain("no command");
			}
			expect(existsSync(evalFileFor(root, "yen-vendor"))).toBe(false);
		} finally {
			rmSync(root, { recursive: true, force: true });
		}
	});

	// The eval file is keyed to the LOCAL date, so a run crossing local midnight
	// splits into two files. `summary` reads today's, so a pre-midnight FAIL
	// would vanish and the post-midnight subset would read green.
	test("summary carries an unresolved failure across local midnight", () => {
		const { root, script } = sandbox();
		try {
			mkdirSync(join(root, "tmp/skill-telemetry"), { recursive: true });
			writeFileSync(
				evalFileForOffset(root, "yen-vendor", -1),
				`${[
					'{"ts":"x","check_id":"VC-01","desc":"pre-midnight ok","pass":true}',
					'{"ts":"x","check_id":"VA-04","desc":"audit layers","pass":false}',
				].join("\n")}\n`,
			);
			writeFileSync(
				evalFileFor(root, "yen-vendor"),
				`${'{"ts":"x","check_id":"VB-01","desc":"post-midnight ok","pass":true}'}\n`,
			);

			const r = run(script, ["summary", "yen-vendor"]);
			expect(r.stdout).toContain("Result: FAIL");
			expect(r.stdout).toContain("VA-04");
			expect(r.status).toBe(1);
		} finally {
			rmSync(root, { recursive: true, force: true });
		}
	});

	test("a failure re-run and passing today is not carried forward", () => {
		const { root, script } = sandbox();
		try {
			mkdirSync(join(root, "tmp/skill-telemetry"), { recursive: true });
			writeFileSync(
				evalFileForOffset(root, "yen-vendor", -1),
				`${'{"ts":"x","check_id":"VA-04","desc":"audit layers","pass":false}'}\n`,
			);
			writeFileSync(
				evalFileFor(root, "yen-vendor"),
				`${'{"ts":"x","check_id":"VA-04","desc":"audit layers","pass":true}'}\n`,
			);

			const r = run(script, ["summary", "yen-vendor"]);
			expect(r.stdout).toContain("Result: PASS");
			expect(r.status).toBe(0);
		} finally {
			rmSync(root, { recursive: true, force: true });
		}
	});

	// Carrying yesterday's PASSes would let a run that verified almost nothing
	// today report a full healthy total — the same false green, one day
	// displaced. Only failures move forward.
	test("yesterday's passes never inflate today's total", () => {
		const { root, script } = sandbox();
		try {
			mkdirSync(join(root, "tmp/skill-telemetry"), { recursive: true });
			writeFileSync(
				evalFileForOffset(root, "yen-vendor", -1),
				`${[
					'{"ts":"x","check_id":"VC-01","desc":"a","pass":true}',
					'{"ts":"x","check_id":"VC-02","desc":"b","pass":true}',
					'{"ts":"x","check_id":"VC-03","desc":"c","pass":true}',
				].join("\n")}\n`,
			);
			writeFileSync(
				evalFileFor(root, "yen-vendor"),
				`${'{"ts":"x","check_id":"VB-01","desc":"only check today","pass":true}'}\n`,
			);

			const r = run(script, ["summary", "yen-vendor"]);
			expect(r.stdout).toContain(
				"Total checks (latest result per check ID): 1",
			);
		} finally {
			rmSync(root, { recursive: true, force: true });
		}
	});

	// A verdict is about ONE RUN, but the eval file is keyed to the DAY. Without a
	// run id the summary reported the latest result per check ID across every run
	// that day, so an earlier run's compile gate counted as this run's evidence.
	test("a later run does not inherit an earlier run's checks", () => {
		const { root, script } = sandbox();
		try {
			run(script, ["begin", "yen-vendor"]);
			expect(
				run(script, ["check", "yen-vendor", "VB-02", "compile gate", "true"])
					.status,
			).toBe(0);

			// A second run that only does a check phase must not borrow VB-02.
			run(script, ["begin", "yen-vendor"]);
			run(script, ["check", "yen-vendor", "VC-01", "upstream check", "true"]);

			const r = run(script, ["summary", "yen-vendor"]);
			expect(r.stdout).toContain(
				"Total checks (latest result per check ID): 1",
			);
			expect(r.stdout).toContain("from earlier runs today excluded");
			expect(r.stdout).not.toContain("VB-02");
			expect(r.status).toBe(0);
		} finally {
			rmSync(root, { recursive: true, force: true });
		}
	});

	test("a failing check in the active run still fails the summary", () => {
		const { root, script } = sandbox();
		try {
			run(script, ["begin", "yen-vendor"]);
			run(script, ["check", "yen-vendor", "VC-01", "passing", "true"]);
			run(script, ["check", "yen-vendor", "VU-01", "failing", "false"]);

			const r = run(script, ["summary", "yen-vendor"]);
			expect(r.stdout).toContain("Result: FAIL");
			expect(r.stdout).toContain("VU-01");
			expect(r.status).toBe(1);
		} finally {
			rmSync(root, { recursive: true, force: true });
		}
	});

	// These files are advertised as machine-evaluable JSONL. The writer escaped
	// `"` but not `\`, so any command carrying a regex escape emitted a record no
	// strict parser could read — and the summary's awk never noticed.
	test("records stay valid JSON when the command contains backslashes", () => {
		const { root, script } = sandbox();
		try {
			const desc = 'regex \\. and \\[deploy\\] with a "quote"';
			expect(
				run(script, ["check", "yen-vendor", "VC-01", desc, "true"]).status,
			).toBe(0);

			const file = evalFileFor(root, "yen-vendor");
			const lines = readFileSync(file, "utf8")
				.split("\n")
				.filter((l) => l.trim().length > 0);
			expect(lines.length).toBeGreaterThan(0);
			for (const line of lines) {
				// Throws on an invalid escape, which is the defect this pins.
				const parsed = JSON.parse(line);
				expect(typeof parsed.check_id).toBe("string");
			}
			const lastLine = lines.at(-1);
			expect(lastLine).toBeDefined();
			expect(JSON.parse(lastLine as string).desc).toBe(desc);
		} finally {
			rmSync(root, { recursive: true, force: true });
		}
	});

	test("the check-ID contract is defined once and shared by check and summary", () => {
		const script = readFileSync(evalScriptPath, "utf8");
		// One definition per skill. Two copies could drift so that `check` accepts
		// an ID the summary then silently drops — the bug this gate exists for.
		expect(
			script.match(/CHECK_ID_PATTERN='\^\(VC\|VU\|VA\|VB\|VK\)/g)?.length,
		).toBe(1);
		expect(
			script.match(/CHECK_ID_PATTERN='\^\(PF\|BD\|VF\|RL\)/g)?.length,
		).toBe(1);
		expect(script.match(/CHECK_ID_PATTERN='\^DP-/g)?.length).toBe(1);
	});
});

// ---------------------------------------------------------------------------
// Skill scripts must resolve REPO_ROOT physically.
//
// The skill directories are symlinked into ~/.claude and ~/.codex, so a LOGICAL
// `cd` applies ".." to the symlink path and lands in the home directory instead
// of the repo. eval-phase.sh then writes to ~/tmp/skill-telemetry and the verifiers
// look for repo files that are not there. Every entry point must resolve its own
// directory with `cd -P` before walking up.
// ---------------------------------------------------------------------------
describe("skill scripts resolve REPO_ROOT physically", () => {
	const skillScripts = [
		".agents/skills/update-yen/scripts/verify-audit-layers.sh",
		".agents/skills/update-yen/scripts/eval-phase.sh",
		".agents/skills/update-yen/scripts/verify-agent-work.sh",
	];

	test("no skill script derives REPO_ROOT with a logical cd", () => {
		for (const rel of skillScripts) {
			const body = readFileSync(join(repoRoot, rel), "utf8");
			// The exact pre-fix idiom. A logical cd here is the bug.
			expect(
				body.includes('REPO_ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"'),
				`${rel} still resolves REPO_ROOT logically`,
			).toBe(false);
			expect(body, `${rel} must resolve its own dir with cd -P`).toContain(
				'SCRIPT_DIR="$(cd -P "$(dirname "$0")" && pwd -P)"',
			);
		}
	});

	test("eval records written through a symlinked skill path land in the repo", () => {
		// A two-hop symlink chain into the repo skill dir, as ~/.codex/skills/update-yen
		// is one hop. Four levels up from the LOGICAL path is the sandbox, so an unfixed script
		// writes its eval records there. A fixed one writes into the repo instead.
		// The probe skill name keeps `begin` from resetting a real run's id.
		const sandbox = mkdtempSync(join(tmpdir(), "yen-skilllink-"));
		try {
			mkdirSync(join(sandbox, "codex/skills"), { recursive: true });
			mkdirSync(join(sandbox, "claude/skills"), { recursive: true });
			symlinkSync(
				join(repoRoot, ".agents/skills/update-yen"),
				join(sandbox, "codex/skills/update-yen"),
			);
			symlinkSync(
				join(sandbox, "codex/skills/update-yen"),
				join(sandbox, "claude/skills/update-yen"),
			);

			const r = spawnSync(
				"bash",
				[
					join(sandbox, "claude/skills/update-yen/scripts/eval-phase.sh"),
					"begin",
					"yen-repo-root-probe",
				],
				{ encoding: "utf8" },
			);
			expect(r.status).toBe(0);

			// The load-bearing assertion: nothing was written beside the symlink.
			expect(
				existsSync(join(sandbox, "tmp")),
				"eval records landed next to the symlink, so REPO_ROOT resolved logically",
			).toBe(false);
			expect(existsSync(join(repoRoot, "tmp/skill-telemetry"))).toBe(true);
		} finally {
			rmSync(sandbox, { recursive: true, force: true });
		}
	});
});

describe("vendor download preflight", () => {
	const vendor = readFileSync(vendorScriptPath, "utf8");
	function extract(name: string): string {
		const body = vendor.match(
			new RegExp(`^${name}\\(\\) \\{\\n[\\s\\S]*?\\n\\}\\n`, "m"),
		)?.[0];
		if (!body) throw new Error(`Missing function ${name}`);
		return body;
	}
	test("incoming Zig pin is checked instead of the installed source pin", () => {
		const root = mkdtempSync(join(tmpdir(), "yen-incoming-zig-"));
		try {
			mkdirSync(join(root, "yen-terminal/ghostty"), { recursive: true });
			writeFileSync(
				join(root, "yen-terminal/ghostty/build.zig.zon"),
				'.minimum_zig_version = "0.16.0",\n',
			);
			const script = [
				'source "$1/scripts/lib/zig-toolchain.sh"',
				extract("preflight_check_zig_version"),
				'REPO_ROOT="$2"',
				'zig() { printf "%s\\n" "$LOCAL_ZIG"; }',
				`upstream_file_content() { printf '%s\\n' '.minimum_zig_version = "0.17.0",'; }`,
				"preflight_check_zig_version aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
			].join("\n");
			for (const [version, status] of [
				["0.16.0", 1],
				["0.17.0", 0],
			] as const) {
				const result = spawnSync(
					"/bin/bash",
					["-c", script, "fixture", repoRoot, root],
					{
						env: { ...process.env, LOCAL_ZIG: version },
						encoding: "utf8",
					},
				);
				expect(result.status, result.stdout + result.stderr).toBe(status);
			}
		} finally {
			rmSync(root, { recursive: true, force: true });
		}
	});
	test("stale binary versions download while matching-version pin mismatches fail closed", () => {
		const root = mkdtempSync(join(tmpdir(), "yen-stale-vendor-"));
		try {
			writeFileSync(
				join(root, "baseline"),
				"upstream_version=v2\nlast_sync=fixture\n",
			);
			writeFileSync(join(root, "binary"), "old bytes");
			const script = [
				extract("process_binary_vendor"),
				'TARGET=""; VENDOR_COUNT=0; ERROR_COUNT=0; UPDATE_COUNT=0; FORCE=true; CHECK_ONLY="$3"',
				"print_vendor_header() { :; }",
				`baseline_value() { command sed -n "s/^$1=//p" "$2"; }`,
				'validate_binary_vendor_provenance_metadata() { printf "PIN_REJECTED\\n"; return 1; }',
				'run_vendor_script() { printf "DOWNLOAD %s\\n" "$2"; }',
				'process_binary_vendor 1 test Test fixture owner/repo "$1/baseline" "$1/version" "$1/binary" updater',
				'printf "errors=%s updates=%s\\n" "$ERROR_COUNT" "$UPDATE_COUNT"',
			].join("\n");
			for (const version of ["v1", "v2"]) {
				writeFileSync(join(root, "version"), `${version}\n`);
				const result = spawnSync(
					"/bin/bash",
					["-c", script, "fixture", root, "unused", "false"],
					{ encoding: "utf8" },
				);
				expect(result.status, result.stderr).toBe(0);
				expect(result.stdout).toContain(
					version === "v1" ? "DOWNLOAD v2" : "PIN_REJECTED",
				);
				expect(result.stdout).toContain(
					version === "v1" ? "errors=0 updates=1" : "errors=1 updates=0",
				);
			}
			writeFileSync(join(root, "version"), "v1\n");
			const check = spawnSync(
				"/bin/bash",
				["-c", script, "fixture", root, "unused", "true"],
				{ encoding: "utf8" },
			);
			expect(check.stdout).toContain("download required");
			expect(check.stdout).toContain("errors=1 updates=0");
			expect(check.stdout).not.toContain("DOWNLOAD");
		} finally {
			rmSync(root, { recursive: true, force: true });
		}
	});
	test("incoming pin fetch failures and empty pins fail closed", () => {
		for (const response of ["return 1", "return 0"]) {
			const script = [
				'source "$1/scripts/lib/zig-toolchain.sh"',
				extract("preflight_check_zig_version"),
				`upstream_file_content() { ${response}; }`,
				"preflight_check_zig_version aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
			].join("\n");
			const result = spawnSync(
				"/bin/bash",
				["-c", script, "fixture", repoRoot],
				{ encoding: "utf8" },
			);
			expect(result.status).toBe(1);
			expect(result.stdout).toMatch(/Cannot read|pin is missing/);
		}
	});
	test("the checked Ghostty commit is the downloaded commit", () => {
		expect(vendor).toContain(
			'preflight_check_zig_version "$GHOSTTY_TARGET_COMMIT"',
		);
		expect(vendor).toContain(
			'"$REPO_ROOT/scripts/10-update-ghostty.sh" "$GHOSTTY_TARGET_COMMIT"',
		);
	});
});
