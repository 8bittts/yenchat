"use client";

import Image from "next/image";
import Link from "next/link";
import { trackProductEvent } from "@/lib/analytics/product-analytics";
import { ThemeToggle } from "./theme-toggle";

interface HeaderProps {
	currentPage?: "home" | "docs" | "tunes" | undefined;
	onMobileNavToggle?: (open: boolean) => void;
	mobileNavOpen?: boolean;
	/**
	 * Origin prefixed to internal links. blog.yen.chat passes yen.chat, because
	 * there "/" is the blog index and other paths only reach yen.chat by redirect.
	 */
	siteOrigin?: string | undefined;
}

export function Header({
	currentPage = "home",
	onMobileNavToggle,
	mobileNavOpen = false,
	siteOrigin = "",
}: HeaderProps) {
	const handleToggle = () => {
		onMobileNavToggle?.(!mobileNavOpen);
	};

	return (
		<>
			<header className="bg-background border-b border-border py-3 md:py-4">
				<div className="container-page flex items-center justify-between">
					<Link
						href={`${siteOrigin}/`}
						className="flex items-center gap-3 text-heading-sm text-text-primary hover:text-brand-dark transition focus-ring rounded"
						aria-label="YEN - home"
						onClick={() => trackProductEvent("header_click", { item: "Logo" })}
					>
						<Image
							src="/yen-logo-square-128.png"
							alt=""
							className="rounded-lg"
							width={32}
							height={32}
						/>
						<span>YEN</span>
					</Link>

					{/* Desktop navigation */}
					<nav
						className="hidden md:flex gap-6 items-center"
						aria-label="Primary navigation"
					>
						<Link
							href={`${siteOrigin}/docs`}
							aria-current={currentPage === "docs" ? "page" : undefined}
							className={`nav-link ${
								currentPage === "docs" ? "nav-link-active" : "nav-link-inactive"
							}`}
							onClick={() =>
								trackProductEvent("header_click", { item: "Docs" })
							}
						>
							Docs
						</Link>
						<a
							href="https://twitter.com/yenFTW"
							className="nav-link nav-link-inactive"
							target="_blank"
							rel="noopener noreferrer"
							onClick={() =>
								trackProductEvent("header_click", { item: "Twitter" })
							}
						>
							@yenFTW
						</a>
						<ThemeToggle />
					</nav>

					{/* Mobile navigation */}
					<nav
						className="md:hidden flex items-center gap-2"
						aria-label="Mobile primary navigation"
					>
						<ThemeToggle />
						<button
							type="button"
							onClick={handleToggle}
							className="p-2.5 text-text-primary hover:bg-card-header rounded-md transition focus-ring"
							aria-label="Toggle navigation menu"
							aria-expanded={mobileNavOpen}
							aria-controls="mobile-site-nav"
						>
							<svg
								className="size-6"
								fill="none"
								stroke="currentColor"
								viewBox="0 0 24 24"
								aria-hidden="true"
							>
								<title>{mobileNavOpen ? "Close menu" : "Open menu"}</title>
								<path
									strokeLinecap="round"
									strokeLinejoin="round"
									strokeWidth={2}
									d={
										mobileNavOpen
											? "M6 18L18 6M6 6l12 12"
											: "M4 6h16M4 12h16M4 18h16"
									}
								/>
							</svg>
						</button>
					</nav>
				</div>
			</header>

			{/* Mobile menu dropdown - shows main nav links when menu is open.
			    Always mounted (toggled via the `hidden` attribute) so the
			    aria-controls="mobile-site-nav" target always resolves to a real
			    DOM node, per the design-system a11y rule. */}
			<nav
				id="mobile-site-nav"
				aria-label="Mobile site navigation"
				className="mobile-menu-dropdown"
				hidden={!mobileNavOpen}
			>
				<div className="mobile-menu-container">
					<div className="text-sm text-text-muted flex items-center gap-6 flex-wrap">
						<Link
							href={`${siteOrigin}/docs`}
							className="mobile-menu-link"
							onClick={() =>
								trackProductEvent("header_click", {
									item: "Docs",
									mobile: true,
								})
							}
						>
							Docs
						</Link>
						<a
							href="https://twitter.com/yenFTW"
							className="mobile-menu-link"
							target="_blank"
							rel="noopener noreferrer"
							onClick={() =>
								trackProductEvent("header_click", {
									item: "Twitter",
									mobile: true,
								})
							}
						>
							@yenFTW
						</a>
					</div>
				</div>
			</nav>
		</>
	);
}
