# yen-vidthumb

Native macOS video thumbnailer for the YEN file browser. Replaces
`ffmpeg` + `ffprobe` with an AVFoundation binary that shares
`yen-thumbcommon/ThumbCommon.swift` with the sibling `yen-svgthumb` /
`yen-pdfthumb` helpers.

## Build

```bash
cd yen-vidthumb
./build.sh
```

## Usage

```bash
./yen-vidthumb input.mp4 output.png
./yen-vidthumb input.mp4 output.png --seek 1 --max-width 2000 --max-height 2000
./yen-vidthumb input.mp4 --duration
```

## Evaluate

```bash
./scripts/38-eval-vidthumb.sh
```

There is no reference renderer (`ffmpeg`/`ffprobe` were removed), so the eval is
**self-validating** rather than a similarity compare. It builds the helper and the
reviewable Swift fixture generator (`make-fixtures.swift`), generates the binary
corpus into `yen-vidthumb/fixtures/` (gitignored; only `manifest.csv` is
committed), then asserts a valid non-empty PNG, the expected orientation, a
downscaled (never upscaled) size that fits the cap and preserves aspect ratio, the
reported duration, and the expected render/fail outcome per `fixtures/manifest.csv`.
Native fixture dimensions are encoded larger than the eval cap so the downscale is
observable (`AVAssetImageGenerator.maximumSize` only downscales).

Outputs land in `yen-vidthumb/.eval/`:
- `results.csv` and `summary.txt`

Policies:
- `render_ok`: must render a valid PNG with the expected orientation and a
  cap-fitting, aspect-preserving size; rotated clips use a preferred transform so
  the applied output orientation is asserted.
- `expected_failure`: input the helper must reject (e.g. an audio-only `.m4a` with
  no video track) should exit non-zero without crash/hang.

## Soak (latency + memory)

```bash
./scripts/39-soak-vidthumb.sh
```

Soak outputs:
- `yen-vidthumb/.eval/soak.csv`
- `yen-vidthumb/.eval/soak-summary.txt`

The soak fails unless every scheduled render emits a decodable PNG with complete latency and RSS samples and all performance gates pass.

## See also

- `yen-svgthumb/README.md` — sibling SVG harness (self-validating, with a blank-render check).
- `yen-pdfthumb/README.md` — sibling PDF harness (same self-validating design).
