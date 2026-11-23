/**
 * The weekly blog.yen.chat issues: one post per Monday-Sunday week, published
 * on that week's Friday.
 *
 * Each issue rolls the week's technical updates (the curated release story in
 * `lib/release-notes/release-notes-data.ts`, plus any agent-written feature
 * notes) into one page. A week in which the creator wrote something is a
 * personal issue: its notes follow the technical updates under "Notes from the
 * creator", and the issue takes its title and deck from the lead note. Every
 * other week is a weekly update, titled in `content/blog/weeks.json`.
 *
 * An issue is published when `content/blog/weeks.json` lists its week, so the
 * site stays deterministic; adding the entry is the Friday publishing step.
 */

import WEEK_COPY from "@/content/blog/weeks.json";
import {
	accessibleArticleHtml,
	BLOG_URL,
	type BlogHeading,
	type BlogImage,
	type BlogPost,
	getBlogHeadings,
	getBlogPosts,
} from "@/lib/blog";
import {
	RELEASE_WEEKS,
	type ReleaseWeek,
} from "@/lib/release-notes/release-notes-data";

export type BlogWeekKind = "personal" | "update";

export interface BlogWeek {
	/** The week's Friday, `YYYY-MM-DD`; also its URL slug. */
	slug: string;
	/** The week's Monday, `YYYY-MM-DD`, as in the release notes. */
	week: string;
	kind: BlogWeekKind;
	title: string;
	deck: string;
	/** Friday at 09:00 Pacific Standard Time (17:00 UTC). */
	publishedAt: string;
	/** "Week of Nov 16–22, 2026" */
	label: string;
	release: ReleaseWeek | null;
	/** Notes the creator wrote that week, lead first, then oldest first. */
	notes: BlogPost[];
	/** Agent-written feature notes for the week, oldest first. */
	features: BlogPost[];
	/** The social card: the lead note's cover, or a generated week card. */
	image: BlogImage;
	imageAlt: string;
}

interface WeekCopy {
	week: string;
	lead?: string;
	title?: string;
	deck?: string;
}

const DAY_MS = 86_400_000;
/** Size of the generated week cards in `public/social/weeks/`. */
export const WEEK_CARD_SIZE = { width: 1200, height: 630 } as const;
export const WEEK_CARD_PATH = "/social/weeks/";

/** A post's calendar day in the author's timezone, `YYYY-MM-DD`. */
const PACIFIC_DAY = new Intl.DateTimeFormat("en-CA", {
	day: "2-digit",
	month: "2-digit",
	timeZone: "America/Los_Angeles",
	year: "numeric",
});

const SHORT_MONTH = new Intl.DateTimeFormat("en-US", {
	month: "short",
	timeZone: "UTC",
});

export function addDays(isoDay: string, days: number): string {
	return new Date(Date.parse(`${isoDay}T00:00:00Z`) + days * DAY_MS)
		.toISOString()
		.slice(0, 10);
}

/** The Monday that starts the week holding `isoDay`. */
export function mondayOf(isoDay: string): string {
	const weekday = (new Date(`${isoDay}T00:00:00Z`).getUTCDay() + 6) % 7;
	return addDays(isoDay, -weekday);
}

export function postDay(post: BlogPost): string {
	return PACIFIC_DAY.format(new Date(post.publishedAt));
}

/** "Week of Nov 16–22, 2026", in the release notes' own format. */
export function weekLabel(monday: string): string {
	const sunday = addDays(monday, 6);
	const start = new Date(`${monday}T00:00:00Z`);
	const end = new Date(`${sunday}T00:00:00Z`);
	const startMonth = SHORT_MONTH.format(start);
	const endMonth = SHORT_MONTH.format(end);
	const range =
		startMonth === endMonth
			? `${startMonth} ${start.getUTCDate()}–${end.getUTCDate()}`
			: `${startMonth} ${start.getUTCDate()}–${endMonth} ${end.getUTCDate()}`;
	return `Week of ${range}, ${end.getUTCFullYear()}`;
}

/** The week's creator notes with the lead first; throws on a bad lead. */
function orderedNotes(copy: WeekCopy, weekPosts: BlogPost[]): BlogPost[] {
	const creatorNotes = weekPosts.filter((post) => post.author === "creator");
	if (!copy.lead) return creatorNotes;
	const lead = creatorNotes.find((post) => post.slug === copy.lead);
	if (!lead) {
		throw new Error(
			`content/blog/weeks.json: ${copy.week} leads with ${copy.lead}, which is not a creator note from that week`,
		);
	}
	return [lead, ...creatorNotes.filter((post) => post !== lead)];
}

function buildWeek(copy: WeekCopy, weekPosts: BlogPost[]): BlogWeek {
	const notes = orderedNotes(copy, weekPosts);
	const lead = copy.lead ? notes[0] : undefined;
	const title = lead?.title ?? copy.title;
	const deck = lead?.subtitle ?? copy.deck;
	if (!title || !deck) {
		throw new Error(
			`content/blog/weeks.json: ${copy.week} needs a lead note or a title and deck`,
		);
	}
	const slug = addDays(copy.week, 4);
	const release = RELEASE_WEEKS.find((week) => week.iso === copy.week) ?? null;
	const label = release?.label ?? weekLabel(copy.week);
	const cover = lead?.coverImage;
	return {
		slug,
		week: copy.week,
		kind: notes.length > 0 ? "personal" : "update",
		title,
		deck,
		publishedAt: `${slug}T17:00:00.000Z`,
		label,
		release,
		notes,
		features: weekPosts.filter((post) => post.author === "agent"),
		image: cover ?? { src: `${WEEK_CARD_PATH}${slug}.png`, ...WEEK_CARD_SIZE },
		imageAlt: cover
			? `Cover of “${title}”, from the creator`
			: `${title}: the YEN weekly update for the ${label.replace(/^Week/, "week")}`,
	};
}

function buildWeeks(): readonly BlogWeek[] {
	const byWeek = new Map<string, BlogPost[]>();
	for (const post of [...getBlogPosts()].reverse()) {
		const monday = mondayOf(postDay(post));
		byWeek.set(monday, [...(byWeek.get(monday) ?? []), post]);
	}
	return (WEEK_COPY as WeekCopy[])
		.map((copy) => buildWeek(copy, byWeek.get(copy.week) ?? []))
		.sort((a, b) => b.slug.localeCompare(a.slug));
}

let cachedWeeks: readonly BlogWeek[] | null = null;

/** Every published weekly issue, newest first. */
export function getBlogWeeks(): readonly BlogWeek[] {
	cachedWeeks ??= buildWeeks();
	return cachedWeeks;
}

export function getBlogWeek(slug: string): BlogWeek | null {
	return getBlogWeeks().find((week) => week.slug === slug) ?? null;
}

/** The published issue that carries a note, if its week is out. */
export function getBlogWeekForPost(post: BlogPost): BlogWeek | null {
	return (
		getBlogWeeks().find(
			(week) => week.notes.includes(post) || week.features.includes(post),
		) ?? null
	);
}

/** The published issue for a release week, if its Friday has come. */
export function getBlogWeekForRelease(release: ReleaseWeek): BlogWeek | null {
	return getBlogWeeks().find((week) => week.week === release.iso) ?? null;
}

export function blogWeekUrl(week: BlogWeek): string {
	return `${BLOG_URL}/${week.slug}`;
}

/** The issues immediately newer and older than `slug`. */
export function getAdjacentBlogWeeks(slug: string): {
	newer: BlogWeek | null;
	older: BlogWeek | null;
} {
	const weeks = getBlogWeeks();
	const index = weeks.findIndex((week) => week.slug === slug);
	if (index < 0) return { newer: null, older: null };
	return { newer: weeks[index - 1] ?? null, older: weeks[index + 1] ?? null };
}

/** "From the creator" or "Weekly update", the label every issue carries. */
export function weekKindLabel(week: BlogWeek): string {
	return week.kind === "personal" ? "From the creator" : "Weekly update";
}

/** "11 builds through v1.284", or a plain note for a week with no build. */
export function describeWeekBuilds(week: BlogWeek): string {
	if (!week.release) return "No build shipped this week";
	const { builds, latestVersion } = week.release;
	return `${builds} ${builds === 1 ? "build" : "builds"} through v${latestVersion}`;
}

export interface RenderedNote {
	post: BlogPost;
	/** The note's markup, ready to render inside its issue. */
	html: string;
	headings: BlogHeading[];
}

/** A note's address: its issue, at the note's anchor. */
export function blogNoteHref(post: BlogPost): string | null {
	const week = getBlogWeekForPost(post);
	return week ? `/${week.slug}#${post.slug}` : null;
}

/**
 * Notes as they render inside one issue. Each note's headings start at
 * `firstLevel`, a heading id that an earlier note on the page already uses
 * gets the note's slug as a prefix (its in-note links follow), and a link to
 * another note points at that note inside its own issue.
 */
export function renderWeekNotes(
	notes: readonly BlogPost[],
	firstLevel: number,
): RenderedNote[] {
	const used = new Set<string>(notes.map((post) => post.slug));
	return notes.map((post) => {
		let html = post.html;
		for (const id of [...html.matchAll(/\sid="([^"]+)"/g)].map(
			(match) => match[1] ?? "",
		)) {
			if (used.has(id) && id !== post.slug) {
				const unique = `${post.slug}-${id}`;
				html = html
					.replaceAll(` id="${id}"`, ` id="${unique}"`)
					.replaceAll(`href="#${id}"`, `href="#${unique}"`);
				used.add(unique);
			} else {
				used.add(id);
			}
		}
		html = html.replace(/href="\/([a-z0-9][a-z0-9-]*)"/g, (link, slug) => {
			const target = getBlogPosts().find((other) => other.slug === slug);
			const href = target ? blogNoteHref(target) : null;
			return href ? `href="${href}"` : link;
		});
		html = accessibleArticleHtml(html, firstLevel);
		return { post, html, headings: getBlogHeadings(html) };
	});
}
