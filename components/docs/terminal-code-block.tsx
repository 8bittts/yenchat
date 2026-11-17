"use client";

import { useState } from "react";

interface TerminalCodeBlockProps {
	code: string;
	title?: string;
	showPrompt?: boolean;
	/**
	 * When true, long content wraps (whitespace-pre-wrap) instead of scrolling
	 * horizontally. Use for prose-style copyable blocks (e.g. a paragraph prompt)
	 * rather than single-line commands.
	 */
	wrap?: boolean;
}

export function TerminalCodeBlock({
	code,
	title,
	showPrompt = false,
	wrap = false,
}: TerminalCodeBlockProps) {
	const [status, setStatus] = useState<"idle" | "copied" | "error">("idle");

	const handleCopy = async () => {
		try {
			await navigator.clipboard.writeText(code);
			setStatus("copied");
		} catch {
			setStatus("error");
		}
		setTimeout(() => setStatus("idle"), 2000);
	};

	const label =
		status === "copied"
			? "Copied!"
			: status === "error"
				? "Copy failed"
				: "Copy";

	return (
		<div className="rounded-lg overflow-hidden border border-code-border bg-code-bg">
			{/* Header with dots and optional title */}
			<div className="flex items-center justify-between px-4 py-2 bg-code-header-bg border-b border-code-border">
				<div className="flex items-center gap-3">
					<div className="flex gap-1.5" aria-hidden="true">
						<div className="size-3 rounded-full bg-terminal-dot-red" />
						<div className="size-3 rounded-full bg-terminal-dot-yellow" />
						<div className="size-3 rounded-full bg-terminal-dot-green" />
					</div>
					{title && (
						<span className="text-xs font-mono text-code-text-muted">
							{title}
						</span>
					)}
				</div>
				<button
					type="button"
					onClick={handleCopy}
					className="text-xs text-code-text-muted hover:text-code-text transition-colors focus:outline-hidden focus:ring-2 focus:ring-brand focus:ring-offset-2 focus:ring-offset-code-bg rounded px-2 py-1"
					aria-label={status === "idle" ? "Copy code" : label}
				>
					{label}
				</button>
				<span className="sr-only" role="status" aria-live="polite">
					{status === "copied"
						? "Code copied to clipboard"
						: status === "error"
							? "Copy failed"
							: ""}
				</span>
			</div>

			{/* Code content */}
			<div className={`p-4 ${wrap ? "" : "overflow-x-auto"}`}>
				<pre
					className={`text-sm font-mono text-code-text ${
						wrap ? "whitespace-pre-wrap break-words" : "whitespace-pre"
					}`}
				>
					{showPrompt && <span className="text-brand select-none">$ </span>}
					{code}
				</pre>
			</div>
		</div>
	);
}
