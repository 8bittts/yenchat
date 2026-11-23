import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { PageShell } from "@/components/shared/page-shell";
import { BLOG_TITLE, formatBlogDate } from "@/lib/blog";
import { RELEASES_PATH, releaseWeekHref } from "@/lib/blog-archive";
import {
	blogWeekUrl,
	describeWeekBuilds,
	getAdjacentBlogWeeks,
	getBlogWeek,
	getBlogWeeks,
	type RenderedNote,
	renderWeekNotes,
	weekKindLabel,
} from "@/lib/blog-weeks";
import { buildPublicPageMetadata, SITE_URL } from "@/lib/seo";

// Served at https://blog.yen.chat/<friday> by proxy.ts; a note's old address
// (/<slug> or /p/<slug>) redirects to its anchor here.
interface BlogWeekRouteProps {
	params: Promise<{ slug: string }>;
}

const TECHNICAL_UPDATES_ID = "technical-updates";
const CREATOR_NOTES_ID = "notes-from-the-creator";

export const dynamicParams = false;

export function generateStaticParams() {
	return getBlogWeeks().map((week) => ({ slug: week.slug }));
}

export async function generateMetadata({
	params,
}: BlogWeekRouteProps): Promise<Metadata> {
	const week = getBlogWeek((await params).slug);
	if (!week) return {};
	const metadata = buildPublicPageMetadata({
		title: `${week.title} — ${BLOG_TITLE}`,
		description: `${week.deck} ${weekKindLabel(week)}, ${week.label.replace(/^Week/, "week")}: ${describeWeekBuilds(week).toLowerCase()}.`,
		url: blogWeekUrl(week),
		imageAlt: week.imageAlt,
		image: {
			url: week.image.src,
			width: week.image.width,
			height: week.image.height,
		},
	});
	return {
		...metadata,
		openGraph: {
			...metadata.openGraph,
			type: "article",
			publishedTime: week.publishedAt,
			authors: ["8BIT"],
			section: weekKindLabel(week),
		},
	};
}

function Note({ note, creator }: { note: RenderedNote; creator: boolean }) {
	return (
		<article
			id={note.post.slug}
			className={creator ? "ed-note ed-note-creator" : "ed-note"}
		>
			<h3>{note.post.title}</h3>
			{note.post.subtitle ? (
				<p className="ed-note-deck">{note.post.subtitle}</p>
			) : null}
			<p className="ed-byline">
				{creator ? "8BIT" : "Feature note"} <span> / </span>{" "}
				<time dateTime={note.post.publishedAt}>
					{formatBlogDate(note.post.publishedAt)}
				</time>
			</p>
			{/* The importer sanitizes this repository-owned article before publication. */}
			{/* react-doctor-disable-next-line react/no-danger, react-doctor/dangerous-html-sink */}
			<div
				className="blog-prose"
				dangerouslySetInnerHTML={{ __html: note.html }}
			/>
		</article>
	);
}

export default async function BlogWeekPage({ params }: BlogWeekRouteProps) {
	const week = getBlogWeek((await params).slug);
	if (!week) notFound();
	const { newer, older } = getAdjacentBlogWeeks(week.slug);
	// Issue h1 > section h2 > note h3 > the note's own headings from h4.
	const features = renderWeekNotes(week.features, 4);
	const notes = renderWeekNotes(week.notes, 4);
	const personal = week.kind === "personal";
	return (
		<PageShell siteOrigin={SITE_URL} mainClassName="ed-page">
			<div
				className={
					personal ? "ph-wrap ed-story ed-story-personal" : "ph-wrap ed-story"
				}
			>
				<header className="ed-story-head">
					<Link className="ed-label" href="/">
						← {BLOG_TITLE}
					</Link>
					<p className="ed-label ed-kind">
						{weekKindLabel(week)} · {week.label}
					</p>
					<h1>{week.title}</h1>
					<p className="ed-deck">{week.deck}</p>
					<p className="ed-byline">
						8BIT <span> / </span>{" "}
						<time dateTime={week.publishedAt}>
							{formatBlogDate(week.publishedAt)}
						</time>
					</p>
				</header>
				<div className="ed-reading">
					<aside>
						<details className="ed-index">
							<summary>In this issue</summary>
							<nav aria-label="Issue sections">
								<a href={`#${TECHNICAL_UPDATES_ID}`}>Technical updates</a>
								{features.map((note) => (
									<a key={note.post.slug} href={`#${note.post.slug}`}>
										{note.post.title}
									</a>
								))}
								{notes.length > 0 ? (
									<a href={`#${CREATOR_NOTES_ID}`}>Notes from the creator</a>
								) : null}
								{notes.map((note) => (
									<a key={note.post.slug} href={`#${note.post.slug}`}>
										{note.post.title}
									</a>
								))}
							</nav>
						</details>
					</aside>
					<div>
						<section
							id={TECHNICAL_UPDATES_ID}
							className="ed-updates"
							aria-labelledby={`${TECHNICAL_UPDATES_ID}-title`}
						>
							<h2 id={`${TECHNICAL_UPDATES_ID}-title`}>Technical updates</h2>
							<p className="ed-label">{describeWeekBuilds(week)}</p>
							{week.release ? (
								<div className="blog-prose">
									{week.release.summary.split("\n\n").map((paragraph) => (
										<p key={paragraph.slice(0, 48)}>{paragraph}</p>
									))}
								</div>
							) : (
								<p className="blog-prose">
									No build shipped this week. The notes below are about the work
									in progress.
								</p>
							)}
							{week.release ? (
								<p>
									<Link
										className="ed-text-link"
										href={releaseWeekHref(week.release)}
									>
										Every build that week, v
										{week.release.versions.at(-1)?.version} to v
										{week.release.latestVersion} ↗
									</Link>
								</p>
							) : null}
							{features.map((note) => (
								<Note key={note.post.slug} note={note} creator={false} />
							))}
						</section>
						{notes.length > 0 ? (
							<section
								id={CREATOR_NOTES_ID}
								className="ed-creator"
								aria-labelledby={`${CREATOR_NOTES_ID}-title`}
							>
								<p className="ed-label">Written by hand</p>
								<h2 id={`${CREATOR_NOTES_ID}-title`}>Notes from the creator</h2>
								{notes.map((note) => (
									<Note key={note.post.slug} note={note} creator />
								))}
							</section>
						) : null}
						<section className="ed-next" id="more-issues">
							<h2>More issues</h2>
							{newer && (
								<Link href={`/${newer.slug}`}>Newer · {newer.title} ↗</Link>
							)}
							{older && (
								<Link href={`/${older.slug}`}>Older · {older.title} ↗</Link>
							)}
							<Link href={RELEASES_PATH}>All release notes ↗</Link>
							<Link href="/">All issues ↗</Link>
						</section>
					</div>
				</div>
			</div>
		</PageShell>
	);
}
