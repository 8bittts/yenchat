# Go-To-Market

Public accuracy and legal copy, blog.yen.chat with its release notes, and the content voice of the YEN website.

Design, quality, growth, and release procedures belong to their owners in `00-docs-map.md`.

## Sources of truth

- `app/globals.css` — every token and shared utility.
- `components/shared/page-shell.tsx`, `components/shared/{header,footer}.tsx` — page shells.
- `lib/seo.ts` (`PUBLIC_PAGE_SEO`), `app/sitemap.ts`, `app/robots.ts`, `app/manifest.ts` — metadata and discovery.
- `lib/http/retired-pages.ts` — former main-site paths.
  Known legacy routes redirect to the homepage.
- `proxy.ts` and `scripts/44-build-web-csp.ts` — host validation and CSP.
- `lib/blog.ts`, `lib/http/blog-host.ts`, `app/blog/`, `content/blog/` and `public/blog-media/` — blog.yen.chat ([Blog](#blog-blogyenchat)).
- `lib/release-notes/release-notes-copy.ts` — curated release prose; `lib/release-notes/release-notes-data.ts` is generated.

## Public Accuracy and Legal Copy

[CRITICAL] Homepage copy is locked: the hero and every tagline in `app/home-client.tsx` change only when the operator asks.

- Privacy and terms match the real service map: Sparkle update checks, Apple Speech, Vercel Analytics and Speed Insights, GitHub source and release downloads, YouTube privacy-enhanced embeds, Cloudflare DNS. Never claim "no third parties".
  Remote sessions name Tailscale as software and a network the user installs and controls, never as a YEN service provider, because YEN only reads the local Tailscale status and connects the user's own Macs with ssh ([04-security.md](04-security.md#remote-attach-threat-model)).
- The header links to Docs at `/#guide`, GitHub, and @yenFTW.
- The footer links to Blog, Email, and Terms and displays the YEN copyright.
- Downloads are GitHub Release assets; `/download` redirects to the current DMG and records nothing.
- Public counts come from manifests or scripts (the curated theme manifest for themes), never from old copy; never advertise retired custom sounds or sound packs.
- Historical public assets such as `public/skills.md` may stay reachable but are labeled historical.
- Performance claims: the upstream engine's "about 100x faster than Terminal.app" is its own qualitative claim with no published method; the measured comparison is one workload in its devlog 006 (73 ms versus iTerm2's 470 ms). Never present either as YEN's benchmark, and never call YEN "fastest".
- The site deploys ahead of the desktop app, so the manual, `public/llms.txt` and a blog update note describe what the shipped build does: `public/stable/version.json` names it.
  Write a desktop change that has not shipped as "Starting in YEN <next version>", and keep the current behavior beside it until that build is out.
- Verify source before editing a public surface, and the live `https://yen.chat` response after deploying.
- A copy correction must also check `public/llms.txt` and `app/manifest.ts`; these independent surfaces can retain the same stale claim.
- Social previews use the Phosphor homepage, privacy receipt, journal masthead, and release log.
  An article uses its own cover when available.
- Settings screenshots and recordings are not current feature evidence; compare their labels and controls with the shipped Settings source before placing them in instructions.

## Release Notes

`https://blog.yen.chat/releases` (`app/blog/releases/page.tsx`) is the public build history, grouped into Monday-Sunday weeks, newest first, each with one curated story, its build count and latest version.
The build log has a month index, a permanent anchor for each week, and a listing in the blog sitemap.
The retired yen.chat `/release` 308s there, and each week keeps its `w-<iso>` anchor, so an old week link still lands on its week; the build script's GitHub Release body links the blog page.

- [HARD REQUIREMENT] Structure is generated, voice is curated. `bun scripts/gen-release-notes.ts` writes `release-notes-data.ts` from the frozen `lib/release-notes/release-ledger.ts` (the 514 builds shipped before the open-source history, which the public git log no longer holds) and then from `public/stable/version.json` bump commits; never edit the data file by hand (Biome ignores it), and never add to the ledger. `tests/161` fails if a regeneration drops a ledger build. `RELEASE_COPY` holds each version's factual line and `RELEASE_WEEK_COPY` each week's story; missing copy in either fails generation.
- [HARD REQUIREMENT] Grouping: Monday-Sunday weeks; provenance sorted by ship day then version, descending; a week spanning two months belongs to the month containing its Thursday.
- [HARD REQUIREMENT] Each weekly story is for the person deciding whether to update: lead with the change a reader would feel, in the second person, name the meaningful improvements, end on why it matters. Prefer one concrete detail over a category. Never a feature inventory or implementation log.
- [HARD REQUIREMENT] Paragraphs are separated by a literal `\n\n`, which `app/blog/releases/page.tsx` renders as one `<p>` each: 2-3 for a big week, 1-2 for a thin one.
- [HARD REQUIREMENT] No hype, emojis, exclamation marks or invented benefits; a thin week stays short. `tests/121` fails on an exclamation mark or summaries regressing toward commit shorthand.
- [HARD REQUIREMENT] Never name the upstream engine; write "terminal engine". The generator strips it per paragraph as a backstop, and `tests/121` fails if `\bGhostty\b` reaches the data file.
- Retired features stay out: versions whose final text matches the `RETIRED` pattern, plus the explicit `RELEASE_EXCLUDE` set, are excluded; mixed builds are curated to the surviving part.
- Keep the hero download CTA, the closing "Ready to try it?" section and every `Download for macOS` link, which passes `siteOrigin` so it reaches `https://yen.chat/download` from the blog host.
- After editing either copy layer, run the generator and `bun run build`, confirm no unused keys, and ship the data and CSP hashes in a `[deploy]` commit.

## Blog (blog.yen.chat)

blog.yen.chat is the self-hosted Digital Onigiri blog; Substack no longer serves it.
The 53 posts imported from the Substack export live in `content/blog/posts/<slug>.json`, and their media in `public/blog-media/`, served same-origin.
`scripts/47-import-substack-blog.ts` wrote both: it sanitizes each body to a small HTML subset, maps Substack post links to `/<slug>`, drops subscribe widgets, keeps the 848px and 1456px webp copies Substack served (GIFs and videos as originals), and fails closed on an unknown component, link or media type.

- Routing lives in `proxy.ts` through `lib/http/blog-host.ts`, never in a `next.config.ts` host rewrite. The proxy picks a page's static CSP by path before rewrites run, so only the proxy can give `blog.yen.chat/<slug>` the hashes of the prerendered `/blog/<slug>`.
- On blog.yen.chat, `/` and `/<slug>` render `app/blog/`; `/feed`, `/sitemap.xml` and `/robots.txt` are the blog's own route handlers; `/p/<slug>` and a trailing slash 308 to `/<slug>`; Substack-only pages 308 to `/`; and every other page path 308s to yen.chat, except a script fetch (`Sec-Fetch-Dest` other than `document`), which gets an empty 204: Next strips the `rsc` header before the proxy, and the 204 keeps a router prefetch of a relative yen.chat link from tripping CSP `connect-src` while a click falls back to a full navigation.
- The blog pages pass `siteOrigin={SITE_URL}` to `PageShell`, so the shared header and footer link to yen.chat directly; a relative `/` there is the blog index, and `tests/55-web-ui-dom.test.tsx` pins every shared link to yen.chat.
- On yen.chat, `/blog` and `/blog/<path>` 308 to blog.yen.chat; previews and local development still render `/blog` directly.
- Local `next dev` and `next start` rewrite the request host to `localhost`, so host routing is proven by `tests/159-blog-host-routing.test.ts` and on the deployed domain, never by a local Host header.
- `tests/158-blog-archive.test.ts` checks that all 53 imported posts remain as creator notes, and fails if a note references media missing from `public/blog-media/` or a slug collides with a blog route such as `releases`.
- A new note is a new `content/blog/posts/<slug>.json` in the same shape, with `"author"` set to `creator` or `agent` and its media under `public/blog-media/`; it appears when its week's issue is published.
- `lib/blog.ts` (`accessibleArticleHtml`) repairs note markup at render: an image link whose image has empty alt text gets an `aria-label`, headings get an `aria-level` so the outline never skips, and each `pre` becomes focusable. The visual tags stay unchanged, so a new note needs none of this by hand; `tests/167-blog-article-accessibility.test.ts` checks every note inside its issue.

### Weekly issues

blog.yen.chat publishes one issue per Monday-Sunday week, dated that week's Friday, at `/<friday>` (for example `/2026-11-20`).
`lib/blog-weeks.ts` builds each issue from the week's release story, the week's notes in `content/blog/posts/`, and its entry in `content/blog/weeks.json`.
An issue exists only when `weeks.json` lists its week, so the current week stays open until its Friday.

Every issue opens with **Technical updates**: the curated week story from `lib/release-notes/release-notes-copy.ts`, the build range, and a link to that week on `/releases`.
A note an agent wrote for the site (`"author": "agent"`) renders inside Technical updates as a feature note.

There are two kinds of issue, and the index, the issue page, the feed and the social card all say which one it is.

| Kind | When | Title and deck | Look |
|------|------|----------------|------|
| From the creator | The creator wrote a note that week (`"author": "creator"`) | The lead note's own title and subtitle (`"lead"` in `weeks.json`) | Card tint and a brand rule on the index row and the lead; Technical updates, then a tinted "Notes from the creator" section with each note under its own title and date |
| Weekly update | No creator note that week | `"title"` and `"deck"` in `weeks.json`, written in the creator's voice (`/voice`) | Plain paper; Technical updates only |

- Personal issues keep the creator's notes word for word; an agent never edits or summarizes them.
- A weekly update's title is short, proper case, and concrete ("Scrollback in Lines"); its deck is one plain sentence with a fact in it. No marketing adjectives.
- A personal issue shares the lead note's cover; a weekly update shares its own card from `public/social/weeks/<friday>.png`, written by `bun scripts/gen-blog-week-cards.tsx`. Each issue's Open Graph and Twitter title, description and image name that issue and its week.
- A note's old address (`/<note>`, `/p/<note>`, `yen.chat/blog/<note>`) 308s to `/<friday>#<note>`, keeping the query before the anchor; `content/blog/slugs.json`, written by `bun scripts/gen-blog-slugs.ts`, is the index `proxy.ts` bundles for that.
- Notes render inside an issue under its h1, a section h2 and their own h3, so `accessibleArticleHtml` starts their headings at level 4; a heading id an earlier note on the page already uses gets the note's slug as a prefix.
- The index, the feed (`/feed`) and the sitemap list issues only. `/releases` stays the build-by-build record the app links to: a week links its issue once it is out, and says when the current week's issue comes out.

To publish a week on its Friday: add its entry to `content/blog/weeks.json` (a `"lead"` note slug for a personal week, or a `"title"` and `"deck"`), then run `bun scripts/gen-blog-slugs.ts` and `bun scripts/gen-blog-week-cards.tsx`, and ship with `[deploy]`.
`tests/158-blog-archive.test.ts` fails if a week lands on a day other than Friday, a release week or note belongs to no issue or to two, an issue's kind does not match its notes, an issue lacks its card, or `slugs.json` is stale; `tests/55` and `tests/167` cover the index markup and the issue outline.

## Content Voice

Applies to marketing, blog posts, social posts and public docs.
YEN is a solo-developer product written in the first person ("I built", never "we" for the builder), for engineers who live in the terminal.

- Be technically specific: say how it works ("the hotkey uses a session-level `CGEventTap`"), not "advanced technology".
- Admit limitations plainly; honesty earns trust.
- Self-deprecating humor is welcome; corporate distance is not.
- Contrast philosophies without attacking anyone.
- Let the joy of building show.

| Channel | Style |
|---------|-------|
| Blog notes from the creator | Long-form, personal, technical; written by the creator; "Hey folks!" and a "— 8" sign-off |
| Blog weekly updates | The week story, plus a title and deck in the creator's voice ([Weekly issues](#weekly-issues)) |
| Social | One insight per post, code welcome |
| Public docs | Clear, scannable, accurate over promotional |
| Release notes (blog.yen.chat/releases) | The weekly story rules above |

Use: "just works", "local-first", "vendor, don't fork", "quiet, methodical work".
Avoid: "AI-powered" (YEN uses native APIs), "revolutionary", "best-in-class", "seamless experience", "leverage".

Formatting: spaced em dashes ("text — text", never `--`); spaced slashes between words ("hover / definition"); inline code for commands; bold rather than capitals; Oxford comma; paragraphs of three or four sentences.

## Public Manual

`app/docs/docs-client.tsx` owns the task-focused manual; `components/home/operator-guide.tsx` embeds it on the homepage.
Keep setup, workspace controls, feature limits, and troubleshooting visible; use bundled command help for the exhaustive CLI inventory.
Preserve useful existing anchors when combining sections, and keep navigation in reading order.
Historical essays and conceptual product comparisons belong outside the manual.
