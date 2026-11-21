import { describe, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import {
	chmodSync,
	existsSync,
	mkdirSync,
	mkdtempSync,
	readdirSync,
	readFileSync,
	realpathSync,
	rmSync,
	symlinkSync,
	utimesSync,
	writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const repoRoot = process.cwd();
const zipSkillPath = join(repoRoot, ".agents/skills/update-yen/SKILL.md");
const zipPreflightRefPath = join(
	repoRoot,
	".agents/skills/update-yen/references/zip-preflight.md",
);
const zipBuildRefPath = join(
	repoRoot,
	".agents/skills/update-yen/references/zip-build.md",
);
const zipVerifyRefPath = join(
	repoRoot,
	".agents/skills/update-yen/references/zip-verify.md",
);
const zipReleaseRefPath = join(
	repoRoot,
	".agents/skills/update-yen/references/zip-release.md",
);
const zipAgentVerifierPath = join(
	repoRoot,
	".agents/skills/update-yen/scripts/verify-agent-work.sh",
);
const nativeSliceDeciderPath = join(
	repoRoot,
	".agents/skills/update-yen/scripts/run-native-slice-if-needed.sh",
);
const vendorRunReaperPath = join(
	repoRoot,
	".agents/skills/update-yen/scripts/reap-vendor-runs.sh",
);
const brandingScriptPath = join(repoRoot, "scripts/04-verify-branding.sh");
const scriptsReadmePath = join(repoRoot, "scripts/00-scripts-readme.md");
const brandingUnitsPath = join(
	repoRoot,
	"scripts/lib/units/04-verify-branding.units",
);
const componentUnitsPath = join(
	repoRoot,
	"scripts/lib/units/03-verify-components.units",
);
const agentsPath = join(repoRoot, "AGENTS.md");
const architectureDocPath = join(repoRoot, "_docs/01-architecture.md");
const desktopBuildDocPath = join(repoRoot, "_docs/05-infrastructure.md");
const stageReleasePath = join(repoRoot, "scripts/07-stage-release.sh");
const componentVerificationPath = join(
	repoRoot,
	"scripts/03-verify-components.sh",
);
const buildPreflightPath = join(
	repoRoot,
	"scripts/lib/build-release-phases/01-preflight.sh",
);
const buildPackagePath = join(
	repoRoot,
	"scripts/lib/build-release-phases/06-package.sh",
);
const finalizePreflightPath = join(
	repoRoot,
	"scripts/lib/finalize-build-phases/01-preflight.sh",
);
const releaseTargetVerifierPath = join(
	repoRoot,
	"scripts/01-verify-release-target.sh",
);

describe("zip process guardrails", () => {
	// Mirror-parity assertions prove the copies match each other, never that they
	// match reality: `tests/53` stayed advertised across all four /update-yen surfaces
	// for months after the file was deleted, and every parity test stayed green.
	test("every tests/ path advertised by the zip surfaces resolves to a real file", () => {
		const surfaces: Array<[string, string]> = [
			[".agents/skills/update-yen/references/zip-build.md", zipBuildRefPath],
			[".agents/skills/update-yen/SKILL.md", zipSkillPath],
		];
		const testFiles = readdirSync(join(repoRoot, "tests"));

		for (const [label, path] of surfaces) {
			// Trailing `.` and `-` are stripped so a sentence-final reference like
			// "pinned by tests/45-overlay-patching.test.ts." does not capture the
			// period and fail with a confusing message.
			const referenced = (
				readFileSync(path, "utf8").match(/(?<![\w/-])tests\/[\w.-]+/g) ?? []
			).map((ref) => ref.replace(/[.-]+$/, ""));

			// Per-surface floor, not a global one: a single counter across all
			// surfaces lets one file lose every reference while the others keep the
			// total above zero -- the exact fail-open class this test exists to close.
			expect(
				referenced.length,
				`${label} advertises no tests/ paths`,
			).toBeGreaterThan(0);

			for (const ref of referenced) {
				const name = ref.slice("tests/".length);
				// Surfaces cite both full filenames and numeric prefixes.
				const resolved = testFiles.some(
					(f) => f === name || f.startsWith(`${name}-`),
				);
				expect(resolved, `${label} references missing ${ref}`).toBe(true);
			}
		}
	});

	test("zip skill documents the current inherited preflight gates", () => {
		const skill = readFileSync(zipSkillPath, "utf8").toLowerCase();

		for (const needle of [
			"toolchain preflight",
			"zig version check",
			"sdk linker probe",
			"rollback-history warning",
			"ghostty rollback history",
			"current...main",
			"baseline revert hint",
			"yen_skip_zig_version_check=1",
			"yen_skip_zig_sdk_workaround=1",
			"stable xcode policy",
			"yen_allow_prerelease_xcode=1",
		]) {
			expect(skill).toContain(needle);
		}
		expect(skill).not.toContain("last 30 commits");
	});

	test("the zip command is global, so the repo carries no pointer or backup copy", () => {
		// /update-yen is the global Claude command ~/.claude/commands/update-yen.md, which runs
		// from any directory. A repo-local pointer would shadow it inside this repo, and
		// the operator's global backups live in 8leeai/_global/, not here.
		for (const rel of [
			".claude/commands/zip.md",
			".claude/commands/update-yen.md",
			"claude-commands",
		]) {
			expect(existsSync(join(repoRoot, rel)), `${rel} must not exist`).toBe(
				false,
			);
		}
	});

	test("release workflow requires weekly narrative copy without build-log concatenation", () => {
		const skill = readFileSync(zipSkillPath, "utf8").toLowerCase();
		const release = readFileSync(zipReleaseRefPath, "utf8").toLowerCase();

		for (const doc of [skill, release]) {
			expect(doc).toContain("release_week_copy");
			expect(doc).toContain("monday-start");
			expect(doc).toContain("do not concatenate every build");
		}
		expect(release).toContain("missing copy in either layer fails generation");
	});

	test("release commit validation survives the required notes follow-up", () => {
		const skill = readFileSync(zipSkillPath, "utf8").toLowerCase();
		const release = readFileSync(zipReleaseRefPath, "utf8").toLowerCase();
		const verifier = readFileSync(zipAgentVerifierPath, "utf8");

		expect(skill).toContain("newest matching versioned release commit");
		expect(skill).toContain("not `head`");
		for (const doc of [release]) {
			expect(doc).toContain("git log --extended-regexp");
			expect(doc).toContain("git push origin head:main");
			expect(doc).toContain("--grep=");
			expect(doc).toContain("-1 --format=%s");
			expect(doc).not.toContain("grep -m1");
			expect(doc).not.toContain("log -1 --pretty=%s");
		}
		expect(verifier).toContain("git log --extended-regexp");
		expect(verifier).toContain('--grep="$RELEASE_COMMIT_REGEX" -1 --format=%s');
		expect(verifier).not.toContain("grep -m1");
		expect(verifier).not.toContain("git log -1 --pretty=%s");
	});

	test("zip skill keeps its mirror and run-anywhere rules", () => {
		const skill = readFileSync(zipSkillPath, "utf8").toLowerCase();

		for (const needle of [
			"name: update-yen",
			"$update-yen",
			"/update-yen local",
			"mirror update rule",
			"runtime sync rule",
			"~/.claude/commands/update-yen.md",
			"~/.codex/skills/update-yen",
			"8leeai/_global/claude-commands/update-yen.md",
			"runs from any directory",
			"cd $home/documents/yenchat",
			".agents/skills/update-yen/skill.md",
			"references",
			"same commit",
			"tests/120-zip-process-guardrails.test.ts",
		]) {
			expect(skill).toContain(needle);
		}
		for (const retired of [
			".claude/commands/zip.md",
			"claude-commands/zip.md",
			"~/.codex/skills/zip",
		]) {
			expect(skill).not.toContain(retired);
		}
	});

	test("zip build-step list has a single source in the skill", () => {
		const buildRef = readFileSync(zipBuildRefPath, "utf8");

		// The global command is a pointer; the 9-step build list lives only in the
		// build reference, so a step-count or skip-behavior edit has one home.
		expect(buildRef).toContain("Build-phase single source");
		expect(buildRef).toContain(
			"The build script prints 9 numbered steps, `[1/9]` to `[9/9]`",
		);
		expect(buildRef).toContain("~/.claude/commands/update-yen.md");
	});

	test("component verification count stays synced across zip docs", () => {
		const script = readFileSync(componentVerificationPath, "utf8");
		const buildRef = readFileSync(zipBuildRefPath, "utf8");
		const scriptsReadme = readFileSync(scriptsReadmePath, "utf8");
		// This used to assert `CHECKS=$((CHECKS + 1))` appeared 16 times AND that
		// the docs said "16 checks" -- pinning a source-code constant to prose.
		// Every increment sat at column 0 outside any guard, so the number was
		// invariant under total non-execution, and this test actively defended the
		// agreement between a false signal and its documentation.
		//
		// The count now comes from the declared unit roster, which the gate must
		// account for at runtime (see tests/145-gate-receipt-contract.test.ts).
		const declaredUnits = readFileSync(componentUnitsPath, "utf8")
			.split("\n")
			.map((l) => l.trim())
			.filter((l) => l.length > 0 && !l.startsWith("#"));

		expect(declaredUnits.length).toBe(17);
		const liveIncrements = script
			.split("\n")
			.filter((l) => !l.trimStart().startsWith("#"))
			.filter((l) => /CHECKS=\$\(\(CHECKS \+ 1\)\)/.test(l));
		expect(liveIncrements).toEqual([]);
		for (const doc of [buildRef, scriptsReadme]) {
			expect(doc).toContain(`${declaredUnits.length} declared units`);
			expect(doc).not.toContain("16 checks");
			expect(doc).toContain("SwiftUI view-modifier hygiene");
			expect(doc).toContain("Overlay recurrence gates");
		}
		const desktopBuildDoc = readFileSync(desktopBuildDocPath, "utf8");
		expect(desktopBuildDoc).toContain(
			`declares ${declaredUnits.length} pre-build units`,
		);
		expect(desktopBuildDoc).not.toContain("16 pre-build checks");
	});

	test("desktop build owner documents release credential preflight", () => {
		const doc = readFileSync(desktopBuildDocPath, "utf8");

		expect(doc).toContain("scripts/01-verify-release-target.sh");
		expect(doc).toContain("non-empty `notarytool history` output");
		expect(doc).toContain(
			"the release repository is unreachable or not public",
		);
		expect(doc).toContain("the session cannot push to it");
	});

	test("branding verification count stays synced across zip docs", () => {
		const brandingScript = readFileSync(brandingScriptPath, "utf8");
		const buildRef = readFileSync(zipBuildRefPath, "utf8");
		const scriptsReadme = readFileSync(scriptsReadmePath, "utf8");
		// The old assertion pinned `^check$` call sites to the literal "53 checks"
		// in four docs. Every one of those call sites sat outside its guard, so
		// the number was invariant under total non-execution -- and this test
		// defended the agreement between a false signal and its documentation.
		// 04 now measures how many of its guarded paths actually RESOLVED.
		const declaredUnits = readFileSync(brandingUnitsPath, "utf8")
			.split("\n")
			.map((l) => l.trim())
			.filter((l) => l.length > 0 && !l.startsWith("#"));

		expect(declaredUnits).toContain("guarded-subjects");
		expect(brandingScript).not.toMatch(/^check$/gm);
		expect(brandingScript).toContain("subject_present");
		expect(brandingScript).toContain("MIN_SUBJECTS_PRESENT");
		for (const doc of [buildRef, scriptsReadme]) {
			expect(doc).not.toContain("53 checks");
			expect(doc).toContain("guarded subjects");
		}
	});

	test("codex zip phase references mirror hard release gates", () => {
		const skill = readFileSync(zipSkillPath, "utf8").toLowerCase();
		const preflight = readFileSync(zipPreflightRefPath, "utf8").toLowerCase();
		const build = readFileSync(zipBuildRefPath, "utf8").toLowerCase();
		const verify = readFileSync(zipVerifyRefPath, "utf8").toLowerCase();

		expect(skill).toContain("pinned-by-rollback exception");
		expect(preflight).toContain("pinned-by-rollback exception");
		// The bypass this line used to pin was never implemented in any script.
		// Pin the correction instead, so the doc cannot drift back to advertising
		// an env override that silently does nothing.
		expect(preflight).toContain(
			"no `yen_zip_allow_stale_vendors` bypass exists",
		);
		expect(preflight).not.toContain("set `yen_zip_allow_stale_vendors=1`");
		expect(build).toContain("prepared but never shipped");
		expect(build).toContain("yen_skip_zig_version_check=1");
		expect(build).toContain("yen_skip_zig_sdk_workaround=1");
		expect(verify).toContain("version.sig");
		expect(verify).not.toContain("sound-pack delta gate");
		expect(verify).toContain("vf-03");
	});

	test("artifact fingerprint docs include bundled shell CLI coverage", () => {
		const skill = readFileSync(zipSkillPath, "utf8").toLowerCase();
		const verify = readFileSync(zipVerifyRefPath, "utf8").toLowerCase();
		const scriptsReadme = readFileSync(scriptsReadmePath, "utf8").toLowerCase();
		const agents = readFileSync(agentsPath, "utf8").toLowerCase();
		const architectureDoc = readFileSync(
			architectureDocPath,
			"utf8",
		).toLowerCase();

		for (const doc of [skill, verify, scriptsReadme, agents, architectureDoc]) {
			expect(doc).toContain("bundled shell cli");
			expect(doc).toContain("contents/resources/bin/yen");
		}
	});

	test("component xcode regression gate is explicit and auto-scoped", () => {
		const script = readFileSync(componentVerificationPath, "utf8");
		const buildRef = readFileSync(zipBuildRefPath, "utf8").toLowerCase();
		const scriptsReadme = readFileSync(scriptsReadmePath, "utf8").toLowerCase();

		expect(script).toContain("YEN_COMPONENT_XCODE_REGRESSION_MODE");
		expect(script).toContain("latest [deploy] release");
		// The auto-mode window anchors on the last RELEASE commit. A bare
		// [deploy] anchor also matched the release-notes commit that every /update-yen
		// pushes right after shipping, plus "chore: update packages [deploy]",
		// which moved the window past native work and reported no native changes.
		expect(script).toContain("--grep='^v[0-9]+\\.[0-9]+: '");
		// tests/123 exercises the shared path predicate with real changed paths.
		expect(script).toContain(
			'source "$REPO_ROOT/scripts/lib/native-component-paths.sh"',
		);

		for (const doc of [buildRef, scriptsReadme]) {
			expect(doc).toContain("yen_component_xcode_regression_mode=auto");
			expect(doc).toContain("set `always` to force");
			expect(doc).toContain("latest `[deploy]` release");
		}
	});

	test("a vendor-bump release still runs the native slice after the build", () => {
		// A Ghostty vendor bump cleans YENKit.xcframework, so Step 4 physically
		// cannot run the native xcodebuild slice and mode=always hard-fails there.
		// Step 5 rebuilds the xcframework, so Step 6 is the ONLY point in a
		// vendor-bump release where the command-palette / browser / keyboard /
		// utility-window suites can run at all. Without this instruction the
		// release ships with those suites never executed.
		const doc = readFileSync(zipVerifyRefPath, "utf8");
		expect(doc).toContain(
			"YEN_COMPONENT_XCODE_REGRESSION_MODE=always bash $HOME/Documents/yenchat/scripts/03-verify-components.sh",
		);
		expect(doc).toContain(
			"SKIP|xcode-regression|xcframework missing/incomplete",
		);
		expect(doc.toLowerCase()).toContain("required");
		// The receipt is read, never inferred from an absent SKIPPED string.
		expect(doc).toContain("Confirm, do not infer");
		expect(doc).toContain("RECEIPT gate=03-verify-components");
	});

	test("Step 6a forces the native slice only when Step 4 did not run it", () => {
		// eval-phase.sh deletes a passing check's log, so Step 4's RAN receipt
		// used to vanish and 6a re-ran all 17 component units on every release
		// whose Step 4 had already run the slice. BD-02 now tees the receipt to a
		// file and VF-04 decides from it; no surface may call 6a unconditional.
		const skill = readFileSync(zipSkillPath, "utf8");
		const buildRef = readFileSync(zipBuildRefPath, "utf8");
		const verifyRef = readFileSync(zipVerifyRefPath, "utf8");
		const savedReceipt =
			"tee $HOME/Documents/yenchat/tmp/skill-telemetry/update-yen-components.out";
		const decider =
			"bash $HOME/Documents/yenchat/.agents/skills/update-yen/scripts/run-native-slice-if-needed.sh";

		expect(buildRef).toContain(
			`set -o pipefail; bash $HOME/Documents/yenchat/scripts/03-verify-components.sh 2>&1 | ${savedReceipt}`,
		);
		expect(buildRef).toContain(`2>&1 \\| ${savedReceipt}`);
		expect(verifyRef).toContain(`| VF-04 |`);
		expect(verifyRef).toContain(decider);
		expect(verifyRef).toContain(
			"Never type the forced invocation by hand after Step 4 recorded `RAN|xcode-regression`",
		);
		expect(skill).toContain("`run-native-slice-if-needed.sh`");
		for (const doc of [skill, buildRef, verifyRef]) {
			expect(doc).not.toContain("keep Step 6a mandatory");
			expect(doc).not.toContain("forced run is the backstop");
		}
	});

	test("VF-01 saves the AppleScript receipt it tells the agent to read", () => {
		// Same eval-phase.sh log deletion as Step 4: without the tee there is no
		// RAN|verifier| or SKIP|verifier| line left to judge after a pass.
		const verifyRef = readFileSync(zipVerifyRefPath, "utf8");
		expect(verifyRef).toContain(
			"16-verify-applescript-if-needed.sh 2>&1 \\| tee $HOME/Documents/yenchat/tmp/skill-telemetry/update-yen-applescript.out",
		);
		expect(verifyRef).toContain("in the saved `update-yen-applescript.out`");
	});

	test("build-release vendor-gate guidance uses absolute script paths", () => {
		const script = readFileSync(buildPreflightPath, "utf8");

		expect(script).toContain('bash "$REPO_ROOT/scripts/14-vendor.sh" --check');
		expect(script).toContain("Run: bash $REPO_ROOT/scripts/14-vendor.sh");
		expect(script).not.toContain("Run: ./scripts/14-vendor.sh");
	});

	test("build-only refreshes ad-hoc signature before advertising local test path", () => {
		const script = readFileSync(buildPackagePath, "utf8");
		const buildOnlyStart = script.indexOf('if [ "$BUILD_ONLY" = true ]; then');
		const releaseStart = script.indexOf(
			"bash customizations/finalize-build.sh",
		);
		const buildOnlyBranch = script.slice(buildOnlyStart, releaseStart);

		expect(buildOnlyStart).toBeGreaterThan(-1);
		expect(releaseStart).toBeGreaterThan(buildOnlyStart);
		expect(buildOnlyBranch).toContain(
			"Refreshing build-only ad-hoc signature metadata",
		);
		expect(buildOnlyBranch).toContain(
			'codesign --force --deep --sign - "$BUILT_APP"',
		);
		expect(buildOnlyBranch).toContain(
			"Build-only mode — skipping release packaging/Developer ID signing/notarization/upload",
		);
		expect(
			buildOnlyBranch.indexOf('codesign --force --deep --sign - "$BUILT_APP"'),
		).toBeLessThan(
			buildOnlyBranch.indexOf(
				'echo "Test locally: open ghostty/zig-out/YEN.app"',
			),
		);
	});

	test("shipping preflight proves notarization credentials with positive output", () => {
		const build = readFileSync(buildPreflightPath, "utf8");
		const finalize = readFileSync(finalizePreflightPath, "utf8");

		for (const script of [build, finalize]) {
			expect(script).toContain("notarytool history");
			expect(script).toContain('if [ -z "$NOTARY_HISTORY" ]');
			expect(script).not.toContain(
				'notarytool history --keychain-profile "$NOTARIZATION_PROFILE" --keychain "$NOTARIZATION_KEYCHAIN" 2>/dev/null | head',
			);
		}
		expect(build.indexOf("notarytool history")).toBeLessThan(
			build.indexOf("[2/9]"),
		);
	});

	test("stage-release commit hint preserves deploy-gated release push", () => {
		const script = readFileSync(stageReleasePath, "utf8");

		expect(script).toContain(
			'git -C \\"$REPO_ROOT\\" commit -m \\"v${VERSION}: Brief description [deploy]\\"',
		);
		expect(script).toContain('git -C \\"$REPO_ROOT\\" push origin main');
		expect(script).not.toContain(
			'git commit -m \\"v${VERSION}: Brief description\\"',
		);
	});
});

describe("GitHub release-target preflight", () => {
	function sandbox(apiOutput: string, apiExit = 0) {
		const root = mkdtempSync(join(tmpdir(), "yen-release-target-"));
		mkdirSync(join(root, "scripts/lib"), { recursive: true });
		mkdirSync(join(root, "fake-bin"), { recursive: true });
		writeFileSync(
			join(root, "scripts/01-verify-release-target.sh"),
			readFileSync(releaseTargetVerifierPath, "utf8"),
		);
		writeFileSync(
			join(root, "scripts/lib/release-constants.sh"),
			'GITHUB_RELEASES_REPO="owner/expected"\n',
		);
		const fakeGh = join(root, "fake-bin/gh");
		writeFileSync(
			fakeGh,
			`#!/bin/bash\nprintf '%b' '${apiOutput}'\nexit ${apiExit}\n`,
		);
		chmodSync(fakeGh, 0o755);
		return root;
	}

	function run(root: string) {
		return spawnSync(
			"bash",
			[join(root, "scripts/01-verify-release-target.sh")],
			{
				cwd: root,
				encoding: "utf8",
				env: {
					...process.env,
					PATH: `${join(root, "fake-bin")}:${process.env.PATH}`,
				},
			},
		);
	}

	test("fails closed when the repository is unreachable", () => {
		const root = sandbox("", 1);
		try {
			const result = run(root);
			expect(result.status).toBe(1);
			expect(result.stderr).toContain("not reachable");
		} finally {
			rmSync(root, { recursive: true, force: true });
		}
	});

	test("fails closed for a private repository or a session without push", () => {
		for (const [output, message] of [
			["private\\ttrue\\n", "not public"],
			["public\\tfalse\\n", "cannot push"],
			["", "not public"],
		] as const) {
			const root = sandbox(output);
			try {
				const result = run(root);
				expect(result.status).toBe(1);
				expect(result.stderr).toContain(message);
			} finally {
				rmSync(root, { recursive: true, force: true });
			}
		}
	});

	test("prints a positive receipt only after visibility and push verification", () => {
		const root = sandbox("public\\ttrue\\n");
		try {
			const result = run(root);
			expect(result.status).toBe(0);
			expect(result.stdout).toContain(
				"RAN|github-release-target|repo=owner/expected visibility=public push=verified",
			);
		} finally {
			rmSync(root, { recursive: true, force: true });
		}
	});
});

// The gate-mode envs are only safe to document if the downgrade guard is
// documented with them: 05-detect-failures.sh refuses to run in any
// non-enforce mode unless YEN_ALLOW_GATE_DOWNGRADE=1, so "report" reads as a
// quiet warning setting when it is actually a hard failure.
describe("gate-mode documentation matches the script", () => {
	test("every documented gate mode names the downgrade acknowledgement", () => {
		const detector = readFileSync(
			join(repoRoot, "scripts/05-detect-failures.sh"),
			"utf8",
		);
		const gateEnvs = [
			"YEN_ARTIFACT_URL_SCAN_GATE_MODE",
			"YEN_FINGERPRINT_GATE_MODE",
			"YEN_DMG_LAYOUT_GATE_MODE",
		];
		for (const env of gateEnvs) {
			expect(detector).toContain(env);
		}
		expect(detector).toContain("YEN_ALLOW_GATE_DOWNGRADE");

		for (const rel of [".agents/skills/update-yen/references/zip-verify.md"]) {
			const doc = readFileSync(join(repoRoot, rel), "utf8");
			expect(doc).toContain("YEN_ALLOW_GATE_DOWNGRADE");
		}
	});

	test("zip version guidance is not pinned to a past milestone", () => {
		for (const rel of [".agents/skills/update-yen/references/zip-build.md"]) {
			const doc = readFileSync(join(repoRoot, rel), "utf8");
			// 1.000 shipped long ago; guidance framed as "the next bump" is stale.
			expect(doc).not.toContain("next bump from `0.999`");
			expect(doc).not.toContain("next bump from the current `0.999`");
		}
	});
});

// Both of these were hit on the v1.160 release. They are silent failures — the
// push succeeds, the commit carries [deploy], and only the live page or the
// untracked baseline reveals the problem — so they have to be written down.
describe("release-process gotchas stay documented", () => {
	test("the push-HEAD ignoreCommand trap is documented in every zip surface", () => {
		for (const rel of [".agents/skills/update-yen/references/zip-release.md"]) {
			const doc = readFileSync(join(repoRoot, rel), "utf8");
			expect(doc).toContain("Push the release-notes commit ALONE");
			// The mechanism, not just the instruction — an instruction without a
			// reason gets optimized away by the next person in a hurry.
			expect(doc).toMatch(/HEAD commit of a push/);
			expect(doc).toContain("empty `[deploy]` commit");
		}
	});

	test("the vendor-artifacts-not-staged trap is documented", () => {
		for (const rel of [".agents/skills/update-yen/references/zip-verify.md"]) {
			const doc = readFileSync(join(repoRoot, rel), "utf8");
			expect(doc).toContain("Commit any vendor bump BEFORE");
			expect(doc).toContain("VENDOR_INFO.txt");
		}
	});

	test("07-stage-release really does omit the vendor tracking files", () => {
		// The warning above is only true while this stays true.
		const script = readFileSync(
			join(repoRoot, "scripts/07-stage-release.sh"),
			"utf8",
		);
		expect(script).not.toContain("VENDOR_INFO.txt");
		expect(script).not.toContain("-baseline");
		expect(script).toContain("public/stable");
	});
});

// ---------------------------------------------------------------------------
// The verify-phase agent check must be able to fail.
//
// check_verify used to call note_pass on BOTH branches: "version.json staged"
// and "staging deferred (OK during verify)". A gate with no failing path is a
// placebo — it cannot fail for the reason it claims to exist, which is exactly
// the defect verify-audit-layers.sh's own header documents. The verify phase
// ends with 07-stage-release.sh, so by the time this runs the staged set is
// either present or the staging step did not happen.
// ---------------------------------------------------------------------------
describe("zip verify-phase agent check is falsifiable", () => {
	const STAGED = [
		"public/stable/version.json",
		"public/stable/version.sig",
		"public/stable/appcast.xml",
		"public/stable/YEN-1.160.dmg.sha256",
		"package.json",
	];

	function sandbox(stage: string[]): { root: string; script: string } {
		const root = mkdtempSync(join(tmpdir(), "update-yenverify-"));
		const scriptDir = join(root, ".agents/skills/update-yen/scripts");
		mkdirSync(scriptDir, { recursive: true });
		mkdirSync(join(root, "public/stable"), { recursive: true });
		const script = join(scriptDir, "verify-agent-work.sh");
		writeFileSync(script, readFileSync(zipAgentVerifierPath, "utf8"));
		chmodSync(script, 0o755);
		for (const f of STAGED) {
			writeFileSync(join(root, f), '{"version":"1.160"}');
		}
		const git = (args: string[]) =>
			spawnSync("git", args, { cwd: root, encoding: "utf8" });
		git(["init", "-q", "."]);
		git(["config", "user.email", "t@t"]);
		git(["config", "user.name", "t"]);
		if (stage.length > 0) git(["add", ...stage]);
		return { root, script };
	}

	function runVerify(root: string, script: string) {
		return spawnSync("bash", [script, "verify"], {
			cwd: root,
			encoding: "utf8",
		});
	}

	test("the full staged release set passes", () => {
		const { root, script } = sandbox(STAGED);
		try {
			const r = runVerify(root, script);
			expect(r.stdout).toContain("all checks passed");
			expect(r.status).toBe(0);
		} finally {
			rmSync(root, { recursive: true, force: true });
		}
	});

	test("nothing staged fails instead of excusing itself", () => {
		const { root, script } = sandbox([]);
		try {
			const r = runVerify(root, script);
			expect(r.stdout).toContain("[FAIL]");
			expect(r.stdout).not.toContain("deferred");
			expect(r.status).toBe(1);
		} finally {
			rmSync(root, { recursive: true, force: true });
		}
	});

	test("each required artifact missing from the staged set fails", () => {
		for (const omitted of STAGED) {
			const { root, script } = sandbox(STAGED.filter((f) => f !== omitted));
			try {
				const r = runVerify(root, script);
				expect(r.status).toBe(1);
				expect(r.stdout).toContain("[FAIL]");
			} finally {
				rmSync(root, { recursive: true, force: true });
			}
		}
	});
});

describe("zip release agent check supports isolated worktrees", () => {
	function sandbox() {
		const root = mkdtempSync(join(tmpdir(), "update-yenrelease-"));
		const remote = mkdtempSync(join(tmpdir(), "update-yenrelease-remote-"));
		const scriptDir = join(root, ".agents/skills/update-yen/scripts");
		mkdirSync(scriptDir, { recursive: true });
		const script = join(scriptDir, "verify-agent-work.sh");
		writeFileSync(script, readFileSync(zipAgentVerifierPath, "utf8"));
		chmodSync(script, 0o755);
		const git = (args: string[], cwd = root) =>
			spawnSync("git", args, { cwd, encoding: "utf8" });
		git(["init", "--bare", "-q", remote], tmpdir());
		git(["init", "-q", "."]);
		git(["config", "user.email", "t@t"]);
		git(["config", "user.name", "t"]);
		mkdirSync(join(root, "public/stable"), { recursive: true });
		writeFileSync(
			join(root, "public/stable/version.json"),
			'{\n  "version": "1.201",\n  "url": "x"\n}\n',
		);
		writeFileSync(join(root, "release.txt"), "release\n");
		git(["add", "release.txt", "public/stable/version.json"]);
		git(["commit", "-qm", "v1.201: Release [deploy]"]);
		git(["branch", "-M", "codex/release-worktree"]);
		git(["remote", "add", "origin", remote]);
		git(["push", "-q", "origin", "HEAD:main"]);
		return { root, remote, script, git };
	}

	test("passes when isolated-branch HEAD is published to remote main", () => {
		const { root, remote, script } = sandbox();
		try {
			const result = spawnSync("bash", [script, "release"], {
				cwd: root,
				encoding: "utf8",
			});
			expect(result.status).toBe(0);
			expect(result.stdout).toContain("Remote main matches HEAD");
		} finally {
			rmSync(root, { recursive: true, force: true });
			rmSync(remote, { recursive: true, force: true });
		}
	});

	test("fails when local HEAD was not published", () => {
		const { root, remote, script, git } = sandbox();
		try {
			writeFileSync(join(root, "later.txt"), "later\n");
			git(["add", "later.txt"]);
			git(["commit", "-qm", "docs: later"]);
			const result = spawnSync("bash", [script, "release"], {
				cwd: root,
				encoding: "utf8",
			});
			expect(result.status).toBe(1);
			expect(result.stdout).toContain("Remote main does not match HEAD");
		} finally {
			rmSync(root, { recursive: true, force: true });
			rmSync(remote, { recursive: true, force: true });
		}
	});

	test("fails when the newest release commit is for an older version than version.json", () => {
		// `git log --grep` finds the newest release commit in ALL of history, so
		// a repo that ever shipped always has one. Without the version binding
		// this check could not fail for a release whose commit was never made.
		const { root, remote, script, git } = sandbox();
		try {
			writeFileSync(
				join(root, "public/stable/version.json"),
				'{\n  "version": "1.202",\n  "url": "x"\n}\n',
			);
			git(["add", "public/stable/version.json"]);
			git(["commit", "-qm", "chore: bump without a release commit"]);
			git(["push", "-q", "origin", "HEAD:main"]);
			const result = spawnSync("bash", [script, "release"], {
				cwd: root,
				encoding: "utf8",
			});
			expect(result.status).toBe(1);
			expect(result.stdout).toContain("Remote main matches HEAD");
			expect(result.stdout).toContain(
				"Newest release commit is v1.201 but version.json says 1.202",
			);
		} finally {
			rmSync(root, { recursive: true, force: true });
			rmSync(remote, { recursive: true, force: true });
		}
	});
});

describe("release vendor window is falsifiable", () => {
	const libPath = join(repoRoot, "scripts/lib/release-vendor-window.sh");

	// A sandbox repo with a bare origin: the baseline commit is a `vendor:`
	// commit pushed to main, so the default case is accepted and each test
	// breaks exactly one of the four conditions.
	function sandbox() {
		const root = mkdtempSync(join(tmpdir(), "yen-relwin-"));
		const remote = mkdtempSync(join(tmpdir(), "yen-relwin-remote-"));
		const git = (args: string[], env: Record<string, string> = {}) =>
			spawnSync("git", args, {
				cwd: root,
				encoding: "utf8",
				env: { ...process.env, ...env },
			});
		spawnSync("git", ["init", "--bare", "-q", remote], { encoding: "utf8" });
		git(["init", "-q", "."]);
		git(["config", "user.email", "t@t"]);
		git(["config", "user.name", "t"]);
		mkdirSync(join(root, "yen-terminal/overlays"), { recursive: true });
		mkdirSync(join(root, "_docs"), { recursive: true });
		writeFileSync(
			join(root, "yen-terminal/.ghostty-baseline"),
			"upstream_commit=abc\n",
		);
		writeFileSync(join(root, "yen-terminal/VENDOR_INFO.txt"), "ghostty abc\n");
		writeFileSync(
			join(root, "yen-terminal/.overlay-upstream-pairs.txt"),
			"# pairs\n",
		);
		writeFileSync(join(root, "yen-terminal/overlays/keep"), "x\n");
		writeFileSync(join(root, "_docs/04-security.md"), "# audit\n");
		git(["add", "-A"]);
		git(["commit", "-qm", "vendor: update ghostty to abc"]);
		git(["branch", "-M", "main"]);
		git(["remote", "add", "origin", remote]);
		git(["push", "-q", "origin", "main"]);
		return { root, remote, git };
	}

	function evaluate(root: string) {
		const r = spawnSync(
			"bash",
			[
				"-c",
				`source "${libPath}"; if release_vendor_window_accepts_ghostty "${root}"; then echo "ACCEPT $RELEASE_VENDOR_WINDOW_EVIDENCE"; else echo "REFUSE $RELEASE_VENDOR_WINDOW_REASON"; exit 1; fi`,
			],
			{ encoding: "utf8" },
		);
		return r;
	}

	test("accepts a clean, recent, published vendor: baseline", () => {
		const { root, remote } = sandbox();
		try {
			const r = evaluate(root);
			expect(r.status).toBe(0);
			expect(r.stdout).toMatch(
				/^ACCEPT baseline_commit=[0-9a-f]{12} age_hours=0 window_hours=24/,
			);
		} finally {
			rmSync(root, { recursive: true, force: true });
			rmSync(remote, { recursive: true, force: true });
		}
	});

	test("refuses a vendor file modified in the working tree", () => {
		const { root, remote } = sandbox();
		try {
			writeFileSync(
				join(root, "yen-terminal/VENDOR_INFO.txt"),
				"ghostty def\n",
			);
			const r = evaluate(root);
			expect(r.status).toBe(1);
			expect(r.stdout).toContain(
				"REFUSE vendor files are modified in the working tree",
			);
		} finally {
			rmSync(root, { recursive: true, force: true });
			rmSync(remote, { recursive: true, force: true });
		}
	});

	test("refuses a baseline whose newest commit is not a vendor: commit", () => {
		const { root, remote, git } = sandbox();
		try {
			writeFileSync(
				join(root, "yen-terminal/.ghostty-baseline"),
				"upstream_commit=def\n",
			);
			git(["add", "yen-terminal/.ghostty-baseline"]);
			git(["commit", "-qm", "wip: hand-edited baseline"]);
			git(["push", "-q", "origin", "main"]);
			const r = evaluate(root);
			expect(r.status).toBe(1);
			expect(r.stdout).toContain(
				"is not a vendor: commit (wip: hand-edited baseline)",
			);
		} finally {
			rmSync(root, { recursive: true, force: true });
			rmSync(remote, { recursive: true, force: true });
		}
	});

	test("refuses a vendor: baseline older than the window", () => {
		const { root, remote, git } = sandbox();
		try {
			const old = new Date(Date.now() - 30 * 3600 * 1000).toISOString();
			writeFileSync(
				join(root, "yen-terminal/.ghostty-baseline"),
				"upstream_commit=def\n",
			);
			git(["add", "yen-terminal/.ghostty-baseline"]);
			git(["commit", "-qm", "vendor: update ghostty to def"], {
				GIT_COMMITTER_DATE: old,
				GIT_AUTHOR_DATE: old,
			});
			git(["push", "-q", "origin", "main"]);
			const r = evaluate(root);
			expect(r.status).toBe(1);
			expect(r.stdout).toMatch(
				/REFUSE baseline commit [0-9a-f]{12} is 30h old, outside the 24h release window/,
			);
		} finally {
			rmSync(root, { recursive: true, force: true });
			rmSync(remote, { recursive: true, force: true });
		}
	});

	test("refuses a vendor: baseline that was never pushed", () => {
		const { root, remote, git } = sandbox();
		try {
			writeFileSync(
				join(root, "yen-terminal/.ghostty-baseline"),
				"upstream_commit=def\n",
			);
			git(["add", "yen-terminal/.ghostty-baseline"]);
			git(["commit", "-qm", "vendor: update ghostty to def"]);
			const r = evaluate(root);
			expect(r.status).toBe(1);
			expect(r.stdout).toContain(
				"is not on origin/main; push the vendor run first",
			);
		} finally {
			rmSync(root, { recursive: true, force: true });
			rmSync(remote, { recursive: true, force: true });
		}
	});

	test("the zip preflight asks for the release reading and the gate declares the unit", () => {
		const preflight = readFileSync(zipPreflightRefPath, "utf8");
		const units = readFileSync(
			join(repoRoot, "scripts/lib/units/14-vendor.units"),
			"utf8",
		);
		const vendorScript = readFileSync(
			join(repoRoot, "scripts/14-vendor.sh"),
			"utf8",
		);
		expect(preflight).toContain("| PF-04 |");
		expect(preflight).toContain(
			"bash $HOME/Documents/yenchat/scripts/14-vendor.sh --check --release",
		);
		expect(units.split("\n").map((l) => l.trim())).toContain("release-window");
		expect(vendorScript).toContain(
			'source "$REPO_ROOT/scripts/lib/release-vendor-window.sh"',
		);
		expect(vendorScript).toContain("--release requires --check");
		// The window is a constant in the lib, never read from the environment.
		const lib = readFileSync(libPath, "utf8");
		expect(lib).toMatch(/^RELEASE_VENDOR_WINDOW_HOURS=24$/m);
		expect(lib).not.toMatch(/RELEASE_VENDOR_WINDOW_HOURS="?\$\{/);
	});
});

describe("Step 6a native-slice decision is falsifiable", () => {
	const RAN = "RAN|xcode-regression|suites=15 executed=273";
	const PASS =
		"RECEIPT gate=03-verify-components ran=17 skipped=0 declared=17 result=PASS";

	// A stub component gate records whether it was invoked and in which mode, so
	// each case proves both directions: skipped when covered, forced otherwise.
	function sandbox(
		step4: string | null,
		opts: { stale?: boolean; gateExit?: number; skill?: string } = {},
	) {
		const skill = opts.skill ?? "update-yen";
		const root = mkdtempSync(join(tmpdir(), "update-yen6a-"));
		const scriptDir = join(root, ".agents/skills/update-yen/scripts");
		const telemetry = join(root, "tmp/skill-telemetry");
		mkdirSync(scriptDir, { recursive: true });
		mkdirSync(join(root, "scripts"), { recursive: true });
		mkdirSync(telemetry, { recursive: true });
		const script = join(scriptDir, "run-native-slice-if-needed.sh");
		writeFileSync(script, readFileSync(nativeSliceDeciderPath, "utf8"));
		chmodSync(script, 0o755);
		const marker = join(root, "gate-invoked");
		writeFileSync(
			join(root, "scripts/03-verify-components.sh"),
			`#!/bin/bash\necho "mode=\${YEN_COMPONENT_XCODE_REGRESSION_MODE:-unset}" > "${marker}"\nexit ${opts.gateExit ?? 0}\n`,
		);
		const runId = join(telemetry, `${skill}-eval-run.id`);
		writeFileSync(runId, "run");
		const now = Date.now() / 1000;
		utimesSync(runId, now - 60, now - 60);
		if (step4 !== null) {
			const out = join(telemetry, `${skill}-components.out`);
			writeFileSync(out, step4);
			const t = opts.stale ? now - 120 : now;
			utimesSync(out, t, t);
		}
		return { root, script, marker };
	}

	function run(s: ReturnType<typeof sandbox>, args: string[] = []) {
		const r = spawnSync("bash", [s.script, ...args], { encoding: "utf8" });
		const invoked = existsSync(s.marker)
			? readFileSync(s.marker, "utf8").trim()
			: null;
		rmSync(s.root, { recursive: true, force: true });
		return { ...r, invoked };
	}

	test("a fresh passing Step 4 receipt that ran the slice skips the forced gate", () => {
		const r = run(sandbox(`${RAN}\n${PASS}\n`));
		expect(r.status).toBe(0);
		expect(r.stdout).toContain(
			`SKIP|native-slice-6a|Step 4 already ran it: ${RAN}`,
		);
		expect(r.invoked).toBeNull();
	});

	const forcedCases: Array<[string, string | null, { stale?: boolean }]> = [
		[
			"Step 4 skipped for a missing xcframework",
			`SKIP|xcode-regression|xcframework missing/incomplete\n${PASS}\n`,
			{},
		],
		[
			"the slice executed zero tests",
			`RAN|xcode-regression|suites=15 executed=0\n${PASS}\n`,
			{},
		],
		[
			"Step 4 has no passing receipt",
			`${RAN}\nRECEIPT gate=03-verify-components ran=16 skipped=1 declared=17 result=FAIL\n`,
			{},
		],
		["Step 4 output is missing", null, {}],
		["Step 4 output predates this run", `${RAN}\n${PASS}\n`, { stale: true }],
	];
	for (const [label, step4, opts] of forcedCases) {
		test(`forces the slice in always mode when ${label}`, () => {
			const r = run(sandbox(step4, opts));
			expect(r.status).toBe(0);
			expect(r.stdout).toContain("RAN|native-slice-6a|forcing the slice:");
			expect(r.invoked).toBe("mode=always");
		});
	}

	test("a failing forced gate fails the decision", () => {
		const r = run(
			sandbox(
				`SKIP|xcode-regression|xcframework missing/incomplete\n${PASS}\n`,
				{ gateExit: 1 },
			),
		);
		expect(r.status).toBe(1);
		expect(r.invoked).toBe("mode=always");
	});

	test("/yen-vendor VB-05 reads its own receipt and run id through the skill argument", () => {
		// A Ghostty bump removes the xcframework, so /yen-vendor's pre-build gate
		// skips the slice too; the same decider serves it from yen-vendor-*.out so
		// the vendor run does not re-run all 17 units by hand after the build.
		const skipped = run(sandbox(`${RAN}\n${PASS}\n`, { skill: "yen-vendor" }), [
			"yen-vendor",
		]);
		expect(skipped.status).toBe(0);
		expect(skipped.stdout).toContain(
			`SKIP|native-slice-vb05|Step 4 already ran it: ${RAN}`,
		);
		expect(skipped.invoked).toBeNull();

		// The zip receipt must not satisfy a vendor decision, or one skill's run
		// would borrow the other's evidence.
		const crossed = run(sandbox(`${RAN}\n${PASS}\n`), ["yen-vendor"]);
		expect(crossed.status).toBe(0);
		expect(crossed.stdout).toContain(
			"RAN|native-slice-vb05|forcing the slice:",
		);
		expect(crossed.invoked).toBe("mode=always");

		const unknown = run(sandbox(null), ["yen-ship"]);
		expect(unknown.status).toBe(2);
	});
});

describe("Step 0f vendor-run reaper is falsifiable", () => {
	const DAY_AGO = Date.now() / 1000 - 2 * 24 * 60 * 60;

	// The script resolves the repo root from its own path, so each sandbox carries a
	// copy at the real skill path, a git repo that ignores tmp/, and a private
	// TMPDIR, so no live lock on this machine can change the outcome.
	function sandbox(opts: { ignored?: boolean } = {}) {
		const root = realpathSync(mkdtempSync(join(tmpdir(), "update-yenreap-")));
		const locks = mkdtempSync(join(tmpdir(), "update-yenreap-locks-"));
		const scriptDir = join(root, ".agents/skills/update-yen/scripts");
		mkdirSync(scriptDir, { recursive: true });
		const script = join(scriptDir, "reap-vendor-runs.sh");
		writeFileSync(script, readFileSync(vendorRunReaperPath, "utf8"));
		chmodSync(script, 0o755);
		spawnSync("git", ["init", "-q", "."], { cwd: root });
		if (opts.ignored !== false)
			writeFileSync(join(root, ".gitignore"), "tmp/\n");
		const runs = join(root, "tmp/vendor-runs");
		mkdirSync(runs, { recursive: true });
		return { root, locks, runs, script };
	}

	// A run directory whose every entry, itself included, carries `mtime`.
	function makeRun(runs: string, name: string, mtime: number): string {
		const dir = join(runs, name);
		const nested = join(dir, "ghostty/src");
		mkdirSync(nested, { recursive: true });
		writeFileSync(join(nested, "Config.zig"), "// mirror\n");
		for (const path of [
			join(nested, "Config.zig"),
			nested,
			join(dir, "ghostty"),
			dir,
		]) {
			utimesSync(path, mtime, mtime);
		}
		return dir;
	}

	function lockKey(root: string): string {
		const r = spawnSync(
			"sh",
			["-c", 'printf "%s\\n" "$1" | cksum', "sh", root],
			{
				encoding: "utf8",
			},
		);
		return r.stdout.trim().split(/\s+/)[0] ?? "";
	}

	function reap(box: { locks: string; script: string; root: string }) {
		return spawnSync("bash", [box.script], {
			cwd: box.root,
			encoding: "utf8",
			env: { ...process.env, TMPDIR: box.locks },
		});
	}

	function cleanup(box: { root: string; locks: string }) {
		spawnSync("chmod", ["-R", "u+w", box.root]);
		rmSync(box.root, { recursive: true, force: true });
		rmSync(box.locks, { recursive: true, force: true });
	}

	test("reaps an old run and holds one changed today", () => {
		const box = sandbox();
		try {
			const old = makeRun(box.runs, "20261005-old", DAY_AGO);
			const fresh = makeRun(box.runs, "20261021-fresh", Date.now() / 1000);
			const r = reap(box);
			expect(r.status).toBe(0);
			expect(existsSync(old)).toBe(false);
			expect(existsSync(fresh)).toBe(true);
			expect(r.stdout).toContain("[reaped] 20261005-old");
			expect(r.stdout).toContain("[held] 20261021-fresh");
			expect(r.stdout).toContain("RECEIPT reaper=vendor-runs reaped=1 held=1");
		} finally {
			cleanup(box);
		}
	});

	test("reaps a run whose Zig cache directories are read-only", () => {
		const box = sandbox();
		try {
			const old = makeRun(box.runs, "20261006-readonly", DAY_AGO);
			chmodSync(join(old, "ghostty/src"), 0o555);
			utimesSync(join(old, "ghostty/src"), DAY_AGO, DAY_AGO);
			const r = reap(box);
			expect(r.status).toBe(0);
			expect(existsSync(old)).toBe(false);
		} finally {
			cleanup(box);
		}
	});

	test("a live vendor lock holds every run and a dead one does not", () => {
		const box = sandbox();
		try {
			const old = makeRun(box.runs, "20261005-old", DAY_AGO);
			const lock = join(box.locks, `yen-vendor-${lockKey(box.root)}.lock`);
			mkdirSync(lock);
			writeFileSync(join(lock, "pid"), `${process.pid}\n`);
			const held = reap(box);
			expect(held.status).toBe(0);
			expect(held.stdout).toContain(
				"[held] every vendor run: the yen-vendor lock is live",
			);
			expect(existsSync(old)).toBe(true);

			const exited = spawnSync("true").pid;
			writeFileSync(join(lock, "pid"), `${exited}\n`);
			const stale = reap(box);
			expect(stale.status).toBe(0);
			expect(existsSync(old)).toBe(false);
		} finally {
			cleanup(box);
		}
	});

	test("refuses a folder git does not ignore", () => {
		const box = sandbox({ ignored: false });
		try {
			const old = makeRun(box.runs, "20261005-old", DAY_AGO);
			const r = reap(box);
			expect(r.status).toBe(1);
			expect(r.stdout).toContain("[FAIL] tmp/vendor-runs is not gitignored");
			expect(existsSync(old)).toBe(true);
		} finally {
			cleanup(box);
		}
	});

	test("refuses a symlinked folder and leaves its target alone", () => {
		const box = sandbox();
		const target = mkdtempSync(join(tmpdir(), "update-yenreap-target-"));
		try {
			rmSync(box.runs, { recursive: true, force: true });
			const kept = makeRun(target, "20261005-old", DAY_AGO);
			symlinkSync(target, box.runs);
			const r = reap(box);
			expect(r.status).toBe(1);
			expect(r.stdout).toContain("not a plain directory");
			expect(existsSync(kept)).toBe(true);
		} finally {
			cleanup(box);
			rmSync(target, { recursive: true, force: true });
		}
	});

	test("a missing folder is a pass with a zero receipt", () => {
		const box = sandbox();
		try {
			rmSync(box.runs, { recursive: true, force: true });
			const r = reap(box);
			expect(r.status).toBe(0);
			expect(r.stdout).toContain(
				"RECEIPT reaper=vendor-runs reaped=0 held=0 freed_kb=0 result=PASS",
			);
		} finally {
			cleanup(box);
		}
	});
});

test("release metadata allows the release notes host and rejects other subdomains", () => {
	const patterns = readFileSync(
		join(repoRoot, "scripts/lib/artifact-url-domain-allowlist.txt"),
		"utf8",
	)
		.split("\n")
		.filter((line) => line && !line.startsWith("#"));
	const isAllowed = (host: string) =>
		spawnSync("grep", ["-Eq", patterns.join("\n")], { input: host }).status ===
		0;

	expect(isAllowed("unlisted.yen.chat")).toBe(false);
	expect(isAllowed("blog.yen.chat.example.org")).toBe(false);
	expect(isAllowed("blog.yen.chat")).toBe(true);
});
