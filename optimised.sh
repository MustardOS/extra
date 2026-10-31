#!/bin/sh

set -eu

BASE_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
SOURCE_DIR="$BASE_DIR/optimised"
OUTPUT="$BASE_DIR/data/optimised.json"
CORE_DATA="$BASE_DIR/data/core.json"

SETTINGS='["rotate","fps_limit","frame_delay_ms","run_ahead","gpu_hard_sync","game_renderer","audio_latency_profile","audio_period_frames","audio_rate_control","sample_rate","content_precache"]'
OPTION_DENY='shader|overlay|filter|palette|bezel|border|crosshair|gamma|brightness|contrast|saturation|colou?r_?correct|language'

USAGE() {
	printf 'Usage: %s [check]\n' "$0"
	printf '  Validates every optimised/<System>/<hash>.json file and, without check,\n'
	printf '  writes them to data/optimised.json for the release and the internal copy.\n'
	exit 2
}

MODE=build
case "${1-}" in
	"") ;;
	check) MODE=check ;;
	*) USAGE ;;
esac

command -v jq >/dev/null 2>&1 || {
	printf 'jq is required\n' >&2
	exit 1
}

KNOWN_CORES=$(jq -c '[.[] | .output? // empty | if type == "array" then .[] else . end | strings | sub("_libretro\\.so$"; "")]' "$CORE_DATA")
FAILED=0
COUNT=0
LIST=$(mktemp)
trap 'rm -f "$LIST"' EXIT INT TERM

FAIL() {
	printf 'FAIL\t%s\n\t%s\n' "$1" "$2" >&2
	FAILED=1
}

for FILE in "$SOURCE_DIR"/*/*.json; do
	[ -f "$FILE" ] || continue

	NAME=${FILE##*/}
	HASH=${NAME%.json}
	SYSTEM=${FILE%/*}
	SYSTEM=${SYSTEM##*/}

	case "$HASH" in
		*[!0-9a-f]*) FAIL "$FILE" "The file name must be the lower case content hash" && continue ;;
	esac
	case "${#HASH}" in
		32 | 8) ;;
		*) FAIL "$FILE" "The file name must be a 32 character RetroAchievements hash or an 8 character CRC32" && continue ;;
	esac

	if ! jq -e . "$FILE" >/dev/null 2>&1; then
		FAIL "$FILE" "Not valid JSON"
		continue
	fi

	PROBLEMS=$(jq -r --argjson settings "$SETTINGS" --arg deny "$OPTION_DENY" '
		def bad_settings($where):
			(.settings // {}) | if type != "object" then "\($where) settings must be an object"
			else to_entries[] | .key as $k | if ($settings | index($k)) == null then "\($where) setting \(.key) is not allowed"
				elif (.value | type) != "number" or (.value | floor) != .value then "\($where) setting \(.key) must be a whole number"
				else empty end end;
		if type != "object" then "The file must hold an object" else
			(if (.name | type) != "string" or (.name | length) == 0 then "name is missing" else empty end),
			((keys - ["name", "settings", "cores"])[] | "Unknown key \(.)"),
			bad_settings("Shared"),
			(if (.cores | type) != "object" or (.cores | length) == 0 then "cores must name at least one core" else
				.cores | to_entries[] | .key as $core | .value |
				if type != "object" then "Core \($core) must be an object" else
					((keys - ["description", "settings", "options"])[] | "Core \($core) has unknown key \(.)"),
					(if (.description | type) != "string" or (.description | length) == 0 then "Core \($core) needs a description of what it fixes" else empty end),
					bad_settings("Core \($core)"),
					((.options // {}) | if type != "object" then "Core \($core) options must be an object"
						else to_entries[] |
							if (.value | type) != "string" then "Core \($core) option \(.key) must be a string"
							elif (.key | test($deny; "i")) then "Core \($core) option \(.key) is a personal preference"
							else empty end end),
					(if ((.settings // {}) | length) + ((.options // {}) | length) == 0 then "Core \($core) changes nothing" else empty end)
				end
			end)
		end' "$FILE") || PROBLEMS="The file could not be checked"

	if [ -n "$PROBLEMS" ]; then
		printf '%s\n' "$PROBLEMS" | while IFS= read -r PROBLEM; do FAIL "$FILE" "$PROBLEM"; done
		FAILED=1
		continue
	fi

	jq -r '.cores | keys[]' "$FILE" | while IFS= read -r CORE; do
		printf '%s' "$KNOWN_CORES" | jq -e --arg c "$CORE" 'index($c) != null' >/dev/null ||
			printf 'NOTE\t%s\n\tCore %s is not built by this repository, check it matches the core file name\n' "$FILE" "$CORE" >&2
	done

	if grep -qx "$HASH" "$LIST"; then
		FAIL "$FILE" "Another file already uses this hash"
		continue
	fi
	printf '%s\n' "$HASH" >>"$LIST"
	COUNT=$((COUNT + 1))
done

[ "$FAILED" -eq 0 ] || exit 1
printf 'Checked %s optimised profiles\n' "$COUNT"

[ "$MODE" = build ] || exit 0

jq -n --argjson generated "$(date +%s)" '
	{generated: $generated, content: (reduce inputs as $p ({}; (input_filename | split("/")) as $f
		| .[$f[-1] | rtrimstr(".json")] = ({name: $p.name, system: $f[-2]} + ($p | del(.name)))))}
' "$SOURCE_DIR"/*/*.json >"$OUTPUT.tmp"
mv -f "$OUTPUT.tmp" "$OUTPUT"
printf 'Wrote %s\n' "$OUTPUT"
