#!/bin/sh

printf "\nMURCB - muOS RetroArch Core Builder\n"

# Show 'build.sh' USAGE options
USAGE() {
	echo "Usage: $0 [options]"
	echo ""
	echo "Options:"
	echo "  -a, --all              Build all cores"
	echo "  -c, --core [cores]     Build specific cores (e.g., -c dosbox-pure sameboy)"
	echo "  -x, --exclude [cores]  Exclude cores when used with -a (e.g., -a -x fbneo mame2010)"
	echo "  -p, --purge            Purge core repo directories (delete cloned repos)"
	echo "  -f, --force            Force build without purge (ignore cache)"
	echo "  -l, --latest           Ignore pinned branch/commit; build remote HEAD"
	echo "  -u, --update           Combine all core archives into a single update archive"
	echo ""
	echo "Notes:"
	echo "  - Either -a, -c, or -u is required, but NOT together"
	echo "  - If -p is used, it MUST be the first argument"
	echo ""
	echo "Examples:"
	echo "  $0 -a"
	echo "  $0 -a -x fbneo mame2010"
	echo "  $0 -c dosbox-pure sameboy"
	echo "  $0 -p -a"
	echo "  $0 -p -c dosbox-pure sameboy"
	echo "  $0 -l -a"
	echo "  $0 -u"
	echo ""
	exit 1
}

# Initialise all options to 0
PURGE=0
FORCE=0
LATEST=0
BUILD_ALLNOW=0
BUILD_CORES=""
EXCLUDE_CORES=""
OPTION_SPECIFIED=0
UPDATE=0
CLEAN=0

# If argument '-p' or '--purge' provided first, set PURGE=1
if [ "$#" -gt 0 ]; then
	case "$1" in
	  -p|--purge)
    	PURGE=1
    	shift
    	;;
	  -f|--force)
    	FORCE=1
    	shift
    	;;
	  -l|--latest)
    	LATEST=1
    	shift
    	;;
	esac
fi

# If no argument(s) provided show USAGE
[ "$#" -eq 0 ] && USAGE

# Check for remaining arguments and set appropriate options
while [ "$#" -gt 0 ]; do
	case "$1" in
		-a | --all)
			[ "$OPTION_SPECIFIED" -ne 0 ] && USAGE
			BUILD_ALLNOW=1
			OPTION_SPECIFIED=1
			shift
			;;
		-c | --core)
			[ "$OPTION_SPECIFIED" -ne 0 ] && USAGE
			OPTION_SPECIFIED=1
			shift
			if [ "$#" -eq 0 ]; then
				printf "Error: Missing cores\n\n" >&2
				USAGE
			fi
			BUILD_CORES="$*"
			break
			;;
		-x | --exclude)
			shift
			if [ "$#" -eq 0 ]; then
				printf "Error: Missing cores for exclude\n\n" >&2
				USAGE
			fi
			EXCLUDE_CORES="$*"
			break
			;;
		-u | --update)
			UPDATE=1
			shift
			;;
		-f | --force)
			FORCE=1
			shift
			;;
		-p | --purge)
			PURGE=1
			shift
			;;
		-l | --latest)
			LATEST=1
			shift
			;;
		*)
			printf "Error: Unknown option '%s'\n" "$1" >&2
			USAGE
			;;
	esac
done

# Confirm a valid argument was provided, else show USAGE
[ "$OPTION_SPECIFIED" -eq 0 ] && [ "$UPDATE" -eq 0 ] && USAGE

# Warn if -x used without -a
if [ -n "$EXCLUDE_CORES" ] && [ "$BUILD_ALLNOW" -ne 1 ]; then
	printf "Warning: --exclude is only effective with --all\n"
fi

# Initialise directory variables
BASE_DIR=$(pwd)
CORE_CONFIG="data/core.json"
RETRO_DIR="$BASE_DIR/core"
BUILD_DIR="$BASE_DIR/build"
PATCH_DIR="$BASE_DIR/patch"

# POSIX safe CPU count
NPROC=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)

# Safe directory removal helper
SAFE_RM_DIR() {
	_TARGET="$1"
	case "$_TARGET" in
		""|"$BUILD_DIR") return 1 ;;
	esac
	case "$_TARGET" in
		"$BUILD_DIR"/*)
			if [ -d "$_TARGET" ]; then
				printf "Removing stale directory: %s\n" "$_TARGET"
				rm -rf -- "$_TARGET"
				return $?
			fi
			;;
		*)
			printf "Refusing to delete non-core path: %s\n" "$_TARGET" >&2
			return 1
			;;
	esac
	return 0
}

# Create an update zip containing all cores
UPDATE_ZIP() {
	UPDATE_ARCHIVE="muOS-RetroArch-Core_Update-$(date +"%Y-%m-%d_%H-%M").muxzip"
	TEMP_DIR="$(mktemp -d)"
	CORE_FOLDER="$TEMP_DIR/core"

	if [ -z "$(ls "$RETRO_DIR"/*.zip 2>/dev/null)" ]; then
		printf "No ZIP files found in '%s'\n" "$RETRO_DIR" >&2
		rmdir "$TEMP_DIR"
		exit 1
	fi

	mkdir -p "$CORE_FOLDER"

	printf "Extracting all ZIP files from '%s' into '%s'\n" "$RETRO_DIR" "$CORE_FOLDER"

	for ZIP_FILE in "$RETRO_DIR"/*.zip; do
		printf "Unpacking '%s'...\n" "$(basename "$ZIP_FILE")"
		unzip -q "$ZIP_FILE" -d "$CORE_FOLDER" || {
			printf "Failed to unpack '%s'\n" "$(basename "$ZIP_FILE")" >&2
			rm -rf "$TEMP_DIR"
			exit 1
		}
	done

	printf "Creating consolidated update archive: %s\n" "$UPDATE_ARCHIVE"

	(cd "$TEMP_DIR" && zip -q -r "$BASE_DIR/$UPDATE_ARCHIVE" .) || {
		printf "Failed to create update archive\n" >&2
		rm -rf "$TEMP_DIR"
		exit 1
	}

	rm -rf "$TEMP_DIR"

	printf "Update archive created successfully: %s\n" "$BASE_DIR/$UPDATE_ARCHIVE"
	exit 0
}

[ "$UPDATE" -eq 1 ] && UPDATE_ZIP

# Detect proper aarch64 objcopy command.
if command -v aarch64-linux-gnu-objcopy >/dev/null 2>&1; then
    OBJCOPY=aarch64-linux-gnu-objcopy
elif command -v aarch64-linux-objcopy >/dev/null 2>&1; then
    OBJCOPY=aarch64-linux-objcopy
else
    printf "Error: Neither aarch64-linux-gnu-objcopy nor aarch64-linux-objcopy found\n" >&2
    exit 1
fi

# Detect proper aarch64 strip command.
if command -v aarch64-linux-gnu-strip >/dev/null 2>&1; then
    STRIP=aarch64-linux-gnu-strip
elif command -v aarch64-linux-strip >/dev/null 2>&1; then
    STRIP=aarch64-linux-strip
elif command -v strip >/dev/null 2>&1; then
    STRIP=strip
else
    printf "Error: No suitable strip command found\n" >&2
    exit 1
fi

# Check for other required commands
for CMD in file git jq make patch pv readelf zip; do
    if ! command -v "$CMD" >/dev/null 2>&1; then
        printf "Error: Missing required command '%s'\n" "$CMD" >&2
        exit 1
    fi
done

# Create required directories
mkdir -p "$RETRO_DIR"
mkdir -p "$BUILD_DIR"

trap 'printf "\nAn error occurred. Returning to base directory.\n"; cd "$BASE_DIR"; exit 1' INT TERM

RETURN_TO_BASE() {
	cd "$BASE_DIR" || {
		printf "Failed to return to base directory\n" >&2
		exit 1
	}
}

RUN_COMMANDS() {
    printf "\nRunning '%s' commands\n" "$1"
    CMD=$(printf '%s\n' "$2" | jq -r '.[]')
    printf "Running:\n%s\n" "$CMD"
    sh <<EOF
$CMD
EOF
}

APPLY_PATCHES() {
	NAME="$1"
	CORE_DIR="$2"

	if [ -d "$PATCH_DIR/$NAME" ]; then
		printf "Applying patches from '%s' to '%s'\n" "$PATCH_DIR/$NAME" "$CORE_DIR"
		for PATCH in "$PATCH_DIR/$NAME"/*.patch; do
			[ -e "$PATCH" ] || continue
			printf "Applying patch: %s\n" "$PATCH"
			patch -d "$CORE_DIR" -p1 <"$PATCH" || {
				printf "Failed to apply patch: %s\n" "$PATCH" >&2
				return 1
			}
		done
		printf "\n"
	fi
}

# Build target list
if [ "$BUILD_ALLNOW" -eq 0 ]; then
	CORES="$BUILD_CORES"
else
	CORES=$(jq -r 'keys[]' "$CORE_CONFIG")
	if [ -n "$EXCLUDE_CORES" ]; then
		for EXC in $EXCLUDE_CORES; do
			CORES=$(printf "%s\n" $CORES | grep -vx "$EXC")
		done
	fi
fi

# Load the cache file
CACHE_FILE="$BASE_DIR/data/cache.json"
if [ ! -f "$CACHE_FILE" ]; then
    echo "{}" > "$CACHE_FILE"
fi

for NAME in $CORES; do
	printf "\n-------------------------------------------------------------------------\n"

	MODULE=$(jq -c --arg name "$NAME" '.[$name]' "$CORE_CONFIG")

	if [ -z "$MODULE" ] || [ "$MODULE" = "null" ]; then
		printf "Core '%s' not found in '%s'\n" "$NAME" "$CORE_CONFIG" >&2
		continue
	fi

	# Required keys
	DIR=$(echo "$MODULE"   | jq -r '.directory')
	OUTPUT_LIST=$(echo "$MODULE" | jq -r '.output | if type=="string" then . else join(" ") end')
	SOURCE=$(echo "$MODULE" | jq -r '.source')
	SYMBOLS=$(echo "$MODULE" | jq -r '.symbols')

	# Make keys
	MAKE_FILE=$(echo "$MODULE" | jq -r '.make.file')
	MAKE_ARGS=$(echo "$MODULE" | jq -r '.make.args')
	MAKE_TARGET=$(echo "$MODULE" | jq -r '.make.target')

	# Verify required keys
	if [ -z "$DIR" ] || [ -z "$OUTPUT_LIST" ] || [ -z "$SOURCE" ] || [ -z "$MAKE_FILE" ] || [ -z "$SYMBOLS" ]; then
		printf "Missing required configuration keys for '%s' in '%s'\n" "$NAME" "$CORE_CONFIG" >&2
		continue
	fi

	BRANCH=$(echo "$MODULE"     | jq -r '.branch // ""')
	PRE_MAKE=$(echo "$MODULE"   | jq -r '.commands["pre-make"] // []')
	POST_MAKE=$(echo "$MODULE"  | jq -r '.commands["post-make"] // []')
	CORE_PURGE_FLAG=$(echo "$MODULE" | jq -r '.purge // 0')
	case "$CORE_PURGE_FLAG" in
		1) CORE_PURGE_FLAG=1 ;;
		*) CORE_PURGE_FLAG=0 ;;
	esac

	CORE_DIR="$BUILD_DIR/$DIR"

	printf "Processing: %s\n\n" "$NAME"

	# Read cached entry
	CACHED_ENTRY=$(jq -c --arg name "$NAME" '.[$name] // empty' "$CACHE_FILE")
	CACHED_HASH=$(printf "%s" "$CACHED_ENTRY" | jq -r 'if type=="object" then .hash // "" else . end' 2>/dev/null)
	CACHED_DIR=$(printf "%s" "$CACHED_ENTRY" | jq -r 'if type=="object" then .dir // "" else "" end' 2>/dev/null)

	# Resolve remote hash (HEAD or branch name / pinned commit)
	if [ "$LATEST" -eq 1 ]; then
		REMOTE_HASH=$(git ls-remote "$SOURCE" HEAD | cut -c 1-7)
	else
		if [ -n "$BRANCH" ]; then
			if echo "$BRANCH" | grep -qE '^[0-9a-f]{7,40}$'; then
				REMOTE_HASH="$BRANCH"
			else
				REMOTE_HASH=$(git ls-remote "$SOURCE" "refs/heads/$BRANCH" | cut -c 1-7)
			fi
		else
			REMOTE_HASH=$(git ls-remote "$SOURCE" HEAD | cut -c 1-7)
		fi
	fi

	if [ -z "$REMOTE_HASH" ]; then
		printf "Failed to get remote hash for '%s'\n" "$NAME" >&2
		continue
	fi

	printf "Remote hash: %s\n" "$REMOTE_HASH"
	printf "Cached hash: %s\n" "$CACHED_HASH"
	[ -n "$CACHED_DIR" ] && printf "Cached dir:  %s\n" "$CACHED_DIR"
	[ "$CORE_PURGE_FLAG" -eq 1 ] && printf "purge: enabled for this core\n"

	# Determine expected zip name
	EXPECTED_ZIP_NAME=$(
		set -- $OUTPUT_LIST
		if [ "$#" -eq 1 ]; then
			bn=$(basename "$1")
			printf "%s.zip" "$bn"
		else
			printf "%s.zip" "$NAME"
		fi
	)
	ZIP_NAME="$EXPECTED_ZIP_NAME"

	# If directory changed since last time, remove the stale one
	if [ -n "$CACHED_DIR" ] && [ "$CACHED_DIR" != "$DIR" ]; then
		SAFE_RM_DIR "$BUILD_DIR/$CACHED_DIR"
	fi

	# If PURGE is set, delete the repo folder *now* (even if we skip later)
	# This implements: "purge is to delete the repo folder"
	if [ "$PURGE" -eq 1 ] || [ "$CORE_PURGE_FLAG" -eq 1 ]; then
		printf "Purging core repo directory: %s\n" "$CORE_DIR"
		rm -rf "$CORE_DIR"
	fi

	# Skip when up to date (purge does not block skipping; we won't re-clone)
	if [ "$FORCE" -eq 0 ] && \
	   [ "$CACHED_HASH" = "$REMOTE_HASH" ] && [ -f "$RETRO_DIR/$ZIP_NAME" ]; then
  		printf "Core '%s' is up to date (hash: %s). Skipping build.\n" "$NAME" "$REMOTE_HASH"
		jq --arg name "$NAME" --arg hash "$REMOTE_HASH" --arg dir "$DIR" \
		   '(.[$name] = {"hash":$hash,"dir":$dir})' "$CACHE_FILE" >"$CACHE_FILE.tmp" && mv "$CACHE_FILE.tmp" "$CACHE_FILE"
  		continue
	fi

	BEEN_CLONED=0
	if [ ! -d "$CORE_DIR" ]; then
		printf "Core '%s' not found\n\n" "$DIR"
		# Clone
		if [ "$LATEST" -eq 1 ]; then
			GC_CMD="git clone --progress --quiet --recurse-submodules -j$NPROC $SOURCE $CORE_DIR"
		elif [ -n "$BRANCH" ] && echo "$BRANCH" | grep -qE '^[0-9a-f]{7,40}$'; then
			GC_CMD="git clone --progress --quiet --recurse-submodules -j$NPROC $SOURCE $CORE_DIR"
		else
			GC_CMD="git clone --progress --quiet --recurse-submodules -j$NPROC"
			[ -n "$BRANCH" ] && GC_CMD="$GC_CMD -b $BRANCH"
			GC_CMD="$GC_CMD $SOURCE $CORE_DIR"
		fi
		eval "$GC_CMD" || { printf "Failed to clone %s\n" "$SOURCE" >&2; continue; }

		# Enter repo to init submodules and optional commit checkout
		cd "$CORE_DIR" || { printf "Failed to enter %s\n" "$CORE_DIR" >&2; RETURN_TO_BASE; continue; }

		if [ "$LATEST" -eq 0 ] && [ -n "$BRANCH" ] && echo "$BRANCH" | grep -qE '^[0-9a-f]{7,40}$'; then
			git fetch --all || { printf "Failed to fetch in %s\n" "$CORE_DIR" >&2; RETURN_TO_BASE; continue; }
			git checkout --detach "$BRANCH" || { printf "Failed to checkout %s\n" "$BRANCH" >&2; RETURN_TO_BASE; continue; }
		fi

		git submodule update --init --recursive || {
			printf "Failed to update submodules for %s\n" "$NAME" >&2
			RETURN_TO_BASE
			continue
		}

		cd - > /dev/null
		printf "\n"
		BEEN_CLONED=1
	fi

	# Enter repo for update and build
	cd "$CORE_DIR" || { printf "Failed to enter %s\n" "$CORE_DIR" >&2; continue; }

	# Ensure submodules are present
	git submodule update --init --recursive || {
		printf "Failed to update submodules for %s\n" "$NAME" >&2
		RETURN_TO_BASE
		continue
	}

	if [ $BEEN_CLONED -eq 0 ]; then
		if [ "$LATEST" -eq 1 ]; then
			printf "Updating '%s' to remote HEAD (latest)\n" "$NAME"
			git fetch --quiet origin || { printf "  fetch failed for '%s'\n" "$NAME" >&2; RETURN_TO_BASE; continue; }
			git reset --hard origin/HEAD || { printf "  reset failed for '%s'\n" "$NAME" >&2; RETURN_TO_BASE; continue; }
			git submodule sync --quiet
			git submodule update --init --recursive --quiet || { printf "  submodule update failed for '%s'\n" "$NAME" >&2; RETURN_TO_BASE; continue; }
		elif [ -n "$BRANCH" ] && echo "$BRANCH" | grep -qE '^[0-9a-f]{7,40}$'; then
			printf "Repository already cloned. Fetching updates and checking out commit '%s'\n" "$BRANCH"
			git fetch --all || { printf "Failed to fetch updates for '%s'\n" "$NAME" >&2; RETURN_TO_BASE; continue; }
			git checkout --detach "$BRANCH" || { printf "Failed to checkout commit '%s' for '%s'\n" "$BRANCH" "$NAME" >&2; RETURN_TO_BASE; continue; }
		else
			printf "Updating '%s' to remote HEAD\n" "$NAME"
			git fetch --quiet origin || { printf "  fetch failed for '%s'\n" "$NAME" >&2; RETURN_TO_BASE; continue; }
			git reset --hard origin/HEAD || { printf "  reset failed for '%s'\n" "$NAME" >&2; RETURN_TO_BASE; continue; }
			git submodule sync --quiet
			git submodule update --init --recursive --quiet || { printf "  submodule update failed for '%s'\n" "$NAME" >&2; RETURN_TO_BASE; continue; }
		fi
	fi

	# Verify local hash matches remote hash after clone or update
	LOCAL_HASH=$(git rev-parse --short HEAD | cut -c 1-7)
	if [ "$LOCAL_HASH" != "$REMOTE_HASH" ]; then
		printf "Warning: Local hash (%s) doesn't match remote hash (%s)\n" "$LOCAL_HASH" "$REMOTE_HASH" >&2
		RETURN_TO_BASE
		continue
	fi

	APPLY_PATCHES "$NAME" "$CORE_DIR" || {
		printf "Failed to apply patches for %s\n" "$NAME" >&2
		RETURN_TO_BASE
		continue
	}

	if [ "$PRE_MAKE" != "[]" ]; then
		if ! RUN_COMMANDS "pre-make" "$PRE_MAKE"; then
			printf "Pre-make commands failed for %s\n" "$NAME" >&2
			RETURN_TO_BASE
			continue
		fi
	fi

	printf "Make Structure:"
	printf "\n\tFILE:\t%s" "$MAKE_FILE"
	printf "\n\tARGS:\t%s" "$MAKE_ARGS"
	printf "\n\tTARGET: %s\n" "$MAKE_TARGET"

	printf "\nBuilding '%s' ...\n" "$NAME"

	(while :; do
		printf '.'
		sleep 1
	done) | pv -q -L 10 -N "Building $NAME" &

	PV_PID=$!
	trap 'kill $PV_PID 2>/dev/null' EXIT

	LOGFILE="$(dirname "$0")/build.log"
	START_TS=$(date +%s)

	# Run make; capture everything into build.log
	kill $PV_PID 2>/dev/null
	if make -j"$NPROC" -f "$MAKE_FILE" $MAKE_ARGS $MAKE_TARGET >>"$LOGFILE" 2>&1; then
		printf "\nBuild succeeded: %s\n" "$NAME"
		jq --arg name "$NAME" --arg hash "$REMOTE_HASH" --arg dir "$DIR" \
		   '(.[$name] = {"hash":$hash,"dir":$dir})' "$CACHE_FILE" >"$CACHE_FILE.tmp" && mv "$CACHE_FILE.tmp" "$CACHE_FILE"
	else
    	printf "\nBuild FAILED: %s - see %s\n" "$NAME" "$LOGFILE" >&2
    	RETURN_TO_BASE
    	continue
	fi

	END_TS=$(date +%s)
	printf "Duration for '%s': %ds\n" "$NAME" "$((END_TS - START_TS))" >>"$LOGFILE"

	if [ "$POST_MAKE" != "[]" ]; then
		if ! RUN_COMMANDS "post-make" "$POST_MAKE"; then
			printf "Post-make commands failed for '%s'\n" "$NAME" >&2
			RETURN_TO_BASE
			continue
		fi
	fi

	# Strip and relocate all outputs, then zip them together as $ZIP_NAME
	OUTPUTS="$OUTPUT_LIST"

	# Validate each output exists
	MISSING=0
	for OUTFILE in $OUTPUTS; do
		if [ ! -f "$OUTFILE" ]; then
			printf "Missing expected output '%s' for '%s'\n" "$OUTFILE" "$NAME" >&2
			MISSING=1
		fi
	done
	if [ "$MISSING" -ne 0 ]; then
		RETURN_TO_BASE
		continue
	fi

	# Process each output
	for OUTFILE in $OUTPUTS; do
		if [ "$SYMBOLS" -eq 0 ]; then
			if file "$OUTFILE" | grep -q 'ELF'; then
				if file "$OUTFILE" | grep -q 'not stripped'; then
					$STRIP -sx "$OUTFILE" 2>/dev/null && printf "Stripped debug symbols: %s\n" "$OUTFILE"
				fi
				if readelf -S "$OUTFILE" 2>/dev/null | grep -Fq '.note.gnu.build-id'; then
					$OBJCOPY --remove-section=.note.gnu.build-id "$OUTFILE" 2>/dev/null && printf "Removed BuildID section: %s\n" "$OUTFILE"
				fi
			fi
		fi
		printf "File Information: %s\n" "$(file -b "$OUTFILE")"
	done

	printf "\nMoving outputs to '%s'\n" "$RETRO_DIR"
	for OUTFILE in $OUTPUTS; do
		mv "$OUTFILE" "$RETRO_DIR" || {
			printf "Failed to move '%s' for '%s' to '%s'\n" "$OUTFILE" "$NAME" "$RETRO_DIR" >&2
			RETURN_TO_BASE
			continue 2
		}
	done

	printf "\nIndexing and compressing outputs for '%s'\n" "$NAME"

	cd "$RETRO_DIR" || { printf "Failed to enter directory %s\n" "$RETRO_DIR" >&2; RETURN_TO_BASE; continue; }

	# Decide zip name based on .so file if present (multi-output)
	SOFILE=$(printf "%s\n" $OUTPUTS | grep '\.so$' | head -n1)
	if [ -n "$SOFILE" ]; then
		ZIP_NAME="$(basename "$SOFILE").zip"
	else
		# fallback to original behavior
		set -- $OUTPUTS
		if [ "$#" -eq 1 ]; then
			ZIP_NAME="$(basename "$1").zip"
		else
			ZIP_NAME="${NAME}.zip"
		fi
	fi

	[ -f "$ZIP_NAME" ] && rm -f "$ZIP_NAME"

	# Zip moved files by basename
	BASENAMES=""
	for OUTFILE in $OUTPUTS; do
		BASENAMES="$BASENAMES $(basename "$OUTFILE")"
	done
	# shellcheck disable=SC2086
	zip -q "$ZIP_NAME" $BASENAMES

	# Remove raw outputs after packaging
	for OUTFILE in $OUTPUTS; do
		rm -f "$(basename "$OUTFILE")"
	done

	# Update indexes using checksum of the zip
	CKSUM=$(cksum "$ZIP_NAME" | awk '{print $1}')
	INDEX_LINE="$(date +%Y-%m-%d) $(printf "%08x" "$CKSUM") $ZIP_NAME"

	ESCAPED_ZIP=$(printf "%s" "$ZIP_NAME" | sed 's/[\\/&]/\\&/g')

	if [ -f .index-extended ]; then
		sed "/$ESCAPED_ZIP/d" .index-extended >.index-extended.tmp && mv .index-extended.tmp .index-extended
	else
		touch .index-extended
	fi
	echo "$INDEX_LINE" >>.index-extended

	if [ -f .index ]; then
		sed "/$ESCAPED_ZIP/d" .index >.index.tmp && mv .index.tmp .index
	else
		touch .index
	fi
	echo "$ZIP_NAME" >>.index

	sort -k3 .index-extended -o .index-extended
	sort .index -o .index

	# After build: if PURGE (global or per-core) was requested, delete the repo folder; otherwise try a clean
	if [ "$PURGE" -eq 1 ] || [ "$CORE_PURGE_FLAG" -eq 1 ]; then
		printf "\nPurging core repo directory: %s\n" "$CORE_DIR"
		rm -rf "$CORE_DIR"
	else
		printf "Cleaning build environment for '%s'\n" "$NAME"
		make -C "$CORE_DIR" clean >/dev/null 2>&1 || {
			printf "Clean failed or not required\n" >&2
		}
	fi

	RETURN_TO_BASE
done

(
	printf "<!DOCTYPE html>\n<html>\n<head>\n<title>MURCB - muOS RetroArch Core Builder</title>\n</head>\n<body>\n"
	printf "<pre style='font-size:2rem;margin-top:-5px;margin-bottom:-15px;'>MURCB - muOS RetroArch Core Builder</pre>\n"
	printf "<pre style='font-size:1rem;'>Currently only <span style='font-weight:800'>"
	printf "aarch64"
	printf "</span> builds for now!</pre>\n"
	printf "<hr>\n<pre>\n"
	[ -f "$RETRO_DIR/.index-extended" ] && cat "$RETRO_DIR/.index-extended" || printf "No cores available!\n"
	printf "</pre>\n</body>\n</html>\n"
) >"$RETRO_DIR/index.html"

printf "\n-------------------------------------------------------------------------\n"
printf "All successful core builds are in '%s'\n\n" "$RETRO_DIR"
