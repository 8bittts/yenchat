"use client";

import { useTheme } from "next-themes";
import { useEffect, useState } from "react";
import { trackProductEvent } from "@/lib/analytics/product-analytics";

export function ThemeToggle() {
	// `mounted` is read by the early-return below — useRef would skip the post-mount re-render that swaps the placeholder for the real icon.
	// react-doctor-disable-next-line react-doctor/rerender-state-only-in-handlers
	const [mounted, setMounted] = useState(false);
	const { resolvedTheme, setTheme } = useTheme();

	// Canonical next-themes hydration guard: render a placeholder until client mount, then swap. Trades a one-frame flash for SSR/CSR consistency.
	// react-doctor-disable-next-line react-doctor/rendering-hydration-no-flicker
	useEffect(() => {
		setMounted(true);
	}, []);

	if (!mounted) {
		return (
			<button
				type="button"
				disabled
				className="p-2.5 rounded-md text-text-muted"
				aria-label="Toggle theme"
			>
				<svg
					className="size-4"
					fill="none"
					stroke="currentColor"
					viewBox="0 0 24 24"
					aria-hidden="true"
				>
					<circle cx="12" cy="12" r="5" strokeWidth={2} />
					<path
						strokeLinecap="round"
						strokeWidth={2}
						d="M12 1v2M12 21v2M4.22 4.22l1.42 1.42M18.36 18.36l1.42 1.42M1 12h2M21 12h2M4.22 19.78l1.42-1.42M18.36 5.64l1.42-1.42"
					/>
				</svg>
			</button>
		);
	}

	const isDark = resolvedTheme === "dark";

	const handleToggle = () => {
		const newTheme = isDark ? "light" : "dark";
		setTheme(newTheme);
		trackProductEvent("theme_toggle", { theme: newTheme });
	};

	return (
		<button
			type="button"
			onClick={handleToggle}
			className="p-2.5 rounded-md text-text-muted hover:text-text-primary hover:bg-card-header transition-colors focus-ring"
			aria-pressed={isDark}
			aria-label={isDark ? "Switch to light mode" : "Switch to dark mode"}
		>
			{isDark ? (
				<svg
					className="size-4"
					fill="none"
					stroke="currentColor"
					viewBox="0 0 24 24"
					aria-hidden="true"
				>
					<circle cx="12" cy="12" r="5" strokeWidth={2} />
					<path
						strokeLinecap="round"
						strokeWidth={2}
						d="M12 1v2M12 21v2M4.22 4.22l1.42 1.42M18.36 18.36l1.42 1.42M1 12h2M21 12h2M4.22 19.78l1.42-1.42M18.36 5.64l1.42-1.42"
					/>
				</svg>
			) : (
				<svg
					className="size-4"
					fill="none"
					stroke="currentColor"
					viewBox="0 0 24 24"
					aria-hidden="true"
				>
					<path
						strokeLinecap="round"
						strokeLinejoin="round"
						strokeWidth={2}
						d="M21 12.79A9 9 0 1111.21 3 7 7 0 0021 12.79z"
					/>
				</svg>
			)}
		</button>
	);
}
