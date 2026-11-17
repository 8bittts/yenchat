#!/bin/bash
# Build yen-pdfthumb as universal binary (arm64 + x86_64)
#
# Usage: ./build.sh
#
# Output: ./yen-pdfthumb (universal binary)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/../scripts/lib/build-thumb.sh" "$SCRIPT_DIR" yen-pdfthumb PDFKit AppKit
