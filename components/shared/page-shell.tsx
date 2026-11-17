"use client";

import type { ReactNode } from "react";
import { useState } from "react";
import { Footer } from "@/components/shared/footer";
import { Header } from "@/components/shared/header";

interface PageShellProps {
	currentPage?: "home" | "docs" | "tunes";
	mainClassName?: string;
	children: ReactNode;
}

/**
 * Shared page frame for the forward-only shells (home, tunes, not-found,
 * library): a `min-h-dvh` flex column with the skip link, Header (which owns
 * the mobile-nav toggle state), `main#main-content`, and Footer. Shells that
 * READ the mobile-nav state (docs) keep their own frame.
 */
export function PageShell({
	currentPage,
	mainClassName = "flex-1",
	children,
}: PageShellProps) {
	const [mobileNavOpen, setMobileNavOpen] = useState(false);

	return (
		<div className="min-h-dvh flex flex-col bg-background text-text-primary">
			<a href="#main-content" className="skip-link">
				Skip to main content
			</a>
			<Header
				currentPage={currentPage}
				mobileNavOpen={mobileNavOpen}
				onMobileNavToggle={setMobileNavOpen}
			/>
			<main id="main-content" className={mainClassName}>
				{children}
			</main>
			<Footer />
		</div>
	);
}
