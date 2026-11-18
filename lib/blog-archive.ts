/**
 * The combined blog.yen.chat archive: posts from the creator and weekly
 * release notes, joined by date.
 *
 * Posts (`lib/blog.ts`) are long-form notes written once. Release notes
 * (`lib/release-notes/release-notes-data.ts`) are the generated week-by-week
 * record of every shipped build. The two never repeat each other: the index
 * lists both in one timeline, a week's story lives only on `/releases`, and
 * each side links to the other for the same Monday-Sunday week.
 */

import { type BlogPost, getBlogPosts } from "@/lib/blog";
import {
	RELEASE_WEEKS,
	type ReleaseWeek,
} from "@/lib/release-notes/release-notes-data";

/** Path of the release notes page on blog.yen.chat. */
export const RELEASES_PATH = "/releases";

/** A post's calendar day, read in the author's timezone like its date label. */
const POST_DAY = new Intl.DateTimeFormat("en-CA", {
	day: "2-digit",
	month: "2-digit",
	timeZone: "America/Los_Angeles",
	year: "numeric",
});

const MONTH_LABEL = new Intl.DateTimeFormat("en-US", {
	month: "long",
	timeZone: "UTC",
	year: "numeric",
});

const DAY_MS = 86_400_000;

export type ArchiveEntry =
	| { kind: "post"; day: string; post: BlogPost }
	| { kind: "release"; day: string; week: ReleaseWeek };

export interface ArchiveMonth {
	id: string;
	label: string;
	entries: ArchiveEntry[];
}

/** The anchor of a week on `/releases`; old yen.chat/release links use it too. */
export function releaseWeekId(week: ReleaseWeek): string {
	return `w-${week.iso}`;
}

export function releaseWeekHref(week: ReleaseWeek): string {
	return `${RELEASES_PATH}#${releaseWeekId(week)}`;
}

function addDays(isoDay: string, days: number): string {
	return new Date(Date.parse(`${isoDay}T00:00:00Z`) + days * DAY_MS)
		.toISOString()
		.slice(0, 10);
}

function postDay(post: BlogPost): string {
	return POST_DAY.format(new Date(post.publishedAt));
}

function weekContains(week: ReleaseWeek, day: string): boolean {
	return day >= week.iso && day <= addDays(week.iso, 6);
}

/** The release week a post was published in, if builds shipped that week. */
export function getReleaseWeekForPost(post: BlogPost): ReleaseWeek | null {
	const day = postDay(post);
	return RELEASE_WEEKS.find((week) => weekContains(week, day)) ?? null;
}

/** Posts published during a release week, newest first. */
export function getPostsForReleaseWeek(week: ReleaseWeek): BlogPost[] {
	return getBlogPosts().filter((post) => weekContains(week, postDay(post)));
}

/** `YYYY-MM` of an ISO day. */
function monthKeyForDay(day: string): string {
	return day.slice(0, 7);
}

/**
 * Every post and every release week in one timeline, grouped by month, newest
 * first. A week sorts by its last ship day, so it follows the posts written
 * while its builds were still shipping.
 */
export function getArchiveByMonth(): ArchiveMonth[] {
	const entries: { month: string; entry: ArchiveEntry }[] = [
		...getBlogPosts().map((post) => {
			const day = postDay(post);
			return {
				month: monthKeyForDay(day),
				entry: { kind: "post", day, post } as const,
			};
		}),
		...RELEASE_WEEKS.map((week) => ({
			// A week's month holds its Thursday, as on the release notes.
			month: monthKeyForDay(addDays(week.iso, 3)),
			entry: {
				kind: "release",
				day: week.versions[0]?.shippedOn ?? addDays(week.iso, 6),
				week,
			} as const,
		})),
	];
	entries.sort(
		(a, b) =>
			b.month.localeCompare(a.month) ||
			b.entry.day.localeCompare(a.entry.day) ||
			// On a shared day the week's summary sits above that day's post.
			(a.entry.kind === b.entry.kind ? 0 : a.entry.kind === "release" ? -1 : 1),
	);

	const months = new Map<string, ArchiveEntry[]>();
	for (const { month, entry } of entries) {
		months.set(month, [...(months.get(month) ?? []), entry]);
	}
	return [...months].map(([month, monthEntries]) => {
		const label = MONTH_LABEL.format(new Date(`${month}-01T00:00:00Z`));
		return {
			id: `m-${label.toLowerCase().replace(/\s+/g, "-")}`,
			label,
			entries: monthEntries,
		};
	});
}

/** "10 builds through v1.268" */
export function describeReleaseWeek(week: ReleaseWeek): string {
	const builds = `${week.builds} ${week.builds === 1 ? "build" : "builds"}`;
	return `${builds} through v${week.latestVersion}`;
}
