/**
 * Reads yen-terminal/customizations/third-party-components.json and the engine's Zig
 * manifests. scripts/gen-third-party-notices.ts writes the notice from it, and
 * tests/171-third-party-notices.test.ts checks that the notice still matches the pins.
 */
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";

export interface ComponentSource {
	zon?: string;
	local?: string;
	spm?: string;
	licenseUrl?: string;
}

export interface BundledComponent {
	key: string;
	name: string;
	license: string;
	home: string;
	note?: string;
	source: ComponentSource;
	files: string[];
}

export interface ComponentManifest {
	bundled: BundledComponent[];
	coveredBy: Record<string, string>;
	excluded: Record<string, string>;
}

export const MANIFEST_PATH =
	"yen-terminal/customizations/third-party-components.json";
export const NOTICE_PATH =
	"yen-terminal/customizations/notices/ThirdPartyComponents.txt";
export const ENGINE_DIR = "yen-terminal/ghostty";

export function readManifest(repoRoot: string): ComponentManifest {
	return JSON.parse(
		readFileSync(join(repoRoot, MANIFEST_PATH), "utf8"),
	) as ComponentManifest;
}

/** The top-level entries of a build.zig.zon `.dependencies` block, as key to body text. */
export function zonDependencies(text: string): Map<string, string> {
	const deps = new Map<string, string>();
	const start = text.search(/\.dependencies\s*=\s*\.\{/);
	if (start < 0) return deps;
	const lines = text.slice(start).split("\n").slice(1);
	let key: string | null = null;
	let body: string[] = [];
	for (const line of lines) {
		if (/^ {4}\},?\s*$/.test(line)) break;
		const open = /^ {8}\.(@"[^"]+"|\w+)\s*=\s*\.\{(.*)$/.exec(line);
		if (open) {
			if (key) deps.set(key, body.join("\n"));
			key = open[1] ?? null;
			body = [open[2] ?? ""];
		} else if (key) {
			body.push(line);
		}
	}
	if (key) deps.set(key, body.join("\n"));
	return deps;
}

/** Every dependency key in the engine's root manifest and its pkg/ manifests. */
export function engineDependencyKeys(repoRoot: string): Set<string> {
	const engine = join(repoRoot, ENGINE_DIR);
	const files = ["build.zig.zon"];
	for (const name of readdirSync(join(engine, "pkg"))) {
		files.push(`pkg/${name}/build.zig.zon`);
	}
	const keys = new Set<string>();
	for (const file of files) {
		let text: string;
		try {
			text = readFileSync(join(engine, file), "utf8");
		} catch {
			continue;
		}
		for (const key of zonDependencies(text).keys()) keys.add(key);
	}
	return keys;
}

/** The pinned archive URL of a dependency, read from the manifest that fetches it. */
export function zonArchiveUrl(
	repoRoot: string,
	zon: string,
	key: string,
): string {
	const text = readFileSync(join(repoRoot, ENGINE_DIR, zon), "utf8");
	const body = zonDependencies(text).get(key);
	const url = body ? /\.url\s*=\s*"([^"]+)"/.exec(body)?.[1] : undefined;
	if (!url) throw new Error(`${zon} has no archive URL for .${key}`);
	return url;
}

/** The revision and version a Swift package is pinned to in Package.resolved. */
export function spmPin(
	repoRoot: string,
	resolvedPath: string,
	identity: string,
): { revision: string; version: string } {
	const resolved = JSON.parse(
		readFileSync(join(repoRoot, ENGINE_DIR, resolvedPath), "utf8"),
	) as {
		pins: { identity: string; state: { revision: string; version: string } }[];
	};
	const pin = resolved.pins.find((entry) => entry.identity === identity);
	if (!pin) throw new Error(`${resolvedPath} pins no ${identity} package`);
	return pin.state;
}

/** The provenance lines a component's notice section starts with. */
export function provenanceLines(
	repoRoot: string,
	component: BundledComponent,
): string[] {
	const { source } = component;
	const lines = [
		component.name,
		`License: ${component.license}`,
		`Project: ${component.home}`,
	];
	if (source.zon) {
		lines.push(
			`Archive: ${zonArchiveUrl(repoRoot, source.zon, component.key)}`,
		);
	}
	if (source.spm) {
		const pin = spmPin(repoRoot, source.spm, component.key);
		lines.push(`Version: ${pin.version} (${pin.revision})`);
	}
	return lines;
}
