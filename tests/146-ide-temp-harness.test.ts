import { describe, expect, test } from "bun:test";
import { spawn, spawnSync } from "node:child_process";
import {
	chmodSync,
	existsSync,
	readdirSync,
	readFileSync,
	writeFileSync,
} from "node:fs";
import { join } from "node:path";
import { createIdeTemp } from "./fixtures/ide-temp";

const repoRoot = process.cwd();
const testsDir = join(repoRoot, "tests");

describe("ide temp harness", () => {
	test("sweep removes the directory and kills a child whose argv contains it", async () => {
		const { ideTemp, sweep } = createIdeTemp();
		const dir = ideTemp("yen-ide-harness-");
		expect(existsSync(dir)).toBe(true);

		const holder = join(dir, "hold.sh");
		writeFileSync(holder, "#!/bin/bash\nwhile true; do /bin/sleep 1; done\n");
		chmodSync(holder, 0o755);
		const child = spawn(holder, [], { stdio: "ignore" });
		expect(child.pid).toBeGreaterThan(0);

		await new Promise((resolve) => setTimeout(resolve, 100));
		sweep();

		expect(existsSync(dir)).toBe(false);
		const leftover = spawnSync("/bin/ps", ["-axo", "pid=,args="], {
			encoding: "utf8",
		});
		const still = (leftover.stdout ?? "")
			.split("\n")
			.filter((line) => line.includes(dir));
		expect(still).toEqual([]);
	});

	test("ide test files create temps only through createIdeTemp", () => {
		const files = readdirSync(testsDir).filter(
			(name) =>
				name.includes("-ide-") &&
				(name.endsWith(".test.ts") || name.endsWith(".integration.ts")),
		);
		expect(files.length).toBeGreaterThan(30);

		const raw: string[] = [];
		for (const name of files) {
			if (name === "146-ide-temp-harness.test.ts") continue;
			const source = readFileSync(join(testsDir, name), "utf8");
			if (/mkdtempSync\(\s*join\(\s*tmpdir\(\)/s.test(source)) {
				raw.push(name);
			}
			const initHits =
				source.split("const { ideTemp } = createIdeTemp();").length - 1;
			if (initHits !== 1) {
				raw.push(`${name} (createIdeTemp init count ${initHits})`);
			}
		}
		expect(
			raw,
			`Raw mkdtempSync(join(tmpdir(), ...)) left in:\n  ${raw.join("\n  ")}`,
		).toEqual([]);
	});
});
