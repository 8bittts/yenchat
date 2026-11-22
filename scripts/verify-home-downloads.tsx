import { JSDOM } from "jsdom";
import { renderToStaticMarkup } from "react-dom/server";
import { HomeClient } from "../app/home-client";
import Home from "../app/page";
import { getVersion } from "../lib/version";
import { getVersionFilename } from "../lib/version-format";

function checkLinks(view: React.ReactElement, version: string) {
	const dom = new JSDOM(renderToStaticMarkup(view));
	try {
		const links = Array.from(dom.window.document.querySelectorAll("main a"));
		const downloads = links.filter((link) =>
			link.textContent?.includes("Download for macOS"),
		);
		if (
			!downloads.length ||
			downloads.some((link) => link.getAttribute("href") !== "/download")
		)
			throw new Error("Expected each macOS download button to use /download");
		const checksum = links.find(
			(link) => link.textContent?.trim() === "SHA256",
		);
		const path = `/stable/yen-${getVersionFilename(version)}.dmg.sha256`;
		if (checksum?.getAttribute("href") !== path)
			throw new Error(`Missing checksum link to ${path}`);
		console.log(
			`Verified ${downloads.length} download buttons and checksum for v${version}`,
		);
	} finally {
		dom.window.close();
	}
}
checkLinks(<Home />, getVersion());
const alternate = getVersion() === "1.002" ? "1.003" : "1.002";
checkLinks(<HomeClient version={alternate} />, alternate);
