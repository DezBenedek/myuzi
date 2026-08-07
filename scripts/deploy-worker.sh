#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../worker"
npm install
npm run check
npm run deploy
echo "Deployed MyÜzi worker."
