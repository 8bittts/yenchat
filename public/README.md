# Public Assets

Tracked files in `public/` are deployed with the web app.
DMGs are hosted on GitHub Releases; `public/stable/version.json` identifies the current release.

## Rules

- Stage only reviewed files for the current task; never stage every asset implicitly.
- Do not delete assets based on static analysis; external links and build tools may still use them.
- `_docs/05-infrastructure.md` owns public-media retention, and `_docs/05-infrastructure.md` owns release-artifact pruning.
