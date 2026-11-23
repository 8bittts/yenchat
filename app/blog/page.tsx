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
} from "@/lib/blog";
import { getArchiveByMonth, RELEASES_PATH } from "@/lib/blog-archive";
import {
	type BlogWeek,
	blogNoteHref,
	describeWeekBuilds,
	getBlogWeeks,
	weekKindLabel,
} from "@/lib/blog-weeks";
import { buildPublicPageMetadata, SITE_URL } from "@/lib/seo";

export const metadata: Metadata = buildPublicPageMetadata({
	title: `${BLOG_TITLE} — the YEN blog`,
	description: `${BLOG_DESCRIPTION}. One issue every Friday: the week's technical updates, and notes from the creator when he writes them.`,
	url: `${BLOG_URL}/`,
	imageAlt: "Digital Onigiri featuring the glowing YEN rice ball",
	image: { url: `${SITE_URL}/social/journal.png`, width: 1200, height: 630 },
});

function WeekRow({ week }: { week: BlogWeek }) {
	const personal = week.kind === "personal";
	return (
		<article className={personal ? "ed-row ed-row-personal" : "ed-row"}>
			<Link href={`/${week.slug}`}>
				<div>
					<p className="ed-label">
						{weekKindLabel(week)} ·{" "}
						<time dateTime={week.publishedAt}>
							{formatBlogDate(week.publishedAt)}
						</time>
					</p>
					<h3>{week.title}</h3>
					<p>{week.deck}</p>
					<p className="ed-row-meta">
						{personal
							? `${week.notes.length} ${week.notes.length === 1 ? "note" : "notes"} from the creator · ${describeWeekBuilds(week)}`
							: describeWeekBuilds(week)}
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
	const firstHref = first ? blogNoteHref(first) : null;
	const latest = getBlogWeeks()[0];
	return (
		<PageShell siteOrigin={SITE_URL} mainClassName="ed-page">
			<header className="ed-cover">
				<div className="ph-wrap ed-cover-grid">
					<div>
						<p className="ph-kicker">
							<i />
							Engineering Journal
						</p>
						<h1>
							Digital
							<br />
							<em>Onigiri</em>
						</h1>
						<p className="ph-hero-lede">
							One issue every Friday from the engineer building YEN. The week's
							technical updates come first. When I write something myself, it
							follows as notes from the creator.
						</p>
						<div className="ph-actions">
							<a className="ph-primary" href="#archive">
								Browse the archive ↓
							</a>
							<Link className="ed-night-link" href={RELEASES_PATH}>
								Release notes ↗
							</Link>
						</div>
					</div>
					{first?.coverImage && firstHref && (
						<Link className="ed-cover-art" href={firstHref}>
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
					<section
						className={
							latest.kind === "personal"
								? "ed-lead ed-lead-personal"
								: "ed-lead"
						}
						aria-labelledby="lead-title"
					>
						<div>
							<p className="ed-label">Latest issue · {weekKindLabel(latest)}</p>
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
							<p>{latest.deck}</p>
						</div>
					</section>
				)}
				<section id="archive" className="ed-archive">
					<header className="ed-archive-head">
						<h2>The archive</h2>
						<a href="/feed">RSS feed ↗</a>
					</header>
					<p className="ed-legend">
						<span className="ed-legend-personal">From the creator</span> issues
						carry notes I wrote myself. <span>Weekly update</span> issues carry
						the week's technical updates only.
					</p>
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
								{m.weeks.map((week) => (
									<WeekRow key={week.slug} week={week} />
								))}
							</div>
						</section>
					))}
				</section>
			</div>
		</PageShell>
	);
}
