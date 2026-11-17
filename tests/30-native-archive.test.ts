import { describe, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import {
	mkdirSync,
	mkdtempSync,
	readFileSync,
	rmSync,
	writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

type ProcResult = {
	status: number | null;
	stdout: string;
	stderr: string;
};

function run(cmd: string, args: string[], cwd: string): ProcResult {
	const res = spawnSync(cmd, args, { cwd, encoding: "utf8" });

	return {
		status: res.status,
		stdout: res.stdout ?? "",
		stderr: res.stderr ?? "",
	};
}

const hasBsdtar = run("bsdtar", ["--version"], process.cwd()).status === 0;
const t = hasBsdtar ? test : test.skip;

function resolve7ZipBinary(): string | null {
	const envOverride = process.env.YEN_TEST_7ZIP_BIN;
	if (envOverride && run(envOverride, ["i"], process.cwd()).status === 0) {
		return envOverride;
	}

	const candidates = ["7zz", "7z", "7za"];
	for (const candidate of candidates) {
		if (run(candidate, ["i"], process.cwd()).status === 0) {
			return candidate;
		}
	}

	return null;
}

function mkFixtureRoot(): string {
	const root = mkdtempSync(join(tmpdir(), "yen-archive-native-"));
	const inputDir = join(root, "input");
	mkdirSync(inputDir, { recursive: true });
	writeFileSync(join(inputDir, "a.txt"), "hello archive\n");
	writeFileSync(join(inputDir, "b.json"), '{"ok":true}\n');
	return root;
}

function createArchive(root: string, fileName: string) {
	const out = run("bsdtar", ["-caf", fileName, "input"], root);
	expect(out.status).toBe(0);
}

describe("Native archive backend (bsdtar)", () => {
	t("lists zip/tar/tar.gz/tar.xz/7z fixtures", () => {
		const root = mkFixtureRoot();
		try {
			const archives = [
				"fixture.zip",
				"fixture.tar",
				"fixture.tar.gz",
				"fixture.tar.xz",
				"fixture.7z",
			];

			for (const archive of archives) {
				createArchive(root, archive);
				const listed = run("bsdtar", ["-tf", archive], root);
				expect(listed.status).toBe(0);
				expect(listed.stdout).toContain("input/a.txt");
				expect(listed.stdout).toContain("input/b.json");
			}
		} finally {
			rmSync(root, { recursive: true, force: true });
		}
	});

	t(
		"extracts zip/tar/tar.gz/tar.xz/7z fixtures with non-interactive passphrase arg",
		() => {
			const root = mkFixtureRoot();
			try {
				const archives = [
					"fixture.zip",
					"fixture.tar",
					"fixture.tar.gz",
					"fixture.tar.xz",
					"fixture.7z",
				];

				for (const archive of archives) {
					createArchive(root, archive);
					const outDir = join(root, `out-${archive.replaceAll(".", "-")}`);
					mkdirSync(outDir, { recursive: true });

					const extracted = run(
						"bsdtar",
						[
							"--passphrase",
							"__YEN_NO_PASSWORD__",
							"-xf",
							archive,
							"-C",
							outDir,
						],
						root,
					);
					expect(extracted.status).toBe(0);
					expect(readFileSync(join(outDir, "input", "a.txt"), "utf8")).toBe(
						"hello archive\n",
					);
					expect(readFileSync(join(outDir, "input", "b.json"), "utf8")).toBe(
						'{"ok":true}\n',
					);
				}
			} finally {
				rmSync(root, { recursive: true, force: true });
			}
		},
	);

	t(
		"documents encrypted failure signatures used by native plugin error handling",
		() => {
			const sevenZipBinary = resolve7ZipBinary();
			if (!sevenZipBinary) {
				return;
			}

			const root = mkFixtureRoot();
			try {
				const zipBuilt = run(
					sevenZipBinary,
					["a", "-psecret", "enc.zip", "input/a.txt"],
					root,
				);
				expect(zipBuilt.status).toBe(0);
				const outEncZip = join(root, "out-enc-zip");
				mkdirSync(outEncZip, { recursive: true });

				const zipExtract = run(
					"bsdtar",
					[
						"--passphrase",
						"__YEN_NO_PASSWORD__",
						"-xf",
						"enc.zip",
						"-C",
						outEncZip,
					],
					root,
				);
				expect(zipExtract.status).not.toBe(0);
				expect(zipExtract.stderr.toLowerCase()).toContain("passphrase");

				const sevenBuilt = run(
					sevenZipBinary,
					["a", "-mhe=on", "-psecret", "enc-hdr.7z", "input/a.txt"],
					root,
				);
				expect(sevenBuilt.status).toBe(0);

				const sevenList = run("bsdtar", ["-tf", "enc-hdr.7z"], root);
				expect(sevenList.status).not.toBe(0);
				expect(sevenList.stderr.toLowerCase()).toContain(
					"currently not supported",
				);
			} finally {
				rmSync(root, { recursive: true, force: true });
			}
		},
	);
});
