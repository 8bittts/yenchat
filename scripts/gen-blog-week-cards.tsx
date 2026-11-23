/**
 * Writes the social card of every weekly issue that has no lead-note cover to
 * public/social/weeks/<friday>.png (1200x630), so each issue shares with its
 * own title, week and build range instead of the generic journal card.
 *
 * Run after publishing a week in content/blog/weeks.json:
 *   bun scripts/gen-blog-week-cards.tsx
 * tests/158-blog-archive.test.ts fails when an issue's card is missing.
 * Personal issues share the lead note's own cover, so they get no card.
 */

import { mkdirSync, writeFileSync } from "node:fs";
import path from "node:path";
import { ImageResponse } from "next/og";
import {
	describeWeekBuilds,
	getBlogWeeks,
	WEEK_CARD_PATH,
	WEEK_CARD_SIZE,
	weekKindLabel,
} from "@/lib/blog-weeks";

// The Phosphor night palette from app/globals.css (--ph-night, --ph-green,
// --ph-text, --ph-muted, --ph-line).
const NIGHT = "#0a110e";
const GREEN = "#a2ffad";
const TEXT = "#ebf3ec";
const MUTED = "#b4c5b9";
const LINE = "#34473b";

async function main(): Promise<void> {
	const outDir = path.join(process.cwd(), "public", WEEK_CARD_PATH);
	mkdirSync(outDir, { recursive: true });
	let written = 0;
	for (const week of getBlogWeeks()) {
		if (!week.image.src.startsWith(WEEK_CARD_PATH)) continue;
		const card = new ImageResponse(
			<div
				style={{
					display: "flex",
					flexDirection: "column",
					justifyContent: "space-between",
					width: "100%",
					height: "100%",
					padding: "64px 72px",
					background: NIGHT,
					color: TEXT,
					borderBottom: `14px solid ${GREEN}`,
				}}
			>
				<div
					style={{
						display: "flex",
						justifyContent: "space-between",
						fontSize: 26,
						letterSpacing: 3,
						color: GREEN,
						textTransform: "uppercase",
					}}
				>
					<span>Digital Onigiri</span>
					<span>{weekKindLabel(week)}</span>
				</div>
				<div style={{ display: "flex", flexDirection: "column" }}>
					<div
						style={{
							fontSize: week.title.length > 28 ? 76 : 92,
							lineHeight: 1.02,
							letterSpacing: -3,
						}}
					>
						{week.title}
					</div>
					<div
						style={{
							marginTop: 26,
							fontSize: 32,
							lineHeight: 1.35,
							color: MUTED,
							maxWidth: 1000,
						}}
					>
						{week.deck}
					</div>
				</div>
				<div
					style={{
						display: "flex",
						justifyContent: "space-between",
						paddingTop: 24,
						borderTop: `2px solid ${LINE}`,
						fontSize: 26,
						color: MUTED,
					}}
				>
					<span>{week.label}</span>
					<span>{describeWeekBuilds(week)}</span>
				</div>
			</div>,
			WEEK_CARD_SIZE,
		);
		writeFileSync(
			path.join(outDir, `${week.slug}.png`),
			Buffer.from(await card.arrayBuffer()),
		);
		written += 1;
	}
	if (written === 0) throw new Error("no weekly update needed a card");
	console.log(`RAN|gen-blog-week-cards|written=${written}`);
}

await main();
