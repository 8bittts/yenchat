#!/usr/bin/env bun

/**
 * Import the Substack export of blog.yen.chat into the self-hosted blog.
 *
 * Usage:
 *   bun scripts/47-import-substack-blog.ts --export <substack-export-dir> --cache <media-cache-dir>
 *   bun scripts/47-import-substack-blog.ts --export <dir> --cache <dir> --convert-only
 *   Add --concurrency <n> (default 6) to run more downloads at once.
 *
 * Phases, each resumable:
 *   1. Parse `posts.csv` and every published `posts/<id>.<slug>.html` body.
 *   2. Rewrite Substack markup into the small HTML subset the blog renders,
 *      collecting every image and video the body uses.
 *   3. Download each media file into the cache directory (skips files already
 *      cached). Images are the 848px and 1456px webp copies Substack served to
 *      readers; GIFs and videos are the originals.
 *   4. Copy the cached media into `public/blog-media/`, served same-origin.
 *   5. Write one `content/blog/posts/<slug>.json` per published post. Run
 *      `bun scripts/gen-blog-slugs.ts` afterwards to rebuild the route index.
 *
 * Nothing in the output depends on Substack hosting: media URLs are
 * `/blog-media/...`, and links to other posts point at `/<slug>` on
 * blog.yen.chat. The script fails closed on a missing post, an unknown Substack
 * component, an unknown media type, a link to an unknown post, or a failed download.
 */

import {
	copyFileSync,
	existsSync,
	mkdirSync,
	readdirSync,
	readFileSync,
	renameSync,
	rmSync,
	statSync,
	writeFileSync,
} from "node:fs";
import path from "node:path";
import { type Element as DomElement, Window } from "happy-dom";
import sanitizeHtml from "sanitize-html";

/** Public path of the blog media; the files live in `public/blog-media/`. */
const MEDIA_BASE = "/blog-media";
const PUBLIC_MEDIA_DIR = path.join(process.cwd(), "public", "blog-media");
const CONTENT_DIR = path.join(process.cwd(), "content", "blog");
/** Hosts that served the Substack publication: the custom domain and the substack.com subdomain. */
const SUBSTACK_HOST =
	/^https?:\/\/(?:blog\.yen\.chat|yenchat\.substack\.com)(?=\/|$)/i;
/** Substack media is fetched through the subdomain so the import still works after the DNS cutover. */
const SUBSTACK_API = "https://yenchat.substack.com/api/v1";
const IMAGE_WIDTHS = [848, 1456] as const;
const DEFAULT_CONCURRENCY = 6;

type AssetKind = "image-gif" | "image-variant" | "video";

interface Asset {
	kind: AssetKind;
	sourceUrl: string;
	storagePath: string;
}

interface CsvPost {
	postId: string;
	slug: string;
	numericId: string;
	publishedAt: string;
	title: string;
	subtitle: string;
}

interface BlogImage {
	src: string;
	width: number;
	height: number;
}

interface ConvertedPost {
	slug: string;
	postId: string;
	/** Every Substack post was written by the creator. */
	author: "creator";
	title: string;
	subtitle: string;
	publishedAt: string;
	coverImage: BlogImage | null;
	wordCount: number;
	html: string;
}

// ---------------------------------------------------------------- CLI

function readFlag(name: string): string | null {
	const index = process.argv.indexOf(name);
	return index >= 0 ? (process.argv[index + 1] ?? null) : null;
}

function requireDir(flag: string): string {
	const value = readFlag(flag);
	if (!value) throw new Error(`Missing ${flag} <dir>`);
	return path.resolve(value);
}

// ---------------------------------------------------------------- CSV

interface CsvState {
	rows: string[][];
	row: string[];
	field: string;
	quoted: boolean;
}

/** Consumes one character; returns how many extra characters it used (an escaped quote uses one). */
function stepCsv(
	state: CsvState,
	char: string,
	next: string | undefined,
): number {
	if (state.quoted) {
		if (char === '"' && next === '"') {
			state.field += '"';
			return 1;
		}
		if (char === '"') state.quoted = false;
		else state.field += char;
		return 0;
	}
	if (char === '"') state.quoted = true;
	else if (char === ",") {
		state.row.push(state.field);
		state.field = "";
	} else if (char === "\n") {
		state.rows.push([...state.row, state.field]);
		state.row = [];
		state.field = "";
	} else if (char !== "\r") state.field += char;
	return 0;
}

function parseCsv(text: string): string[][] {
	const state: CsvState = { rows: [], row: [], field: "", quoted: false };
	for (let i = 0; i < text.length; i++)
		i += stepCsv(state, text[i] ?? "", text[i + 1]);
	if (state.field || state.row.length)
		state.rows.push([...state.row, state.field]);
	return state.rows;
}

function readPublishedPosts(exportDir: string): CsvPost[] {
	const [header = [], ...rows] = parseCsv(
		readFileSync(path.join(exportDir, "posts.csv"), "utf8"),
	);
	const col = (name: string) => {
		const index = header.indexOf(name);
		if (index < 0) throw new Error(`posts.csv is missing column ${name}`);
		return index;
	};
	const [idCol, publishedCol, dateCol, titleCol, subtitleCol] = [
		col("post_id"),
		col("is_published"),
		col("post_date"),
		col("title"),
		col("subtitle"),
	];
	return rows
		.filter((row) => row[publishedCol] === "true")
		.map((row) => {
			const postId = row[idCol] ?? "";
			const dot = postId.indexOf(".");
			return {
				postId,
				numericId: postId.slice(0, dot),
				slug: postId.slice(dot + 1),
				publishedAt: row[dateCol] ?? "",
				title: (row[titleCol] ?? "").trim(),
				subtitle: (row[subtitleCol] ?? "").trim(),
			};
		});
}

// ---------------------------------------------------------------- Media naming

function s3ImageUrlFrom(src: string): string {
	const decoded = decodeURIComponent(src);
	const match = decoded.match(
		/https:\/\/substack-post-media\.s3\.amazonaws\.com\/public\/images\/[^\s?"]+/,
	);
	if (!match) throw new Error(`Unrecognized image source: ${src}`);
	return match[0];
}

function isGif(name: string): boolean {
	return name.toLowerCase().endsWith(".gif");
}

function variantName(baseName: string, width: number): string {
	return `${baseName.replace(/\.[a-z0-9]+$/i, "")}.w${width}.webp`;
}

function mediaUrl(storagePath: string): string {
	return `${MEDIA_BASE}/${storagePath.split("/").map(encodeURIComponent).join("/")}`;
}

// ---------------------------------------------------------------- Conversion context

class ConversionContext {
	readonly assets = new Map<string, Asset>();
	readonly unknownComponents = new Set<string>();

	constructor(
		readonly slugs: ReadonlySet<string>,
		readonly slugByNumericId: ReadonlyMap<string, string>,
	) {}

	addAsset(asset: Asset): string {
		this.assets.set(asset.storagePath, asset);
		return mediaUrl(asset.storagePath);
	}

	/**
	 * Registers the webp display copies of an image, or the original of a GIF
	 * (a webp copy would lose its animation); `full` is the largest copy.
	 */
	addImage(sourceUrl: string): {
		full: string;
		variants: { width: number; url: string }[];
	} {
		const baseName = path.posix.basename(new URL(sourceUrl).pathname);
		if (isGif(baseName)) {
			const full = this.addAsset({
				kind: "image-gif",
				sourceUrl,
				storagePath: `images/${baseName}`,
			});
			return { full, variants: [] };
		}
		const variants = IMAGE_WIDTHS.map((width) => ({
			width,
			url: this.addAsset({
				kind: "image-variant",
				sourceUrl: `https://substackcdn.com/image/fetch/w_${width},c_limit,f_webp,q_auto:good,fl_progressive:steep/${encodeURIComponent(sourceUrl)}`,
				storagePath: `images/${variantName(baseName, width)}`,
			}),
		}));
		return { full: variants.at(-1)?.url ?? "", variants };
	}

	/** Maps a Substack link to its blog.yen.chat path; leaves every other link unchanged. */
	rewriteHref(href: string): string {
		if (!SUBSTACK_HOST.test(href)) return href;
		const url = new URL(href);
		// Some authored links carry trailing sentence punctuation inside the href, e.g. "/p/pickaxes)".
		const postMatch = url.pathname.match(/^\/p\/([^/]+?)[).,;:]*(?:\/|$)/);
		if (postMatch?.[1]) return this.postPath(postMatch[1], href);
		const draftMatch = url.pathname.match(/^\/(?:publish\/post|i)\/(\d+)/);
		if (draftMatch?.[1])
			return this.postPath(this.slugByNumericId.get(draftMatch[1]) ?? "", href);
		return "/";
	}

	private postPath(slug: string, original: string): string {
		if (!this.slugs.has(slug))
			throw new Error(`Link to unknown blog post: ${original}`);
		return `/${slug}`;
	}
}

// ---------------------------------------------------------------- Element converters

type El = DomElement;

function parseAttrs(element: El): Record<string, unknown> {
	const raw = element.getAttribute("data-attrs");
	return raw ? (JSON.parse(raw) as Record<string, unknown>) : {};
}

function escapeHtml(value: string): string {
	return value
		.replace(/&/g, "&amp;")
		.replace(/</g, "&lt;")
		.replace(/>/g, "&gt;")
		.replace(/"/g, "&quot;");
}

function replaceWith(element: El, markup: string): void {
	element.outerHTML = markup;
}

function figureMarkup(
	images: ReturnType<ConversionContext["addImage"]>,
	options: {
		width: number;
		height: number;
		alt: string;
		href: string;
		caption: string;
	},
): string {
	const display = images.full;
	const srcset = images.variants
		.map((variant) => `${variant.url} ${variant.width}w`)
		.join(", ");
	const srcsetAttr = srcset
		? ` srcset="${srcset}" sizes="(min-width: 768px) 768px, 100vw"`
		: "";
	const captionHtml = options.caption
		? `<figcaption>${options.caption}</figcaption>`
		: "";
	return `<figure class="blog-figure"><a href="${options.href}"><img src="${display}"${srcsetAttr} width="${options.width}" height="${options.height}" alt="${escapeHtml(options.alt)}" loading="lazy" decoding="async"></a>${captionHtml}</figure>`;
}

function convertImage(container: El, ctx: ConversionContext): void {
	const img = container.querySelector("img");
	if (!img) throw new Error("Image container without <img>");
	const attrs = parseAttrs(img);
	const images = ctx.addImage(s3ImageUrlFrom(img.getAttribute("src") ?? ""));
	replaceWith(
		container,
		figureMarkup(images, {
			width: Math.round(
				Number(img.getAttribute("width")) || Number(attrs.width) || 1200,
			),
			height: Math.round(
				Number(img.getAttribute("height")) || Number(attrs.height) || 800,
			),
			alt:
				typeof attrs.alt === "string"
					? attrs.alt
					: (img.getAttribute("alt") ?? ""),
			href:
				typeof attrs.href === "string" && attrs.href
					? ctx.rewriteHref(attrs.href)
					: images.full,
			caption: container.querySelector("figcaption")?.innerHTML ?? "",
		}),
	);
}

function convertYoutube(element: El): void {
	const attrs = parseAttrs(element);
	const videoId = String(attrs.videoId ?? "");
	if (!/^[\w-]{6,}$/.test(videoId))
		throw new Error(`Bad YouTube id: ${videoId}`);
	const start =
		Number(attrs.startTime) > 0 ? `&start=${Number(attrs.startTime)}` : "";
	const end = Number(attrs.endTime) > 0 ? `&end=${Number(attrs.endTime)}` : "";
	replaceWith(
		element,
		`<figure class="blog-embed"><iframe src="https://www.youtube-nocookie.com/embed/${videoId}?rel=0${start}${end}" title="YouTube video" loading="lazy" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture" allowfullscreen referrerpolicy="strict-origin-when-cross-origin" sandbox="allow-scripts allow-same-origin allow-presentation allow-popups allow-popups-to-escape-sandbox"></iframe></figure>`,
	);
}

function convertVideo(element: El, ctx: ConversionContext): void {
	const id = String(parseAttrs(element).mediaUploadId ?? "");
	if (!id) throw new Error("Video without mediaUploadId");
	const src = ctx.addAsset({
		kind: "video",
		sourceUrl: `${SUBSTACK_API}/video/upload/${id}/src`,
		storagePath: `videos/${id}.mp4`,
	});
	replaceWith(
		element,
		`<video class="blog-video" src="${src}" controls preload="metadata" playsinline></video>`,
	);
}

function convertCodeBlock(element: El): void {
	const code = element.querySelector("code");
	if (!code) throw new Error("Code block without <code>");
	replaceWith(
		element,
		`<pre><code>${escapeHtml(code.textContent ?? "")}</code></pre>`,
	);
}

function convertTweet(element: El, ctx: ConversionContext): void {
	const attrs = parseAttrs(element);
	const url = String(attrs.url ?? "");
	if (!/^https:\/\/(?:x|twitter)\.com\//.test(url))
		throw new Error(`Bad tweet URL: ${url}`);
	const photos = Array.isArray(attrs.photos)
		? (attrs.photos as { img_url?: string }[])
		: [];
	const images = photos
		.map((photo) => photo.img_url ?? "")
		.filter((src) => src.startsWith("https://pbs.substack.com/media/"))
		.map((src) => {
			const { full } = ctx.addImage(src);
			return `<p><img src="${full}" alt="" loading="lazy" decoding="async"></p>`;
		})
		.join("");
	const date = new Date(String(attrs.date ?? "")).toLocaleDateString("en-US", {
		year: "numeric",
		month: "long",
		day: "numeric",
		timeZone: "UTC",
	});
	const name = escapeHtml(String(attrs.name ?? ""));
	const username = escapeHtml(String(attrs.username ?? ""));
	replaceWith(
		element,
		`<blockquote class="blog-embed-card"><p>${escapeHtml(String(attrs.full_text ?? "").trim())}</p>${images}<p>— ${name} (@${username}) <a href="${url}">${date}</a></p></blockquote>`,
	);
}

function convertDigestEmbed(element: El, ctx: ConversionContext): void {
	const attrs = parseAttrs(element);
	const href = ctx.rewriteHref(String(attrs.canonical_url ?? ""));
	const caption = attrs.caption
		? `<p>${escapeHtml(String(attrs.caption))}</p>`
		: "";
	replaceWith(
		element,
		`<blockquote class="blog-embed-card"><p><a href="${href}"><strong>${escapeHtml(String(attrs.title ?? ""))}</strong></a></p>${caption}</blockquote>`,
	);
}

function convertButton(element: El, ctx: ConversionContext): void {
	const link = element.querySelector("a");
	const href = link?.getAttribute("href") ?? "";
	if (!link || /\/subscribe(?:[?#]|$)/i.test(href)) {
		element.remove();
		return;
	}
	const text = link.textContent?.trim() ?? "";
	replaceWith(
		element,
		`<p class="blog-cta"><a href="${ctx.rewriteHref(href)}">${escapeHtml(text)}</a></p>`,
	);
}

const COMPONENT_CONVERTERS: Record<
	string,
	(element: El, ctx: ConversionContext) => void
> = {
	Youtube2ToDOM: (element) => convertYoutube(element),
	VideoPlaceholder: convertVideo,
	HighlightedCodeBlockToDOM: (element) => convertCodeBlock(element),
	Twitter2ToDOM: convertTweet,
	ButtonCreateButton: convertButton,
	SubscribeWidgetToDOM: (element) => element.remove(),
};

/** Components handled through their wrapping element rather than their own node. */
const PASSIVE_COMPONENTS = new Set(["Image2ToDOM"]);

function convertComponents(root: El, ctx: ConversionContext): void {
	for (const container of root.querySelectorAll(
		"div.captioned-image-container",
	))
		convertImage(container, ctx);
	for (const embed of root.querySelectorAll("div.digest-post-embed"))
		convertDigestEmbed(embed, ctx);
	for (const element of root.querySelectorAll("[data-component-name]")) {
		const name = element.getAttribute("data-component-name") ?? "";
		const converter = COMPONENT_CONVERTERS[name];
		if (converter) converter(element, ctx);
		else if (!PASSIVE_COMPONENTS.has(name)) ctx.unknownComponents.add(name);
	}
	for (const leftover of root.querySelectorAll(
		"img, picture, iframe, video, audio, form",
	)) {
		const inConverted = leftover.closest(
			".blog-figure, .blog-embed, .blog-embed-card",
		);
		if (!inConverted && !leftover.matches(".blog-video")) {
			throw new Error(`Unconverted media: ${leftover.outerHTML.slice(0, 200)}`);
		}
	}
}

function rewriteLinks(root: El, ctx: ConversionContext): void {
	for (const anchor of root.querySelectorAll("a[href]")) {
		const rewritten = ctx.rewriteHref(anchor.getAttribute("href") ?? "");
		anchor.setAttribute("href", rewritten);
		if (/^https?:\/\//.test(rewritten) && !rewritten.startsWith(MEDIA_BASE)) {
			anchor.setAttribute("target", "_blank");
			anchor.setAttribute("rel", "noopener noreferrer");
		}
	}
}

const SANITIZE_OPTIONS: sanitizeHtml.IOptions = {
	allowedTags: [
		"p",
		"h2",
		"h3",
		"h4",
		"h5",
		"h6",
		"a",
		"strong",
		"em",
		"b",
		"i",
		"u",
		"s",
		"code",
		"pre",
		"blockquote",
		"ul",
		"ol",
		"li",
		"hr",
		"br",
		"sup",
		"sub",
		"figure",
		"figcaption",
		"img",
		"iframe",
		"video",
	],
	allowedAttributes: {
		a: ["href", "target", "rel"],
		img: [
			"src",
			"srcset",
			"sizes",
			"width",
			"height",
			"alt",
			"loading",
			"decoding",
		],
		// Same embed attributes as app/docs: YouTube needs a referrer and allow-same-origin to build its player.
		iframe: [
			"src",
			"title",
			"loading",
			"allow",
			"allowfullscreen",
			"referrerpolicy",
			"sandbox",
		],
		video: ["src", "controls", "preload", "playsinline", "class"],
		figure: ["class"],
		p: ["class"],
		blockquote: ["class"],
		ol: ["start"],
	},
	allowedClasses: {
		figure: ["blog-figure", "blog-embed"],
		p: ["blog-cta"],
		blockquote: ["blog-embed-card"],
		video: ["blog-video"],
	},
	allowedSchemes: ["https", "http", "mailto"],
	allowedSchemesAppliedToAttributes: ["href", "src"],
	allowedIframeHostnames: ["www.youtube-nocookie.com"],
	allowProtocolRelative: false,
	transformTags: { h1: "h2" },
};

function tidy(markup: string): string {
	return sanitizeHtml(markup, SANITIZE_OPTIONS)
		.replace(/<p>\s*<\/p>/g, "")
		.trim();
}

/** Gives each h2/h3 a stable anchor id so the post page can list its sections. */
function addHeadingIds(root: El): void {
	const used = new Set<string>();
	for (const heading of root.querySelectorAll("h2, h3")) {
		const base =
			(heading.textContent ?? "")
				.toLowerCase()
				.replace(/[^a-z0-9]+/g, "-")
				.replace(/^-+|-+$/g, "")
				.slice(0, 60) || "section";
		let id = base;
		for (let n = 2; used.has(id); n++) id = `${base}-${n}`;
		used.add(id);
		heading.setAttribute("id", id);
	}
}

function firstImage(root: El): BlogImage | null {
	const img = root.querySelector(".blog-figure img");
	if (!img) return null;
	return {
		src: img.getAttribute("src") ?? "",
		width: Number(img.getAttribute("width")) || 1200,
		height: Number(img.getAttribute("height")) || 630,
	};
}

function convertPost(
	post: CsvPost,
	body: string,
	ctx: ConversionContext,
): ConvertedPost {
	const window = new Window();
	const root = window.document.createElement("div");
	root.innerHTML = body;
	convertComponents(root, ctx);
	rewriteLinks(root, ctx);
	const check = window.document.createElement("div");
	check.innerHTML = tidy(root.innerHTML);
	addHeadingIds(check);
	const markup = check.innerHTML;
	const converted: ConvertedPost = {
		slug: post.slug,
		postId: post.numericId,
		author: "creator",
		title: post.title,
		subtitle: post.subtitle,
		publishedAt: post.publishedAt,
		coverImage: firstImage(check),
		wordCount: (check.textContent ?? "").split(/\s+/).filter(Boolean).length,
		html: markup,
	};
	window.close();
	return converted;
}

// ---------------------------------------------------------------- Download + publish

async function pool<T>(
	items: readonly T[],
	worker: (item: T) => Promise<void>,
): Promise<void> {
	let next = 0;
	const run = async () => {
		for (let item = items[next++]; item !== undefined; item = items[next++])
			await worker(item);
	};
	const concurrency = Number(readFlag("--concurrency")) || DEFAULT_CONCURRENCY;
	await Promise.all(Array.from({ length: concurrency }, run));
}

async function fetchWithRetry(url: string, attempts = 4): Promise<Response> {
	let lastError: unknown;
	for (let attempt = 1; attempt <= attempts; attempt++) {
		try {
			const response = await fetch(url, { redirect: "follow" });
			if (response.ok) return response;
			lastError = new Error(`HTTP ${response.status} for ${url}`);
			if (response.status === 404) break;
		} catch (error) {
			lastError = error;
		}
		await Bun.sleep(1000 * attempt);
	}
	throw lastError;
}

async function downloadAll(
	assets: readonly Asset[],
	cacheDir: string,
): Promise<string[]> {
	const failures: string[] = [];
	await pool(assets, async (asset) => {
		const target = path.join(cacheDir, asset.storagePath);
		if (existsSync(target) && statSync(target).size > 0) return;
		try {
			const response = await fetchWithRetry(asset.sourceUrl);
			mkdirSync(path.dirname(target), { recursive: true });
			await Bun.write(`${target}.part`, response);
			if (statSync(`${target}.part`).size === 0) throw new Error("empty body");
			renameSync(`${target}.part`, target);
		} catch (error) {
			failures.push(
				`${asset.storagePath} <- ${asset.sourceUrl}: ${String(error)}`,
			);
		}
	});
	return failures;
}

const MEDIA_EXTENSIONS = new Set([".gif", ".webp", ".mp4"]);

function unexpectedMediaTypes(assets: readonly Asset[]): string[] {
	return assets
		.map((asset) => asset.storagePath)
		.filter(
			(storagePath) =>
				!MEDIA_EXTENSIONS.has(path.extname(storagePath).toLowerCase()),
		);
}

/** Replaces public/blog-media/ with the cached copy of every media file the posts use. */
function publishMedia(assets: readonly Asset[], cacheDir: string): void {
	rmSync(PUBLIC_MEDIA_DIR, { recursive: true, force: true });
	for (const asset of assets) {
		const target = path.join(PUBLIC_MEDIA_DIR, asset.storagePath);
		mkdirSync(path.dirname(target), { recursive: true });
		copyFileSync(path.join(cacheDir, asset.storagePath), target);
	}
}

// ---------------------------------------------------------------- Main

function failIf(problems: readonly string[], label: string): void {
	if (problems.length === 0) return;
	console.error(`\n${label} (${problems.length}):`);
	for (const problem of problems.slice(0, 50)) console.error(`   ${problem}`);
	process.exit(1);
}

function convertAll(
	exportDir: string,
	posts: readonly CsvPost[],
): { converted: ConvertedPost[]; ctx: ConversionContext } {
	const ctx = new ConversionContext(
		new Set(posts.map((post) => post.slug)),
		new Map(posts.map((post) => [post.numericId, post.slug])),
	);
	const bodies = new Set(
		readdirSync(path.join(exportDir, "posts")).filter((name) =>
			name.endsWith(".html"),
		),
	);
	failIf(
		posts
			.filter((post) => !bodies.has(`${post.postId}.html`))
			.map((post) => post.postId),
		"Published posts without an HTML body",
	);
	const converted = posts.map((post) =>
		convertPost(
			post,
			readFileSync(
				path.join(exportDir, "posts", `${post.postId}.html`),
				"utf8",
			),
			ctx,
		),
	);
	failIf([...ctx.unknownComponents], "Unrecognized Substack components");
	return { converted, ctx };
}

function writePosts(converted: readonly ConvertedPost[]): void {
	rmSync(CONTENT_DIR, { recursive: true, force: true });
	mkdirSync(path.join(CONTENT_DIR, "posts"), { recursive: true });
	for (const post of converted) {
		writeFileSync(
			path.join(CONTENT_DIR, "posts", `${post.slug}.json`),
			`${JSON.stringify(post, null, "\t")}\n`,
		);
	}
}

async function main(): Promise<void> {
	const exportDir = requireDir("--export");
	const cacheDir = requireDir("--cache");
	const posts = readPublishedPosts(exportDir);
	console.log(`1. ${posts.length} published posts in posts.csv`);

	// The importer replaces both the post archive and its media directory.
	const postsDir = path.join(CONTENT_DIR, "posts");
	if (existsSync(postsDir)) {
		const incoming = new Set(posts.map((post) => `${post.slug}.json`));
		failIf(
			readdirSync(postsDir).filter(
				(name) => name.endsWith(".json") && !incoming.has(name),
			),
			"Import would remove local posts",
		);
	}
	const { converted, ctx } = convertAll(exportDir, posts);
	const assets = [...ctx.assets.values()];
	failIf(unexpectedMediaTypes(assets), "Unexpected media types");
	console.log(
		`2. Converted ${converted.length} posts; ${assets.length} media files`,
	);

	if (process.argv.includes("--convert-only")) {
		writePosts(converted);
		console.log(
			`Wrote ${converted.length} posts without touching media (--convert-only)`,
		);
		return;
	}

	console.log("3. Downloading media into the cache");
	failIf(await downloadAll(assets, cacheDir), "Media downloads failed");

	publishMedia(assets, cacheDir);
	console.log(`4. Copied ${assets.length} media files to public/blog-media/`);

	writePosts(converted);
	console.log(
		`5. Wrote ${converted.length} posts to ${path.relative(process.cwd(), CONTENT_DIR)}/`,
	);
}

await main();
