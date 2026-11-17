/**
 * Documentation Section Component
 *
 * Wraps content in a navigable section with anchor link support.
 * Anchor landings use the shared --header-height for breathing room (the
 * header is not fixed — it scrolls away — so this is spacing, not clearance).
 */
interface DocSectionProps {
	id: string;
	title: string;
	children: React.ReactNode;
}

export function DocSection({ id, title, children }: DocSectionProps) {
	return (
		<section id={id} className="scroll-mt-[var(--header-height)]">
			<h2 className="text-heading-md heading-spacing pb-2 border-b border-border">
				{title}
			</h2>
			<div className="space-y-6">{children}</div>
		</section>
	);
}
