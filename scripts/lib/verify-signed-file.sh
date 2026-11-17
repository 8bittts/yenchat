#!/bin/bash

set -euo pipefail

if [ "$#" -ne 3 ]; then
    echo "Usage: verify-signed-file.sh <payload_path> <signature_path> <public_key_b64>" >&2
    exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/signature-utils.sh"

verify_signed_file_with_signature_file "$1" "$2" "$3"
