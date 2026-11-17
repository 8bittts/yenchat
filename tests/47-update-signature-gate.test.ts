import { describe, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import { generateKeyPairSync, sign as signData } from "node:crypto";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

type ProcResult = {
	status: number | null;
	signal: NodeJS.Signals | null;
	stdout: string;
	stderr: string;
};

const repoRoot = process.cwd();
const updateScript = join(repoRoot, "yen-cli/commands/core/update");
const yenLib = join(repoRoot, "yen-cli/lib");
const yenCmdDir = join(repoRoot, "yen-cli/commands");

function withTempDir(fn: (dir: string) => void) {
	const dir = mkdtempSync(join(tmpdir(), "yen-update-test-"));
	try {
		fn(dir);
	} finally {
		rmSync(dir, { recursive: true, force: true });
	}
}

function signVersionJson(versionJson: string): {
	publicKeyBase64: string;
	signatureBase64: string;
} {
	const { privateKey, publicKey } = generateKeyPairSync("ed25519");
	const signature = signData(
		null,
		Buffer.from(versionJson, "utf8"),
		privateKey,
	);
	const spkiDer = Buffer.from(
		publicKey.export({ type: "spki", format: "der" }),
	);
	const rawPublicKey = spkiDer.subarray(spkiDer.length - 32);

	return {
		publicKeyBase64: rawPublicKey.toString("base64"),
		signatureBase64: signature.toString("base64"),
	};
}

function writeMetadataFixture(
	rootDir: string,
	versionJson: string,
	versionSig: string,
): { versionJsonUrl: string; versionSigUrl: string } {
	const stableDir = join(rootDir, "stable");
	mkdirSync(stableDir, { recursive: true });

	const versionJsonPath = join(stableDir, "version.json");
	const versionSigPath = join(stableDir, "version.sig");
	writeFileSync(versionJsonPath, versionJson, "utf8");
	writeFileSync(versionSigPath, versionSig, "utf8");

	return {
		versionJsonUrl: pathToFileURL(versionJsonPath).toString(),
		versionSigUrl: pathToFileURL(versionSigPath).toString(),
	};
}

function runUpdateCommand(env: Record<string, string>): ProcResult {
	const proc = spawnSync("bash", [updateScript], {
		cwd: repoRoot,
		encoding: "utf8",
		env: {
			...process.env,
			YEN_LIB: yenLib,
			YEN_CMD_DIR: yenCmdDir,
			...env,
		},
	});

	return {
		status: proc.status,
		signal: proc.signal,
		stdout: proc.stdout ?? "",
		stderr: proc.stderr ?? "",
	};
}

describe("yen update signed metadata gate", () => {
	test("accepts valid signed metadata and reports available updates", () => {
		withTempDir((dir) => {
			const versionJson =
				'{"version":"0.946","url":"https://example.com/yen-0946.dmg","notes":"Signed metadata test","releaseDate":"2026-02-26"}\n';
			const { publicKeyBase64, signatureBase64 } = signVersionJson(versionJson);
			const { versionJsonUrl, versionSigUrl } = writeMetadataFixture(
				dir,
				versionJson,
				`${signatureBase64}\n`,
			);
			const stateFile = join(dir, "state", "seen-version");
			const result = runUpdateCommand({
				YEN_UPDATE_VERSION_URL: versionJsonUrl,
				YEN_UPDATE_SIGNATURE_URL: versionSigUrl,
				YEN_UPDATE_PUBLIC_KEY_BASE64: publicKeyBase64,
				YEN_UPDATE_CURRENT_VERSION: "0.900",
				YEN_UPDATE_STATE_FILE: stateFile,
			});

			const combined = `${result.stdout}\n${result.stderr}`;
			expect(result.status).toBe(0);
			expect(combined).toContain("Signed metadata verified.");
			expect(combined).toContain("Update available!");
		});
	});

	test("reports exact match when current version equals latest metadata", () => {
		withTempDir((dir) => {
			const versionJson =
				'{"version":"0.982","url":"https://example.com/yen-0982.dmg","notes":"Equal version test","releaseDate":"2026-03-01"}\n';
			const { publicKeyBase64, signatureBase64 } = signVersionJson(versionJson);
			const { versionJsonUrl, versionSigUrl } = writeMetadataFixture(
				dir,
				versionJson,
				`${signatureBase64}\n`,
			);
			const stateFile = join(dir, "state", "seen-version");
			const result = runUpdateCommand({
				YEN_UPDATE_VERSION_URL: versionJsonUrl,
				YEN_UPDATE_SIGNATURE_URL: versionSigUrl,
				YEN_UPDATE_PUBLIC_KEY_BASE64: publicKeyBase64,
				YEN_UPDATE_CURRENT_VERSION: "0.982",
				YEN_UPDATE_STATE_FILE: stateFile,
			});

			const combined = `${result.stdout}\n${result.stderr}`;
			expect(result.status).toBe(0);
			expect(combined).toContain("You're up to date!");
			expect(combined).toContain("YEN 0.982 matches the latest version.");
		});
	});

	test("reports local install ahead when current version is newer than metadata", () => {
		withTempDir((dir) => {
			const versionJson =
				'{"version":"0.982","url":"https://example.com/yen-0982.dmg","notes":"Ahead version test","releaseDate":"2026-03-01"}\n';
			const { publicKeyBase64, signatureBase64 } = signVersionJson(versionJson);
			const { versionJsonUrl, versionSigUrl } = writeMetadataFixture(
				dir,
				versionJson,
				`${signatureBase64}\n`,
			);
			const stateFile = join(dir, "state", "seen-version");
			const result = runUpdateCommand({
				YEN_UPDATE_VERSION_URL: versionJsonUrl,
				YEN_UPDATE_SIGNATURE_URL: versionSigUrl,
				YEN_UPDATE_PUBLIC_KEY_BASE64: publicKeyBase64,
				YEN_UPDATE_CURRENT_VERSION: "0.983",
				YEN_UPDATE_STATE_FILE: stateFile,
			});

			const combined = `${result.stdout}\n${result.stderr}`;
			expect(result.status).toBe(0);
			expect(combined).toContain(
				"You're ahead of the latest published release.",
			);
			expect(combined).toContain("Installed version: 0.983");
			expect(combined).toContain("Published latest:");
			expect(combined).not.toContain("is the latest version.");
		});
	});

	test("treats v1.000 as newer than v0.999 across the major-release boundary", () => {
		withTempDir((dir) => {
			const versionJson =
				'{"version":"1.000","url":"https://example.com/yen-1000.dmg","notes":"Major release test","releaseDate":"2026-03-11"}\n';
			const { publicKeyBase64, signatureBase64 } = signVersionJson(versionJson);
			const { versionJsonUrl, versionSigUrl } = writeMetadataFixture(
				dir,
				versionJson,
				`${signatureBase64}\n`,
			);
			const stateFile = join(dir, "state", "seen-version");
			const result = runUpdateCommand({
				YEN_UPDATE_VERSION_URL: versionJsonUrl,
				YEN_UPDATE_SIGNATURE_URL: versionSigUrl,
				YEN_UPDATE_PUBLIC_KEY_BASE64: publicKeyBase64,
				YEN_UPDATE_CURRENT_VERSION: "0.999",
				YEN_UPDATE_STATE_FILE: stateFile,
			});

			const combined = `${result.stdout}\n${result.stderr}`;
			expect(result.status).toBe(0);
			expect(combined).toContain("Signed metadata verified.");
			expect(combined).toContain("Update available!");
			expect(combined).toContain("Current version:");
			expect(combined).toContain("0.999");
			expect(combined).toContain("Latest version:");
			expect(combined).toContain("1.000");
		});
	});

	test("treats v1.001 as newer than v1.000 for the first post-v1 point release", () => {
		withTempDir((dir) => {
			const versionJson =
				'{"version":"1.001","url":"https://example.com/yen-1001.dmg","notes":"Post-v1 release test","releaseDate":"2026-03-12"}\n';
			const { publicKeyBase64, signatureBase64 } = signVersionJson(versionJson);
			const { versionJsonUrl, versionSigUrl } = writeMetadataFixture(
				dir,
				versionJson,
				`${signatureBase64}\n`,
			);
			const stateFile = join(dir, "state", "seen-version");
			const result = runUpdateCommand({
				YEN_UPDATE_VERSION_URL: versionJsonUrl,
				YEN_UPDATE_SIGNATURE_URL: versionSigUrl,
				YEN_UPDATE_PUBLIC_KEY_BASE64: publicKeyBase64,
				YEN_UPDATE_CURRENT_VERSION: "1.000",
				YEN_UPDATE_STATE_FILE: stateFile,
			});

			const combined = `${result.stdout}\n${result.stderr}`;
			expect(result.status).toBe(0);
			expect(combined).toContain("Signed metadata verified.");
			expect(combined).toContain("Update available!");
			expect(combined).toContain("Current version:");
			expect(combined).toContain("1.000");
			expect(combined).toContain("Latest version:");
			expect(combined).toContain("1.001");
		});
	});

	test("rejects tampered version.json when signature does not match", () => {
		withTempDir((dir) => {
			const signedPayload =
				'{"version":"0.946","url":"https://example.com/yen-0946.dmg","notes":"Original payload","releaseDate":"2026-02-26"}\n';
			const tamperedPayload =
				'{"version":"9.999","url":"https://evil.example/yen-9999.dmg","notes":"Tampered payload","releaseDate":"2026-02-26"}\n';
			const { publicKeyBase64, signatureBase64 } =
				signVersionJson(signedPayload);
			const { versionJsonUrl, versionSigUrl } = writeMetadataFixture(
				dir,
				tamperedPayload,
				`${signatureBase64}\n`,
			);
			const stateFile = join(dir, "state", "seen-version");
			const result = runUpdateCommand({
				YEN_UPDATE_VERSION_URL: versionJsonUrl,
				YEN_UPDATE_SIGNATURE_URL: versionSigUrl,
				YEN_UPDATE_PUBLIC_KEY_BASE64: publicKeyBase64,
				YEN_UPDATE_CURRENT_VERSION: "0.900",
				YEN_UPDATE_STATE_FILE: stateFile,
			});

			const combined = `${result.stdout}\n${result.stderr}`;
			expect(result.status).not.toBe(0);
			expect(combined).toContain("Signed update metadata verification failed.");
		});
	});

	test("rejects signed metadata older than last trusted version", () => {
		withTempDir((dir) => {
			const versionJson =
				'{"version":"0.944","url":"https://example.com/yen-0944.dmg","notes":"Replay check","releaseDate":"2026-02-26"}\n';
			const { publicKeyBase64, signatureBase64 } = signVersionJson(versionJson);
			const { versionJsonUrl, versionSigUrl } = writeMetadataFixture(
				dir,
				versionJson,
				`${signatureBase64}\n`,
			);
			const stateDir = join(dir, "state");
			const stateFile = join(stateDir, "seen-version");
			mkdirSync(stateDir, { recursive: true });
			writeFileSync(stateFile, "0.950\n", "utf8");
			const result = runUpdateCommand({
				YEN_UPDATE_VERSION_URL: versionJsonUrl,
				YEN_UPDATE_SIGNATURE_URL: versionSigUrl,
				YEN_UPDATE_PUBLIC_KEY_BASE64: publicKeyBase64,
				YEN_UPDATE_CURRENT_VERSION: "0.900",
				YEN_UPDATE_STATE_FILE: stateFile,
			});

			const combined = `${result.stdout}\n${result.stderr}`;
			expect(result.status).not.toBe(0);
			expect(combined).toContain(
				"Signed metadata is older than last trusted version (0.950).",
			);
		});
	});
});
