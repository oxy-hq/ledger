#!/usr/bin/env bash
# Copies external sources (schemas repo, service-account key, config) into the
# Flutter assets/ directory so the app can load them at runtime on every
# platform (Android, iOS, macOS, web).
#
# Run this before `flutter run` whenever schemas change.

set -euo pipefail
cd "$(dirname "$0")/.."

SCHEMAS_SRC="${SCHEMAS_SRC:-$HOME/repos/ledger-schemas/views}"
TEMPLATES_SRC="${TEMPLATES_SRC:-$HOME/repos/ledger-schemas/templates}"
SA_KEY_SRC="${SA_KEY_SRC:-$HOME/.config/ledger/service-account.json}"
CONFIG_SRC="${CONFIG_SRC:-$HOME/.config/ledger/config.yaml}"

mkdir -p assets/schemas assets/templates

# Schemas: clear and recopy so deletions in the source propagate
rm -f assets/schemas/*.view.yml
cp "$SCHEMAS_SRC"/*.view.yml assets/schemas/
echo "synced $(ls assets/schemas/*.view.yml | wc -l | tr -d ' ') schema(s) from $SCHEMAS_SRC"

# Templates: mirror the templates/<view>/<name>.yml structure
rm -rf assets/templates
mkdir -p assets/templates
if [ -d "$TEMPLATES_SRC" ]; then
  cp -R "$TEMPLATES_SRC"/. assets/templates/
  echo "synced $(find assets/templates -name '*.yml' | wc -l | tr -d ' ') template(s) from $TEMPLATES_SRC"
else
  echo "no templates dir at $TEMPLATES_SRC (skipping)"
fi

# Service account key
cp "$SA_KEY_SRC" assets/service-account.json
echo "synced service-account.json"

# Config: extract just the bits the app needs at runtime (spreadsheet_id).
# The other config keys (paths) are now baked into asset paths.
SPREADSHEET_ID=$(grep -E '^spreadsheet_id:' "$CONFIG_SRC" | sed 's/spreadsheet_id:[[:space:]]*//')
cat > assets/config.yaml <<EOF
spreadsheet_id: $SPREADSHEET_ID
EOF
echo "synced config.yaml (spreadsheet_id=$SPREADSHEET_ID)"
