import { createHash } from "node:crypto";
import { readdirSync, readFileSync } from "node:fs";
import { join, relative, sep } from "node:path";

const INPUT_DIRECTORIES = ["app", "components", "lib"] as const;
const INPUT_FILES = [
	"bun.lock",
	"next.config.ts",
	"package.json",
	"postcss.config.mjs",
	"proxy.ts",
	"public/stable/version.json",
	"tsconfig.json",
] as const;
const GENERATED_MANIFEST_PATH = "lib/csp/generated-inline-script-hashes.ts";

function collectFiles(root: string, directory: string): string[] {
	const absoluteDirectory = join(root, directory);
	const files: string[] = [];

	for (const entry of readdirSync(absoluteDirectory, { withFileTypes: true })) {
		const path = join(absoluteDirectory, entry.name);
		if (entry.isDirectory()) {
			files.push(...collectFiles(root, relative(root, path)));
		} else if (entry.isFile()) {
			files.push(relative(root, path).split(sep).join("/"));
		}
	}

	return files;
}

export function computeWebBuildId(root = process.cwd()): string {
	const files = [
		...INPUT_FILES,
		...INPUT_DIRECTORIES.flatMap((directory) => collectFiles(root, directory)),
	]
		.filter((path) => path !== GENERATED_MANIFEST_PATH)
		.sort();
	const hash = createHash("sha256");

	for (const path of files) {
		const content = readFileSync(join(root, path));
		hash.update(path);
		hash.update("\0");
		hash.update(String(content.byteLength));
		hash.update("\0");
		hash.update(content);
		hash.update("\0");
	}

	return hash.digest("hex").slice(0, 32);
}
