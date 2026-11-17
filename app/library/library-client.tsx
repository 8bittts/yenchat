"use client";

import { PageShell } from "@/components/shared/page-shell";
import type { SeoInventoryPage } from "@/lib/library/seo-inventory";

type LibrarySection = {
	id: string;
	title: string;
	pages: readonly SeoInventoryPage[];
};

export function LibraryClient({ sections }: { sections: LibrarySection[] }) {
	return (
		<PageShell>
			<section className="container-page py-10 md:py-14">
				<div className="max-w-4xl">
					<h1 className="text-heading-lg text-balance">Page library</h1>
					<p className="mt-4 max-w-3xl text-body text-text-muted">
						A clear inventory of YEN pages.
					</p>
				</div>

				<div className="mt-10 space-y-10">
					{sections.map((section) => (
						<PageSection key={section.id} section={section} />
					))}
				</div>
			</section>
		</PageShell>
	);
}

function PageSection({ section }: { section: LibrarySection }) {
	return (
		<section aria-labelledby={`${section.id}-title`}>
			<div className="flex flex-wrap items-end justify-between gap-3 border-b border-border pb-3">
				<h2 id={`${section.id}-title`} className="text-heading-md">
					{section.title}
				</h2>
				<p className="text-body-xs text-text-muted">
					{section.pages.length} pages
				</p>
			</div>
			<ul className="mt-4 divide-y divide-border">
				{section.pages.map((page) => (
					<li key={page.path}>
						<a
							href={page.path}
							className="group focus-ring -mx-2 flex flex-col gap-2 rounded-md px-2 py-4 transition-colors hover:bg-card md:flex-row md:items-start md:justify-between"
						>
							<div>
								<h3 className="text-heading-sm group-hover:text-brand">
									{page.title}
								</h3>
								<p className="mt-1 max-w-3xl text-body-sm text-text-muted">
									{page.description}
								</p>
							</div>
							<p className="shrink-0 font-mono text-body-xs text-text-muted group-hover:text-text-primary">
								{page.path}
							</p>
						</a>
					</li>
				))}
			</ul>
		</section>
	);
}
