"use client";

/**
 * Global Error Handler
 *
 * Catches unhandled errors in the root layout.
 * Must import globals.css — this route replaces the root layout.
 */

import "./globals.css";

export default function GlobalError({
	reset,
}: {
	error: Error & { digest?: string };
	reset: () => void;
}) {
	return (
		<html lang="en">
			<body className="ph-site flex min-h-dvh items-center justify-center bg-background text-text-primary antialiased">
				<main className="ph-wrap ed-error">
					<h1 className="text-heading-md">Something went wrong</h1>
					<p className="ph-lede">Please try again or refresh the page.</p>
					<button type="button" onClick={reset} className="ph-primary mt-4">
						Try again
					</button>
				</main>
			</body>
		</html>
	);
}
