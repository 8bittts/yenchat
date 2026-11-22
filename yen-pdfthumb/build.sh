#!/bin/bash
# Build yen-pdfthumb as an arm64 binary
#
# Usage: ./build.sh
#
# Output: ./yen-pdfthumb (arm64)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/../scripts/lib/build-thumb.sh" "$SCRIPT_DIR" yen-pdfthumb PDFKit AppKit
