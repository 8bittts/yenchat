import type { MetadataRoute } from "next";
import { DOWNLOAD_HREF } from "@/lib/analytics/download-cta";
import { SITE_URL } from "@/lib/seo";

// Re-exported for existing consumers; the canonical definition lives in lib/seo.
export { SITE_URL };
export const PUBLIC_LIBRARY_LAST_MODIFIED = new Date(
	"2026-11-10T00:00:00.000Z",
);
export const PUBLIC_LIBRARY_SOURCE_CHECKED_AT = "2026-11-10";
export const PUBLIC_LIBRARY_MIN_EVIDENCE_SCORE = 80;

export type PublicLibraryPageKind = "alternative" | "use-case";

export interface PublicLibrarySource {
	title: string;
	url: string;
	lastCheckedAt: string;
}

export interface PublicLibraryTextPoint {
	label: string;
	text: string;
	source?: PublicLibrarySource;
}

export interface PublicLibraryLink {
	label: string;
	href: string;
	description: string;
}

export interface PublicLibraryPage {
	kind: PublicLibraryPageKind;
	slug: string;
	path: string;
	competitorName?: string;
	seo: {
		title: string;
		description: string;
		imageAlt: string;
	};
	h1: string;
	kicker: string;
	summary: string;
	audience: string;
	evidenceScore: number;
	publicEligible: boolean;
	officialSources: readonly PublicLibrarySource[];
	yenProofPoints: readonly PublicLibraryTextPoint[];
	decisionPoints: readonly PublicLibraryTextPoint[];
	conversionLinks: readonly PublicLibraryLink[];
	relatedPaths: readonly string[];
	lastModified: Date;
}

function officialSource(title: string, url: string): PublicLibrarySource {
	return {
		title,
		url,
		lastCheckedAt: PUBLIC_LIBRARY_SOURCE_CHECKED_AT,
	};
}

const yenDocsSource = officialSource("YEN docs", `${SITE_URL}/docs`);

const yenLlmsSource = officialSource("YEN llms.txt", `${SITE_URL}/llms.txt`);

const yenDownloadLink: PublicLibraryLink = {
	label: "Download YEN",
	href: DOWNLOAD_HREF,
	description: "Install the current public macOS build.",
};

const yenDocsLink: PublicLibraryLink = {
	label: "Read the docs",
	href: "/docs",
	description:
		"Verify shipped terminal, IDE, browser, Git, and dictation flows.",
};

const yenPrivacyLink: PublicLibraryLink = {
	label: "Review privacy",
	href: "/terms",
	description: "Check the service map and local-first data boundaries.",
};

const defaultConversionLinks: readonly PublicLibraryLink[] = [
	yenDownloadLink,
	yenDocsLink,
	yenPrivacyLink,
];

const sharedYenProofPoints = [
	{
		label: "macOS terminal",
		text: "YEN is a macOS terminal with Metal rendering, native tabs and splits, and a command palette.",
		source: yenDocsSource,
	},
	{
		label: "Local workflow surfaces",
		text: "YEN ships local file browsing, native WebKit preview, a read-only Git drawer, and terminal-first IDE commands.",
		source: yenDocsSource,
	},
	{
		label: "Speech-to-text",
		text: "YEN's Option + Space dictation is built around macOS speech recognition and works outside the terminal too.",
		source: yenDocsSource,
	},
] as const satisfies readonly PublicLibraryTextPoint[];

function alternativePage(input: {
	slug: string;
	competitorName: string;
	title: string;
	description: string;
	summary: string;
	audience: string;
	officialSources: readonly PublicLibrarySource[];
	decisionPoints: readonly PublicLibraryTextPoint[];
	relatedPaths: readonly string[];
	evidenceScore?: number;
}): PublicLibraryPage {
	return {
		kind: "alternative",
		slug: input.slug,
		path: `/alternatives/${input.slug}`,
		competitorName: input.competitorName,
		seo: {
			title: input.title,
			description: input.description,
			imageAlt: `YEN alternative notes for ${input.competitorName}`,
		},
		h1: `${input.competitorName} alternative for terminal-first developers`,
		kicker: "Terminal alternative",
		summary: input.summary,
		audience: input.audience,
		evidenceScore: input.evidenceScore ?? 88,
		publicEligible: true,
		officialSources: input.officialSources,
		yenProofPoints: sharedYenProofPoints,
		decisionPoints: input.decisionPoints,
		conversionLinks: defaultConversionLinks,
		relatedPaths: input.relatedPaths,
		lastModified: PUBLIC_LIBRARY_LAST_MODIFIED,
	};
}

function createUseCasePage(input: {
	slug: string;
	title: string;
	description: string;
	h1: string;
	summary: string;
	audience: string;
	decisionPoints: readonly PublicLibraryTextPoint[];
	relatedPaths: readonly string[];
	evidenceScore?: number;
}): PublicLibraryPage {
	return {
		kind: "use-case",
		slug: input.slug,
		path: `/use-cases/${input.slug}`,
		seo: {
			title: input.title,
			description: input.description,
			imageAlt: `YEN use case notes for ${input.h1}`,
		},
		h1: input.h1,
		kicker: "Terminal use case",
		summary: input.summary,
		audience: input.audience,
		evidenceScore: input.evidenceScore ?? 86,
		publicEligible: true,
		officialSources: [],
		yenProofPoints: sharedYenProofPoints,
		decisionPoints: input.decisionPoints,
		conversionLinks: defaultConversionLinks,
		relatedPaths: input.relatedPaths,
		lastModified: PUBLIC_LIBRARY_LAST_MODIFIED,
	};
}

export const PUBLIC_LIBRARY_PAGES = [
	alternativePage({
		slug: "warp",
		competitorName: "Warp",
		title: "Warp Alternative for Terminal-First Workflows",
		description:
			"Compare Warp's agentic terminal model with YEN's local macOS terminal workflows, native browser preview, Git drawer, and dictation.",
		summary:
			"Warp is a serious agentic development environment. YEN is for developers who want the terminal to stay local, native, and centered on shipped macOS workflows.",
		audience:
			"Use this page if you like modern terminal UX but want to evaluate a smaller macOS-native surface before moving your daily shell.",
		officialSources: [
			officialSource("Warp getting started", "https://docs.warp.dev/"),
			officialSource(
				"Warp terminal features",
				"https://docs.warp.dev/terminal/comparisons/terminal-features/",
			),
		],
		decisionPoints: [
			{
				label: "Agent surface",
				text: "Warp positions terminal and agent modes as a combined development environment; YEN keeps the daily terminal surface focused and exposes local IDE commands from the command palette.",
			},
			{
				label: "Native preview",
				text: "YEN includes an isolated WebKit browser preview for docs, HTTPS pages, and localhost loops from terminal context.",
				source: yenDocsSource,
			},
			{
				label: "Dictation workflow",
				text: "YEN's system-wide dictation is useful when the terminal is only one of several macOS apps in the loop.",
				source: yenDocsSource,
			},
		],
		relatedPaths: [
			"/alternatives/ghostty",
			"/use-cases/terminal-ide-local-workflows",
			"/use-cases/privacy-focused-ai-terminal",
		],
	}),
	alternativePage({
		slug: "wave",
		competitorName: "Wave Terminal",
		title: "Wave Terminal Alternative for Local Workflows",
		description:
			"Compare Wave Terminal's graphical terminal workspace with YEN's macOS terminal, WebKit preview, Git drawer, and dictation.",
		summary:
			"Wave Terminal blends terminal sessions with graphical workspace surfaces. YEN is for macOS developers who want a native terminal with local workflow tools close to the shell.",
		audience:
			"Use this page if file previews, web browsing, and AI assistance are the workflow you are evaluating, but you want the comparison grounded in local macOS app behavior.",
		officialSources: [
			officialSource("Wave documentation", "https://docs.waveterm.dev/"),
			officialSource("Wave AI modes", "https://docs.waveterm.dev/waveai-modes"),
		],
		decisionPoints: [
			{
				label: "Workspace model",
				text: "Wave's docs describe a terminal with graphical capabilities such as file previews, web browsing, and AI assistance; YEN keeps the comparison to its shipped native macOS browser, file, Git, and dictation surfaces.",
				source: officialSource(
					"Wave documentation",
					"https://docs.waveterm.dev/",
				),
			},
			{
				label: "Browser preview",
				text: "YEN includes an isolated WebKit preview for docs, HTTPS pages, localhost, and loopback URLs launched from terminal context.",
				source: yenDocsSource,
			},
			{
				label: "Local control surface",
				text: "YEN's command palette routes files, browser preview, Git review, settings, and terminal IDE actions through native app workflows.",
				source: yenDocsSource,
			},
		],
		relatedPaths: [
			"/alternatives/warp",
			"/use-cases/terminal-with-native-browser-preview",
			"/use-cases/terminal-ide-local-workflows",
		],
	}),
	alternativePage({
		slug: "ghostty",
		competitorName: "Ghostty",
		title: "Ghostty Alternative for macOS Terminal Workflows",
		description:
			"Compare Ghostty's native GPU terminal focus with YEN's macOS terminal, browser preview, Git drawer, dictation, and IDE commands.",
		summary:
			"Ghostty is a strong choice for a native, GPU-accelerated terminal. YEN adds opinionated macOS workflow surfaces around that same daily-terminal need.",
		audience:
			"Use this page if your baseline is a fast terminal and you are deciding whether built-in workflow surfaces should live beside it.",
		officialSources: [
			officialSource("Ghostty docs", "https://ghostty.org/docs"),
			officialSource("Ghostty features", "https://ghostty.org/docs/features"),
		],
		decisionPoints: [
			{
				label: "Terminal baseline",
				text: "Ghostty emphasizes a native UI, speed, and terminal protocol coverage; YEN's public claim set is a macOS terminal with Metal rendering and bundled workflow surfaces.",
			},
			{
				label: "Git context",
				text: "YEN includes a read-only local Git drawer for branch status, grouped file changes, raw diffs, and a bundled lazygit handoff.",
				source: yenDocsSource,
			},
			{
				label: "File and browser context",
				text: "YEN keeps file browsing and browser preview inside the same command palette path instead of making them external app hops.",
				source: yenDocsSource,
			},
		],
		relatedPaths: [
			"/alternatives/iterm2",
			"/alternatives/alacritty",
			"/use-cases/fast-gpu-terminal-for-macos",
		],
	}),
	alternativePage({
		slug: "iterm2",
		competitorName: "iTerm2",
		title: "iTerm2 Alternative for Modern macOS Terminals",
		description:
			"Compare iTerm2's mature macOS terminal features with YEN's native browser preview, Git drawer, dictation, and IDE workflows.",
		summary:
			"iTerm2 is the mature macOS terminal many developers know. YEN is narrower, newer, and focused on local workflow shortcuts around a GPU terminal.",
		audience:
			"Use this page if you already rely on panes, hotkeys, and search, but want to evaluate newer macOS-native workflow surfaces.",
		officialSources: [
			officialSource("iTerm2 features", "https://iterm2.com/features.html"),
			officialSource(
				"iTerm2 documentation",
				"https://iterm2.com/documentation.html",
			),
		],
		decisionPoints: [
			{
				label: "Maturity tradeoff",
				text: "iTerm2 has a long-running macOS feature set; YEN is a newer app that prioritizes a compact set of terminal, browser, Git, and dictation workflows.",
			},
			{
				label: "Command palette",
				text: "YEN routes app actions, files, browser preview, Git review, and IDE commands through one command palette.",
				source: yenDocsSource,
			},
			{
				label: "Speech input",
				text: "YEN includes a system-wide Option + Space speech-to-text path for macOS users who want voice input in YEN and other apps, subject to permissions, Secure Input, and target-app behavior.",
				source: yenDocsSource,
			},
		],
		relatedPaths: [
			"/alternatives/ghostty",
			"/alternatives/wezterm",
			"/use-cases/macos-terminal-with-speech-to-text",
		],
	}),
	alternativePage({
		slug: "wezterm",
		competitorName: "WezTerm",
		title: "WezTerm Alternative for Local Terminal Workflows",
		description:
			"Compare WezTerm's cross-platform multiplexing with YEN's macOS-focused terminal, command palette, browser preview, and Git drawer.",
		summary:
			"WezTerm is powerful when cross-platform multiplexing and configuration are central. YEN optimizes for a macOS-first local workflow surface.",
		audience:
			"Use this page if you like panes and terminal control, but your daily machine is macOS and you want native adjacent tools.",
		officialSources: [
			officialSource("WezTerm overview", "https://wezterm.org/"),
			officialSource(
				"WezTerm multiplexing",
				"https://wezterm.org/multiplexing.html",
			),
		],
		decisionPoints: [
			{
				label: "Platform shape",
				text: "WezTerm is a cross-platform terminal and multiplexer; YEN's public app surface is explicitly macOS-first.",
			},
			{
				label: "Local browser loop",
				text: "YEN's `yen web` and Browser Split flows target docs, HTTPS pages, localhost, and loopback URLs from terminal context.",
				source: yenDocsSource,
			},
			{
				label: "Review flow",
				text: "YEN keeps a read-only Git drawer and desktop PR review workspace close to the terminal without replacing Git itself.",
				source: yenDocsSource,
			},
		],
		relatedPaths: [
			"/alternatives/kitty",
			"/use-cases/terminal-with-native-browser-preview",
			"/use-cases/terminal-git-diff-drawer",
		],
	}),
	alternativePage({
		slug: "kitty",
		competitorName: "kitty",
		title: "kitty Alternative for macOS Terminal Workflows",
		description:
			"Compare kitty's GPU terminal and protocol extensions with YEN's macOS terminal, file browser, WebKit preview, and Git surfaces.",
		summary:
			"kitty is a fast, feature-rich terminal with its own protocol ecosystem. YEN is a macOS product surface that bundles terminal-adjacent workflows.",
		audience:
			"Use this page if graphics, keyboard handling, and terminal extensions matter, but you also want integrated macOS workflow affordances.",
		officialSources: [
			officialSource("kitty homepage", "https://sw.kovidgoyal.net/kitty/"),
			officialSource(
				"kitty graphics protocol",
				"https://sw.kovidgoyal.net/kitty/graphics-protocol/",
			),
		],
		decisionPoints: [
			{
				label: "Protocol depth",
				text: "kitty's public docs emphasize terminal graphics and protocol extensions; YEN's public docs emphasize shipped app workflows around the terminal.",
			},
			{
				label: "File previews",
				text: "YEN includes a bundled terminal file browser with Quick Look, incremental search, and syntax-highlighted code previews.",
				source: yenDocsSource,
			},
			{
				label: "macOS feel",
				text: "YEN uses native macOS surfaces for settings, browser preview, notifications, and app-level shortcuts.",
				source: yenDocsSource,
			},
		],
		relatedPaths: [
			"/alternatives/alacritty",
			"/use-cases/fast-gpu-terminal-for-macos",
			"/use-cases/terminal-with-native-browser-preview",
		],
	}),
	alternativePage({
		slug: "alacritty",
		competitorName: "Alacritty",
		title: "Alacritty Alternative for macOS Developers",
		description:
			"Compare Alacritty's OpenGL terminal approach with YEN's macOS terminal, command palette, file browser, dictation, and Git drawer.",
		summary:
			"Alacritty stays intentionally lean. YEN is for developers who still want speed, but also want opinionated local tools built into the app.",
		audience:
			"Use this page if you prefer minimal terminals and want to decide whether bundled workflow tools are useful or unnecessary for you.",
		officialSources: [
			officialSource("Alacritty homepage", "https://alacritty.org/"),
			officialSource(
				"Alacritty repository",
				"https://github.com/alacritty/alacritty",
			),
		],
		decisionPoints: [
			{
				label: "Minimal surface",
				text: "Alacritty focuses on being a terminal emulator and integrating with other apps; YEN intentionally includes more first-party workflow surfaces.",
			},
			{
				label: "Bundled tools",
				text: "YEN ships bundled developer CLIs including rg, fd, fzf, zoxide, bat, jq, lazygit, delta, btop, and fastfetch.",
				source: yenLlmsSource,
			},
			{
				label: "Input workflow",
				text: "YEN adds a native dictation path and command palette for users who want app-level shortcuts beyond terminal emulation.",
				source: yenDocsSource,
			},
		],
		relatedPaths: [
			"/alternatives/ghostty",
			"/alternatives/kitty",
			"/use-cases/macos-terminal-with-speech-to-text",
		],
	}),
	alternativePage({
		slug: "tabby",
		competitorName: "Tabby",
		title: "Tabby Alternative for Local Terminal Workflows",
		description:
			"Compare Tabby's terminal, SSH, serial, and plugin surface with YEN's macOS terminal, browser preview, Git drawer, and local tools.",
		summary:
			"Tabby is a configurable terminal, SSH, and serial client. YEN focuses on a macOS-native terminal with local browser, Git, file, dictation, and IDE command workflows.",
		audience:
			"Use this page if you need to decide whether remote connection management or local macOS workflow integration matters more for your daily terminal.",
		officialSources: [
			officialSource("Tabby repository", "https://github.com/Eugeny/tabby"),
			officialSource("Tabby site", "https://tabby.sh/"),
		],
		decisionPoints: [
			{
				label: "Connection surface",
				text: "Tabby's official repository describes a terminal, SSH, and serial client; YEN's public pages focus on local macOS terminal workflows rather than remote-session management.",
				source: officialSource(
					"Tabby repository",
					"https://github.com/Eugeny/tabby",
				),
			},
			{
				label: "Local app workflows",
				text: "YEN keeps terminal file browsing, WebKit preview, read-only Git review, and command-palette actions close to the shell.",
				source: yenDocsSource,
			},
			{
				label: "Bundled tools",
				text: "YEN ships bundled developer CLIs including rg, fd, fzf, zoxide, bat, jq, lazygit, delta, btop, and fastfetch.",
				source: yenLlmsSource,
			},
		],
		relatedPaths: [
			"/alternatives/wezterm",
			"/alternatives/kitty",
			"/use-cases/terminal-ide-local-workflows",
		],
	}),
	alternativePage({
		slug: "cursor",
		competitorName: "Cursor",
		title: "Cursor Alternative for Terminal-First Coding",
		description:
			"Compare Cursor's IDE and terminal agent workflows with YEN's terminal-first local IDE commands, browser preview, and Git surfaces.",
		summary:
			"Cursor provides coding agents in its editor and CLI. YEN is for developers who want the shell to remain the main workspace while still gaining local IDE-style helpers.",
		audience:
			"Use this page if you are choosing between moving more work into an AI IDE or strengthening the terminal workflows you already use.",
		officialSources: [
			officialSource("Cursor CLI", "https://cursor.com/cli"),
			officialSource("Cursor docs", "https://cursor.com/docs"),
		],
		decisionPoints: [
			{
				label: "Workspace center",
				text: "Cursor offers code editing and agents through its editor and terminal CLI; YEN centers shell, panes, local commands, browser preview, Git context, and bundled tools.",
			},
			{
				label: "IDE commands",
				text: "YEN exposes `yen ide` commands for doctor, search, LSP, diagnostics, devcontainers, workflow execution, testing, and verify gates.",
				source: yenLlmsSource,
			},
			{
				label: "Local evidence",
				text: "YEN's agent timeline and PR evidence surfaces are designed around local artifacts and explicit handoffs.",
				source: yenDocsSource,
			},
		],
		relatedPaths: [
			"/alternatives/vscode",
			"/use-cases/terminal-ide-local-workflows",
			"/use-cases/privacy-focused-ai-terminal",
		],
	}),
	alternativePage({
		slug: "zed",
		competitorName: "Zed",
		title: "Zed Alternative for Terminal-First Developers",
		description:
			"Compare Zed's collaborative AI editor model with YEN's terminal-first macOS workflows, local IDE commands, browser preview, and Git drawer.",
		summary:
			"Zed is a fast collaborative editor built around coding with humans and AI. YEN is a terminal-first macOS workspace for developers who want shell workflows to stay primary.",
		audience:
			"Use this page if you are choosing between moving daily work into an AI editor or keeping the terminal as the control plane with local helper surfaces.",
		officialSources: [
			officialSource("Zed homepage", "https://zed.dev/"),
			officialSource("Zed docs", "https://zed.dev/docs/"),
		],
		decisionPoints: [
			{
				label: "Workspace center",
				text: "Zed positions itself as a code editor for collaboration with humans and AI; YEN centers shell, panes, local commands, browser preview, Git context, and bundled tools.",
				source: officialSource("Zed homepage", "https://zed.dev/"),
			},
			{
				label: "Terminal IDE commands",
				text: "YEN exposes `yen ide` commands for doctor, search, LSP, diagnostics, devcontainers, workflow execution, testing, and verify gates.",
				source: yenLlmsSource,
			},
			{
				label: "Review context",
				text: "YEN's read-only Git drawer and PR evidence surfaces are designed around local artifacts and explicit handoffs.",
				source: yenDocsSource,
			},
		],
		relatedPaths: [
			"/alternatives/cursor",
			"/alternatives/vscode",
			"/use-cases/terminal-ide-local-workflows",
		],
	}),
	alternativePage({
		slug: "vscode",
		competitorName: "VS Code",
		title: "VS Code Terminal Alternative for Local Workflows",
		description:
			"Compare VS Code's agent and integrated terminal model with YEN's terminal-first local workflow, command palette, and native macOS tools.",
		summary:
			"VS Code is the extensible editor many teams standardize on. YEN is a terminal-first companion for developers who want local command workflows to remain primary.",
		audience:
			"Use this page if you work in VS Code today but want a stronger standalone terminal for local Git, browser, dictation, and IDE command loops.",
		officialSources: [
			officialSource(
				"VS Code agents overview",
				"https://code.visualstudio.com/docs/agents/overview",
			),
			officialSource(
				"VS Code terminal docs",
				"https://code.visualstudio.com/docs/terminal/basics",
			),
		],
		decisionPoints: [
			{
				label: "Editor vs terminal",
				text: "VS Code combines editor, terminal, extensions, and agents; YEN keeps the terminal as the durable control plane and connects local IDE commands around it.",
			},
			{
				label: "Migration bridge",
				text: "YEN includes VS Code inventory and import dry-run commands as part of its terminal IDE workflow set.",
				source: yenLlmsSource,
			},
			{
				label: "Native macOS surfaces",
				text: "YEN's Settings panel, browser preview, dictation, and Git drawer are built as native app workflows around the shell.",
				source: yenDocsSource,
			},
		],
		relatedPaths: [
			"/alternatives/cursor",
			"/use-cases/terminal-ide-local-workflows",
			"/use-cases/terminal-git-diff-drawer",
		],
	}),
	alternativePage({
		slug: "jetbrains-ai",
		competitorName: "JetBrains AI",
		title: "JetBrains AI Alternative for Terminal Workflows",
		description:
			"Compare JetBrains AI's IDE assistant workflows with YEN's terminal-first macOS commands, WebKit preview, Git drawer, and local tools.",
		summary:
			"JetBrains AI brings assistant workflows into JetBrains IDEs. YEN is for developers who want the terminal to remain the primary workspace while local IDE-style commands sit nearby.",
		audience:
			"Use this page if your decision is about IDE-centered assistance versus a terminal-centered workflow with native macOS companion surfaces.",
		officialSources: [
			officialSource(
				"JetBrains AI Assistant",
				"https://www.jetbrains.com/help/ai-assistant/about-ai-assistant.html",
			),
			officialSource("JetBrains AI IDEs", "https://www.jetbrains.com/ai-ides/"),
		],
		decisionPoints: [
			{
				label: "IDE integration",
				text: "JetBrains AI documentation describes AI assistance inside JetBrains IDE workflows; YEN centers shell, native browser preview, Git context, and local terminal IDE commands.",
				source: officialSource(
					"JetBrains AI Assistant",
					"https://www.jetbrains.com/help/ai-assistant/about-ai-assistant.html",
				),
			},
			{
				label: "Command palette",
				text: "YEN routes app actions, files, browser preview, Git review, and IDE commands through one command palette.",
				source: yenDocsSource,
			},
			{
				label: "Local evidence",
				text: "YEN's agent timeline and PR evidence surfaces are designed around local artifacts and explicit handoffs.",
				source: yenDocsSource,
			},
		],
		relatedPaths: [
			"/alternatives/cursor",
			"/alternatives/vscode",
			"/use-cases/terminal-ide-local-workflows",
		],
	}),
	alternativePage({
		slug: "devin-desktop",
		competitorName: "Devin Desktop",
		title: "Devin Desktop Alternative for Terminal Workflows",
		description:
			"Compare Devin's agent and embedded-IDE workflow with YEN's terminal-first macOS workflow, local commands, browser preview, and Git surfaces.",
		summary:
			"Devin centers delegated coding-agent work with an embedded IDE. YEN is a local macOS terminal workspace for developers who want shell, browser, Git, and IDE command loops in one app.",
		audience:
			"Use this page if you are comparing agent command-center workflows with a terminal-first environment that keeps local macOS surfaces explicit.",
		officialSources: [
			officialSource(
				"Devin introduction",
				"https://docs.devin.ai/get-started/devin-intro",
			),
			officialSource(
				"Devin session tools",
				"https://docs.devin.ai/work-with-devin/devin-session-tools",
			),
		],
		decisionPoints: [
			{
				label: "Agent workspace",
				text: "Devin's docs describe delegated agent work with an embedded IDE; YEN's public surface is a macOS terminal with local workflow tools and explicit review handoffs.",
				source: officialSource(
					"Devin introduction",
					"https://docs.devin.ai/get-started/devin-intro",
				),
			},
			{
				label: "Local review",
				text: "YEN includes a read-only local Git drawer for branch status, grouped file changes, raw diffs, and a bundled lazygit handoff.",
				source: yenDocsSource,
			},
			{
				label: "Browser loop",
				text: "YEN's native WebKit preview targets docs, HTTPS pages, localhost, and loopback URLs from terminal context.",
				source: yenDocsSource,
			},
		],
		relatedPaths: [
			"/alternatives/cursor",
			"/alternatives/jetbrains-ai",
			"/use-cases/terminal-ide-local-workflows",
		],
	}),
	alternativePage({
		slug: "claude-code",
		competitorName: "Claude Code",
		title: "Claude Code Alternative for Terminal Workflows",
		description:
			"Compare Claude Code's terminal agent workflow with YEN's macOS terminal, local IDE commands, browser preview, and Git drawer.",
		summary:
			"Claude Code is a terminal-based coding agent. YEN is a macOS terminal workspace that keeps local shell, browser, Git, dictation, and IDE command surfaces close together.",
		audience:
			"Use this page if you are deciding whether the main need is an agent in the terminal or a broader local terminal workspace for everyday development.",
		officialSources: [
			officialSource(
				"Claude Code overview",
				"https://code.claude.com/docs/en/overview",
			),
			officialSource(
				"How Claude Code works",
				"https://code.claude.com/docs/en/how-claude-code-works",
			),
		],
		decisionPoints: [
			{
				label: "Agent role",
				text: "Claude Code documentation describes an agentic coding tool for terminal workflows; YEN does not claim agent parity and instead documents local terminal, browser, Git, dictation, and IDE helper surfaces.",
				source: officialSource(
					"Claude Code overview",
					"https://code.claude.com/docs/en/overview",
				),
			},
			{
				label: "Terminal IDE commands",
				text: "YEN exposes `yen ide` commands for doctor, search, LSP, diagnostics, devcontainers, workflow execution, testing, and verify gates.",
				source: yenLlmsSource,
			},
			{
				label: "Evidence discipline",
				text: "YEN's docs describe shared evidence vocabulary and linked artifact blocks for review, workflow, and quality outputs.",
				source: yenDocsSource,
			},
		],
		relatedPaths: [
			"/alternatives/cursor",
			"/alternatives/codex-cli",
			"/use-cases/terminal-ide-local-workflows",
		],
	}),
	alternativePage({
		slug: "codex-cli",
		competitorName: "OpenAI Codex CLI",
		title: "Codex CLI Alternative for Terminal Workflows",
		description:
			"Compare OpenAI Codex CLI's local coding-agent workflow with YEN's macOS terminal, local commands, browser preview, and Git drawer.",
		summary:
			"OpenAI Codex CLI is a local terminal coding agent. YEN is a macOS terminal workspace for developers who want shell, native browser, Git, dictation, and local IDE command loops.",
		audience:
			"Use this page if you are comparing coding-agent terminal tools with a broader terminal app that keeps native macOS workflow surfaces nearby.",
		officialSources: [
			officialSource("Codex CLI", "https://learn.chatgpt.com/docs/codex/cli"),
			officialSource(
				"Codex CLI reference",
				"https://learn.chatgpt.com/docs/developer-commands?surface=cli",
			),
		],
		decisionPoints: [
			{
				label: "Agent surface",
				text: "OpenAI's Codex CLI docs describe a local coding agent that runs from the terminal; YEN's public docs describe a terminal app and local workflow surfaces rather than a replacement coding model.",
				source: officialSource(
					"Codex CLI",
					"https://learn.chatgpt.com/docs/codex/cli",
				),
			},
			{
				label: "Local app surfaces",
				text: "YEN keeps file browsing, native WebKit preview, read-only Git review, and command-palette actions close to the shell.",
				source: yenDocsSource,
			},
			{
				label: "Review workflow",
				text: "YEN's read-only Git drawer and PR evidence surfaces are designed around local artifacts and explicit handoffs.",
				source: yenDocsSource,
			},
		],
		relatedPaths: [
			"/alternatives/claude-code",
			"/alternatives/cursor",
			"/use-cases/terminal-ide-local-workflows",
		],
	}),
	createUseCasePage({
		slug: "macos-terminal-with-speech-to-text",
		title: "Speech-to-Text Terminal for macOS",
		description:
			"Use YEN when you want a macOS terminal with Option + Space dictation that can paste text into the shell or other Mac apps.",
		h1: "macOS terminal with speech-to-text",
		summary:
			"YEN's dictation path is built for developers who want voice input while they move between shell prompts, editors, browsers, and other macOS apps.",
		audience:
			"Use this page if your search is about reducing typing friction rather than choosing a cloud assistant.",
		decisionPoints: [
			{
				label: "Global shortcut",
				text: "Option + Space is the hold-to-dictate shortcut, with setup and permission recovery in native settings.",
				source: yenDocsSource,
			},
			{
				label: "Not just terminal",
				text: "The dictation flow is designed to paste into the active macOS target, so the terminal does not have to be the only destination.",
				source: yenDocsSource,
			},
			{
				label: "Privacy framing",
				text: "The public privacy page separates macOS speech recognition from website analytics, updates, and release hosting.",
				source: yenPrivacyLinkToSource(),
			},
		],
		relatedPaths: [
			"/alternatives/iterm2",
			"/alternatives/alacritty",
			"/use-cases/privacy-focused-ai-terminal",
		],
	}),
	createUseCasePage({
		slug: "terminal-with-native-browser-preview",
		title: "Terminal With Native Browser Preview",
		description:
			"Use YEN for a macOS terminal that can open docs, HTTPS pages, localhost, and loopback URLs in an isolated WebKit preview.",
		h1: "Terminal with native browser preview",
		summary:
			"YEN's browser preview is for developers who jump between terminal commands, local dev servers, docs, and web pages all day.",
		audience:
			"Use this page if context switching between a shell and browser is the workflow cost you are trying to reduce.",
		decisionPoints: [
			{
				label: "Localhost loop",
				text: "`yen web`, Browser, and Browser Split can target localhost, loopback, docs, and HTTPS pages from terminal context.",
				source: yenDocsSource,
			},
			{
				label: "Native runtime",
				text: "YEN uses WebKit for the preview and does not bundle a separate browser runtime.",
				source: yenDocsSource,
			},
			{
				label: "Explicit activation",
				text: "Terminal link capture is default-off and explicit-activation-only in the documented browser workflow.",
				source: yenDocsSource,
			},
		],
		relatedPaths: [
			"/alternatives/warp",
			"/alternatives/wezterm",
			"/use-cases/terminal-ide-local-workflows",
		],
	}),
	createUseCasePage({
		slug: "terminal-git-diff-drawer",
		title: "Terminal Git Diff Drawer for Local Repos",
		description:
			"Use YEN when you want a read-only native Git drawer with branch status, grouped changes, raw diffs, and lazygit handoff.",
		h1: "Terminal Git diff drawer for local repositories",
		summary:
			"YEN's Git drawer is a bottom overlay for checking local repository state without turning the terminal into a full Git client.",
		audience:
			"Use this page if you want quick repository awareness while keeping commits and advanced operations in your normal Git tools.",
		decisionPoints: [
			{
				label: "Read-only by design",
				text: "The local Git drawer is documented as read-only and shows branch/upstream state, grouped changes, stash file lists, and raw diffs.",
				source: yenDocsSource,
			},
			{
				label: "Shortcut",
				text: "Cmd + Shift + G toggles the drawer from the focused terminal context.",
				source: yenDocsSource,
			},
			{
				label: "Tool handoff",
				text: "YEN includes a bundled lazygit handoff for users who want a full terminal Git TUI after reviewing the drawer.",
				source: yenDocsSource,
			},
		],
		relatedPaths: [
			"/alternatives/vscode",
			"/alternatives/wezterm",
			"/use-cases/terminal-ide-local-workflows",
		],
	}),
	createUseCasePage({
		slug: "terminal-ide-local-workflows",
		title: "Terminal IDE Workflows Without Leaving the Shell",
		description:
			"Use YEN for local IDE-style terminal workflows: LSP, diagnostics, search, devcontainers, test runs, verification, and PR evidence.",
		h1: "Terminal IDE workflows without leaving the shell",
		summary:
			"YEN is not trying to replace editors. It adds local IDE-style commands to the terminal so build, test, review, and evidence loops stay close to the shell.",
		audience:
			"Use this page if you already trust terminal workflows and want structured local helpers without centering an editor.",
		decisionPoints: [
			{
				label: "Local command set",
				text: "`yen ide` includes doctor, trust, debug, LSP, diagnostics, search, devcontainer, test, format, lint, fix, verify, gate, workflow, and PR-review commands.",
				source: yenLlmsSource,
			},
			{
				label: "Command palette access",
				text: "The macOS command palette exposes terminal IDE actions alongside files, browser preview, Git review, settings, and app actions.",
				source: yenDocsSource,
			},
			{
				label: "Evidence discipline",
				text: "YEN's docs describe shared evidence vocabulary and linked artifact blocks for review, workflow, and quality outputs.",
				source: yenDocsSource,
			},
		],
		relatedPaths: [
			"/alternatives/cursor",
			"/alternatives/vscode",
			"/use-cases/terminal-git-diff-drawer",
		],
	}),
	createUseCasePage({
		slug: "privacy-focused-ai-terminal",
		title: "Privacy-Focused Terminal Workflows",
		description:
			"Use YEN when you want local-first terminal workflows with clear privacy boundaries for dictation, website analytics, and updates.",
		h1: "Privacy-focused terminal workflows",
		summary:
			"YEN's public privacy posture is not a blanket no-third-party claim. It is a source-of-truth map for what runs locally and which services are involved.",
		audience:
			"Use this page if you want product copy to be precise about local workflows, analytics, updates, and release hosting.",
		decisionPoints: [
			{
				label: "Precise service map",
				text: "The privacy page names the desktop, website, release, and service-provider boundaries instead of making absolute claims.",
				source: yenPrivacyLinkToSource(),
			},
			{
				label: "On-device dictation framing",
				text: "YEN's docs describe built-in dictation through macOS speech recognition, with permission and recovery states handled in the app.",
				source: yenDocsSource,
			},
			{
				label: "Local artifacts",
				text: "YEN's terminal IDE and agent surfaces emphasize local state, explicit exports, and redacted short-retention artifacts.",
				source: yenDocsSource,
			},
		],
		relatedPaths: [
			"/alternatives/warp",
			"/alternatives/cursor",
			"/use-cases/macos-terminal-with-speech-to-text",
		],
	}),
	createUseCasePage({
		slug: "fast-gpu-terminal-for-macos",
		title: "Fast GPU Terminal for macOS",
		description:
			"Use YEN when you want a macOS terminal with Metal rendering, native settings, tabs, splits, themes, browser preview, and local tools.",
		h1: "Fast GPU terminal for macOS",
		summary:
			"YEN's speed story is tied to a practical macOS terminal surface: Metal rendering, native app controls, curated themes, and workflow tools.",
		audience:
			"Use this page if terminal rendering speed matters, but you also want to inspect the surrounding day-to-day workflow features.",
		decisionPoints: [
			{
				label: "Rendering claim",
				text: "YEN uses GPU-accelerated Metal rendering. Frame rate and latency depend on hardware and workload; no fixed performance guarantee is published.",
				source: yenLlmsSource,
			},
			{
				label: "Native controls",
				text: "YEN includes native macOS settings with a live preview: appearance and themes, general and workspace behavior, notifications, dictation, and keyboard shortcuts.",
				source: yenDocsSource,
			},
			{
				label: "Daily workflow",
				text: "Tabs, splits, a tab sidebar, scratchpad, split layout presets, Quick Terminal, and window restoration are part of the documented app surface.",
				source: yenDocsSource,
			},
		],
		relatedPaths: [
			"/alternatives/ghostty",
			"/alternatives/kitty",
			"/alternatives/alacritty",
		],
	}),
] as const satisfies readonly PublicLibraryPage[];

const PUBLIC_LIBRARY_LLMS_EXCLUDED_PATHS = ["/alternatives/ghostty"] as const;

function yenPrivacyLinkToSource(): PublicLibrarySource {
	return officialSource("YEN privacy policy", `${SITE_URL}/terms`);
}

export function getPublicLibraryPagesByKind(kind: PublicLibraryPageKind) {
	return PUBLIC_LIBRARY_PAGES.filter(
		(page) => page.kind === kind && isPublicLibraryPageEligible(page),
	);
}

export function getAlternativePage(slug: string) {
	return getPublicLibraryPagesByKind("alternative").find(
		(page) => page.slug === slug,
	);
}

export function getUseCasePage(slug: string) {
	return getPublicLibraryPagesByKind("use-case").find(
		(page) => page.slug === slug,
	);
}

export function getPublicLibraryPageByPath(path: string) {
	return PUBLIC_LIBRARY_PAGES.find((page) => page.path === path);
}

export function isPublicLibraryPageEligible(page: PublicLibraryPage) {
	return (
		page.publicEligible &&
		page.evidenceScore >= PUBLIC_LIBRARY_MIN_EVIDENCE_SCORE
	);
}

export function isPublicLibraryPageLlmsDiscoverable(page: PublicLibraryPage) {
	return !PUBLIC_LIBRARY_LLMS_EXCLUDED_PATHS.some(
		(excludedPath) => excludedPath === page.path,
	);
}

export function getPublicLibrarySitemapEntries(): MetadataRoute.Sitemap {
	const entries: MetadataRoute.Sitemap = [];

	for (const page of PUBLIC_LIBRARY_PAGES) {
		if (!isPublicLibraryPageEligible(page)) {
			continue;
		}

		entries.push({
			url: `${SITE_URL}${page.path}`,
			lastModified: page.lastModified,
			changeFrequency: "monthly",
			priority: page.kind === "alternative" ? 0.74 : 0.72,
		});
	}

	return entries;
}
