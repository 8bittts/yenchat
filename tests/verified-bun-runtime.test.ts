import { expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import {
	chmodSync,
	constants,
	copyFileSync,
	mkdirSync,
	mkdtempSync,
	rmSync,
	writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

test("a downloaded runtime named bun.exe owns nested bun calls", () => {
	const root = mkdtempSync(join(tmpdir(), "verified-bun-"));
	try {
		mkdirSync(join(root, "scripts"));
		mkdirSync(join(root, "bin"));
		const executable = join(root, "bun.exe");
		copyFileSync(process.execPath, executable, constants.COPYFILE_FICLONE);
		chmodSync(executable, 0o755);
		copyFileSync(
			new URL("../scripts/run-pinned-bun.cjs", import.meta.url),
			join(root, "scripts/run-pinned-bun.cjs"),
		);
		writeFileSync(
			join(root, "package.json"),
			JSON.stringify({
				packageManager: `bun@${process.versions.bun}`,
				scripts: { build: "bun --version" },
			}),
		);
		writeFileSync(join(root, "bin/bun"), "#!/bin/sh\nexit 97\n");
		chmodSync(join(root, "bin/bun"), 0o755);
		const result = spawnSync(
			executable,
			["scripts/run-pinned-bun.cjs", "build"],
			{
				cwd: root,
				env: {
					...process.env,
					PATH: `${join(root, "bin")}:${process.env.PATH ?? ""}`,
				},
				encoding: "utf8",
			},
		);
		expect(result.status).toBe(0);
		expect(result.stdout).toContain(
			`required=${process.versions.bun} running=${process.versions.bun}`,
		);
		expect(result.stdout.trim().split("\n").at(-1)).toBe(process.versions.bun);
	} finally {
		rmSync(root, { recursive: true, force: true });
	}
});
