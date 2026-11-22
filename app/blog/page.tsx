import type { Metadata } from "next";
import Image from "next/image";
import Link from "next/link";
import { PageShell } from "@/components/shared/page-shell";
import {
	BLOG_DESCRIPTION,
	BLOG_TITLE,
	BLOG_URL,
	formatBlogDate,
	getBlogPost,
	getBlogPosts,
} from "@/lib/blog";
import {
	type ArchiveEntry,
	describeReleaseWeek,
	getArchiveByMonth,
	releaseWeekHref,
} from "@/lib/blog-archive";
import { buildPublicPageMetadata, SITE_URL } from "@/lib/seo";

export const metadata: Metadata = buildPublicPageMetadata({
	title: `${BLOG_TITLE} — the YEN blog`,
	description: BLOG_DESCRIPTION,
	url: `${BLOG_URL}/`,
	imageAlt: "Digital Onigiri featuring the glowing YEN rice ball",
	image: { url: `${SITE_URL}/social/journal.png`, width: 1200, height: 630 },
});

function ArchiveRow({ entry }: { entry: ArchiveEntry }) {
	const isPost = entry.kind === "post";
	const href = isPost ? `/${entry.post.slug}` : releaseWeekHref(entry.week);
	return (
		<article className="ed-row">
			<Link href={href}>
				<div>
					<p className="ed-label">
						{isPost ? (
							<>
								From the creator ·{" "}
								<time dateTime={entry.post.publishedAt}>
									{formatBlogDate(entry.post.publishedAt)}
								</time>
							</>
						) : (
							"Release notes"
						)}
					</p>
					<h3>{isPost ? entry.post.title : entry.week.label}</h3>
					<p>
						{isPost ? entry.post.subtitle : describeReleaseWeek(entry.week)}
					</p>
				</div>
				<span aria-hidden="true">↗</span>
			</Link>
		</article>
	);
}

export default function BlogIndexPage() {
	const months = getArchiveByMonth();
	const first = getBlogPost("small-bites-from-the-digital-onigiri");
	const latest = getBlogPosts()[0];
	return (
		<PageShell siteOrigin={SITE_URL} mainClassName="ed-page">
			<header className="ed-cover">
				<div className="ph-wrap ed-cover-grid">
					<div>
						<p className="ph-kicker">
							<i />
							Independent engineering journal
						</p>
						<h1>
							Digital
							<br />
							<em>Onigiri</em>
						</h1>
						<p className="ph-hero-lede">
							Field notes from one engineer building YEN. The pane that needed a
							name, the shell that kept running, and the builds that got them
							there.
						</p>
						<div className="ph-actions">
							<a className="ph-primary" href="#archive">
								Browse the archive ↓
							</a>
							<Link className="ed-night-link" href="/releases">
								Release notes ↗
							</Link>
						</div>
					</div>
					{first?.coverImage && (
						<Link className="ed-cover-art" href={`/${first.slug}`}>
							<Image
								src={first.coverImage.src}
								width={first.coverImage.width}
								height={first.coverImage.height}
								sizes="(max-width: 700px) 90vw, 400px"
								loading="eager"
								alt="A rice ball wrapped in nori bears a glowing green terminal mark."
							/>
							<span>
								The first issue <b aria-hidden="true">↗</b>
							</span>
						</Link>
					)}
				</div>
			</header>
			<div className="ph-wrap ed-sheet">
				{latest && (
					<section className="ed-lead" aria-labelledby="lead-title">
						<div>
							<p className="ed-label">Latest field note</p>
							<time dateTime={latest.publishedAt}>
								{formatBlogDate(latest.publishedAt)}
							</time>
						</div>
						<div>
							<h2 id="lead-title">
								<Link href={`/${latest.slug}`}>
									{latest.title} <span aria-hidden="true">↗</span>
								</Link>
							</h2>
							<p>{latest.subtitle}</p>
						</div>
					</section>
				)}
				<section id="archive" className="ed-archive">
					<header className="ed-archive-head">
						<h2>The archive</h2>
						<a href="/feed">RSS feed ↗</a>
					</header>
					<details className="ed-index">
						<summary>Jump to a month</summary>
						<nav aria-label="Archive months">
							{months.map((m) => (
								<a key={m.id} href={`#${m.id}`}>
									{m.label}
								</a>
							))}
						</nav>
					</details>
					{months.map((m) => (
						<section className="ed-month" id={m.id} key={m.id}>
							<h2>{m.label}</h2>
							<div>
								{m.entries.map((e) => (
									<ArchiveRow
										key={e.kind === "post" ? e.post.slug : e.week.iso}
										entry={e}
									/>
								))}
							</div>
						</section>
					))}
				</section>
			</div>
		</PageShell>
	);
}
