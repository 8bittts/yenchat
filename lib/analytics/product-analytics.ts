"use client";

import { track } from "@vercel/analytics";

/**
 * Every Vercel Web Analytics custom event the site sends, in snake_case; add a new name here
 * before using it. Until 2026-10-22 they were Title Case ("Download Click"), so dashboard history
 * before that date sits under the old names.
 */
export type ProductEventName =
	| "download_click"
	| "footer_click"
	| "header_click"
	| "theme_toggle"
	| "tunes_platform_click";

type ProductEventValue = string | number | boolean;
type ProductEventProperties = Record<
	string,
	ProductEventValue | null | undefined
>;

// Vercel's custom-event limits: flat values, 255 characters, 8 properties on Web Analytics Plus.
const MAX_PROPERTY_LENGTH = 255;
const MAX_PROPERTIES = 8;

function sanitizeProperties(
	properties: ProductEventProperties,
): Record<string, ProductEventValue> {
	const sanitized: Record<string, ProductEventValue> = {};
	for (const [key, value] of Object.entries(properties)) {
		if (value === null || value === undefined) continue;
		if (Object.keys(sanitized).length === MAX_PROPERTIES) break;
		sanitized[key] =
			typeof value === "string" ? value.slice(0, MAX_PROPERTY_LENGTH) : value;
	}
	return sanitized;
}

/** The one entry point for custom events; analytics must never break a click handler. */
export function trackProductEvent(
	name: ProductEventName,
	properties: ProductEventProperties = {},
): void {
	try {
		track(name, sanitizeProperties(properties));
	} catch {
		// Analytics must never block the visitor's workflow.
	}
}
