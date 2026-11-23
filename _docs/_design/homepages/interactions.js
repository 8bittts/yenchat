const sessionToggle = document.querySelector("#session-toggle");
let attached = true;
sessionToggle?.addEventListener("click", () => {
	attached = !attached;
	document.querySelector(".terminal-log").hidden = !attached;
	document.querySelector(".detached").hidden = attached;
	sessionToggle.textContent = attached ? "Quit YEN　⌘Q" : "Reopen YEN　↵";
	document.querySelector("#session-status").textContent = attached
		? "Reattached · port 4321"
		: "Detached · port 4321";
});
const panes = document.querySelectorAll("[data-pane]");
for (const pane of panes)
	pane.addEventListener("click", () => {
		for (const peer of panes)
			peer.setAttribute("aria-pressed", String(peer === pane));
		const other = [...panes].find((peer) => peer !== pane);
		document.querySelector("#pane-caption").textContent =
			pane.dataset.pane +
			" has focus. Select " +
			other.dataset.pane +
			" to move the outline.";
	});
const storyButtons = document.querySelectorAll("[data-story]");
for (const button of storyButtons)
	button.addEventListener("click", () => {
		for (const peer of storyButtons)
			peer.setAttribute("aria-pressed", String(peer === button));
		for (const article of document.querySelectorAll("[data-article]"))
			article.hidden = article.dataset.article !== button.dataset.story;
	});
function openLinkedTopic() {
	const target = document.getElementById(location.hash.slice(1));
	if (target instanceof HTMLDetailsElement) target.open = true;
}
window.addEventListener("hashchange", openLinkedTopic);
openLinkedTopic();
let requestCount = 1;
document.querySelector("#make-request")?.addEventListener("click", () => {
	requestCount += 1;
	const log = document.querySelector("#request-log");
	log.append(
		document.createElement("br"),
		"GET / 200 · request " + requestCount,
	);
	document.querySelector("#session-status").textContent =
		"200 OK · request " +
		requestCount +
		(attached ? " · attached" : " · app closed");
});
