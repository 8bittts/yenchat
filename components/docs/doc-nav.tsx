"use client";

import { useEffect, useMemo, useState } from "react";

export interface DocNavItem {
	id: string;
	title: string;
	children?: { id: string; title: string }[];
}

interface DocNavProps {
	items: DocNavItem[];
}

export function DocNav({ items }: DocNavProps) {
	const [activeId, setActiveId] = useState<string>("");
	const navIds = useMemo(() => {
		const ids = new Set<string>();

		for (const item of items) {
			ids.add(item.id);
			if (item.children) {
				for (const child of item.children) {
					ids.add(child.id);
				}
			}
		}

		return ids;
	}, [items]);

	useEffect(() => {
		const observer = new IntersectionObserver(
			(entries) => {
				for (const entry of entries) {
					if (entry.isIntersecting && navIds.has(entry.target.id)) {
						setActiveId(entry.target.id);
					}
				}
			},
			{
				// Active-section detection band: the top inset (~--header-height plus
				// buffer) delays activation until a heading is comfortably in view.
				// This is observer tuning, not anchor-landing offset.
				rootMargin: "-100px 0px -60% 0px",
				threshold: 0,
			},
		);

		// Only observe sections that match our nav items
		for (const id of navIds) {
			const element = document.getElementById(id);
			if (element) {
				observer.observe(element);
			}
		}

		return () => observer.disconnect();
	}, [navIds]);

	const handleClick = (event: React.MouseEvent<HTMLAnchorElement>) => {
		event.preventDefault();
		const id = event.currentTarget.getAttribute("href")?.slice(1);
		if (!id || !navIds.has(id)) {
			return;
		}
		const element = document.getElementById(id);
		if (element) {
			const prefersReducedMotion =
				typeof window !== "undefined" &&
				window.matchMedia("(prefers-reduced-motion: reduce)").matches;
			element.scrollIntoView({
				behavior: prefersReducedMotion ? "auto" : "smooth",
				block: "start",
			});
			// Update URL hash without jumping
			window.history.pushState(null, "", `#${id}`);
			setActiveId(id);
		}
	};

	return (
		<nav
			className="hidden lg:block"
			aria-label="Documentation table of contents"
		>
			<ul className="space-y-2 text-sm">
				{items.map((item) => (
					<li key={item.id}>
						<a
							href={`#${item.id}`}
							onClick={handleClick}
							aria-current={activeId === item.id ? "page" : undefined}
							className={`block py-1 font-bold transition hover:text-text-primary focus-ring rounded ${
								activeId === item.id ? "text-brand-dark" : "text-text-primary"
							}`}
						>
							{item.title}
						</a>
						{item.children && (
							<ul className="ml-4 mt-1 space-y-1">
								{item.children.map((child) => (
									<li key={child.id}>
										<a
											href={`#${child.id}`}
											onClick={handleClick}
											aria-current={activeId === child.id ? "page" : undefined}
											className={`block py-1 transition hover:text-text-primary focus-ring rounded ${
												activeId === child.id
													? "nav-link-active"
													: "text-text-muted"
											}`}
										>
											{child.title}
										</a>
									</li>
								))}
							</ul>
						)}
					</li>
				))}
			</ul>
		</nav>
	);
}

interface DocNavMobileProps extends DocNavProps {
	open?: boolean;
	onClose?: () => void;
}

export function DocNavMobile({
	items,
	open = false,
	onClose,
}: DocNavMobileProps) {
	if (!open) {
		return null;
	}

	return (
		<div className="mobile-menu-dropdown">
			<div className="mobile-menu-container">
				<p className="eyebrow-text mb-2 text-text-muted">On this page</p>
				<nav id="mobile-doc-nav" aria-label="Documentation navigation">
					<ul className="space-y-1 text-sm">
						{items.map((item) => (
							<li key={item.id}>
								<a
									href={`#${item.id}`}
									onClick={onClose}
									className="block py-2 text-text-muted hover:text-text-primary transition focus-ring rounded"
								>
									{item.title}
								</a>
								{item.children && (
									<ul className="ml-4 mt-1 space-y-1">
										{item.children.map((child) => (
											<li key={child.id}>
												<a
													href={`#${child.id}`}
													onClick={onClose}
													className="block py-1 text-text-muted hover:text-text-primary transition focus-ring rounded"
												>
													{child.title}
												</a>
											</li>
										))}
									</ul>
								)}
							</li>
						))}
					</ul>
				</nav>
			</div>
		</div>
	);
}
