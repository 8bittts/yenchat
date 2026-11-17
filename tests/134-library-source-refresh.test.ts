import { describe, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { PUBLIC_LIBRARY_PAGES } from "../lib/library/public-pages";

const repoRoot = process.cwd();
const scriptPath = join(repoRoot, "scripts/43-check-library-sources.ts");

describe("library source refresh command", () => {
	test("lists every registered official source without network fetches", () => {
		const result = spawnSync("bun", [scriptPath, "--list-only", "--json"], {
			cwd: repoRoot,
			encoding: "utf8",
		});
		expect(result.status).toBe(0);

		const payload = JSON.parse(result.stdout) as {
			listOnly: boolean;
			sourceCount: number;
			results: Array<{ url: string; owners: string[] }>;
		};
		const urls = new Set(payload.results.map((source) => source.url));

		expect(payload.listOnly).toBe(true);
		const publicSourceCount = new Set(
			PUBLIC_LIBRARY_PAGES.flatMap((page) =>
				page.officialSources.map((source) => source.url),
			),
		).size;
		expect(payload.sourceCount).toBe(publicSourceCount);
		for (const page of PUBLIC_LIBRARY_PAGES) {
			for (const source of page.officialSources) {
				expect(urls.has(source.url), source.url).toBe(true);
			}
		}
	});

	test("fails closed on invalid numeric options", () => {
		const result = spawnSync(
			"bun",
			[scriptPath, "--list-only", "--max-age-days", "soon"],
			{
				cwd: repoRoot,
				encoding: "utf8",
			},
		);

		expect(result.status).not.toBe(0);
		expect(result.stderr).toContain(
			"--max-age-days must be a non-negative number",
		);
	});

	test("registers the source-refresh command", () => {
		const packageJson = readFileSync(join(repoRoot, "package.json"), "utf8");
		expect(packageJson).toContain('"seo:source-check"');
	});
});
