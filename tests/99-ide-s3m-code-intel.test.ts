import { describe, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import { mkdirSync, realpathSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { createIdeTemp } from "./fixtures/ide-temp";

const { ideTemp } = createIdeTemp();

const repoRoot = process.cwd();
const yenBinPath = join(repoRoot, "yen-cli/bin/yen");

function runYen(
	args: string[],
	envOverrides: Record<string, string> = {},
	cwd = repoRoot,
) {
	const result = spawnSync(yenBinPath, args, {
		cwd,
		encoding: "utf8",
		timeout: 10_000,
		env: {
			...process.env,
			...envOverrides,
		},
	});
	if (result.error) {
		throw new Error(
			`yen ${args.join(" ")}: ${result.error.message}\n${result.stderr}`,
		);
	}
	return result;
}

function createZigProject(prefix: string) {
	const root = ideTemp(prefix);
	writeFileSync(
		join(root, "build.zig"),
		'const std = @import("std");\n',
		"utf8",
	);
	return realpathSync(root);
}

function createTypeScriptProject(prefix: string) {
	const root = ideTemp(prefix);
	writeFileSync(join(root, "package.json"), '{"name":"ts-fixture"}\n', "utf8");
	writeFileSync(
		join(root, "tsconfig.json"),
		'{"compilerOptions":{"target":"ES2020"}}\n',
		"utf8",
	);
	writeFileSync(join(root, "index.ts"), "export const widget = 1;\n", "utf8");
	return realpathSync(root);
}

function createJavaScriptProject(prefix: string) {
	const root = ideTemp(prefix);
	writeFileSync(join(root, "package.json"), '{"name":"js-fixture"}\n', "utf8");
	writeFileSync(join(root, "index.js"), "console.log(1);\n", "utf8");
	return realpathSync(root);
}

function createBunProject(prefix: string) {
	const root = ideTemp(prefix);
	writeFileSync(join(root, "package.json"), '{"name":"bun-fixture"}\n', "utf8");
	writeFileSync(join(root, "bun.lock"), "", "utf8");
	writeFileSync(
		join(root, "index.js"),
		"const Widget = 1;\nconsole.log(Widget);\n",
		"utf8",
	);
	return realpathSync(root);
}

function createGoProject(prefix: string) {
	const root = ideTemp(prefix);
	writeFileSync(
		join(root, "go.mod"),
		"module example.com/ast\n\ngo 1.22\n",
		"utf8",
	);
	writeFileSync(
		join(root, "main.go"),
		[
			"package main",
			"",
			"type Widget struct{}",
			"",
			"func UseWidget() Widget {",
			"\tvar local Widget",
			"\treturn local",
			"}",
			"",
		].join("\n"),
		"utf8",
	);
	return realpathSync(root);
}

function createSwiftProject(prefix: string) {
	const root = ideTemp(prefix);
	writeFileSync(
		join(root, "Package.swift"),
		[
			"// swift-tools-version: 6.0",
			"import PackageDescription",
			'let package = Package(name: "SwiftAST")',
			"",
		].join("\n"),
		"utf8",
	);
	writeFileSync(
		join(root, "Widget.swift"),
		[
			"struct Widget {}",
			"func useWidget() -> Widget {",
			"  let value = Widget()",
			"  return value",
			"}",
			"",
		].join("\n"),
		"utf8",
	);
	return realpathSync(root);
}

function createNestedWorkspaceAstFixture(prefix: string) {
	const root = ideTemp(prefix);
	const container = join(root, "yen-terminal");
	const overlays = join(container, "overlays");
	const ghostty = join(container, "ghostty");
	mkdirSync(overlays, { recursive: true });
	mkdirSync(ghostty, { recursive: true });
	writeFileSync(join(root, "package.json"), '{"name":"repo-root"}\n', "utf8");
	writeFileSync(
		join(overlays, "build.zig"),
		'const std = @import("std");\n',
		"utf8",
	);
	writeFileSync(
		join(ghostty, "build.zig"),
		'const std = @import("std");\n',
		"utf8",
	);
	return {
		root: realpathSync(root),
		container: realpathSync(container),
		overlays: realpathSync(overlays),
	};
}

function commandAvailable(command: string) {
	const check = spawnSync(
		"/bin/zsh",
		["-lc", `command -v ${command} >/dev/null 2>&1`],
		{
			cwd: repoRoot,
			encoding: "utf8",
			env: process.env,
		},
	);
	return check.status === 0;
}

describe("IDE S3M polyglot code-intelligence baseline", () => {
	test("lsp install status --all includes zig in the baseline matrix", () => {
		const project = createZigProject("yen-ide-lsp-zig-install-");
		const status = runYen(
			["ide", "lsp", "install", "status", "--all", "--project", project],
			{},
			project,
		);
		const output = `${status.stdout ?? ""}\n${status.stderr ?? ""}`;
		expect(status.status).toBe(0);
		expect(output).toContain("LANGUAGE");
		expect(output).toContain("AST");
		expect(output).toContain("zig");
		expect(output).toContain("toolchain-path");
		expect(output).toContain("not-shipped");
		expect(output).toContain("brew install zls");
	});

	test("lsp status exposes detected-language coverage posture for zig projects", () => {
		const project = createZigProject("yen-ide-lsp-zig-status-");
		const status = runYen(
			["ide", "lsp", "status", "--project", project, "--format", "json"],
			{},
			project,
		);
		expect(status.status).toBe(0);
		const payload = JSON.parse(status.stdout ?? "{}");
		expect(payload.detectedLanguage).toBe("zig");
		expect(payload.expectedServer).toBe("zls");
		expect(payload.installStrategy).toBe("toolchain-path");
		expect(payload.installManager).toBe("external-package-manager");
		expect(payload.installFamily).toBe("zig");
		expect(payload.installRoot).toBe("toolchain-path");
		expect(payload.installStatus).toBe("no");
		expect(payload.installHint).toContain("zls");
		expect(payload.updateHint).toContain("zls");
		expect(payload.installNote).toContain("does not vendor or auto-install");
		expect(payload.astLanguage).toBe("zig");
		expect(payload.astSource).toBe("none");
		expect(payload.astReady).toBe(false);
		expect(payload.astGuidance).toContain("not shipped yet for zig");
	});

	test(
		"lsp status makes the shared JavaScript/TypeScript runtime explicit",
		() => {
			const javascriptProject = createJavaScriptProject("yen-ide-js-status-");
			const typescriptProject = createTypeScriptProject("yen-ide-ts-status-");

			const javascriptStatus = runYen(
				[
					"ide",
					"lsp",
					"status",
					"--project",
					javascriptProject,
					"--format",
					"json",
				],
				{},
				javascriptProject,
			);
			const typescriptStatus = runYen(
				[
					"ide",
					"lsp",
					"status",
					"--project",
					typescriptProject,
					"--format",
					"json",
				],
				{},
				typescriptProject,
			);

			expect(
				javascriptStatus.status,
				`${javascriptStatus.stdout}\n${javascriptStatus.stderr}`,
			).toBe(0);
			expect(
				typescriptStatus.status,
				`${typescriptStatus.stdout}\n${typescriptStatus.stderr}`,
			).toBe(0);

			const javascriptPayload = JSON.parse(javascriptStatus.stdout ?? "{}");
			const typescriptPayload = JSON.parse(typescriptStatus.stdout ?? "{}");

			expect(javascriptPayload.detectedLanguage).toBe("javascript");
			expect(typescriptPayload.detectedLanguage).toBe("typescript");
			expect(javascriptPayload.installFamily).toBe("shared-js-ts");
			expect(typescriptPayload.installFamily).toBe("shared-js-ts");
			expect(javascriptPayload.installManager).toBe("yen-managed-node");
			expect(typescriptPayload.installManager).toBe("yen-managed-node");
			expect(javascriptPayload.installRoot).toContain("/lsp-tools/node");
			expect(typescriptPayload.installRoot).toContain("/lsp-tools/node");
			expect(javascriptPayload.installHint).toBe(typescriptPayload.installHint);
			expect(javascriptPayload.installNote).toContain(
				"covers both JavaScript and TypeScript projects",
			);
			expect(typescriptPayload.installNote).toContain(
				"covers both JavaScript and TypeScript projects",
			);
		},
		// Two real CLI probes can exceed the default 5s under concurrent build load.
		{ timeout: 15_000 },
	);

	test("lsp install status calls out toolchain-managed ownership for rust and zig", () => {
		const zigProject = createZigProject("yen-ide-zig-install-status-");
		const rustProject = ideTemp("yen-ide-rust-install-status-");
		writeFileSync(
			join(rustProject, "Cargo.toml"),
			'[package]\nname = "r"\nversion = "0.1.0"\nedition = "2021"\n',
			"utf8",
		);

		const zigStatus = runYen(
			["ide", "lsp", "install", "status", "--project", zigProject],
			{},
			zigProject,
		);
		const rustStatus = runYen(
			["ide", "lsp", "install", "status", "--project", rustProject],
			{},
			rustProject,
		);

		const zigOutput = `${zigStatus.stdout ?? ""}\n${zigStatus.stderr ?? ""}`;
		const rustOutput = `${rustStatus.stdout ?? ""}\n${rustStatus.stderr ?? ""}`;
		expect(zigStatus.status).toBe(0);
		expect(rustStatus.status).toBe(0);

		expect(zigOutput).toContain("external-package-manager");
		expect(zigOutput).toContain("root:      toolchain-path");
		expect(zigOutput).toContain(
			"note:      zls stays toolchain-managed on PATH",
		);
		expect(rustOutput).toContain("rustup-toolchain");
		expect(rustOutput).toContain("root:      toolchain-path");
		expect(rustOutput).toContain(
			"note:      rust-analyzer stays toolchain-managed",
		);
	});

	test("ast status distinguishes not-ready TypeScript fallback from unsupported zig fallback", () => {
		const typescriptProject = createTypeScriptProject("yen-ide-ast-ts-");
		const tsStatus = runYen(
			["ide", "ast", "status", "--project", typescriptProject],
			{},
			typescriptProject,
		);
		const tsOutput = `${tsStatus.stdout ?? ""}\n${tsStatus.stderr ?? ""}`;
		expect(tsStatus.status).toBe(0);
		expect(tsOutput).toContain("Supported: yes");
		expect(tsOutput).toContain("Language:  typescript");
		expect(tsOutput).toContain("Ready:     no");
		expect(tsOutput).toContain("Source:    typescript-compiler-api");
		expect(tsOutput).toContain("Install:   yen ide lsp install typescript");
		expect(tsOutput).toContain("LSP:       typescript-language-server --stdio");

		const zigProject = createZigProject("yen-ide-ast-zig-");
		const zigStatus = runYen(
			["ide", "ast", "status", "--project", zigProject],
			{},
			zigProject,
		);
		const zigOutput = `${zigStatus.stdout ?? ""}\n${zigStatus.stderr ?? ""}`;
		expect(zigStatus.status).toBe(0);
		expect(zigOutput).toContain("Supported: no");
		expect(zigOutput).toContain("Language:  zig");
		expect(zigOutput).toContain("Ready:     no");
		expect(zigOutput).toContain("LSP:       zls");
		expect(zigOutput).toContain("Install:   brew install zls");
		expect(zigOutput).toContain("AST fallback is not shipped yet for zig");
	});

	test("ast status keeps Bun projects on the JavaScript fallback path", () => {
		const project = createBunProject("yen-ide-ast-bun-");
		const status = runYen(
			["ide", "ast", "status", "--project", project],
			{},
			project,
		);
		const output = `${status.stdout ?? ""}\n${status.stderr ?? ""}`;
		expect(status.status).toBe(0);
		expect(output).toContain("Supported: yes");
		expect(output).toContain("Language:  javascript");
		expect(output).toContain("Source:    typescript-compiler-api");
		expect(output).toContain("Install:   yen ide lsp install typescript");
	});

	test("ast status resolves nested workspace container paths to the concrete product root", () => {
		const fixture = createNestedWorkspaceAstFixture("yen-ide-ast-nested-");
		const status = runYen(
			["ide", "ast", "status", "--project", fixture.container],
			{},
			fixture.root,
		);
		const output = `${status.stdout ?? ""}\n${status.stderr ?? ""}`;
		expect(status.status).toBe(0);
		expect(output).toContain(`Root:     ${fixture.overlays}`);
		expect(output).toContain("Language:  zig");
	});

	test("lsp install status reflects the new Go and Swift AST fallback engines", () => {
		const goProject = createGoProject("yen-ide-go-install-matrix-");
		const swiftProject = createSwiftProject("yen-ide-swift-install-matrix-");

		const goStatus = runYen(
			["ide", "lsp", "install", "status", "--project", goProject],
			{},
			goProject,
		);
		const swiftStatus = runYen(
			["ide", "lsp", "install", "status", "--project", swiftProject],
			{},
			swiftProject,
		);

		expect(goStatus.status).toBe(0);
		expect(swiftStatus.status).toBe(0);
		expect(`${goStatus.stdout ?? ""}\n${goStatus.stderr ?? ""}`).toContain(
			"go-parser",
		);
		expect(
			`${swiftStatus.stdout ?? ""}\n${swiftStatus.stderr ?? ""}`,
		).toContain("swiftc-dump-ast-json");
	});

	test("ast definition and references use parser-backed fallback for Go projects", () => {
		const project = createGoProject("yen-ide-go-ast-");
		const goAvailable = commandAvailable("go");

		const status = runYen(
			["ide", "ast", "status", "--project", project],
			{},
			project,
		);
		const statusOutput = `${status.stdout ?? ""}\n${status.stderr ?? ""}`;
		expect(status.status).toBe(0);
		expect(statusOutput).toContain("Supported: yes");
		expect(statusOutput).toContain("Language:  go");
		expect(statusOutput).toContain("Source:    go-parser");

		const definition = runYen(
			["ide", "ast", "definition", "Widget", project],
			{},
			project,
		);
		const references = runYen(
			["ide", "ast", "references", "Widget", project],
			{},
			project,
		);
		const definitionOutput = `${definition.stdout ?? ""}\n${definition.stderr ?? ""}`;
		const referencesOutput = `${references.stdout ?? ""}\n${references.stderr ?? ""}`;

		if (goAvailable) {
			expect(statusOutput).toContain("Ready:     yes");
			expect(statusOutput).toContain(
				"Guidance:  Go fallback uses the standard-library go/parser and token APIs.",
			);
			expect(definition.status).toBe(0);
			expect(definitionOutput).toContain("Engine:    go-parser");
			expect(definitionOutput).toContain("main.go:3:6");
			expect(references.status).toBe(0);
			expect(referencesOutput).toContain("main.go:3:6");
			expect(referencesOutput).toContain("main.go:5:18");
			expect(referencesOutput).toContain("main.go:6:12");
		} else {
			expect(statusOutput).toContain("Ready:     no");
			expect(statusOutput).toContain(
				"Install:   Install Go so the standard parser/token toolchain is available on PATH",
			);
			expect(definition.status).toBe(1);
			expect(definitionOutput).toContain(
				"Go AST queries require the Go toolchain on PATH",
			);
			expect(references.status).toBe(1);
			expect(referencesOutput).toContain(
				"Go AST queries require the Go toolchain on PATH",
			);
		}
	});

	test("ast definition and references use parser-backed fallback for Swift projects", () => {
		const project = createSwiftProject("yen-ide-swift-ast-");
		const swiftcAvailable = commandAvailable("swiftc");

		const status = runYen(
			["ide", "ast", "status", "--project", project],
			{},
			project,
		);
		const statusOutput = `${status.stdout ?? ""}\n${status.stderr ?? ""}`;
		expect(status.status).toBe(0);
		expect(statusOutput).toContain("Supported: yes");
		expect(statusOutput).toContain("Language:  swift");
		expect(statusOutput).toContain("Source:    swiftc-dump-ast-json");

		const definition = runYen(
			["ide", "ast", "definition", "Widget", project],
			{},
			project,
		);
		const references = runYen(
			["ide", "ast", "references", "Widget", project],
			{},
			project,
		);
		const definitionOutput = `${definition.stdout ?? ""}\n${definition.stderr ?? ""}`;
		const referencesOutput = `${references.stdout ?? ""}\n${references.stderr ?? ""}`;

		if (swiftcAvailable) {
			expect(statusOutput).toContain("Ready:     yes");
			expect(statusOutput).toContain(
				"Guidance:  Swift fallback uses swiftc -dump-ast-format json -dump-ast.",
			);
			expect(definition.status).toBe(0);
			expect(definitionOutput).toContain("Engine:    swiftc-dump-ast-json");
			expect(definitionOutput).toContain("Widget.swift:1:8");
			expect(references.status).toBe(0);
			expect(referencesOutput).toContain("Widget.swift:1:8");
			expect(referencesOutput).toContain("Widget.swift:3:15");
		} else {
			expect(statusOutput).toContain("Ready:     no");
			expect(statusOutput).toContain("Install:   xcode-select --install");
			expect(definition.status).toBe(1);
			expect(definitionOutput).toContain(
				"Swift AST queries require swiftc on PATH",
			);
			expect(references.status).toBe(1);
			expect(referencesOutput).toContain(
				"Swift AST queries require swiftc on PATH",
			);
		}
	});
});
