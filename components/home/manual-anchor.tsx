"use client";
import { useEffect } from "react";

// Open the chapter for direct links, same-page links and browser history.
function revealChapter() {
	const target = document.getElementById(window.location.hash.slice(1));
	const chapter = target?.closest("details");
	if (!target || !chapter || chapter.open) return;
	chapter.open = true;
	target.scrollIntoView({ block: "start" });
}
export function ManualAnchor() {
	useEffect(() => {
		revealChapter();
		window.addEventListener("hashchange", revealChapter);
		window.addEventListener("popstate", revealChapter);
		function handleClick(event: MouseEvent) {
			const link =
				event.target instanceof Element ? event.target.closest("a") : null;
			if (
				!link?.hash ||
				link.pathname !== location.pathname ||
				link.origin !== location.origin
			)
				return;
			const chapter = document
				.getElementById(link.hash.slice(1))
				?.closest("details");
			if (chapter) chapter.open = true;
		}
		document.addEventListener("click", handleClick, true);
		return () => {
			window.removeEventListener("hashchange", revealChapter);
			window.removeEventListener("popstate", revealChapter);
			document.removeEventListener("click", handleClick, true);
		};
	}, []);
	return null;
}
