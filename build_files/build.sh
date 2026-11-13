#!/usr/bin/bash
set -euo pipefail

echo "Running PrecisionOS custom build steps..."

# Ensure dconf directory exists
mkdir -p /etc/dconf/db/local.d/

echo "Build steps completed successfully."
