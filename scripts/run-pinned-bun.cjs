// Vercel's host Bun can differ from packageManager. Bootstrap once, then verify it.
const { spawnSync } = require("node:child_process");
const { mkdtempSync, readFileSync, rmSync, symlinkSync } = require("node:fs");
const { tmpdir } = require("node:os");
const { delimiter, dirname, join, resolve } = require("node:path");

const root = resolve(__dirname, "..");

function run(command, args, env = process.env) {
	const result = spawnSync(command, args, { cwd: root, env, stdio: "inherit" });
	if (result.error)
		console.error(`[bun-runtime] FAIL: ${result.error.message}`);
	return result.status ?? 1;
}

function runVerified(args) {
	// npm's POSIX Bun download is named bun.exe, which a bare `bun` cannot resolve.
	// A temporary command alias keeps every nested call on the verified executable.
	const alias =
		process.platform === "win32"
			? null
			: mkdtempSync(join(tmpdir(), "pinned-bun-"));
	try {
		if (alias) symlinkSync(process.execPath, join(alias, "bun"));
		return run(process.execPath, args, {
			...process.env,
			PATH: `${alias ?? dirname(process.execPath)}${delimiter}${process.env.PATH ?? ""}`,
		});
	} finally {
		if (alias) rmSync(alias, { recursive: true, force: true });
	}
}

function main() {
	const manifest = JSON.parse(
		readFileSync(resolve(root, "package.json"), "utf8"),
	);
	const required = manifest.packageManager;
	if (typeof required !== "string" || !/^bun@\d+\.\d+\.\d+$/.test(required)) {
		throw new Error("packageManager must declare an exact Bun version");
	}
	const [phase, script = "build", ...extra] = process.argv.slice(2);
	if (!["install", "build"].includes(phase) || extra.length > 0) {
		throw new Error("usage: run-pinned-bun.cjs install | build [script]");
	}
	if (phase === "build" && !Object.hasOwn(manifest.scripts ?? {}, script)) {
		throw new Error(`build script is missing: ${script}`);
	}
	if (!process.versions.bun) {
		return run("bunx", [required, __filename, ...process.argv.slice(2)]);
	}
	const expected = required.slice(4);
	if (process.versions.bun !== expected) {
		throw new Error(`running ${process.versions.bun}; required ${expected}`);
	}
	console.info(
		`[bun-runtime] PASS ${phase}: required=${expected} running=${process.versions.bun}`,
	);
	const args =
		phase === "install" ? ["install", "--frozen-lockfile"] : ["run", script];
	return runVerified(args);
}

try {
	process.exit(main());
} catch (error) {
	console.error(`[bun-runtime] FAIL: ${error.message}`);
	process.exit(1);
}
