import { describe, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { join } from "node:path";

const repoRoot = process.cwd();
const libPath = join(repoRoot, "scripts/lib/upstream.sh");

type ProbeResult = {
	host: string;
	owner: string;
	repo: string;
	web: string;
	git: string;
	tarball: string;
	compare: string;
	commit: string;
	grepPattern: string;
	regexPattern: string;
};

function probe(env: Record<string, string> = {}): ProbeResult {
	const script = `
set -euo pipefail
source "${libPath}"
printf 'host=%s\\n' "$UPSTREAM_HOST"
printf 'owner=%s\\n' "$UPSTREAM_OWNER"
printf 'repo=%s\\n' "$UPSTREAM_REPO"
printf 'web=%s\\n' "$(upstream_web_url)"
printf 'git=%s\\n' "$(upstream_git_url)"
printf 'tarball=%s\\n' "$(upstream_tarball_url DEADBEEF)"
printf 'compare=%s\\n' "$(upstream_compare_url BASE HEAD)"
printf 'commit=%s\\n' "$(upstream_commit_url main)"
printf 'grepPattern=%s\\n' "$(upstream_url_pattern_grep)"
printf 'regexPattern=%s\\n' "$(upstream_url_pattern_regex)"
`;
	const proc = spawnSync("bash", ["-c", script], {
		cwd: repoRoot,
		env: { ...process.env, ...env },
		encoding: "utf8",
	});
	if (proc.status !== 0) {
		throw new Error(
			`probe failed (status=${proc.status}): ${proc.stderr || proc.stdout}`,
		);
	}
	const out: Record<string, string> = {};
	for (const line of proc.stdout.split("\n")) {
		const idx = line.indexOf("=");
		if (idx === -1) continue;
		out[line.slice(0, idx)] = line.slice(idx + 1);
	}
	return out as unknown as ProbeResult;
}

describe("scripts/lib/upstream.sh contract", () => {
	test("default values match the current upstream pin (github.com/ghostty-org/ghostty)", () => {
		const r = probe();
		expect(r.host).toBe("github.com");
		expect(r.owner).toBe("ghostty-org");
		expect(r.repo).toBe("ghostty");
		expect(r.web).toBe("https://github.com/ghostty-org/ghostty");
		expect(r.git).toBe("https://github.com/ghostty-org/ghostty.git");
		expect(r.grepPattern).toBe("github.com/ghostty-org/ghostty");
		expect(r.regexPattern).toBe("github\\.com/ghostty-org/ghostty");
	});

	test("github forge adapter produces the exact URL shapes vendor scripts depend on", () => {
		const r = probe();
		expect(r.tarball).toBe(
			"https://github.com/ghostty-org/ghostty/archive/DEADBEEF.tar.gz",
		);
		expect(r.compare).toBe(
			"https://api.github.com/repos/ghostty-org/ghostty/compare/BASE...HEAD",
		);
		expect(r.commit).toBe(
			"https://api.github.com/repos/ghostty-org/ghostty/commits/main",
		);
	});

	test("YEN_UPSTREAM_* env vars override defaults end-to-end", () => {
		const r = probe({
			YEN_UPSTREAM_HOST: "git.example.com",
			YEN_UPSTREAM_OWNER: "mitchell",
			YEN_UPSTREAM_REPO: "ghostty",
		});
		expect(r.host).toBe("git.example.com");
		expect(r.owner).toBe("mitchell");
		expect(r.web).toBe("https://git.example.com/mitchell/ghostty");
		expect(r.tarball).toBe(
			"https://git.example.com/mitchell/ghostty/archive/DEADBEEF.tar.gz",
		);
		expect(r.compare).toBe(
			"https://api.git.example.com/repos/mitchell/ghostty/compare/BASE...HEAD",
		);
		expect(r.regexPattern).toBe("git\\.example\\.com/mitchell/ghostty");
	});

	test("idempotent: sourcing twice does not re-export or duplicate", () => {
		const proc = spawnSync(
			"bash",
			[
				"-c",
				`set -euo pipefail
source "${libPath}"
source "${libPath}"
echo "$_YEN_UPSTREAM_LOADED"
echo "$(upstream_web_url)"`,
			],
			{ cwd: repoRoot, encoding: "utf8" },
		);
		expect(proc.status).toBe(0);
		expect(proc.stdout.trim()).toBe(
			"1\nhttps://github.com/ghostty-org/ghostty",
		);
	});

	test("forge adapter dispatch is wired to YEN_UPSTREAM_FORGE", () => {
		const lib = readFileSync(libPath, "utf8");
		// Only forge_github is implemented today; Phase 1 will add a sibling.
		expect(lib).toContain('"forge_${UPSTREAM_FORGE}_tarball_url"');
		expect(lib).toContain('"forge_${UPSTREAM_FORGE}_compare_url"');
		expect(lib).toContain('"forge_${UPSTREAM_FORGE}_commit_url"');
		expect(lib).toContain("forge_github_tarball_url()");
		expect(lib).toContain("forge_github_compare_url()");
		expect(lib).toContain("forge_github_commit_url()");
	});
});

test("file reads use the configured forge and require an immutable commit", () => {
	const result = spawnSync(
		"/bin/bash",
		[
			"-c",
			`
source "$1"
forge_github_auth_header() { :; }
curl() { printf '%s\\n' "$@"; }
upstream_file_content aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa build.zig.zon
upstream_file_content main build.zig.zon
`,
			"fixture",
			libPath,
		],
		{
			encoding: "utf8",
			env: {
				...process.env,
				YEN_UPSTREAM_HOST: "git.example.com",
				YEN_UPSTREAM_OWNER: "owner",
				YEN_UPSTREAM_REPO: "engine",
			},
		},
	);
	expect(result.status).toBe(1);
	expect(result.stdout).toContain(
		"https://api.git.example.com/repos/owner/engine/contents/build.zig.zon?ref=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
	);
	expect(result.stdout).toContain("Accept: application/vnd.github.raw+json");
	expect(result.stdout).not.toContain("ref=main");
});
