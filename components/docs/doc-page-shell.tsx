"use client";

/**
 * Documentation Page Shell
 *
 * Responsive 2-column layout with fixed left sidebar on desktop.
 * Used by docs, privacy, terms, and release pages.
 * Single layout that works for both mobile and desktop to avoid duplicate IDs.
 */

import { type ReactNode, useState } from "react";
import { Footer } from "@/components/shared/footer";
import { Header } from "@/components/shared/header";
import { DocNav, type DocNavItem, DocNavMobile } from "./doc-nav";

interface DocPageShellProps {
	currentPage?: "home" | "docs";
	navItems: DocNavItem[];
	hero?: ReactNode;
	/** Centered guide, equal halves, or viewport-wide narrow navigation. */
	variant?: "half" | "narrow" | "guide";
	children: ReactNode;
	/** Origin for shared header and footer links; see Header. */
	siteOrigin?: string;
}

const layouts = {
	half: {
		frame: "flex-1 lg:flex",
		sidebar: "lg:w-1/2 lg:flex-shrink-0 lg:border-r lg:border-border",
		sidebarContent: "container-page py-8 lg:pt-10 lg:docs-sidebar-fixed",
		hero: "lg:max-w-xl lg:ml-auto lg:pr-6",
		main: "lg:w-1/2 lg:flex-shrink-0",
		content:
			"container-page py-8 lg:px-6 lg:pt-10 border-t border-border lg:border-t-0",
		contentInner: "lg:max-w-xl",
	},
	narrow: {
		frame: "flex-1 lg:flex",
		sidebar: "lg:w-72 lg:flex-shrink-0 lg:border-r lg:border-border",
		sidebarContent:
			"px-4 sm:px-6 py-8 lg:pt-10 lg:sticky lg:top-[var(--header-height)] lg:h-[calc(100dvh-var(--header-height))] lg:overflow-y-auto",
		hero: "",
		main: "lg:flex-1 min-w-0",
		content:
			"px-4 sm:px-6 py-8 lg:pt-10 lg:pl-8 max-w-[1800px] border-t border-border lg:border-t-0",
		contentInner: "",
	},
	guide: {
		frame: "container-page w-full flex-1 lg:flex",
		sidebar: "lg:w-1/3 lg:flex-shrink-0 lg:border-r lg:border-border",
		sidebarContent:
			"py-8 lg:pt-10 lg:pr-6 lg:sticky lg:top-[var(--header-height)] lg:h-[calc(100dvh-var(--header-height))] lg:overflow-y-auto",
		hero: "",
		main: "lg:w-2/3 min-w-0",
		content: "py-8 lg:pt-10 lg:pl-6 border-t border-border lg:border-t-0",
		contentInner: "",
	},
};

export function DocPageShell({
	currentPage,
	navItems,
	hero,
	variant = "half",
	children,
	siteOrigin,
}: DocPageShellProps) {
	const [mobileNavOpen, setMobileNavOpen] = useState(false);
	const layout = layouts[variant];

	return (
		<div className="min-h-dvh flex flex-col bg-background text-text-primary">
			<a href="#main-content" className="skip-link">
				Skip to main content
			</a>

			<Header
				currentPage={currentPage}
				onMobileNavToggle={setMobileNavOpen}
				mobileNavOpen={mobileNavOpen}
				siteOrigin={siteOrigin}
			/>

			<DocNavMobile
				items={navItems}
				open={mobileNavOpen}
				onClose={() => setMobileNavOpen(false)}
			/>

			<div className={layout.frame}>
				<div className={layout.sidebar}>
					<div className={layout.sidebarContent}>
						<div className={layout.hero}>
							{hero}
							<div className="mt-6">
								<DocNav items={navItems} />
							</div>
						</div>
					</div>
				</div>

				<main id="main-content" className={layout.main}>
					<div className={layout.content}>
						<div className={layout.contentInner}>
							<div className="content-spacing-lg">{children}</div>
						</div>
					</div>
				</main>
			</div>

			<Footer siteOrigin={siteOrigin} />
		</div>
	);
}
