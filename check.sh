#!/bin/sh

WIDTH=$(tput cols 2>/dev/null || echo 80)
LINE=$(printf '%*s' "$WIDTH" '' | tr ' ' '-')

find . -type f -name "*.ini" | while IFS= read -r INI; do
	DIRNAME=$(basename "$(dirname "$INI")")
	VALUE=$(sed -n 's/^[[:space:]]*catalogue[[:space:]]*=[[:space:]]*//p' "$INI" | head -n1)

	if [ -n "$VALUE" ] && [ "$VALUE" != "$DIRNAME" ]; then
		printf "MISMATCH\t%s\nDETECTED\tINI HAS: %s\tSHOULD BE: %s\n%s\n" "$INI" "$VALUE" "$DIRNAME" "$LINE"
	fi
done
