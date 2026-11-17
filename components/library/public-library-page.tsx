import Link from "next/link";
import type { ReactNode } from "react";
import { PageShell } from "@/components/shared/page-shell";
import { isDownloadHref } from "@/lib/analytics/download-cta";
import type { PublicLibraryPage as PublicLibraryPageModel } from "@/lib/library/public-pages";

interface PublicLibraryPageProps {
	page: PublicLibraryPageModel;
	relatedPages: readonly PublicLibraryPageModel[];
}

interface FactRow {
	key: string;
	area: string;
	claim: ReactNode;
	source: { url: string; title: string } | null;
}

export function PublicLibraryPage({
	page,
	relatedPages,
}: PublicLibraryPageProps) {
	const factRows: FactRow[] = [
		...page.yenProofPoints.map((point) => ({
			key: point.label,
			area: point.label,
			claim: point.text,
			source: point.source ?? null,
		})),
		...page.officialSources.map((source) => ({
			key: source.url,
			area: page.competitorName ?? "Official source",
			claim: `Official product source checked ${source.lastCheckedAt}.`,
			source: { url: source.url, title: source.title },
		})),
	];

	return (
		<PageShell currentPage="home">
			<section className="container-page py-10 md:py-16">
				<nav aria-label="Breadcrumb" className="text-body-xs text-text-muted">
					<Link href="/" className="link-brand">
						YEN
					</Link>
					<span aria-hidden="true" className="mx-2">
						/
					</span>
					<Link
						href={page.kind === "alternative" ? "/alternatives" : "/use-cases"}
						className="link-brand"
					>
						{page.kind === "alternative" ? "Alternatives" : "Use cases"}
					</Link>
				</nav>

				<div className="mt-8 max-w-4xl">
					<p className="text-body-sm text-text-muted">{page.kicker}</p>
					<h1 className="mt-3 text-heading-lg text-balance">{page.h1}</h1>
					<p className="mt-5 max-w-3xl text-body">{page.summary}</p>
					<p className="mt-4 max-w-3xl text-body text-text-muted">
						{page.audience}
					</p>
					<div className="mt-6 flex flex-wrap gap-3">
						{page.conversionLinks.map((link) => (
							<Link
								key={link.href}
								href={link.href}
								className={
									isDownloadHref(link.href) ? "btn-primary" : "btn-secondary"
								}
							>
								{link.label}
							</Link>
						))}
					</div>
				</div>
			</section>

			<section
				className="border-y border-border bg-card/60"
				aria-labelledby="decision-points"
			>
				<div className="container-page py-10 md:py-14">
					<div className="grid gap-8 lg:grid-cols-[minmax(0,0.85fr)_minmax(0,1.15fr)]">
						<div>
							<h2 id="decision-points" className="text-heading-md">
								Decision points
							</h2>
							<p className="mt-3 text-body">
								Every point here is either tied to YEN docs or framed as a
								workflow distinction from official product positioning.
							</p>
						</div>
						<div className="grid gap-3">
							{page.decisionPoints.map((point) => (
								<article key={point.label} className="callout-card">
									<h3 className="text-heading-sm">{point.label}</h3>
									<p className="mt-2 text-body-sm">{point.text}</p>
									{point.source ? (
										<a
											href={point.source.url}
											className="mt-3 inline-block link-brand"
										>
											{point.source.title}
										</a>
									) : null}
								</article>
							))}
						</div>
					</div>
				</div>
			</section>

			<section
				className="container-page py-10 md:py-14"
				aria-labelledby="source-backed-proof"
			>
				<div className="grid gap-8 lg:grid-cols-[minmax(0,0.9fr)_minmax(0,1.1fr)]">
					<div>
						<h2 id="source-backed-proof" className="text-heading-md">
							Source-backed facts
						</h2>
						<p className="mt-3 text-body">
							This page avoids benchmark, pricing, and availability claims
							unless a current official source supports them.
						</p>
					</div>
					<div>
						{/* Mobile: stacked cards so the Source links never break mid-word in
						    a pinned narrow column. Desktop (md+): the 30/45/25 table. */}
						<ul className="overflow-hidden rounded-lg border border-border md:hidden">
							{factRows.map((row) => (
								<li
									key={row.key}
									className="border-t border-border p-4 first:border-t-0"
								>
									<p className="font-medium text-text-primary">{row.area}</p>
									<p className="mt-1 text-body-sm text-text-body">
										{row.claim}
									</p>
									<p className="mt-2 text-body-xs">
										{row.source ? (
											<a href={row.source.url} className="link-brand">
												{row.source.title}
											</a>
										) : (
											<span className="text-text-muted">YEN source</span>
										)}
									</p>
								</li>
							))}
						</ul>
						<div className="hidden overflow-hidden rounded-lg border border-border md:block">
							<table className="w-full table-fixed border-collapse text-left text-body-sm">
								<colgroup>
									<col className="w-[30%]" />
									<col className="w-[45%]" />
									<col className="w-[25%]" />
								</colgroup>
								<thead className="bg-card-header text-text-muted">
									<tr>
										<th scope="col" className="px-4 py-3 font-medium">
											Area
										</th>
										<th scope="col" className="px-4 py-3 font-medium">
											Claim
										</th>
										<th scope="col" className="px-4 py-3 font-medium">
											Source
										</th>
									</tr>
								</thead>
								<tbody>
									{factRows.map((row) => (
										<tr key={row.key} className="border-t border-border">
											<th
												scope="row"
												className="px-4 py-3 align-top font-medium text-text-primary"
											>
												{row.area}
											</th>
											<td className="break-words px-4 py-3 align-top text-text-body">
												{row.claim}
											</td>
											<td className="break-words px-4 py-3 align-top">
												{row.source ? (
													<a
														href={row.source.url}
														className="link-brand text-body-xs"
													>
														{row.source.title}
													</a>
												) : (
													<span className="text-text-muted">YEN source</span>
												)}
											</td>
										</tr>
									))}
								</tbody>
							</table>
						</div>
					</div>
				</div>
			</section>

			<section
				className="border-t border-border"
				aria-labelledby="related-public-pages"
			>
				<div className="container-page py-10 md:py-14">
					<h2 id="related-public-pages" className="text-heading-md">
						Related pages
					</h2>
					<nav aria-label="Related public pages" className="mt-5">
						<ul className="grid gap-3 md:grid-cols-3">
							{relatedPages.map((relatedPage) => (
								<li key={relatedPage.path}>
									<Link
										href={relatedPage.path}
										className="callout-card focus-ring group block h-full rounded-lg transition-colors hover:bg-card"
									>
										<span className="text-heading-sm text-brand-dark group-hover:text-brand">
											{relatedPage.seo.title}
										</span>
										<span className="mt-2 block text-body-sm">
											{relatedPage.seo.description}
										</span>
									</Link>
								</li>
							))}
						</ul>
					</nav>
				</div>
			</section>
		</PageShell>
	);
}
