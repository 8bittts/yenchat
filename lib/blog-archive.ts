/**
 * The blog.yen.chat archive: one weekly issue per week, grouped by month, and
 * the links between an issue and the release notes for the same week.
 *
 * Issues (`lib/blog-weeks.ts`) are what the index, the feed and the sitemap
 * list. The release notes page (`/releases`) stays the build-by-build record
 * that the app links to: it shows the current week's story while builds are
 * still shipping, and each week links to its issue once that Friday's issue
 * is out.
 */

import { type BlogWeek, getBlogWeeks } from "@/lib/blog-weeks";
import type { ReleaseWeek } from "@/lib/release-notes/release-notes-data";

/** Path of the release notes page on blog.yen.chat. */
export const RELEASES_PATH = "/releases";

const MONTH_LABEL = new Intl.DateTimeFormat("en-US", {
	month: "long",
	timeZone: "UTC",
	year: "numeric",
});

export interface ArchiveMonth {
	id: string;
	label: string;
	weeks: BlogWeek[];
}

/** The anchor of a week on `/releases`; old yen.chat/release links use it too. */
export function releaseWeekId(week: ReleaseWeek): string {
	return `w-${week.iso}`;
}

export function releaseWeekHref(week: ReleaseWeek): string {
	return `${RELEASES_PATH}#${releaseWeekId(week)}`;
}

/** Every issue grouped by the month of its Friday, newest first. */
export function getArchiveByMonth(): ArchiveMonth[] {
	const months = new Map<string, BlogWeek[]>();
	for (const week of getBlogWeeks()) {
		const month = week.slug.slice(0, 7);
		months.set(month, [...(months.get(month) ?? []), week]);
	}
	return [...months].map(([month, weeks]) => {
		const label = MONTH_LABEL.format(new Date(`${month}-01T00:00:00Z`));
		return {
			id: `m-${label.toLowerCase().replace(/\s+/g, "-")}`,
			label,
			weeks,
		};
	});
}

/** "10 builds through v1.268" */
export function describeReleaseWeek(week: ReleaseWeek): string {
	const builds = `${week.builds} ${week.builds === 1 ? "build" : "builds"}`;
	return `${builds} through v${week.latestVersion}`;
}
