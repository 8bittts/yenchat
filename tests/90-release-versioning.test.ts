import { describe, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import {
	getVersionFilename,
	getVersionFromFilename,
	isValidReleaseVersion,
} from "../lib/version-format";

const repoRoot = process.cwd();

function runBash(script: string) {
	return spawnSync("bash", ["-lc", script], {
		cwd: repoRoot,
		encoding: "utf8",
	});
}

describe("release version filename encode/decode", () => {
	test("getVersionFromFilename inverts getVersionFilename", () => {
		for (const version of ["0.001", "0.999", "1.000", "1.117", "12.345"]) {
			const encoded = getVersionFilename(version);
			expect(getVersionFromFilename(encoded)).toBe(version);
		}
	});

	test("getVersionFromFilename returns unknown for non-numeric input", () => {
		expect(getVersionFromFilename("abc")).toBe("unknown");
		expect(getVersionFromFilename("")).toBe("unknown");
	});
});

describe("release version helpers", () => {
	test("derive monotonic build numbers, filenames, and semver across 0.999 -> 1.000 -> 1.001", () => {
		const result = runBash(`
			source scripts/lib/version-utils.sh
			printf '%s\n' \
				"$(get_version_int 0.999)" \
				"$(get_version_int 1.000)" \
				"$(get_version_int 1.001)" \
				"$(get_version_filename 0.999)" \
				"$(get_version_filename 1.000)" \
				"$(get_version_filename 1.001)" \
				"$(get_version_semver 0.999)" \
				"$(get_version_semver 1.000)" \
				"$(get_version_semver 1.001)"
		`);

		expect(result.status).toBe(0);
		expect(result.stdout.trim().split("\n")).toEqual([
			"999",
			"1000",
			"1001",
			"0999",
			"1000",
			"1001",
			"0.999.0",
			"1.0.0",
			"1.0.1",
		]);
	});

	test("TypeScript filename helper matches the shell helper across release boundaries", () => {
		const versions = ["0.999", "1.000", "1.001", "1.999", "2.000", "10.001"];
		const result = runBash(`
			source scripts/lib/version-utils.sh
			for version in ${versions.join(" ")}; do
				get_version_filename "$version"
			done
		`);

		expect(result.status).toBe(0);
		expect(result.stdout.trim().split("\n")).toEqual(
			versions.map((version) => getVersionFilename(version)),
		);
	});

	test("shell helper stays valid when grep is aliased elsewhere", () => {
		const result = runBash(`
			shopt -s expand_aliases
			alias grep='rg'
			source scripts/lib/version-utils.sh
			printf '%s\n' \
				"$(get_version_filename 1.001)" \
				"$(get_dmg_filename 1.001)"
		`);

		expect(result.status).toBe(0);
		expect(result.stdout.trim().split("\n")).toEqual(["1001", "yen-1001.dmg"]);
	});

	test("legacy version_to_filename wrapper stays compatible with canonical helper", () => {
		const result = runBash(`
			source scripts/lib/version-utils.sh
			printf '%s\n' \
				"$(version_to_filename 1.001)" \
				"$(get_version_filename 1.001)"
		`);

		expect(result.status).toBe(0);
		expect(result.stdout.trim().split("\n")).toEqual(["1001", "1001"]);
	});

	test("rejects unpadded display versions that would confuse the release workflow", () => {
		const result = runBash(`
			source scripts/lib/version-utils.sh
			is_valid_release_version 1.0
		`);

		expect(result.status).toBe(1);
		expect(isValidReleaseVersion("1.0")).toBeFalse();
		expect(() => getVersionFilename("1.0")).toThrow(
			"Invalid release version: 1.0",
		);
	});
});
