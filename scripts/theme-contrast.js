#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const THEME_COLOR_KEYS = [
	"background",
	"foreground",
	"cursor-color",
	"cursor-text",
	"selection-background",
	"selection-foreground",
];

const CONTRAST_RULES = {
	foreground: 4.5,
	cursor: 3.0,
	cursorText: 3.0,
	selectionText: 4.5,
	selectionBackground: 3.0,
};

function normalizeHex(value) {
	if (!value) return null;
	const trimmed = value.trim().toLowerCase();
	if (!/^#[0-9a-f]{6}$/.test(trimmed)) return null;
	return trimmed;
}

function parseThemeContent(content) {
	const lines = content.split(/\r?\n/);
	const values = {
		palette: [],
	};
	const keyLines = new Map();

	for (let index = 0; index < lines.length; index += 1) {
		const trimmed = lines[index].trim();
		if (!trimmed || trimmed.startsWith("#")) continue;

		const match = trimmed.match(/^([^=]+?)\s*=\s*(.+)$/);
		if (!match) continue;

		const key = match[1].trim();
		const value = match[2].trim();
		if (key === "palette") {
			const paletteMatch = value.match(/^(\d+)=\s*(#[0-9a-fA-F]{6})$/);
			if (!paletteMatch) continue;
			values.palette.push({
				index: Number(paletteMatch[1]),
				color: paletteMatch[2].toLowerCase(),
			});
			continue;
		}

		if (!THEME_COLOR_KEYS.includes(key)) continue;
		const normalized = normalizeHex(value);
		if (!normalized) continue;
		values[key] = normalized;
		keyLines.set(key, index);
	}

	return {
		lines,
		values,
		keyLines,
	};
}

function serializeTheme(parsed, normalizedValues) {
	const lines = [...parsed.lines];
	const handled = new Set();

	for (let index = 0; index < lines.length; index += 1) {
		const trimmed = lines[index].trim();
		if (!trimmed || trimmed.startsWith("#")) continue;

		const match = trimmed.match(/^([^=]+?)\s*=\s*(.+)$/);
		if (!match) continue;

		const key = match[1].trim();
		if (!THEME_COLOR_KEYS.includes(key) || !(key in normalizedValues)) continue;

		lines[index] = `${key} = ${normalizedValues[key]}`;
		handled.add(key);
	}

	for (const key of THEME_COLOR_KEYS) {
		if (!(key in normalizedValues) || handled.has(key)) continue;
		lines.push(`${key} = ${normalizedValues[key]}`);
	}

	return `${lines.join("\n").replace(/\n+$/u, "")}\n`;
}

function hexToRgb(hex) {
	return {
		r: Number.parseInt(hex.slice(1, 3), 16),
		g: Number.parseInt(hex.slice(3, 5), 16),
		b: Number.parseInt(hex.slice(5, 7), 16),
	};
}

function channelLuminance(value) {
	const normalized = value / 255;
	if (normalized <= 0.04045) return normalized / 12.92;
	return ((normalized + 0.055) / 1.055) ** 2.4;
}

function luminance(hex) {
	const rgb = hexToRgb(hex);
	return (
		0.2126 * channelLuminance(rgb.r) +
		0.7152 * channelLuminance(rgb.g) +
		0.0722 * channelLuminance(rgb.b)
	);
}

function contrastRatio(left, right) {
	const a = luminance(left);
	const b = luminance(right);
	const lighter = Math.max(a, b);
	const darker = Math.min(a, b);
	return (lighter + 0.05) / (darker + 0.05);
}

function colorDistance(left, right) {
	const a = hexToRgb(left);
	const b = hexToRgb(right);
	const dr = a.r - b.r;
	const dg = a.g - b.g;
	const db = a.b - b.b;
	return dr * dr + dg * dg + db * db;
}

function uniqueColors(colors) {
	const result = [];
	const seen = new Set();

	for (const color of colors) {
		const normalized = normalizeHex(color);
		if (!normalized || seen.has(normalized)) continue;
		seen.add(normalized);
		result.push(normalized);
	}

	return result;
}

function pickClosestAccessibleColor({
	preferred,
	candidates,
	against,
	threshold,
	fallbackCandidates = [],
}) {
	const preferredColor = normalizeHex(preferred) ?? "#ffffff";
	const accessible = uniqueColors([
		...candidates,
		...fallbackCandidates,
	]).filter((color) => contrastRatio(color, against) >= threshold);

	if (accessible.length === 0) {
		throw new Error(
			`No accessible colors available for ${preferredColor} against ${against} at ${threshold}:1`,
		);
	}

	accessible.sort((left, right) => {
		const distanceDelta =
			colorDistance(left, preferredColor) -
			colorDistance(right, preferredColor);
		if (distanceDelta !== 0) return distanceDelta;
		return contrastRatio(right, against) - contrastRatio(left, against);
	});

	return accessible[0];
}

function candidatePool(values) {
	return uniqueColors([
		values.foreground,
		values["cursor-color"],
		values["cursor-text"],
		values["selection-background"],
		values["selection-foreground"],
		...values.palette.map((entry) => entry.color),
		"#000000",
		"#ffffff",
	]);
}

function normalizeThemeValues(values) {
	const background = normalizeHex(values.background);
	if (!background) {
		throw new Error("Theme is missing a valid background color");
	}

	const normalized = {
		...values,
		background,
	};
	const baseCandidates = candidatePool(values);

	const foreground = (() => {
		const current = normalizeHex(values.foreground);
		if (
			current &&
			contrastRatio(current, background) >= CONTRAST_RULES.foreground
		) {
			return current;
		}

		return pickClosestAccessibleColor({
			preferred:
				current ?? values["cursor-color"] ?? values["selection-foreground"],
			candidates: baseCandidates,
			against: background,
			threshold: CONTRAST_RULES.foreground,
			fallbackCandidates: ["#000000", "#ffffff"],
		});
	})();

	normalized.foreground = foreground;

	const extendedCandidates = uniqueColors([foreground, ...baseCandidates]);

	const cursorColor = (() => {
		const current = normalizeHex(values["cursor-color"]);
		if (
			current &&
			contrastRatio(current, background) >= CONTRAST_RULES.cursor
		) {
			return current;
		}

		return pickClosestAccessibleColor({
			preferred: current ?? foreground,
			candidates: [foreground, ...extendedCandidates],
			against: background,
			threshold: CONTRAST_RULES.cursor,
			fallbackCandidates: ["#000000", "#ffffff"],
		});
	})();

	normalized["cursor-color"] = cursorColor;

	const cursorText = (() => {
		const current = normalizeHex(values["cursor-text"]);
		if (
			current &&
			contrastRatio(current, cursorColor) >= CONTRAST_RULES.cursorText
		) {
			return current;
		}

		return pickClosestAccessibleColor({
			preferred: current ?? background,
			candidates: [background, foreground, ...extendedCandidates],
			against: cursorColor,
			threshold: CONTRAST_RULES.cursorText,
			fallbackCandidates: ["#000000", "#ffffff"],
		});
	})();

	normalized["cursor-text"] = cursorText;

	const selectionBackground = (() => {
		const current = normalizeHex(values["selection-background"]);
		if (
			current &&
			contrastRatio(current, background) >= CONTRAST_RULES.selectionBackground
		) {
			return current;
		}

		return pickClosestAccessibleColor({
			preferred: current ?? cursorColor,
			candidates: [foreground, cursorColor, ...extendedCandidates],
			against: background,
			threshold: CONTRAST_RULES.selectionBackground,
			fallbackCandidates: ["#000000", "#ffffff"],
		});
	})();

	normalized["selection-background"] = selectionBackground;

	const selectionForeground = (() => {
		const current = normalizeHex(values["selection-foreground"]);
		if (
			current &&
			contrastRatio(current, selectionBackground) >=
				CONTRAST_RULES.selectionText
		) {
			return current;
		}

		return pickClosestAccessibleColor({
			preferred: current ?? background,
			candidates: [background, foreground, cursorText, ...extendedCandidates],
			against: selectionBackground,
			threshold: CONTRAST_RULES.selectionText,
			fallbackCandidates: ["#000000", "#ffffff"],
		});
	})();

	normalized["selection-foreground"] = selectionForeground;
	return normalized;
}

function auditThemeValues(values) {
	const background = normalizeHex(values.background);
	const foreground = normalizeHex(values.foreground);
	const cursorColor = normalizeHex(values["cursor-color"]);
	const cursorText = normalizeHex(values["cursor-text"]);
	const selectionBackground = normalizeHex(values["selection-background"]);
	const selectionForeground = normalizeHex(values["selection-foreground"]);

	return {
		background,
		foreground,
		cursorColor,
		cursorText,
		selectionBackground,
		selectionForeground,
		foregroundRatio:
			background && foreground ? contrastRatio(foreground, background) : null,
		cursorRatio:
			background && cursorColor ? contrastRatio(cursorColor, background) : null,
		cursorTextRatio:
			cursorColor && cursorText ? contrastRatio(cursorText, cursorColor) : null,
		selectionTextRatio:
			selectionBackground && selectionForeground
				? contrastRatio(selectionForeground, selectionBackground)
				: null,
		selectionBackgroundRatio:
			background && selectionBackground
				? contrastRatio(selectionBackground, background)
				: null,
	};
}

function normalizeThemeContent(content) {
	const parsed = parseThemeContent(content);
	const normalizedValues = normalizeThemeValues(parsed.values);
	return {
		content: serializeTheme(parsed, normalizedValues),
		values: normalizedValues,
		audit: auditThemeValues(normalizedValues),
	};
}

function normalizeThemeFile(inputPath, outputPath) {
	const original = fs.readFileSync(inputPath, "utf8");
	const normalized = normalizeThemeContent(original);
	fs.writeFileSync(outputPath, normalized.content, "utf8");
	return normalized;
}

function normalizeThemeManifest(manifestPath) {
	const lines = fs.readFileSync(manifestPath, "utf8").split(/\r?\n/);
	for (const rawLine of lines) {
		const line = rawLine.trim();
		if (!line || line.startsWith("#")) continue;
		const parts = rawLine.split("\t");
		if (parts.length !== 2) {
			throw new Error(`Invalid normalize-manifest row: ${rawLine}`);
		}
		const [inputPath, outputPath] = parts;
		normalizeThemeFile(path.resolve(inputPath), path.resolve(outputPath));
	}
}

function printUsage() {
	console.error(
		`Usage:
  node scripts/theme-contrast.js normalize <input-theme> <output-theme>
  node scripts/theme-contrast.js normalize-manifest <manifest-file>
  node scripts/theme-contrast.js audit <input-theme>`,
	);
}

const scriptPath = fileURLToPath(import.meta.url);

if (process.argv[1] && path.resolve(process.argv[1]) === scriptPath) {
	const [, , mode, inputPath, outputPath] = process.argv;
	try {
		if (mode === "normalize" && inputPath && outputPath) {
			normalizeThemeFile(path.resolve(inputPath), path.resolve(outputPath));
			process.exit(0);
		}

		if (mode === "normalize-manifest" && inputPath) {
			normalizeThemeManifest(path.resolve(inputPath));
			process.exit(0);
		}

		if (mode === "audit" && inputPath) {
			const content = fs.readFileSync(path.resolve(inputPath), "utf8");
			const normalized = normalizeThemeContent(content);
			process.stdout.write(JSON.stringify(normalized.audit, null, 2));
			process.stdout.write("\n");
			process.exit(0);
		}

		printUsage();
		process.exit(1);
	} catch (error) {
		console.error(error instanceof Error ? error.message : String(error));
		process.exit(1);
	}
}

export {
	auditThemeValues,
	CONTRAST_RULES,
	contrastRatio,
	normalizeThemeContent,
	parseThemeContent,
};
