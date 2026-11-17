import { describe, expect, test } from "bun:test";
import { NextRequest } from "next/server";
import {
	blogUrlForMainHostPath,
	routeBlogHostPath,
} from "@/lib/http/blog-host";
import { proxy } from "@/proxy";

describe("blog.yen.chat host routing", () => {
	test("renders the index, posts, and blog files from app/blog", () => {
		expect(routeBlogHostPath("/")).toEqual({ kind: "page", pathname: "/blog" });
		expect(routeBlogHostPath("/skills")).toEqual({
			kind: "page",
			pathname: "/blog/skills",
		});
		expect(routeBlogHostPath("/feed")).toEqual({
			kind: "file",
			pathname: "/blog/feed",
		});
		expect(routeBlogHostPath("/sitemap.xml")).toEqual({
			kind: "file",
			pathname: "/blog/sitemap.xml",
		});
		expect(routeBlogHostPath("/robots.txt")).toEqual({
			kind: "file",
			pathname: "/blog/robots.txt",
		});
	});

	test("redirects Substack /p/ addresses to the clean post address", () => {
		expect(routeBlogHostPath("/p/skills")).toEqual({
			kind: "redirect",
			url: "https://blog.yen.chat/skills",
		});
		expect(routeBlogHostPath("/p/skills/comments")).toEqual({
			kind: "redirect",
			url: "https://blog.yen.chat/skills",
		});
		expect(routeBlogHostPath("/p/no-such-post")).toEqual({
			kind: "redirect",
			url: "https://blog.yen.chat/",
		});
		expect(routeBlogHostPath("/skills/")).toEqual({
			kind: "redirect",
			url: "https://blog.yen.chat/skills",
		});
	});

	test("sends Substack-only pages to the index and site pages to yen.chat", () => {
		for (const path of [
			"/archive",
			"/about",
			"/subscribe",
			"/s/notes",
			"/podcast",
		]) {
			expect(routeBlogHostPath(path)).toEqual({
				kind: "redirect",
				url: "https://blog.yen.chat/",
			});
		}
		expect(routeBlogHostPath("/docs")).toEqual({
			kind: "redirect",
			url: "https://yen.chat/docs",
		});
		expect(routeBlogHostPath("/download")).toEqual({
			kind: "redirect",
			url: "https://yen.chat/download",
		});
		expect(routeBlogHostPath("/blog/skills")).toEqual({
			kind: "redirect",
			url: "https://yen.chat/blog/skills",
		});
	});

	test("lets shared assets load from the blog host", () => {
		for (const path of [
			"/_next/static/chunks/app.js",
			"/_vercel/insights/view",
			"/api/x",
			"/favicon.ico",
			"/og-image.png",
		]) {
			expect(routeBlogHostPath(path)).toEqual({ kind: "asset" });
		}
	});

	test("moves yen.chat/blog to blog.yen.chat", () => {
		expect(blogUrlForMainHostPath("/blog")).toBe("https://blog.yen.chat/");
		expect(blogUrlForMainHostPath("/blog/skills")).toBe(
			"https://blog.yen.chat/skills",
		);
		expect(blogUrlForMainHostPath("/blogger")).toBeNull();
		expect(blogUrlForMainHostPath("/docs")).toBeNull();
	});
});

describe("proxy on blog.yen.chat", () => {
	function request(url: string) {
		return new NextRequest(url, { headers: { host: new URL(url).host } });
	}

	test("308s a Substack address to the clean post address", () => {
		const response = proxy(
			request("https://blog.yen.chat/p/skills?utm_source=x"),
		);
		expect(response.status).toBe(308);
		expect(response.headers.get("location")).toBe(
			"https://blog.yen.chat/skills?utm_source=x",
		);
	});

	test("renders a post from /blog/<slug> with a page CSP", () => {
		const response = proxy(request("https://blog.yen.chat/skills"));
		expect(response.headers.get("x-middleware-rewrite")).toBe(
			"https://blog.yen.chat/blog/skills",
		);
		expect(response.headers.get("content-security-policy")).toContain(
			"script-src 'self'",
		);
	});

	test("rewrites the feed without a page CSP and sends site pages to yen.chat", () => {
		const feed = proxy(request("https://blog.yen.chat/feed"));
		expect(feed.headers.get("x-middleware-rewrite")).toBe(
			"https://blog.yen.chat/blog/feed",
		);
		const docs = proxy(request("https://blog.yen.chat/docs"));
		expect(docs.status).toBe(308);
		expect(docs.headers.get("location")).toBe("https://yen.chat/docs");
	});

	test("answers router fetches of site links without a cross-origin redirect", () => {
		const prefetch = proxy(
			new NextRequest("https://blog.yen.chat/docs", {
				headers: { host: "blog.yen.chat", "sec-fetch-dest": "empty" },
			}),
		);
		expect(prefetch.status).toBe(204);
		expect(prefetch.headers.get("location")).toBeNull();
		const navigation = proxy(
			new NextRequest("https://blog.yen.chat/docs", {
				headers: { host: "blog.yen.chat", "sec-fetch-dest": "document" },
			}),
		);
		expect(navigation.status).toBe(308);
		expect(navigation.headers.get("location")).toBe("https://yen.chat/docs");
	});

	test("moves yen.chat/blog/<slug> to blog.yen.chat", () => {
		const response = proxy(request("https://yen.chat/blog/skills"));
		expect(response.status).toBe(308);
		expect(response.headers.get("location")).toBe(
			"https://blog.yen.chat/skills",
		);
	});
});
