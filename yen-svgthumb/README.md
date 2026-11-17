# yen-svgthumb

Native macOS SVG thumbnailer for the YEN file browser; the vendored `resvg` remains the fallback for `.svgz` and edge cases.

## Build

```bash
cd yen-svgthumb
./build.sh
```

## Usage

```bash
./yen-svgthumb input.svg output.png
./yen-svgthumb input.svg output.png --max-dimension 2000
```

## Evaluate vs resvg

```bash
./scripts/30-eval-svgthumb.sh
```

Outputs are written to `yen-svgthumb/.eval/`:
- `results.csv` and `summary.txt`
- Policy-aware gating via `yen-svgthumb/fixtures/manifest.csv`

Policies:
- `strict_compare`: must render in both engines and pass similarity gate
- `baseline_limitation`: known `resvg` baseline mismatch (tracked, excluded from strict pass/fail)
- `fallback_expected`: native may fail, but fallback preview must succeed via `resvg`
- `expected_failure`: malformed input should fail fast without crash/hang

## Soak (latency + memory)

```bash
./scripts/31-soak-svgthumb.sh
```

Soak outputs:
- `yen-svgthumb/.eval/soak.csv`
- `yen-svgthumb/.eval/soak-summary.txt`

## See also

- `yen-pdfthumb/README.md` and `yen-vidthumb/README.md` — sibling PDF/video harnesses. They have no reference renderer (`pdftoppm`/`ffmpeg` were removed), so their evals are self-validating (`render_ok` / `expected_failure`) instead of a similarity compare.
