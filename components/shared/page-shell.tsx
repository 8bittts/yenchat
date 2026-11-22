"use client";

import type { ReactNode } from "react";
import { useState } from "react";
import { Footer } from "@/components/shared/footer";
import { Header } from "@/components/shared/header";

interface PageShellProps {
	currentPage?: "home" | "docs";
	mainClassName?: string;
	siteOrigin?: string;
	children: ReactNode;
}

export function PageShell({
	currentPage,
	mainClassName = "flex-1",
	siteOrigin = "",
	children,
}: PageShellProps) {
	const [mobileNavOpen, setMobileNavOpen] = useState(false);

	return (
		<div className="ph-site min-h-dvh flex flex-col bg-background text-text-primary">
			<a href="#main-content" className="skip-link">
				Skip to main content
			</a>
			<Header
				currentPage={currentPage}
				siteOrigin={siteOrigin}
				mobileNavOpen={mobileNavOpen}
				onMobileNavToggle={setMobileNavOpen}
			/>
			<main id="main-content" className={mainClassName}>
				{children}
			</main>
			<Footer siteOrigin={siteOrigin} />
		</div>
	);
}
