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
import { dirname, join } from "node:path";

const repoRoot = process.cwd();
test("theme branding gate checks the phase and rejects wrong or missing destinations", () => {
	fixture((root) => {
		const path = "scripts/lib/bundle-resource-phases/01-themes.sh";
		copy(root, path);
		const source = readFileSync(
			join(repoRoot, "scripts/04-verify-branding.sh"),
			"utf8",
		);
		const guard = source.slice(
			source.indexOf("# Check 18:"),
			source.indexOf("# Check 19:"),
		);
		const script = `REPO_ROOT="$PWD"
ISSUES=0
subject_present() { test -f "$2"; }
add_issue() { printf '%s\\n' "$*"; ISSUES=$((ISSUES + 1)); }
${guard}
exit "$ISSUES"`;
		expect(shell(root, script).status).toBe(0);
		write(join(root, path), 'mkdir -p "$APP_PATH/Contents/Resources/themes"\n');
		const wrong = shell(root, script);
		expect(wrong.status).toBe(2);
		expect(wrong.stdout).toContain("still using old Resources/themes/");
		rmSync(join(root, path));
		const missing = shell(root, script);
		expect(missing.status).toBe(1);
		expect(missing.stdout).toContain("Theme bundle phase missing");
	});
});
describe("weather removal gate after bundle decomposition", () => {
	for (const fallback of [false, true]) {
		test(`allows legacy cleanup and rejects restored runtime code (${fallback ? "grep" : "rg"})`, () => {
			fixture((root) => {
				copy(root, "scripts/lib/bundle-resource-phases/03-binaries.sh");
				const source = readFileSync(
					join(repoRoot, "scripts/03-verify-components.sh"),
					"utf8",
				);
				const guard = source.slice(
					source.indexOf('[ ! -e "$REPO_ROOT/yen-cli/commands/core/weather" ]'),
					source.indexOf("# Check 14: Curated Theme Manifest Gate"),
				);
				const script = `REPO_ROOT="$PWD"
fail() { printf '%s\\n' "$*"; exit 1; }
gate_unit_ran() { printf 'RAN|%s\\n' "$1"; }
${fallback ? 'command() { if [ "$1" = -v ] && [ "$2" = rg ]; then return 1; fi; builtin command "$@"; }' : ""}
${guard}`;
				const clean = shell(root, script);
				expect(clean.status).toBe(0);
				expect(clean.stdout).toContain("RAN|weather-removal-guard");
				write(
					join(root, "yen-terminal/overlays/RestoredWeather.swift"),
					'let helper = "yen-weather"\n',
				);
				const restored = shell(root, script);
				expect(restored.status).toBe(1);
				expect(restored.stdout).toContain(
					"Weather removal regression detected",
				);
			});
		});
	}
});
const phases = [
	"01-preflight.sh",
	"02-prepare.sh",
	"03-overlays.sh",
	"04-build.sh",
	"05-verify.sh",
	"06-package.sh",
];
const phaseRoot = join(repoRoot, "scripts/lib/build-release-phases");

function fixture(run: (root: string) => void) {
	const root = mkdtempSync(join(tmpdir(), "yen-release-phases-"));
	try {
		run(root);
	} finally {
		rmSync(root, { recursive: true, force: true });
	}
}
function write(path: string, content: string) {
	mkdirSync(dirname(path), { recursive: true });
	writeFileSync(path, content);
}
function copy(root: string, path: string) {
	write(join(root, path), readFileSync(join(repoRoot, path), "utf8"));
}
function shell(root: string, script: string, args: string[] = []) {
	return spawnSync("bash", ["-c", script, "fixture", ...args], {
		cwd: root,
		encoding: "utf8",
		env: {
			...process.env,
			TMPDIR: `${root}/`,
			ZIG_GLOBAL_CACHE_DIR: join(root, "zig-cache"),
		},
	});
}
function installOrchestrator(root: string) {
	copy(root, "yen-terminal/customizations/build-release.sh");
	for (const name of [
		"version-utils",
		"upstream",
		"zip-notify",
		"zig-sdk-workaround",
	])
		write(join(root, `scripts/lib/${name}.sh`), "# fixture dependency\n");
	write(
		join(root, "scripts/lib/workflow-lock.sh"),
		`
init_shared_workflow_lock() { :; }
acquire_shared_workflow_lock() { echo shared-acquired; }
release_shared_workflow_lock() { echo shared-released; }
acquire_yen_process_lock() { mkdir -p "$1"; printf -v "$2" true; echo process-acquired; }
`,
	);
	for (const [index, name] of phases.entries()) {
		write(
			join(root, "scripts/lib/build-release-phases", name),
			`
test "$BUILD_ONLY" = true
test "$LOCAL_BUILD" = true
test "$(pwd)" = "$REPO_ROOT/yen-terminal"
test "\u0024{sequence:-0}" = ${index}
sequence=${index + 1}
echo "phase=${name}"
`,
		);
	}
}

describe("release build phases", () => {
	test("every declared phase exists and has valid Bash syntax", () => {
		expect(readdirSync(phaseRoot).sort()).toEqual(phases);
		for (const phase of phases) {
			const result = spawnSync("bash", ["-n", join(phaseRoot, phase)], {
				encoding: "utf8",
			});
			expect(result.status, result.stderr).toBe(0);
		}
	});
	test("missing cleanup helper fails before preparation", () =>
		fixture((root) => {
			const result = shell(root, 'REPO_ROOT="$1"; source "$2"', [
				root,
				join(phaseRoot, "02-prepare.sh"),
			]);
			expect(result.status).not.toBe(0);
			expect(result.stderr).toContain("Build cleanup helper missing");
		}));

	test("orchestrator preserves phase order, shell state, and cleanup traps", () =>
		fixture((root) => {
			installOrchestrator(root);
			const result = shell(
				root,
				"bash yen-terminal/customizations/build-release.sh --local",
			);
			expect(result.status, result.stderr).toBe(0);
			expect(
				result.stdout.split("\n").filter((line) => line.startsWith("phase=")),
			).toEqual(phases.map((name) => `phase=${name}`));
			expect(result.stdout).toContain("shared-acquired");
			expect(result.stdout).toContain("process-acquired");
			expect(result.stdout.trim().endsWith("shared-released")).toBe(true);
		}));
	test("missing phase fails and still releases the workflow lock", () =>
		fixture((root) => {
			installOrchestrator(root);
			rmSync(join(root, "scripts/lib/build-release-phases/03-overlays.sh"));
			const result = shell(
				root,
				"bash yen-terminal/customizations/build-release.sh --local",
			);
			expect(result.status, `${result.stdout}\n${result.stderr}`).not.toBe(0);
			expect(result.stderr).toContain("03-overlays.sh");
			expect(result.stdout).toContain("shared-released");
			expect(result.stdout).not.toContain("phase=04-build.sh");
		}));
	test.each([
		["exit 7", 7],
		["kill -TERM $$", 143],
	] as const)(
		"phase termination preserves its failure status: %s",
		(command, status) =>
			fixture((root) => {
				installOrchestrator(root);
				write(
					join(root, "scripts/lib/build-release-phases/02-prepare.sh"),
					`${command}\n`,
				);
				const result = shell(
					root,
					"bash yen-terminal/customizations/build-release.sh --local",
				);
				expect(result.status, result.stderr).toBe(status);
				expect(result.stdout).toContain("shared-released");
				expect(result.stdout).not.toContain("phase=03-overlays.sh");
			}),
	);

	test("cleanup removes only this project's recorded DerivedData", () =>
		fixture((root) => {
			const project = join(root, "current project/YEN.xcodeproj");
			const derived = join(root, "DerivedData");
			mkdirSync(project, { recursive: true });
			mkdirSync(`${project}-other`, { recursive: true });
			for (const [name, recorded] of [
				["YEN-owned", project],
				["YEN-foreign", `${project}-other`],
			] as const) {
				write(
					join(derived, name, "info.plist"),
					`<?xml version="1.0"?><plist version="1.0"><dict><key>WorkspacePath</key><string>${recorded}</string></dict></plist>`,
				);
			}
			write(join(derived, "YEN-unknown/keep"), "unknown ownership");
			write(join(derived, "YEN-malformed/info.plist"), "broken plist");
			const target = join(root, "symlink target");
			write(
				join(target, "info.plist"),
				readFileSync(join(derived, "YEN-owned/info.plist"), "utf8"),
			);
			symlinkSync(target, join(derived, "YEN-link"));
			const result = shell(
				root,
				'set -e; source "$1"; remove_project_derived_data "$2" "$3"; echo CLEANUP_PASSED',
				[join(repoRoot, "scripts/lib/build-cleanup.sh"), project, derived],
			);
			expect(result.status, result.stderr).toBe(0);
			expect(result.stdout).toContain("CLEANUP_PASSED");
			expect(existsSync(join(derived, "YEN-owned"))).toBe(false);
			for (const name of [
				"YEN-foreign",
				"YEN-unknown",
				"YEN-malformed",
				"YEN-link",
			])
				expect(existsSync(join(derived, name))).toBe(true);
			expect(existsSync(join(target, "info.plist"))).toBe(true);
		}));
	test("missing project fails before deleting any DerivedData", () =>
		fixture((root) => {
			write(join(root, "DerivedData/YEN-keep/info.plist"), "keep");
			const result = shell(
				root,
				'source "$1"; remove_project_derived_data "$2" "$3"',
				[
					join(repoRoot, "scripts/lib/build-cleanup.sh"),
					join(root, "missing"),
					join(root, "DerivedData"),
				],
			);
			expect(result.status, `${result.stdout}\n${result.stderr}`).not.toBe(0);
			expect(existsSync(join(root, "DerivedData/YEN-keep/info.plist"))).toBe(
				true,
			);
		}));
	test.each(["true", "false"])(
		"build-only mode never finalizes (local=%s)",
		(local) =>
			fixture((root) => {
				const fakeBin = join(root, "bin");
				write(join(fakeBin, "codesign"), '#!/bin/bash\nprintf "SIGNED\\n"\n');
				chmodSync(join(fakeBin, "codesign"), 0o755);
				write(
					join(root, "customizations/finalize-build.sh"),
					"echo UNEXPECTED_FINALIZE; exit 9\n",
				);
				const result = shell(
					root,
					'PATH="$1:$PATH"; BUILD_ONLY=true; LOCAL_BUILD="$2"; BUILT_APP=fixture.app; source "$3"',
					[fakeBin, local, join(phaseRoot, "06-package.sh")],
				);
				expect(result.status, result.stderr).toBe(0);
				expect(result.stdout).toContain("BUILD COMPLETE");
				expect(result.stdout).not.toContain("UNEXPECTED_FINALIZE");
			}),
	);
	test("shipping mode propagates finalizer failure", () =>
		fixture((root) => {
			write(
				join(root, "customizations/finalize-build.sh"),
				"echo FINALIZER_RAN; exit 9\n",
			);
			const result = shell(
				root,
				'zip_notify() { echo "NOTICE:$1"; }; BUILD_ONLY=false; VERSION=1.260; source "$1"',
				[join(phaseRoot, "06-package.sh")],
			);
			expect(result.status, `${result.stdout}\n${result.stderr}`).not.toBe(0);
			expect(result.stdout).toContain("FINALIZER_RAN");
			expect(result.stdout).toContain("NOTICE:Release FAILED");
		}));
});

const finalizePhases = [
	"01-preflight.sh",
	"02-services.sh",
	"03-sign.sh",
	"04-dmg.sh",
	"05-metadata.sh",
	"06-upload.sh",
	"07-appcast.sh",
];
const finalizeRoot = join(repoRoot, "scripts/lib/finalize-build-phases");

function installFinalizer(root: string) {
	copy(root, "yen-terminal/customizations/finalize-build.sh");
	copy(root, "scripts/lib/finalize-cleanup.sh");
	write(join(root, "package.json"), "{}\n");
	write(
		join(root, "scripts/lib/zip-notify.sh"),
		'zip_notify() { echo "NOTICE:$1"; }\n',
	);
	write(
		join(root, "scripts/lib/workflow-lock.sh"),
		`
init_shared_workflow_lock() { :; }
acquire_shared_workflow_lock() { echo shared-acquired; }
release_shared_workflow_lock() { echo shared-released; }
acquire_yen_process_lock() { mkdir -p "$1"; printf -v "$2" true; echo process-acquired; }
`,
	);
	for (const [index, name] of finalizePhases.entries()) {
		write(
			join(root, "scripts/lib/finalize-build-phases", name),
			`
test "\u0024{sequence:-0}" = ${index}
sequence=${index + 1}
echo "phase=${name}"
VERSION=1.260
DMG_FILENAME=fixture.dmg
DMG_PATH="$REPO_ROOT/release.dmg"
printf fixture > "$DMG_PATH"
`,
		);
	}
	const dmgPhase = join(root, "scripts/lib/finalize-build-phases/04-dmg.sh");
	write(
		dmgPhase,
		readFileSync(dmgPhase, "utf8") +
			`
STAGING_DIR="$REPO_ROOT/staging"
DMG_TEMP="$REPO_ROOT/dmg/temp.dmg"
mkdir -p "$STAGING_DIR" "$(dirname "$DMG_TEMP")"
printf temporary > "$DMG_TEMP"
source "$REPO_ROOT/scripts/lib/finalize-cleanup.sh"
`,
	);
}

describe("release finalization phases", () => {
	test("declared finalization phases exist and parse in Bash", () => {
		expect(readdirSync(finalizeRoot).sort()).toEqual(finalizePhases);
		for (const phase of finalizePhases) {
			const result = spawnSync("bash", ["-n", join(finalizeRoot, phase)], {
				encoding: "utf8",
			});
			expect(result.status, result.stderr).toBe(0);
		}
	});
	test("orchestrator shares state and chains staging cleanup with lock release", () =>
		fixture((root) => {
			installFinalizer(root);
			const result = shell(
				root,
				"bash yen-terminal/customizations/finalize-build.sh",
			);
			expect(result.status, result.stderr).toBe(0);
			expect(
				result.stdout.split("\n").filter((line) => line.startsWith("phase=")),
			).toEqual(finalizePhases.map((name) => `phase=${name}`));
			expect(result.stdout).toContain("Release packaged: v1.260");
			expect(result.stdout.match(/shared-released/g)?.length).toBe(1);
			expect(existsSync(join(root, "staging"))).toBe(false);
			expect(existsSync(join(root, "dmg"))).toBe(false);
			expect(existsSync(join(root, "release.dmg"))).toBe(true);
		}));
	test.each(["03-sign.sh", "05-metadata.sh"])(
		"missing phase fails before or after staging: %s",
		(phase) =>
			fixture((root) => {
				installFinalizer(root);
				rmSync(join(root, "scripts/lib/finalize-build-phases", phase));
				const result = shell(
					root,
					"bash yen-terminal/customizations/finalize-build.sh",
				);
				expect(result.status, result.stdout).not.toBe(0);
				expect(result.stderr).toContain(
					"Finalize source missing or unreadable:",
				);
				expect(result.stderr).toContain(phase);
				expect(result.stdout.match(/shared-released/g)?.length).toBe(1);
				expect(existsSync(join(root, "staging"))).toBe(false);
				expect(existsSync(join(root, "dmg"))).toBe(false);
			}),
	);
	test.each([
		["exit 7", 7],
		["kill -TERM $$", 143],
	] as const)(
		"staging cleanup preserves failure status: %s",
		(command, status) =>
			fixture((root) => {
				installFinalizer(root);
				write(
					join(root, "scripts/lib/finalize-build-phases/05-metadata.sh"),
					`${command}\n`,
				);
				const result = shell(
					root,
					"bash yen-terminal/customizations/finalize-build.sh",
				);
				expect(result.status, result.stderr).toBe(status);
				expect(result.stdout.match(/shared-released/g)?.length).toBe(1);
				expect(existsSync(join(root, "staging"))).toBe(false);
				expect(existsSync(join(root, "dmg"))).toBe(false);
				expect(result.stdout).not.toContain("phase=06-upload.sh");
			}),
	);
	test("signing retries timestamp failures and retains pressure state", () =>
		fixture((root) => {
			write(join(root, "calls"), "0");
			const result = shell(
				root,
				`
source "$1"
CALLS="$2/calls"
codesign() {
 count=$(cat "$CALLS"); count=$((count+1)); printf '%s' "$count" > "$CALLS"
 if [ "$count" = 1 ]; then echo 'timestamp unavailable' >&2; return 1; fi
 return 0
}
# Replace real waiting with a fixture-only trace.
sleep() { printf '%s\\n' "$1" >> "$CALLS.sleep"; }
sign_with_retry fixture.app
echo "PRESSURE=$SIGN_TIMESTAMP_PRESSURE_SEEN"
`,
				[join(finalizeRoot, "02-services.sh"), root],
			);
			expect(result.status, result.stderr).toBe(0);
			expect(readFileSync(join(root, "calls"), "utf8")).toBe("2");
			expect(readFileSync(join(root, "calls.sleep"), "utf8")).toBe("10\n1\n");
			expect(result.stdout).toContain("PRESSURE=1");
		}));
	test("signing fails immediately for non-timestamp errors", () =>
		fixture((root) => {
			const result = shell(
				root,
				`
source "$1"
codesign() { echo 'certificate missing' >&2; return 1; }
sleep() { echo UNEXPECTED_RETRY; }
sign_with_retry fixture.app
`,
				[join(finalizeRoot, "02-services.sh")],
			);
			expect(result.status).not.toBe(0);
			expect(result.stderr).toContain("certificate missing");
			expect(result.stdout).not.toContain("UNEXPECTED_RETRY");
		}));
	test("release asset upload retries a transient network error", () =>
		fixture((root) => {
			write(join(root, "calls"), "0");
			write(join(root, "fixture.delta"), "delta");
			const result = shell(
				root,
				`
source "$1"
CALLS="$2/calls"
GITHUB_RELEASES_REPO=owner/repo
gh() {
 [ "$2" = upload ] || return 0
 count=$(cat "$CALLS"); count=$((count+1)); printf '%s' "$count" > "$CALLS"
 if [ "$count" = 1 ]; then
  echo 'Post "https://uploads.github.com/...": net/http: TLS handshake timeout'
  return 1
 fi
 return 0
}
sleep() { :; }
upload_github_release_asset_retry "delta (fixture)" fixture.delta v1.000
echo "UPLOADED"
`,
				[join(finalizeRoot, "02-services.sh"), root],
			);
			expect(result.status, result.stderr).toBe(0);
			expect(readFileSync(join(root, "calls"), "utf8")).toBe("2");
			expect(result.stdout).toContain("network error (attempt 1/5)");
			expect(result.stdout).toContain("UPLOADED");
		}));
	test("release asset upload fails at once on a non-transient error", () =>
		fixture((root) => {
			write(join(root, "fixture.dmg"), "dmg");
			const result = shell(
				root,
				`
source "$1"
GITHUB_RELEASES_REPO=owner/repo
gh() { [ "$2" = upload ] || return 0; echo 'HTTP 403: Resource not accessible by integration'; return 1; }
sleep() { :; }
upload_github_release_asset_retry "dmg" fixture.dmg v1.000
`,
				[join(finalizeRoot, "02-services.sh")],
			);
			expect(result.status).not.toBe(0);
			expect(result.stdout).toContain("Failed to upload dmg");
			expect(result.stdout).not.toContain("retrying");
		}));
	test("release asset upload fails closed on a missing file", () =>
		fixture((root) => {
			const result = shell(
				root,
				`
source "$1"
gh() { echo UNEXPECTED_UPLOAD; return 0; }
upload_github_release_asset_retry "dmg" missing.dmg v1.000
`,
				[join(finalizeRoot, "02-services.sh")],
			);
			expect(result.status).not.toBe(0);
			expect(result.stdout).toContain("dmg not found");
			expect(result.stdout).not.toContain("UNEXPECTED_UPLOAD");
		}));
	test("release creation reuses an existing release and fails closed on read errors", () =>
		fixture((root) => {
			const existing = shell(
				root,
				`
source "$1"
GITHUB_RELEASES_REPO=owner/repo
gh() { if [ "$2" = view ]; then echo v1.000; return 0; fi; echo UNEXPECTED_CREATE; return 1; }
ensure_github_release v1.000 "YEN 1.000" notes && echo REUSED
`,
				[join(finalizeRoot, "02-services.sh")],
			);
			expect(existing.status, existing.stderr).toBe(0);
			expect(existing.stdout).toContain("REUSED");
			expect(existing.stdout).not.toContain("UNEXPECTED_CREATE");

			const created = shell(
				root,
				`
source "$1"
GITHUB_RELEASES_REPO=owner/repo
gh() { if [ "$2" = view ]; then echo 'release not found' >&2; return 1; fi; [ "$2" = create ] && echo CREATED; }
ensure_github_release v1.000 "YEN 1.000" notes
`,
				[join(finalizeRoot, "02-services.sh")],
			);
			expect(created.status, created.stderr).toBe(0);

			const broken = shell(
				root,
				`
source "$1"
GITHUB_RELEASES_REPO=owner/repo
gh() { if [ "$2" = view ]; then echo 'HTTP 401: Bad credentials' >&2; return 1; fi; echo UNEXPECTED_CREATE; }
ensure_github_release v1.000 "YEN 1.000" notes
`,
				[join(finalizeRoot, "02-services.sh")],
			);
			expect(broken.status).not.toBe(0);
			expect(broken.stdout).toContain("Could not read GitHub Release v1.000");
			expect(broken.stdout).not.toContain("UNEXPECTED_CREATE");
		}));
	test.each([
		["200", 0],
		["503", 1],
		["", 1],
	] as const)("public upload verification fails closed: %s", (http, status) =>
		fixture((root) => {
			const result = shell(
				root,
				`
source "$1"
HTTP_STATUS="$2"
YEN_RELEASE_URL_VERIFY_ATTEMPTS=3
YEN_RELEASE_URL_VERIFY_DELAY_SECONDS=0
curl() { printf '%s' "$HTTP_STATUS"; }
verify_public_url fixture https://example.invalid/fixture HEAD
echo VERIFIED
`,
				[join(finalizeRoot, "02-services.sh"), http],
			);
			expect(result.status, result.stderr).toBe(status);
			if (status === 0) expect(result.stdout).toContain("VERIFIED");
			else expect(result.stdout).toContain("upload verification failed");
		}),
	);
	test("public upload verification waits out a brief 404 after upload", () =>
		fixture((root) => {
			const result = shell(
				root,
				`
source "$1"
YEN_RELEASE_URL_VERIFY_ATTEMPTS=3
YEN_RELEASE_URL_VERIFY_DELAY_SECONDS=0
# curl runs inside $(...), so the call count lives in a file, not a variable.
curl() { echo probe >> "$PWD/probes"; if [ "$(wc -l < "$PWD/probes")" -lt 2 ]; then printf 404; else printf 200; fi; }
verify_public_url fixture https://example.invalid/fixture.sha256
echo "VERIFIED after $(wc -l < "$PWD/probes" | tr -d ' ')"
`,
				[join(finalizeRoot, "02-services.sh")],
			);
			expect(result.status, result.stderr).toBe(0);
			expect(result.stdout).toContain("HTTP 404 on attempt 1/3");
			expect(result.stdout).toContain("VERIFIED after 2");
		}));
	test("public upload verification stops after its last attempt", () =>
		fixture((root) => {
			const result = shell(
				root,
				`
source "$1"
YEN_RELEASE_URL_VERIFY_ATTEMPTS=3
YEN_RELEASE_URL_VERIFY_DELAY_SECONDS=0
curl() { echo probe >> "$PWD/probes"; printf 404; }
verify_public_url fixture https://example.invalid/fixture.sha256
echo UNEXPECTED
`,
				[join(finalizeRoot, "02-services.sh")],
			);
			expect(result.status).not.toBe(0);
			expect(result.stdout).toContain("HTTP 404 after 3 attempts");
			expect(result.stdout).not.toContain("UNEXPECTED");
			expect(
				readFileSync(join(root, "probes"), "utf8").trim().split("\n"),
			).toHaveLength(3);
		}));
	test.each(["0", "x", "-1"])(
		"public upload verification refuses a bad attempt count: %p",
		(attempts) =>
			fixture((root) => {
				const result = shell(
					root,
					`
source "$1"
YEN_RELEASE_URL_VERIFY_ATTEMPTS="$2"
curl() { printf 200; }
verify_public_url fixture https://example.invalid/fixture
echo UNEXPECTED
`,
					[join(finalizeRoot, "02-services.sh"), attempts],
				);
				expect(result.status).not.toBe(0);
				expect(result.stdout).not.toContain("UNEXPECTED");
			}),
	);
});

const bundlePhases = [
	"01-themes.sh",
	"02-cli-resources.sh",
	"03-binaries.sh",
	"04-yazi.sh",
	"05-shell-integration.sh",
	"06-locales.sh",
];
function installBundleOrchestrator(root: string) {
	copy(root, "yen-terminal/customizations/bundle-yen-resources.sh");
	write(
		join(root, "scripts/lib/version-utils.sh"),
		"get_version() { echo 1.260; }; get_version_int() { echo 1260; }; get_git_commit() { echo fixture; }\n",
	);
	write(
		join(root, "scripts/lib/python-utils.sh"),
		"require_python3() { :; }\n",
	);
	write(join(root, "public/stable/version.json"), "{}\n");
	mkdirSync(join(root, "YEN.app"));
	for (const [index, name] of bundlePhases.entries()) {
		write(
			join(root, "scripts/lib/bundle-resource-phases", name),
			`
test "$VERSION" = 1.260
test "$COMMIT" = fixture
test "\u0024{sequence:-0}" = ${index}
sequence=${index + 1}
echo "phase=${name}"
`,
		);
	}
}
function runBundle(root: string) {
	return shell(
		root,
		'bash yen-terminal/customizations/bundle-yen-resources.sh "$1/YEN.app"',
		[root],
	);
}
describe("resource bundling phases", () => {
	test("declared phases exist and parse with Bash", () => {
		const directory = join(repoRoot, "scripts/lib/bundle-resource-phases");
		expect(readdirSync(directory).sort()).toEqual(bundlePhases);
		for (const name of bundlePhases) {
			const result = spawnSync("/bin/bash", ["-n", join(directory, name)], {
				encoding: "utf8",
			});
			expect(result.status, result.stderr).toBe(0);
		}
	});
	test("orchestrator preserves phase order and shared variables", () =>
		fixture((root) => {
			installBundleOrchestrator(root);
			const result = runBundle(root);
			expect(result.status, result.stdout + result.stderr).toBe(0);
			expect(Array.from(result.stdout.match(/phase=.+/g) ?? [])).toEqual(
				bundlePhases.map((name) => `phase=${name}`),
			);
			expect(result.stdout).toContain(
				"Done. YEN resources bundled successfully.",
			);
		}));
	test("missing phase fails even after a cleanup trap is installed", () =>
		fixture((root) => {
			installBundleOrchestrator(root);
			write(
				join(root, "scripts/lib/bundle-resource-phases/01-themes.sh"),
				"trap 'echo cleanup' EXIT\n",
			);
			rmSync(
				join(root, "scripts/lib/bundle-resource-phases/02-cli-resources.sh"),
			);
			const result = runBundle(root);
			expect(result.status).toBe(1);
			expect(result.stderr).toContain("resource bundling source missing:");
			expect(result.stdout).toContain("cleanup");
		}));
	test("phase failure stops before later resources", () =>
		fixture((root) => {
			installBundleOrchestrator(root);
			write(
				join(root, "scripts/lib/bundle-resource-phases/03-binaries.sh"),
				"exit 7\n",
			);
			const result = runBundle(root);
			expect(result.status).toBe(7);
			expect(Array.from(result.stdout.match(/phase=.+/g) ?? [])).toEqual(
				bundlePhases.slice(0, 2).map((name) => `phase=${name}`),
			);
		}));
	test("CLI phase copies resources and updates an actual bundle plist", () =>
		fixture((root) => {
			for (const name of ["commands", "lib", "fixtures"])
				write(join(root, "cli", name, "payload"), name);
			write(join(root, "YEN.app/Contents/Resources/stale"), "stale");
			write(
				join(root, "YEN.app/Contents/Info.plist"),
				'<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleShortVersionString</key><string>old</string><key>CFBundleVersion</key><string>1</string><key>YENBuild</key><string>old</string><key>YENCommit</key><string>old</string></dict></plist>',
			);
			const result = shell(
				root,
				'set -e; APP_PATH="$1/YEN.app"; YEN_CLI_DIR="$1/cli"; VERSION=1.260; VERSION_INT=1260; COMMIT=fixture; source "$2"',
				[
					root,
					join(
						repoRoot,
						"scripts/lib/bundle-resource-phases/02-cli-resources.sh",
					),
				],
			);
			expect(result.status, result.stdout + result.stderr).toBe(0);
			for (const name of ["commands", "lib", "fixtures"])
				expect(
					readFileSync(
						join(root, "YEN.app/Contents/Resources", name, "payload"),
						"utf8",
					),
				).toBe(name);
			const plist = spawnSync(
				"/usr/libexec/PlistBuddy",
				["-c", "Print :YENCommit", join(root, "YEN.app/Contents/Info.plist")],
				{ encoding: "utf8" },
			);
			expect(plist.status).toBe(0);
			expect(plist.stdout.trim()).toBe("fixture");
		}));
});

test("shell resource phase allows absent optional upstream integrations", () =>
	fixture((root) => {
		const custom = "yen-terminal/customizations/";
		for (const file of [
			"lazygit/config.yml",
			"shell-integration/zsh/.zshenv",
			"shell-integration/zsh/yen-integration.zsh",
			"shell-integration/bash/yen-integration.bash",
			"shell-integration/yen-welcome.sh",
		])
			copy(root, custom + file);
		write(join(root, "version.json"), "{}\n");
		write(
			join(
				root,
				"YEN.app/Contents/Resources/yen/shell-integration/bash/bash-preexec.sh",
			),
			"# prerequisite\n",
		);
		const result = shell(
			root,
			'set -e; APP_PATH="$1/YEN.app"; CUSTOMIZATIONS_DIR="$1/yen-terminal/customizations"; VERSION_JSON="$1/version.json"; source "$2"; echo shell-phase-complete',
			[
				root,
				join(
					repoRoot,
					"scripts/lib/bundle-resource-phases/05-shell-integration.sh",
				),
			],
		);
		expect(result.status, result.stdout + result.stderr).toBe(0);
		expect(result.stdout).toContain("shell-phase-complete");
		expect(
			existsSync(
				join(
					root,
					"YEN.app/Contents/Resources/yen/shell-integration/bash/yen.bash",
				),
			),
		).toBe(true);
	}));

test("locale verification rejects an empty catalog set", () =>
	fixture((root) => {
		for (const path of ["locale", "yen/themes", "yen/shell-integration"])
			mkdirSync(join(root, "YEN.app/Contents/Resources", path), {
				recursive: true,
			});
		const result = shell(root, 'set -e; APP_PATH="$1/YEN.app"; source "$2"', [
			root,
			join(repoRoot, "scripts/lib/bundle-resource-phases/06-locales.sh"),
		]);
		expect(result.status).toBe(1);
		expect(result.stdout).toContain(
			"ERROR: no locale catalogs found for resource verification",
		);
	}));

test("locale phase rebrands and verifies a real compiled catalog", () =>
	fixture((root) => {
		for (const name of ["yen-locale-in.XXXXXX.po", "yen-locale-out.XXXXXX.po"])
			write(join(root, name), "other run");
		for (const path of [
			"locale/en/LC_MESSAGES",
			"yen/themes",
			"yen/shell-integration",
		])
			mkdirSync(join(root, "YEN.app/Contents/Resources", path), {
				recursive: true,
			});
		write(
			join(root, "catalog.po"),
			'msgid ""\nmsgstr ""\n"Content-Type: text/plain; charset=UTF-8\\n"\n"Language: en\\n"\n\nmsgid "Ghostty window"\nmsgstr "Ghostty window"\n',
		);
		const catalog = join(
			root,
			"YEN.app/Contents/Resources/locale/en/LC_MESSAGES/com.yenchat.yen.mo",
		);
		const compile = spawnSync(
			"msgfmt",
			["-o", catalog, join(root, "catalog.po")],
			{ encoding: "utf8" },
		);
		expect(compile.status, compile.stderr).toBe(0);
		const result = shell(root, 'set -e; APP_PATH="$1/YEN.app"; source "$2"', [
			root,
			join(repoRoot, "scripts/lib/bundle-resource-phases/06-locales.sh"),
		]);
		expect(result.status, result.stdout + result.stderr).toBe(0);
		expect(result.stdout).toContain("Verified 1 locale catalogs");
		const decoded = spawnSync("msgunfmt", [catalog], { encoding: "utf8" });
		expect(decoded.status).toBe(0);
		expect(decoded.stdout).toContain('msgstr "YEN window"');
		for (const name of ["yen-locale-in.XXXXXX.po", "yen-locale-out.XXXXXX.po"])
			expect(readFileSync(join(root, name), "utf8")).toBe("other run");
	}));
