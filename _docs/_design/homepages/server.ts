import { join } from "node:path";
import { page } from "./pages";
const root = import.meta.dir;
const media: Record<string, string> = {
	"/style.css": "style.css",
	"/interactions.js": "interactions.js",
	"/assets/mark.png": "../../../public/vector-squashed-2.png",
	"/assets/phosphor.png": "../../../public/yen-logo-square-512.png",
	"/assets/splits.png": "../../../public/doc-images/split-headers.png",
};
for (let i = 0; i < 3; i++)
	media["/assets/cover-" + i + ".webp"] = "cover-" + i + ".webp";
const routes = new Set(["/", "/phosphor", "/field-manual", "/workshop"]);
const server = Bun.serve({
	hostname: "127.0.0.1",
	port: Number(process.env.PORT || 4282),
	fetch(request) {
		const path = new URL(request.url).pathname;
		if (routes.has(path))
			return new Response(page(path), {
				headers: { "Content-Type": "text/html; charset=utf-8" },
			});
		const file = Object.hasOwn(media, path) ? media[path] : undefined;
		if (file) return new Response(Bun.file(join(root, file)));
		return new Response("Page not found", { status: 404 });
	},
});
console.log("YEN homepage concepts at " + server.url);
