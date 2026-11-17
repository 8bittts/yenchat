import Link from "next/link";
import { PageShell } from "@/components/shared/page-shell";
import { DOWNLOAD_HREF } from "@/lib/analytics/download-cta";
import type {
	PublicLibraryPage,
	PublicLibraryPageKind,
} from "@/lib/library/public-pages";

interface PublicLibraryHubProps {
	kind: PublicLibraryPageKind;
	title: string;
	description: string;
	pages: readonly PublicLibraryPage[];
}

export function PublicLibraryHub({
	kind,
	title,
	description,
	pages,
}: PublicLibraryHubProps) {
	const siblingHref = kind === "alternative" ? "/use-cases" : "/alternatives";
	const siblingLabel = kind === "alternative" ? "Use cases" : "Alternatives";

	return (
		<PageShell currentPage="home">
			<section className="container-page py-10 md:py-16">
				<div className="max-w-4xl">
					<p className="text-body-sm text-text-muted">
						{kind === "alternative"
							? "Terminal and IDE alternatives"
							: "Terminal workflow use cases"}
					</p>
					<h1 className="mt-3 text-heading-lg text-balance">{title}</h1>
					<p className="mt-5 max-w-3xl text-body">{description}</p>
					<div className="mt-6 flex flex-wrap gap-3">
						<Link href={DOWNLOAD_HREF} className="btn-primary">
							Download YEN
						</Link>
						<Link href={siblingHref} className="btn-secondary">
							{siblingLabel}
						</Link>
						<Link href="/docs" className="btn-secondary">
							Docs
						</Link>
					</div>
				</div>
			</section>

			<section
				className="border-y border-border bg-card/60"
				aria-labelledby="public-page-index"
			>
				<div className="container-page py-10 md:py-14">
					<h2 id="public-page-index" className="sr-only">
						Public page index
					</h2>
					<div className="grid gap-4 md:grid-cols-2">
						{pages.map((page) => (
							<Link
								key={page.path}
								href={page.path}
								className="callout-card focus-ring group block h-full transition-colors hover:bg-card"
							>
								<p className="text-body-xs text-text-muted">{page.kicker}</p>
								<h3 className="mt-2 text-heading-sm text-brand-dark group-hover:text-brand">
									{page.seo.title}
								</h3>
								<p className="mt-3 text-body-sm">{page.seo.description}</p>
								<dl className="mt-4 grid gap-2 text-body-xs">
									<div className="flex gap-2">
										<dt className="font-medium text-text-primary">Evidence</dt>
										<dd>{page.evidenceScore}/100</dd>
									</div>
									<div className="flex gap-2">
										<dt className="font-medium text-text-primary">Sources</dt>
										<dd>
											{page.officialSources.length + page.yenProofPoints.length}
										</dd>
									</div>
								</dl>
							</Link>
						))}
					</div>
				</div>
			</section>

			<section
				className="container-page py-10 md:py-14"
				aria-labelledby="quality-gate"
			>
				<div className="max-w-3xl">
					<h2 id="quality-gate" className="text-heading-md">
						Why this set is small
					</h2>
					<p className="mt-3 text-body">
						These pages are in the sitemap because they have enough current
						source material and shipped YEN facts to avoid thin comparison copy.
						Dormant competitor research is not stored in the product repository.
					</p>
				</div>
			</section>
		</PageShell>
	);
}
