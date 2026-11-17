/**
 * Terminal Panel
 *
 * Shared chrome for the "terminal-window" mockups: the traffic-light dots
 * header (optionally with a title) plus a content area. Extracted so the dots
 * header markup lives in one place instead of being copy-pasted at every call
 * site. Defaults to a horizontally-scrollable content area for tables; pass
 * `contentClassName` to override (e.g. a padded frame for an embed). For
 * copyable command examples use TerminalCodeBlock instead.
 */

import type { ReactNode } from "react";

interface TerminalPanelProps {
	className?: string;
	/** Optional right-aligned title shown in the header bar. */
	title?: string;
	/** Content-wrapper classes. Defaults to a scrollable area for tables. */
	contentClassName?: string;
	children: ReactNode;
}

export function TerminalPanel({
	className,
	title,
	contentClassName = "overflow-x-auto",
	children,
}: TerminalPanelProps) {
	return (
		<div className={`terminal-window${className ? ` ${className}` : ""}`}>
			<div className="terminal-header">
				<div className="terminal-dots" aria-hidden="true">
					<div className="terminal-dot bg-terminal-dot-red" />
					<div className="terminal-dot bg-terminal-dot-yellow" />
					<div className="terminal-dot bg-terminal-dot-green" />
				</div>
				{title && (
					<span className="ml-auto text-xs text-text-tertiary font-mono">
						{title}
					</span>
				)}
			</div>
			<div className={contentClassName}>{children}</div>
		</div>
	);
}
