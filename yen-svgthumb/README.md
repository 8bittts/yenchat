# yen-svgthumb

Native macOS SVG thumbnailer for the YEN file browser.
It also inflates gzip-compressed `.svgz` files itself, up to 64 MB of SVG text.

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

## Evaluate

```bash
./scripts/30-eval-svgthumb.sh
```

The eval is self-validating; there is no reference renderer.
Outputs are written to `yen-svgthumb/.eval/`: `results.csv` and `summary.txt`.
`inspect.swift` reports each render's size and its share of drawn pixels.

Policies in `yen-svgthumb/fixtures/manifest.csv`:
- `render_ok`: must exit 0 with a readable PNG whose long edge equals the cap and that is not blank
- `expected_failure`: malformed input must exit non-zero and write nothing

A `.svgz` fixture must render the same bytes as its `.svg` sibling.
A fixture missing from the manifest fails the eval.

## Soak (latency + memory)

```bash
./scripts/31-soak-svgthumb.sh
```

Soak outputs:
- `yen-svgthumb/.eval/soak.csv`
- `yen-svgthumb/.eval/soak-summary.txt`

## See also

- `yen-pdfthumb/README.md` and `yen-vidthumb/README.md` — sibling PDF/video harnesses. Their evals are self-validating in the same way (`render_ok` / `expected_failure`).
