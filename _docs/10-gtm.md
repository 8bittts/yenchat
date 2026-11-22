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
- `content/blog/slugs.json` is the slug index the proxy bundles; `tests/158-blog-archive.test.ts` keeps it equal to the post files, checks that all 53 imported posts remain alongside locally authored posts, and fails if a post references media missing from `public/blog-media/`.
- A new post is a new `content/blog/posts/<slug>.json` in the same shape plus its slug in `slugs.json`, with its media under `public/blog-media/`.
- `tests/158` refuses a post slug that collides with a blog route such as `releases`.
- `lib/blog.ts` (`accessibleArticleHtml`) repairs article markup on load: an image link whose image has empty alt text gets an `aria-label`, headings get an `aria-level` so the outline under the page `h1` starts at 2 and never skips, and each `pre` becomes focusable. The visual tags stay unchanged, so a new post needs none of this by hand; `tests/167-blog-article-accessibility.test.ts` checks every post.

### Posts and release notes

The blog holds two kinds of writing, and each says which it is.
Posts are labeled "From the creator": long-form, first-person notes on why and how YEN is built.
Release notes are labeled "Release notes": the weekly record of what changed, written for the person deciding whether to update.

- The index (`app/blog/page.tsx`) is one month-by-month timeline of both, built by `lib/blog-archive.ts`. A week's entry shows its label, build count and latest version and links to its anchor on `/releases`; its story is never repeated on the index.
- A week's month is the month of its Thursday, the same rule as the release notes nav; a post's month and day are read in Pacific time, like its date label.
- The two cross-link by week: a release week lists that week's posts under "From the creator this week", and a post's "More field notes" section links the release notes for the week it was published in.
- A post can introduce a feature that the same week's release notes also mention. The post explains why; the week story stays the short factual record. Neither copies the other's text.
- The feed (`/feed`) carries posts only, because a week's story is refreshed by every build that week.
- `tests/55` and `tests/158` fail if the index drops or repeats an entry, or prints a week's story.

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
| Blog (blog.yen.chat) | Long-form, personal, technical; "Hey folks!" and a "— 8" sign-off |
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
