#!/bin/sh

BASE_DIR=$(pwd)

CORE_JSON="$BASE_DIR/data/core.json"
CACHE_JSON="$BASE_DIR/data/cache.json"

# Check if -c or --clean is specified
if [ "$#" -gt 0 ]; then
  case "$1" in
    -c | --clean)
      # Replace all short_commit with "0000000 to force build cores and bypass hash check"
      jq 'to_entries | map(.value = "0000000") | from_entries' "$CACHE_JSON" > tmp.$$.json && mv tmp.$$.json "$CACHE_JSON"
      exit 0
      ;;
    *)
      # If an unknown option is passed, print usage or exit
      echo "Usage: $0 [-c|--clean]" >&2
      exit 1
      ;;
  esac
fi

# Create an empty JSON object if cache.json doesn't exist or is empty
if [ ! -s "$CACHE_JSON" ]; then
  echo "{}" > "$CACHE_JSON"
fi

# Loop through each URL and core name
jq -r 'to_entries[] | "\(.key) \(.value.source)"' "$CORE_JSON" | while read -r CORE_NAME SOURCE; do
  # Run the git ls-remote command and grab the short commit ID
  SHORT_COMMIT=$(git ls-remote "$SOURCE" HEAD | cut -c 1-7)

  # Use jq to update the output JSON file with the new structure
  jq --arg corename "$CORE_NAME" \
     --arg commit "$SHORT_COMMIT" \
     '.[$corename] = $commit' "$CACHE_JSON" > tmp.$$.json && mv tmp.$$.json "$CACHE_JSON"
done
