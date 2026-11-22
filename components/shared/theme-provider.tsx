"use client";

import { ThemeProvider as NextThemesProvider } from "next-themes";
import type { ReactNode } from "react";

interface ThemeProviderProps {
	children: ReactNode;
	nonce?: string | undefined;
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
			{children}
		</NextThemesProvider>
	);
}
