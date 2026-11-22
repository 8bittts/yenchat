import { describe, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import { chmodSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

// The shipping gate asks a built engine binary what `copy-on-select = true`
// resolves to. These cases drive that check with stand-in binaries, so the
// gate is proven to fail on the upstream mapping and on a probe that never
// reached its temporary config.

const repoRoot = process.cwd();
const checkPath = join(repoRoot, "scripts/lib/copy-on-select-compat.sh");

type Mapping = Record<string, string>;

function withStandInBinary(
	body: string,
	runCheck: (binary: string) => void,
): void {
	const dir = mkdtempSync(join(tmpdir(), "yen-copy-on-select-test-"));
	try {
		const binary = join(dir, "yen");
		writeFileSync(binary, `#!/bin/bash\n${body}\n`, "utf8");
		chmodSync(binary, 0o755);
		runCheck(binary);
	} finally {
		rmSync(dir, { recursive: true, force: true });
	}
}

// A stand-in engine: it reads the one config line from the home the check
// points it at, and prints the resolved value the way `+show-config` does.
function engineBody(mapping: Mapping): string {
	const arms = Object.entries(mapping)
		.map(([value, resolved]) => `  ${value}) resolved=${resolved} ;;`)
		.join("\n");
	return [
		'[ "$YEN_CLI_SUPPORT_ACTIONS" = "1" ] || exit 1',
		'[ "$1" = "+show-config" ] || exit 1',
		'config="$CFFIXED_USER_HOME/Library/Application Support/com.yenchat.yen/config.yen"',
		'value="$(sed -n \'s/^copy-on-select = //p\' "$config")"',
		'case "$value" in',
		arms,
		"  *) resolved=unknown ;;",
		"esac",
		'echo "font-size = 14"',
		'echo "copy-on-select = $resolved"',
	].join("\n");
}

function runCheck(binary: string) {
	const result = spawnSync(
		"bash",
		[
			"-c",
			'source "$1"; copy_on_select_compat_check "$2"',
			"bash",
			checkPath,
			binary,
		],
		{ encoding: "utf8" },
	);
	return { status: result.status, stdout: result.stdout.trim() };
}

describe("copy-on-select compatibility gate", () => {
	test("passes when true resolves to both and false to none", () => {
		withStandInBinary(engineBody({ true: "both", false: "none" }), (binary) => {
			expect(runCheck(binary)).toEqual({ status: 0, stdout: "" });
		});
	});

	test("fails on upstream's mapping of true to the selection pasteboard", () => {
		withStandInBinary(
			engineBody({ true: "primary", false: "none" }),
			(binary) => {
				const result = runCheck(binary);
				expect(result.status).toBe(1);
				expect(result.stdout).toBe(
					"copy-on-select = true resolved to 'primary', expected 'both'",
				);
			},
		);
	});

	test("fails when true resolves to the system clipboard alone", () => {
		withStandInBinary(
			engineBody({ true: "clipboard", false: "none" }),
			(binary) => {
				const result = runCheck(binary);
				expect(result.status).toBe(1);
				expect(result.stdout).toContain("resolved to 'clipboard'");
			},
		);
	});

	test("fails closed when the binary ignores the temporary config", () => {
		// A binary that reads the real user config reports that file's value
		// for every probe, so `true` would look correct by accident.
		withStandInBinary('echo "copy-on-select = both"', (binary) => {
			const result = runCheck(binary);
			expect(result.status).toBe(1);
			expect(result.stdout).toContain("did not read its temporary config");
		});
	});

	test("fails closed when the binary prints no value or is missing", () => {
		withStandInBinary("exit 0", (binary) => {
			const result = runCheck(binary);
			expect(result.status).toBe(1);
			expect(result.stdout).toContain("false resolved to 'nothing'");
		});

		const missing = runCheck(join(tmpdir(), "yen-no-such-binary"));
		expect(missing.status).toBe(1);
		expect(missing.stdout).toContain("has no executable binary");
	});
});
