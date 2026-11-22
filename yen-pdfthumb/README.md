# yen-pdfthumb

Native macOS PDF thumbnailer for the YEN file browser. Replaces `pdftoppm` with a
small AppKit/PDFKit binary that shares `yen-thumbcommon/ThumbCommon.swift`
with the sibling `yen-svgthumb` / `yen-vidthumb` helpers.

## Build

```bash
cd yen-pdfthumb
./build.sh
```

## Usage

```bash
./yen-pdfthumb input.pdf output.png
./yen-pdfthumb input.pdf output.png --page 0 --max-width 2000 --max-height 2000
./yen-pdfthumb input.pdf --pages
```

## Evaluate

```bash
./scripts/36-eval-pdfthumb.sh
```

There is no reference renderer (`pdftoppm` was removed), so the eval is
**self-validating** rather than a similarity compare. It builds the helper and the
reviewable Swift fixture generator (`make-fixtures.swift`), generates the binary
corpus into `yen-pdfthumb/fixtures/` (gitignored; only `manifest.csv` is
committed), then asserts a valid non-empty PNG, the expected orientation, an
upscaled long edge equal to the cap, the expected page count, and the expected
render/fail outcome per `fixtures/manifest.csv`.

Outputs land in `yen-pdfthumb/.eval/`:
- `results.csv` and `summary.txt`

Policies:
- `render_ok`: must render a valid PNG with the expected orientation/pages; every
  in-range page renders and the first out-of-range page index fails.
- `expected_failure`: input the helper must reject (e.g. a user-password-encrypted
  PDF that `unlock("")` cannot open) should exit non-zero without crash/hang.

## Soak (latency + memory)

```bash
./scripts/37-soak-pdfthumb.sh
```

Soak outputs:
- `yen-pdfthumb/.eval/soak.csv`
- `yen-pdfthumb/.eval/soak-summary.txt`

The soak fails unless every scheduled render emits a decodable PNG with complete latency and RSS samples and all performance gates pass.

## See also

- `yen-svgthumb/README.md` — sibling SVG harness (self-validating, with a blank-render check).
- `yen-vidthumb/README.md` — sibling video harness (same self-validating design).
