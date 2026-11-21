import type { DocNavItem } from "@/components/docs/doc-nav";
import { buildPublicPageMetadata, PUBLIC_PAGE_SEO } from "@/lib/seo";
import { DocsPageClient } from "./docs-client";

export const metadata = buildPublicPageMetadata(PUBLIC_PAGE_SEO.docs);

const navItems: DocNavItem[] = [
	{ id: "install", title: "Install" },
	{
		id: "terminal-ide",
		title: "Workspace",
		children: [
			{ id: "tab-sidebar", title: "Tab Sidebar" },
			{ id: "split-pane-labels", title: "Split Labels" },
			{ id: "persistent-sessions", title: "Persistent Sessions" },
		],
	},
	{ id: "clipboard", title: "Clipboard & Paste" },
	{ id: "ide-workflows", title: "IDE Workflows" },
	{ id: "agent-token-usage", title: "Agent Token Usage" },
	{ id: "voice-dictation", title: "Speech-to-Text" },
	{ id: "settings", title: "Settings" },
	{ id: "file-browser", title: "File Browser" },
	{ id: "browser-preview", title: "Browser Preview" },
	{ id: "automation", title: "macOS Automation" },
	{ id: "commands", title: "Commands & Shortcuts" },
	{ id: "troubleshooting", title: "Troubleshooting" },
];

export default function DocsPage() {
	return <DocsPageClient navItems={navItems} />;
}
