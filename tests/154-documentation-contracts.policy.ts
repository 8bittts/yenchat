import { describe, expect, test } from "bun:test";
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";

const repoRoot = process.cwd();
const read = (path: string) => readFileSync(join(repoRoot, path), "utf8");

describe("documentation contracts", () => {
	test("public docs name the Hosts palette rows as the Swift source titles them", () => {
		const rowsSource = read(
			"yen-terminal/overlays/macos/Sources/Features/Command Palette/TerminalCommandPaletteHostsResults.swift",
		);
		// A row is `row("<key>", "<title>", ...)` or `statusRow("<key>", "<title>", ...)`,
		// and the palette shows it under the `Hosts: ` prefix. `\\(name)` in a title is
		// the Mac the row names, written <Mac> in the docs.
		const title = (key: string) => {
			const match = rowsSource.match(
				new RegExp(`(?:row|Row)\\(\\s*"${key}",\\s*"([^"]+)"`),
			);
			expect(match, `palette row ${key}`).not.toBeNull();
			return `Hosts: ${(match?.[1] ?? "").replace("\\(name)", "<Mac>")}`;
		};
		const manual = read("app/docs/docs-client.tsx").replaceAll(
			"&lt;Mac&gt;",
			"<Mac>",
		);
		const llms = read("public/llms.txt");
		const security = read("_docs/04-security.md");
		const desktop = read("_docs/13-desktop-features.md");

		for (const key of ["first-connection", "key-sign-in", "refresh"]) {
			const name = title(key);
			const bare = name.slice("Hosts: ".length);
			expect(manual, key).toContain(bare);
			expect(llms, key).toContain(bare);
			expect(desktop, key).toContain(bare);
		}
		for (const key of ["first-connection", "key-sign-in"]) {
			expect(security, key).toContain(`\`${title(key)}\``);
		}
	});

	test("public docs, privacy and terms carry the remote sessions contract", () => {
		const manual = read("app/docs/docs-client.tsx");
		const start = manual.indexOf('<h3 id="remote-sessions"');
		const end = manual.indexOf("</DocSection>", start);
		expect(start).toBeGreaterThanOrEqual(0);
		expect(end).toBeGreaterThan(start);
		const remote = manual.slice(start, end);
		const llms = read("public/llms.txt");
		const privacy = read("components/docs/legal-privacy-content.tsx");
		const terms = read("app/terms/terms-client.tsx");
		const security = read("_docs/04-security.md");

		// How to reach the other Mac, as the CLI and the palette do it.
		expect(remote).toContain("yen sessions list --host studio");
		expect(remote).toContain("yen sessions attach --host studio <id>");
		expect(remote).toContain("turn on Remote Login in System Settings &gt;");
		expect(remote).toContain("signing in must work without a password");
		expect(remote).toContain("Set Up Key Sign-In for &lt;Mac&gt;");
		expect(llms).toContain("exit codes 10-16");
		expect(remote).toContain(
			"SSH server; the open-source command-line Tailscale can.",
		);
		expect(manual).toContain('<a href="#remote-sessions"');
		expect(llms).toContain("https://yen.chat/#remote-sessions");
		expect(llms).toContain("`yen sessions attach --host <mac> <id>`");
		expect(llms).toContain("cannot be a Tailscale SSH server");
		expect(llms).toContain("nothing is sent to YEN");

		// Tailscale is the user's software and network, never a YEN provider.
		expect(privacy).toContain("not a YEN service provider");
		expect(privacy).toContain("YEN stores no passwords");
		expect(privacy).toContain("None of this is sent to YEN.");
		expect(terms).toContain("Tailscale and SSH are third-party");
		expect(security).toContain("## Remote Attach Threat Model");
		expect(security).toContain(
			"Nothing here has run on a real tailnet or between two Macs.",
		);

		// No public claim the code and its tests cannot back.
		const llmsRemote = llms
			.split("\n")
			.filter((line) => line.includes("remote-sessions"))
			.join("\n");
		const privacyRemote = privacy.slice(
			privacy.indexOf(">Remote sessions</h3>"),
			privacy.indexOf("</div>", privacy.indexOf(">Remote sessions</h3>")),
		);
		expect(llmsRemote).not.toBe("");
		expect(privacyRemote).toContain("Tailscale");
		for (const text of [remote, llmsRemote, privacyRemote]) {
			expect(text).not.toMatch(
				/security audit|audited|end-to-end encrypt|guarantee/i,
			);
		}
	});

	test("docs record the lsp command/state contract and security review", () => {
		const commandsDoc = read("_docs/12-commands.md");
		const vendorDoc = read("_docs/04-security.md");
		const coreReadme = read("yen-cli/00-core-readme.md");

		expect(commandsDoc).toContain("yen ide lsp status [path]");
		expect(commandsDoc).toContain("yen ide lsp start [path]");
		expect(commandsDoc).toContain("yen ide lsp stop [path]");
		expect(commandsDoc).toContain("trusted-lsp-projects");
		expect(commandsDoc).toContain("lsp-trust");
		expect(commandsDoc).toContain("lsp-crash");
		expect(commandsDoc).toContain("unavailable-server");

		expect(vendorDoc).toContain("YEN bundles no language servers");
		expect(vendorDoc).toContain("yen ide lsp install");
		expect(vendorDoc).toContain("devcontainer");

		expect(coreReadme).toContain(
			"detect/doctor/env/lsp/share/ast/devcontainer/vscode",
		);
		expect(coreReadme).toContain("yen ide lsp status");
	});

	test("docs record the diagnostics command and diagnostics snapshot state", () => {
		const commandsDoc = read("_docs/12-commands.md");

		expect(commandsDoc).toContain("yen ide lsp diagnostics [path]");
		expect(commandsDoc).toContain("diagnostics.json");
		expect(commandsDoc).toContain("fresh");
		expect(commandsDoc).toContain("stale");
	});

	test("docs record the sharing contract, state paths, and public quick-start surfaces", () => {
		const commandsDoc = readFileSync(
			join(repoRoot, "_docs/12-commands.md"),
			"utf8",
		);
		const vendorDoc = readFileSync(
			join(repoRoot, "_docs/04-security.md"),
			"utf8",
		);
		const coreReadme = readFileSync(
			join(repoRoot, "yen-cli/00-core-readme.md"),
			"utf8",
		);
		const docsClient = readFileSync(
			join(repoRoot, "app/docs/docs-client.tsx"),
			"utf8",
		);
		const llms = readFileSync(join(repoRoot, "public/llms.txt"), "utf8");
		const coreHelp = readFileSync(
			join(repoRoot, "yen-cli/commands/core/help"),
			"utf8",
		);
		const paletteDir = join(
			repoRoot,
			"yen-terminal/overlays/macos/Sources/Features/Command Palette",
		);
		const palette = readdirSync(paletteDir)
			.filter((fileName) => /^TerminalCommandPalette.*\.swift$/.test(fileName))
			.sort()
			.map((fileName) => readFileSync(join(paletteDir, fileName), "utf8"))
			.join("\n");

		expect(commandsDoc).toContain(
			"yen ide share host [path\\|ssh://user@host/abs/path]",
		);
		expect(commandsDoc).toContain("trusted-share-projects");
		expect(commandsDoc).toContain("share-host");
		expect(commandsDoc).toContain("share-expire");

		expect(vendorDoc).toContain("upterm");
		expect(vendorDoc).toContain("tmate");
		expect(coreReadme).toContain("yen ide share host");
		expect(docsClient).toContain("yen ide share");
		// The docs page's keyword meta was removed (crawlers ignore it); the
		// "terminal sharing" concept is documented in the actual docs content.
		expect(docsClient.toLowerCase()).toContain("terminal sharing");
		expect(docsClient).toContain("passphrase-encrypted");
		expect(llms).toContain("`yen ide share host`");
		expect(llms).toContain("`yen ide share status`");
		expect(coreHelp).toContain("detect/env/lsp/share/ast/devcontainer/vscode");
		expect(palette).toContain("IDE: Share Status");
		expect(palette).toContain("IDE: Share Host (Read-Only)");
		expect(palette).toContain("IDE: Share Revoke");
	});

	test("doctor docs are registered across command, internal, and public references", () => {
		const commands = readFileSync(
			join(repoRoot, "_docs/12-commands.md"),
			"utf8",
		);
		const readme = readFileSync(
			join(repoRoot, "yen-cli/00-core-readme.md"),
			"utf8",
		);
		const docs = readFileSync(
			join(repoRoot, "app/docs/docs-client.tsx"),
			"utf8",
		);
		const llmsText = readFileSync(join(repoRoot, "public/llms.txt"), "utf8");

		expect(commands).toContain(
			"yen ide doctor [path\\|ssh://user@host/abs/path]",
		);
		expect(readme).toContain("yen ide doctor");
		expect(docs).toContain("yen ide doctor");
		expect(llmsText).toContain("`yen ide doctor`");
	});

	test("trust center docs are registered across command, internal, README, and public references", () => {
		const commands = readFileSync(
			join(repoRoot, "_docs/12-commands.md"),
			"utf8",
		);
		const readme = readFileSync(
			join(repoRoot, "yen-cli/00-core-readme.md"),
			"utf8",
		);
		const docs = readFileSync(
			join(repoRoot, "app/docs/docs-client.tsx"),
			"utf8",
		);
		const llmsText = readFileSync(join(repoRoot, "public/llms.txt"), "utf8");

		expect(commands).toContain("yen ide trust status");
		expect(commands).toContain("yen ide trust revoke");
		expect(commands).toContain("yen ide trust reset");
		expect(commands).toContain("Workspace Trust Center (`yen ide trust`)");
		expect(commands).toContain(
			"yen ide trust status [path\\|ssh://user@host/abs/path]",
		);
		expect(readme).toContain("yen ide trust status");
		expect(docs).toContain("yen ide trust status / revoke / reset");
		expect(llmsText).toContain("`yen ide trust status`");
	});

	test("test runner docs are registered across command, internal, README, and public references", () => {
		const commands = readFileSync(
			join(repoRoot, "_docs/12-commands.md"),
			"utf8",
		);
		const readme = readFileSync(
			join(repoRoot, "yen-cli/00-core-readme.md"),
			"utf8",
		);
		const docs = readFileSync(
			join(repoRoot, "app/docs/docs-client.tsx"),
			"utf8",
		);
		const llmsText = readFileSync(join(repoRoot, "public/llms.txt"), "utf8");

		expect(commands).toContain("yen ide test status");
		expect(commands).toContain("yen ide test run");
		expect(commands).toContain("--watch --watch-interval <sec> --max-runs <N>");
		expect(commands).toContain(
			"test run [path] [--runner <id>] [--failed] [--quick] [--watch --watch-interval <sec> --max-runs <N>]",
		);
		expect(commands).toContain("yen ide test status [path]");
		expect(commands).toContain("fixed runner-id snapshot");
		expect(readme).toContain("yen ide test status");
		expect(readme).toContain("yen ide test run --runner node-test --watch");
		expect(docs).toContain("yen ide test status / run");
		expect(docs).toContain(
			"yen ide test run --runner node-test --watch --watch-interval 0.5 --max-runs 3",
		);
		expect(llmsText).toContain("`yen ide test status`");
		expect(llmsText).toContain("`yen ide test run`");
		expect(llmsText).toContain("watch-mode parity for `test run`");
	});

	test("workflow native watch flags are advertised in documentation", () => {
		const commands = readFileSync(
			join(repoRoot, "_docs/12-commands.md"),
			"utf8",
		);
		const readme = readFileSync(
			join(repoRoot, "yen-cli/00-core-readme.md"),
			"utf8",
		);
		const docs = readFileSync(
			join(repoRoot, "app/docs/docs-client.tsx"),
			"utf8",
		);
		const llmsText = readFileSync(join(repoRoot, "public/llms.txt"), "utf8");

		expect(commands).toContain(
			"yen ide workflow run --native <task-id> [--watch --watch-interval <sec> --max-runs <N>]",
		);
		expect(commands).toContain("run --native --watch");
		expect(commands).toContain("fixed native-task id snapshot");
		expect(readme).toContain(
			"yen ide workflow run --native package.json:test --watch --watch-interval 0.5 --max-runs 2",
		);
		expect(docs).toContain(
			"yen ide workflow run --native package.json:test --watch --watch-interval 0.5 --max-runs 2",
		);
		expect(llmsText).toContain(
			"local watch-mode parity for `test run`, `workflow run --native`, and `verify`",
		);
	});

	test("documents the hosted public page inventory", () => {
		const gtmDoc = readFileSync(join(repoRoot, "_docs/08-growth.md"), "utf8");
		const scriptsReadme = readFileSync(
			join(repoRoot, "scripts/00-scripts-readme.md"),
			"utf8",
		);

		expect(gtmDoc).toContain("The sitemap lists these two pages.");
		expect(scriptsReadme).toContain("44-build-web-csp.ts");
	});

	test("PR Review descriptions distinguish raw diffs from Delta resolution previews", () => {
		const commandPaletteTypes = readFileSync(
			join(
				repoRoot,
				"yen-terminal/overlays/macos/Sources/Features/Command Palette/TerminalCommandPaletteTypes.swift",
			),
			"utf8",
		);
		const commandDocs = readFileSync(
			join(repoRoot, "_docs/12-commands.md"),
			"utf8",
		);
		const publicDocs = readFileSync(
			join(repoRoot, "app/docs/docs-client.tsx"),
			"utf8",
		);
		const start = commandPaletteTypes.indexOf('id: "review:pull-request"');
		const end = commandPaletteTypes.indexOf(
			'id: "review:merge-conflicts"',
			start + 1,
		);
		expect(start).toBeGreaterThanOrEqual(0);
		expect(end).toBeGreaterThan(start);
		const pullRequestBlueprint = commandPaletteTypes.slice(start, end);

		expect(pullRequestBlueprint).toContain("raw selectable previews");
		expect(pullRequestBlueprint).not.toContain("delta");
		expect(commandDocs).toContain("raw selectable/colorized focused diffs");
		expect(commandDocs).not.toContain("delta-backed focused previews");
		expect(publicDocs).toContain("with raw selectable previews");
		expect(publicDocs).not.toContain("with delta-backed previews");
	});
});
