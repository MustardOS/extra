#!/bin/sh

# Regenerate the frontend download catalogue from the system tree.
# Usage: catalogue.sh [version]     (default: the newest data/<version>.json present)

set -eu

BASE_DIR=$(CDPATH='' cd "$(dirname "$0")" && pwd)
DATA_DIR="$BASE_DIR/data"
SYSTEM_DIR="$BASE_DIR/system"
REPOSITORY="https://github.com/MustardOS/extra/releases/latest/download"

VERSION=${1:-}
if [ -z "$VERSION" ]; then
	VERSION=$(find "$DATA_DIR" -maxdepth 1 -name '[0-9]*_[0-9]*.json' -exec basename {} .json \; |
		sort -r | head -1)
fi

[ -n "$VERSION" ] || { printf 'No catalogue version found in %s\n' "$DATA_DIR" >&2; exit 1; }

TARGET="$DATA_DIR/$VERSION.json"
[ -d "$SYSTEM_DIR" ] || { printf 'No extra system tree at %s\n' "$SYSTEM_DIR" >&2; exit 1; }

OLD_JSON='[]'
[ -f "$TARGET" ] && OLD_JSON=$(cat "$TARGET")

NAMES=$(find "$SYSTEM_DIR" -mindepth 3 -maxdepth 4 -path '*/assign/*' -name '*.ini' 2>/dev/null |
	sed "s|^$SYSTEM_DIR/||; s|/assign/.*||" | LC_ALL=C sort -u)

[ -n "$NAMES" ] || { printf 'No systems with assignments found\n' >&2; exit 1; }

TMP=$(mktemp "$DATA_DIR/.catalogue.XXXXXX")
trap 'rm -f "$TMP"' EXIT HUP INT TERM

printf '%s\n' "$NAMES" |
	jq -R -s --argjson old "$OLD_JSON" --arg base "$REPOSITORY" '
		($old | map({key: .name, value: .}) | from_entries) as $prev
		| split("\n") | map(select(length > 0))
		| map({
			name: .,
			url: ($base + "/Base.-." + (. | gsub(" "; ".")) + ".muxzip"),
			type: "core",
			help: (($prev[.] // {}).help // "")
		})
	' >"$TMP"

jq -e 'type == "array" and length > 0' "$TMP" >/dev/null ||
	{ printf 'Generated catalogue is not usable\n' >&2; exit 1; }

BEFORE=$(printf '%s' "$OLD_JSON" | jq 'length')
AFTER=$(jq 'length' "$TMP")

mv "$TMP" "$TARGET"
trap - EXIT HUP INT TERM

printf 'Catalogue %s regenerated: %s -> %s entries\n' "$VERSION" "$BEFORE" "$AFTER"
