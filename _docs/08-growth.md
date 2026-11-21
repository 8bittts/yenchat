# Growth

The public comparison and PSEO pages of YEN, and the limits on what the site measures.

## Measurement

YEN has no product analytics, accounts, license server, or revenue.
`/download` redirects to the current DMG on GitHub Releases and records nothing.
The website runs Vercel Web Analytics and Speed Insights only; the custom events are listed in [09-quality.md](09-quality.md).
Never add a download counter, a growth database, or an owner report without an explicit operator request and a privacy-policy update in the same change.

## Public Comparison and PSEO

Competitor names appear on `/alternatives` pages and in tests, the backlog, this file, and the private `/library`.
They are nominative only: never imply affiliation, endorsement or compatibility without an official source.

| Claim class | May appear as fact |
|-------------|--------------------|
| `official-source-backed` (competitor's own docs, with `lastCheckedAt`) | Yes |
| `YEN-source-backed` (YEN docs, `llms.txt`, code, artifacts) | Yes |
| `inference`, `opinion` | Only reframed as such |
| `blocked` (pricing, availability, benchmarks, privacy, security or superiority without current evidence) | Never |

- No fake benchmarks, "best" or "fastest" claims, or pricing without a same-day source refresh.
- Pages render from compact registries (`lib/library/public-pages.ts`), never from raw research or scraped text.
- Each comparison or use-case page has at least one YEN-source-backed fact, one workflow decision point, source links for competitor claims, related links, and a path to `/download`, `/docs` or `/terms`.
- The registry controls eligibility, canonical path, metadata, freshness, related links and sitemap membership; sitemap, hubs, metadata, routes and related links all call the same eligibility predicate.
- Finite PSEO routes set `dynamicParams=false` and pre-render every eligible slug.
- Every eligible page that may appear on plaintext surfaces is also a Markdown link in `public/llms.txt` (`isPublicLibraryPageLlmsDiscoverable`, guarded by `tests/121`).
- The public manual stays task-focused; product comparisons live on `/alternatives` under these source rules.
- Run `bun run seo:source-check` after changing any comparison claim.

**`/library`.** A noindex HTML page inventory for the operator, not an SEO page or research dump.
It renders for a direct URL but stays out of public chrome, `PUBLIC_PAGE_SEO`, `public/llms.txt` and the sitemap, and lists only page links (no notes, queues or PDFs).
`lib/library/seo-inventory.ts` derives it from the shared eligibility predicate, and `tests/130-library-workbench.test.ts` proves it mirrors the sitemap and stays undiscoverable.
PSEO management surfaces never appear in the shared header or footer unless the operator asks.

The optional desktop usage menu reads local tool counts only. Its readings never enter site analytics.
