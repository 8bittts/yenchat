"use client";

import { ThemeProvider as NextThemesProvider, useTheme } from "next-themes";
import type { ReactNode } from "react";
import { useEffect } from "react";
import { COLORS } from "@/app/constants";

interface ThemeProviderProps {
	children: ReactNode;
	nonce?: string | undefined;
}

function ThemeMetaSync() {
	const { resolvedTheme } = useTheme();

	useEffect(() => {
		const color =
			resolvedTheme === "dark" ? COLORS.backgroundDark : COLORS.background;

		for (const name of ["theme-color", "msapplication-TileColor"]) {
			const metas = document.querySelectorAll<HTMLMetaElement>(
				`meta[name="${name}"]`,
			);
			for (const meta of metas) {
				meta.content = color;
			}
		}
	}, [resolvedTheme]);

	return null;
}

export function ThemeProvider({ children, nonce }: ThemeProviderProps) {
	return (
		<NextThemesProvider
			attribute="class"
			defaultTheme="light"
			enableSystem={false}
			enableColorScheme
			disableTransitionOnChange
			{...(nonce === undefined ? {} : { nonce })}
		>
			<ThemeMetaSync />
			{children}
		</NextThemesProvider>
	);
}
