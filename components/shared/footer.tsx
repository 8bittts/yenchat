"use client";

import Link from "next/link";
import { trackProductEvent } from "@/lib/analytics/product-analytics";

interface FooterProps {
	/**
	 * Origin prefixed to internal links. blog.yen.chat passes yen.chat, because
	 * there "/" is the blog index and other paths only reach yen.chat by redirect.
	 */
	siteOrigin?: string | undefined;
}

export function Footer({ siteOrigin = "" }: FooterProps) {
	return (
		<footer className="relative z-10 bg-background border-t border-border pt-3 pb-[calc(0.75rem+env(safe-area-inset-bottom))] md:py-4">
			<div className="container-page flex flex-col items-start gap-3 sm:flex-row sm:items-center sm:justify-between">
				{/* Navigation links */}
				<nav
					className="flex flex-wrap items-center gap-3 md:gap-6"
					aria-label="Footer navigation"
				>
					<a
						href="https://blog.yen.chat/"
						className="nav-link nav-link-inactive"
						target="_blank"
						rel="noopener noreferrer"
						onClick={() =>
							trackProductEvent("footer_click", { item: "Substack" })
						}
					>
						Onigiri
					</a>
					<Link
						href={`${siteOrigin}/tunes`}
						className="nav-link nav-link-inactive"
						onClick={() => trackProductEvent("footer_click", { item: "Music" })}
					>
						Music
					</Link>
					<a
						href="https://btc.email"
						className="nav-link nav-link-inactive"
						target="_blank"
						rel="noopener noreferrer"
						onClick={() =>
							trackProductEvent("footer_click", { item: "Bitcoin Email" })
						}
					>
						Bitcoin Email
					</a>
					<a
						href="https://jpthecat.com"
						className="nav-link nav-link-inactive"
						target="_blank"
						rel="noopener noreferrer"
						onClick={() =>
							trackProductEvent("footer_click", { item: "JP the Cat" })
						}
					>
						JP the Cat
					</a>
					<a
						href="https://github.com/8bittts/yenchat"
						className="nav-link nav-link-inactive"
						target="_blank"
						rel="noopener noreferrer"
						onClick={() =>
							trackProductEvent("footer_click", { item: "GitHub" })
						}
					>
						GitHub
					</a>
				</nav>

				{/* Legal + Copyright */}
				<div className="flex w-full items-baseline gap-3 sm:w-auto md:gap-6">
					<nav
						className="flex items-center gap-3 whitespace-nowrap md:gap-6"
						aria-label="Legal"
					>
						<Link
							href={`${siteOrigin}/terms`}
							className="nav-link nav-link-inactive"
							onClick={() =>
								trackProductEvent("footer_click", { item: "Terms" })
							}
						>
							Terms
						</Link>
					</nav>
					<p className="text-body-xs hidden md:block" suppressHydrationWarning>
						YEN © {new Date().getFullYear()}
					</p>
				</div>
			</div>
		</footer>
	);
}
