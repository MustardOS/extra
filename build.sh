#!/bin/sh

printf "\nMURCB - muOS RetroArch Core Builder\n"

# Track the original parent shell PID so we can self-terminate if it disappears.
ORIG_PPID=$PPID

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
	echo "  -t, --target [arch]    Target architecture: aarch64, x86_64, armhf, x86, riscv64"
	echo ""
	echo "Notes:"
	echo "  - Either -a, -c, or -u is required, but NOT together"
	echo "  - If -p is used, it MUST be the first argument"
	echo ""
	echo "Examples:"
	echo "  $0 -t aarch64 -a"
	echo "  $0 -t x86_64 -a"
	echo "  $0 -t armhf -a"
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
CORE_CLEAN_FLAG=0
TARGET_ARCH=aarch64

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
			[ "$OPTION_SPECIFIED" -ne 0 ] && USAGE
			OPTION_SPECIFIED=1
			shift
			UPDATE=1
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
		-t | --target)
			shift
			[ "$#" -gt 0 ] || USAGE
			TARGET_ARCH=$1
			shift
			;;
		*)
			printf "Error: Unknown option '%s'\n" "$1" >&2
			USAGE
			;;
	esac
done

case "$TARGET_ARCH" in
	aarch64 | armhf | x86_64 | x86 | riscv64) ;;
	x64 | amd64) TARGET_ARCH=x86_64 ;;
	arm32 | armv7) TARGET_ARCH=armhf ;;
	*)
		printf "Unsupported target architecture: %s\n" "$TARGET_ARCH" >&2
		exit 1
		;;
esac

# Do not inherit a host shell's CMake generator or stale make-program path.
# Recipes which require a generator select one explicitly.
unset CMAKE_GENERATOR CMAKE_GENERATOR_INSTANCE CMAKE_GENERATOR_PLATFORM CMAKE_GENERATOR_TOOLSET CMAKE_MAKE_PROGRAM

# Confirm a valid argument was provided, else show USAGE
[ "$OPTION_SPECIFIED" -eq 0 ] && [ "$UPDATE" -eq 0 ] && USAGE

# Warn if -x used without -a
if [ -n "$EXCLUDE_CORES" ] && [ "$BUILD_ALLNOW" -ne 1 ]; then
	printf "Warning: --exclude is only effective with --all\n"
fi

# Initialise directory variables
BASE_DIR=$(pwd)
CORE_CONFIG="data/core.json"
RETRO_DIR="$BASE_DIR/core/$TARGET_ARCH"
BUILD_DIR="$BASE_DIR/build"
PATCH_DIR="$BASE_DIR/patch"

# Create a per-run temp directory for ALL scratch files (always cleaned up)
TMPDIR_BASE=${TMPDIR:-/tmp}
RUN_TMPDIR="$(mktemp -d "$TMPDIR_BASE/murcb.XXXXXX")" || {
	printf "Error: mktemp failed\n" >&2
	exit 1
}

SPINNER_PID=""

# Added: watcher + child tracking so the script cannot become "unreachable"
WATCHER_PID=""
CHILD_PIDS=""
IN_CLEANUP=0

ADD_CHILD_PID() {
	_p=$1
	[ -n "$_p" ] || return 0
	case " $CHILD_PIDS " in
		*" $_p "*) return 0 ;;
	esac
	CHILD_PIDS="${CHILD_PIDS:+$CHILD_PIDS }$_p"
}

REMOVE_CHILD_PID() {
	_p=$1
	[ -n "$_p" ] || return 0
	_new=""
	for _x in $CHILD_PIDS; do
		[ "$_x" = "$_p" ] && continue
		_new="${_new:+$_new }$_x"
	done
	CHILD_PIDS="$_new"
}

# Snapshot all processes: "PID PPID"
_PS_SNAPSHOT() {
	ps -e -o pid= -o ppid= 2>/dev/null
}

# Return a space-separated list of all descendants of $1, including $1
DESCENDANTS_OF() {
	_root=$1
	[ -n "$_root" ] || return 0

	_pp="$(_PS_SNAPSHOT)" || return 0

	_list="$_root"
	_front="$_root"

	while [ -n "$_front" ]; do
		_next=""
		for _p in $_front; do
			_children=$(printf "%s\n" "$_pp" | awk -v p="$_p" '$2==p {print $1}')
			for _c in $_children; do
				case " $_list " in
					*" $_c "*) : ;;
					*) _list="$_list $_c"; _next="${_next}${_next:+ }$_c" ;;
				esac
			done
		done
		_front="$_next"
	done

	printf '%s' "$_list"
}

KILL_TREE() {
	_pid=$1
	[ -n "$_pid" ] || return 0

	# Build descendant list once
	_all=$(DESCENDANTS_OF "$_pid")

	# Best effort: kill process group, then the pid, then all descendants
	kill -TERM -- "-$_pid" 2>/dev/null || :
	kill -TERM "$_pid" 2>/dev/null || :
	for _p in $_all; do
		kill -TERM "$_p" 2>/dev/null || :
	done

	sleep 0.2 2>/dev/null || :

	# Escalate
	kill -KILL -- "-$_pid" 2>/dev/null || :
	for _p in $_all; do
		kill -0 "$_p" 2>/dev/null || continue
		kill -KILL "$_p" 2>/dev/null || :
	done
}

PARENT_WATCH() {
	_pp=$1
	while kill -0 "$_pp" 2>/dev/null; do
		sleep 1
	done
	# Parent is gone. Trigger our HUP handler even if the kernel didn't deliver SIGHUP.
	kill -HUP "$$" 2>/dev/null || :
}

CLEANUP() {
	# Prevent re-entrancy
	if [ "$IN_CLEANUP" -ne 0 ]; then
		return 0
	fi
	IN_CLEANUP=1

	# stop watcher first
	if [ -n "$WATCHER_PID" ]; then
		kill "$WATCHER_PID" 2>/dev/null || :
		wait "$WATCHER_PID" 2>/dev/null || :
		REMOVE_CHILD_PID "$WATCHER_PID"
		WATCHER_PID=""
	fi

	# stop spinner
	if [ -n "$SPINNER_PID" ]; then
		kill "$SPINNER_PID" 2>/dev/null || :
		wait "$SPINNER_PID" 2>/dev/null || :
		REMOVE_CHILD_PID "$SPINNER_PID"
		SPINNER_PID=""
		printf "\r\033[K"
	fi

	# Kill any tracked child processes (make, logged command subshells, etc.)
	if [ -n "$CHILD_PIDS" ]; then
		trap '' INT TERM HUP

		for _p in $CHILD_PIDS; do
			KILL_TREE "$_p"
		done

		for _p in $CHILD_PIDS; do
			wait "$_p" 2>/dev/null || :
		done

		CHILD_PIDS=""
	fi

	# Remove all scratch files
	if [ -n "$RUN_TMPDIR" ] && [ -d "$RUN_TMPDIR" ]; then
		rm -rf -- "$RUN_TMPDIR" 2>/dev/null || true
	fi

	# Best-effort return to base
	cd "$BASE_DIR" 2>/dev/null || true
}

# Always cleanup, including Ctrl+C
trap 'CLEANUP; exit 1' INT TERM HUP
trap 'CLEANUP' EXIT

# Added: start parent watcher so script cannot outlive its invoking shell unnoticed
PARENT_WATCH "$ORIG_PPID" &
WATCHER_PID=$!
ADD_CHILD_PID "$WATCHER_PID"

# POSIX safe CPU count
NPROC=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)

# Default behavior: nproc-1 (min 1)
# Override: export MAKE_CORES=<n> (must be positive int)
if [ -z "${MAKE_CORES+x}" ] || [ -z "$MAKE_CORES" ]; then
	if [ "$NPROC" -gt 1 ]; then
		MAKE_CORES=$((NPROC - 1))
	else
		MAKE_CORES=1
	fi
fi

# Validate it's a positive integer
case "$MAKE_CORES" in
	*[!0-9]*|"")
		printf "Error: MAKE_CORES must be a positive integer (got '%s')\n" "$MAKE_CORES" >&2
		exit 1
		;;
esac
if [ "$MAKE_CORES" -lt 1 ]; then
	printf "Error: MAKE_CORES must be >= 1 (got '%s')\n" "$MAKE_CORES" >&2
	exit 1
fi

# Timestamps
NOW() { date '+%Y-%m-%d %H:%M:%S %z'; }

# Failure tracking (per-run scratch, plus end-of-run summary in core/)
FAIL_LOG="$RUN_TMPDIR/failed-cores.tsv"
: >"$FAIL_LOG" || {
	printf "Error: could not create failure log in %s\n" "$RUN_TMPDIR" >&2
	exit 1
}
printf "core\tstage\treason\ttime\n" >>"$FAIL_LOG"

MARK_FAIL() {
	_core="$1"
	_stage="$2"
	_reason="$3"
	# Keep it one line, tab separated
	_reason_s=$(printf "%s" "$_reason" | tr '\n' ' ' | tr '\t' ' ' | sed 's/[[:space:]][[:space:]]*/ /g; s/[[:space:]]*$//')
	printf "%s\t%s\t%s\t%s\n" "$_core" "$_stage" "$_reason_s" "$(NOW)" >>"$FAIL_LOG"
}

RECORD_FAILURE() {
	_core="$1"
	_stage="$2"
	_reason="$3"
	MARK_FAIL "$_core" "$_stage" "$_reason"
	RETURN_TO_BASE
}

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
	UPDATE_ARCHIVE="muOS-RetroArch-Core_Update-${TARGET_ARCH}-$(date +"%Y-%m-%d_%H-%M").muxzip"
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

FIND_TOOL() {
	for TOOL_CANDIDATE in "$@"; do
		TOOL_PATH=$(command -v "$TOOL_CANDIDATE" 2>/dev/null || true)
		if [ -n "$TOOL_PATH" ] && [ -x "$TOOL_PATH" ]; then
			printf '%s\n' "$TOOL_PATH"
			return 0
		fi
		if [ -x "$TOOL_CANDIDATE" ]; then
			printf '%s\n' "$TOOL_CANDIDATE"
			return 0
		fi
	done
	return 1
}

case "$TARGET_ARCH" in
	aarch64)
		TOOL_PREFIX="$HOME/x-tools/aarch64-buildroot-linux-gnu/bin/aarch64-buildroot-linux-gnu-"
		TARGET_CC=$(FIND_TOOL aarch64-linux-gnu-gcc aarch64-linux-gcc aarch64-buildroot-linux-gnu-gcc "${TOOL_PREFIX}gcc")
		TARGET_CXX=$(FIND_TOOL aarch64-linux-gnu-g++ aarch64-linux-g++ aarch64-buildroot-linux-gnu-g++ "${TOOL_PREFIX}g++")
		TARGET_AR=$(FIND_TOOL aarch64-linux-gnu-ar aarch64-linux-ar aarch64-buildroot-linux-gnu-ar "${TOOL_PREFIX}ar")
		TARGET_RANLIB=$(FIND_TOOL aarch64-linux-gnu-ranlib aarch64-linux-ranlib aarch64-buildroot-linux-gnu-ranlib "${TOOL_PREFIX}ranlib")
		OBJCOPY=$(FIND_TOOL aarch64-linux-gnu-objcopy aarch64-linux-objcopy aarch64-buildroot-linux-gnu-objcopy "${TOOL_PREFIX}objcopy")
		STRIP=$(FIND_TOOL aarch64-linux-gnu-strip aarch64-linux-strip aarch64-buildroot-linux-gnu-strip "${TOOL_PREFIX}strip")
		MAKE_ARCH='-march=armv8-a+crc+crypto -mtune=cortex-a53'
		TARGET_MACHINE='AArch64'
		TARGET_PLATFORM=aarch64
		TARGET_DYNAREC=aarch64
		TARGET_LCPU=arm64
		;;
	armhf)
		TOOL_PREFIX="$HOME/x-tools/arm-buildroot-linux-gnueabihf/bin/arm-buildroot-linux-gnueabihf-"
		TARGET_CC=$(FIND_TOOL arm-linux-gnueabihf-gcc arm-buildroot-linux-gnueabihf-gcc "${TOOL_PREFIX}gcc")
		TARGET_CXX=$(FIND_TOOL arm-linux-gnueabihf-g++ arm-buildroot-linux-gnueabihf-g++ "${TOOL_PREFIX}g++")
		TARGET_AR=$(FIND_TOOL arm-linux-gnueabihf-ar arm-buildroot-linux-gnueabihf-ar "${TOOL_PREFIX}ar")
		TARGET_RANLIB=$(FIND_TOOL arm-linux-gnueabihf-ranlib arm-buildroot-linux-gnueabihf-ranlib "${TOOL_PREFIX}ranlib")
		OBJCOPY=$(FIND_TOOL arm-linux-gnueabihf-objcopy arm-buildroot-linux-gnueabihf-objcopy "${TOOL_PREFIX}objcopy")
		STRIP=$(FIND_TOOL arm-linux-gnueabihf-strip arm-buildroot-linux-gnueabihf-strip "${TOOL_PREFIX}strip")
		MAKE_ARCH='-march=armv7-a -mfpu=vfpv3-d16 -mfloat-abi=hard'
		TARGET_MACHINE='ARM'
		TARGET_PLATFORM=armv
		TARGET_DYNAREC=arm
		TARGET_LCPU=arm
		;;
	x86_64 | x86)
		if [ "$TARGET_ARCH" = x86_64 ]; then
			TARGET_CC=$(FIND_TOOL x86_64-buildroot-linux-gnu-gcc gcc)
			TARGET_CXX=$(FIND_TOOL x86_64-buildroot-linux-gnu-g++ g++)
			TARGET_AR=$(FIND_TOOL x86_64-buildroot-linux-gnu-ar ar)
			TARGET_RANLIB=$(FIND_TOOL x86_64-buildroot-linux-gnu-ranlib ranlib)
			OBJCOPY=$(FIND_TOOL x86_64-buildroot-linux-gnu-objcopy objcopy)
			STRIP=$(FIND_TOOL x86_64-buildroot-linux-gnu-strip strip)
			MAKE_ARCH='-march=x86-64-v2 -mtune=generic'
			TARGET_MACHINE='Advanced Micro Devices X86-64'
			TARGET_DYNAREC=x86_64
			TARGET_LCPU=x86_64
		else
			TARGET_CC=$(FIND_TOOL gcc)
			TARGET_CXX=$(FIND_TOOL g++)
			TARGET_AR=$(FIND_TOOL ar)
			TARGET_RANLIB=$(FIND_TOOL ranlib)
			OBJCOPY=$(FIND_TOOL objcopy)
			STRIP=$(FIND_TOOL strip)
			MAKE_ARCH='-m32 -march=i686'
			TARGET_MACHINE='Intel 80386'
			TARGET_DYNAREC=x86
			TARGET_LCPU=x86
		fi
		TARGET_PLATFORM=unix
		;;
	riscv64)
		TOOL_PREFIX="$HOME/x-tools/riscv64-buildroot-linux-gnu/bin/riscv64-buildroot-linux-gnu-"
		TARGET_CC=$(FIND_TOOL riscv64-linux-gnu-gcc riscv64-buildroot-linux-gnu-gcc "${TOOL_PREFIX}gcc")
		TARGET_CXX=$(FIND_TOOL riscv64-linux-gnu-g++ riscv64-buildroot-linux-gnu-g++ "${TOOL_PREFIX}g++")
		TARGET_AR=$(FIND_TOOL riscv64-linux-gnu-ar riscv64-buildroot-linux-gnu-ar "${TOOL_PREFIX}ar")
		TARGET_RANLIB=$(FIND_TOOL riscv64-linux-gnu-ranlib riscv64-buildroot-linux-gnu-ranlib "${TOOL_PREFIX}ranlib")
		OBJCOPY=$(FIND_TOOL riscv64-linux-gnu-objcopy riscv64-buildroot-linux-gnu-objcopy "${TOOL_PREFIX}objcopy")
		STRIP=$(FIND_TOOL riscv64-linux-gnu-strip riscv64-buildroot-linux-gnu-strip "${TOOL_PREFIX}strip")
		MAKE_ARCH='-march=rv64gc -mabi=lp64d'
		TARGET_MACHINE='RISC-V'
		TARGET_PLATFORM=unix
		TARGET_DYNAREC=riscv64
		TARGET_LCPU=riscv64
		;;
esac

if [ -z "$TARGET_CC" ] || [ -z "$TARGET_CXX" ] || [ -z "$TARGET_AR" ] || [ -z "$TARGET_RANLIB" ] \
	|| [ -z "$OBJCOPY" ] || [ -z "$STRIP" ]; then
	printf "Error: Incomplete %s compiler toolchain\n" "$TARGET_ARCH" >&2
	exit 1
fi

export CC="$TARGET_CC"
export CXX="$TARGET_CXX"
export AR="$TARGET_AR"
export RANLIB="$TARGET_RANLIB"
export STRIP

# Check for other required commands
for CMD in file git jq make patch readelf zip unzip cksum sort sed awk grep head cut tr find pwd; do
	if ! command -v "$CMD" >/dev/null 2>&1; then
		printf "Error: Missing required command '%s'\n" "$CMD" >&2
		exit 1
	fi
done

# Create required directories
mkdir -p "$RETRO_DIR"
mkdir -p "$BUILD_DIR"

RETURN_TO_BASE() {
	cd "$BASE_DIR" || {
		printf "Failed to return to base directory\n" >&2
		exit 1
	}
}

# Spinner (single-line) + logged command runner
SPINNER_START() {
	_label=$1
	_t0=$(date +%s)

	# Only animate on a real terminal
	if [ ! -t 1 ]; then
		SPINNER_PID=""
		return 0
	fi

	# Do not start a second spinner
	if [ -n "$SPINNER_PID" ]; then
		return 0
	fi

	(
		trap 'exit 0' HUP INT TERM

		step=0
		cycle=0

		ESC=$(printf '\033')
		RESET="${ESC}[0m"

		rainbow() {
			h=$1
			h=$((h % 360))
			[ "$h" -lt 0 ] && h=$((h + 360))

			region=$((h / 60))
			f=$((h % 60))

			q=$((255 - (f * 255 / 60)))
			t2=$((f * 255 / 60))

			r=0 g=0 b=0
			case "$region" in
				0) r=255; g=$t2; b=0 ;;
				1) r=$q;  g=255; b=0 ;;
				2) r=0;   g=255; b=$t2 ;;
				3) r=0;   g=$q;  b=255 ;;
				4) r=$t2; g=0;   b=255 ;;
				5) r=255; g=0;   b=$q ;;
			esac

			rr=$(((r * 5 + 127) / 255))
			gg=$(((g * 5 + 127) / 255))
			bb=$(((b * 5 + 127) / 255))

			printf '%s' "${ESC}[38;5;$((16 + 36*rr + 6*gg + bb))m"
		}

		part_char() {
			case "$1" in
				0) printf ' ' ;;
				1) printf '▏' ;;
				2) printf '▎' ;;
				3) printf '▍' ;;
				4) printf '▌' ;;
				5) printf '▋' ;;
				6) printf '▊' ;;
				7) printf '▉' ;;
				8) printf '█' ;;
			esac
		}

		while :; do
			m=$((step % 160))
			if [ "$m" -le 80 ]; then
				units=$m
			else
				units=$((160 - m))
			fi

			# cycle increments when we start a new rising pass (units goes 0->...)
			if [ "$units" -eq 0 ] && [ "$step" -ne 0 ] && [ "$m" -eq 0 ]; then
				cycle=$((cycle + 1))
			fi

			full=$((units / 8))
			rem=$((units % 8))

			now=$(date +%s)
			el=$((now - _t0))

			h=$((el / 3600))
			m=$(((el % 3600) / 60))
			s=$((el % 60))

			base_hue=$((cycle * 12))

			bar=""
			i=1
			while [ "$i" -le 10 ]; do
				hue=$((base_hue - (i - 1) * 36))
				col=$(rainbow "$hue")

				if [ "$i" -le "$full" ]; then
					bar="${bar}${col}█${RESET}"
				elif [ "$i" -eq $((full + 1)) ] && [ "$rem" -gt 0 ]; then
					bar="${bar}${col}$(part_char "$rem")${RESET}"
				else
					bar="${bar} "
				fi

				i=$((i + 1))
			done

			printf "\r%s  ┤%s├  %d:%02d:%02d elapsed\033[K" "$_label" "$bar" "$h" "$m" "$s"

			step=$((step + 1))
			sleep 0.05
		done
	) &
	SPINNER_PID=$!
	ADD_CHILD_PID "$SPINNER_PID"
}

SPINNER_STOP() {
	_pid=$SPINNER_PID
	SPINNER_PID=""
	if [ -n "$_pid" ]; then
		kill "$_pid" 2>/dev/null || :
		wait "$_pid" 2>/dev/null || :
		REMOVE_CHILD_PID "$_pid"
		[ -t 1 ] && printf "\n"
	fi
}

RUN_WITH_SPINNER_LOG() {
	_label=$1
	_log=$2
	shift 2

	[ -n "$_log" ] || _log="$RUN_TMPDIR/build.log"

	SPINNER_START "$_label"

	if command -v setsid >/dev/null 2>&1; then
		setsid "$@" >>"$_log" 2>&1 &
	else
		"$@" >>"$_log" 2>&1 &
	fi
	_cmdpid=$!
	ADD_CHILD_PID "$_cmdpid"
	wait "$_cmdpid"
	_rc=$?
	REMOVE_CHILD_PID "$_cmdpid"

	SPINNER_STOP
	return $_rc
}

# WORKDIR is per-core and must persist across pre-make -> make -> post-make.
# We execute command lists in a subshell for safety/logging, but then we apply any `cd ...`
# directives to WORKDIR in the parent shell so later phases run in the expected directory.
WORKDIR=""

APPLY_CD_EFFECTS() {
	_CMD_FILE="$1"

	# Track cd - support minimally
	_prev="$WORKDIR"

	while IFS= read -r _CMD; do
		# trim leading spaces
		case "$_CMD" in
			"") continue ;;
		esac

		case "$_CMD" in
			cd\ *|cd)
				# Parse: cd <arg>
				# shellcheck disable=SC2086
				set -- $_CMD

				# If it's just `cd`, go to HOME
				if [ "$#" -lt 2 ]; then
					_target=${HOME:-/}
				else
					_target=$2
				fi

				if [ "$_target" = "-" ]; then
					# swap
					_tmp="$_prev"
					_prev="$WORKDIR"
					WORKDIR="$_tmp"
					continue
				fi

				# Resolve relative to current WORKDIR
				_new=$(cd "$WORKDIR" 2>/dev/null && cd "$_target" 2>/dev/null && pwd -P) || {
					printf "Error: cd failed while applying command '%s' (WORKDIR=%s)\n" "$_CMD" "$WORKDIR" >&2
					return 1
				}
				_prev="$WORKDIR"
				WORKDIR="$_new"
				;;
		esac
	done <"$_CMD_FILE"

	return 0
}

RUN_COMMANDS() {
	_PHASE="$1"
	_JSON="$2"

	printf "\nRunning '%s' commands\n" "$_PHASE"

	_CMD_FILE="$RUN_TMPDIR/.commands.${_PHASE}.${NAME}.$$"
	: >"$_CMD_FILE" || return 1

	if ! printf '%s\n' "$_JSON" | jq -r '.[]' >"$_CMD_FILE" 2>/dev/null; then
		printf "Failed to parse '%s' commands JSON\n" "$_PHASE" >&2
		return 1
	fi

	# Echo what will run
	while IFS= read -r _CMD; do
		[ -n "$_CMD" ] || continue
		printf 'Running: %s\n' "$_CMD"
	done <"$_CMD_FILE"

	# Run in WORKDIR so relative paths behave
	(
		set -e
		cd "$WORKDIR"
		. "$_CMD_FILE"
	)
	_rc=$?

	# If it succeeded, apply any cd effects to WORKDIR for subsequent phases
	if [ "$_rc" -eq 0 ]; then
		APPLY_CD_EFFECTS "$_CMD_FILE" || return 1
	fi

	return $_rc
}

RUN_COMMANDS_LOGGED() {
	_PHASE="$1"
	_JSON="$2"
	_LOG="$3"

	printf "\nRunning '%s' commands\n" "$_PHASE"

	_CMD_FILE="$RUN_TMPDIR/.commands.${_PHASE}.${NAME}.$$"
	: >"$_CMD_FILE" || return 1

	if ! printf '%s\n' "$_JSON" | jq -r '.[]' >"$_CMD_FILE" 2>/dev/null; then
		printf "Failed to parse '%s' commands JSON\n" "$_PHASE" >&2
		return 1
	fi

	# Echo what will run (to terminal, not log)
	while IFS= read -r _CMD; do
		[ -n "$_CMD" ] || continue
		printf 'Running: %s\n' "$_CMD"
	done <"$_CMD_FILE"

	SPINNER_START "$_PHASE: $NAME"

	# Changed: run as a child so CLEANUP can kill it
	(
		set -e
		cd "$WORKDIR"
		. "$_CMD_FILE"
	) >>"$_LOG" 2>&1 &
	_cmdpid=$!
	ADD_CHILD_PID "$_cmdpid"
	wait "$_cmdpid"
	_rc=$?
	REMOVE_CHILD_PID "$_cmdpid"

	SPINNER_STOP

	# Persist cd for later phases
	if [ "$_rc" -eq 0 ]; then
		if ! APPLY_CD_EFFECTS "$_CMD_FILE"; then
			return 1
		fi
	fi

	return $_rc
}

APPLY_PATCHES() {
	NAME="$1"
	CORE_DIR="$2"

	if [ -d "$PATCH_DIR/$NAME" ]; then
		printf "Applying patches from '%s' to '%s'\n" "$PATCH_DIR/$NAME" "$CORE_DIR"
		for PATCH in "$PATCH_DIR/$NAME"/*.patch; do
			[ -e "$PATCH" ] || continue
			printf "Applying patch: %s\n" "$PATCH"
			# Preserve CRLF context for upstream files which intentionally retain
			# DOS line endings. GNU patch otherwise strips the patch CR characters
			# and every contextual hunk is rejected against the untouched source.
			patch --binary -d "$CORE_DIR" -p1 <"$PATCH" || {
				printf "Failed to apply patch: %s\n" "$PATCH" >&2
				return 1
			}
		done
		printf "\n"
	fi
}

DECIDE_ZIP_NAME() {
	_outputs=$1
	_name=$2

	_so=$(printf "%s\n" $_outputs | grep '\.so$' | head -n1)
	if [ -n "$_so" ]; then
		printf "%s.zip" "$(basename "$_so")"
		return 0
	fi

	# shellcheck disable=SC2086
	set -- $_outputs
	if [ "$#" -eq 1 ]; then
		printf "%s.zip" "$(basename "$1")"
	else
		printf "%s.zip" "$_name"
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
CACHE_FILE="$BASE_DIR/data/cache/$TARGET_ARCH.json"
mkdir -p "$(dirname "$CACHE_FILE")"
if [ "$TARGET_ARCH" = aarch64 ] && [ ! -f "$CACHE_FILE" ] && [ -f "$BASE_DIR/data/cache.json" ]; then
	cp "$BASE_DIR/data/cache.json" "$CACHE_FILE"
fi
if [ ! -f "$CACHE_FILE" ]; then
	echo "{}" > "$CACHE_FILE"
fi

MANIFEST_FILE="$BASE_DIR/data/manifest/$TARGET_ARCH.json"
mkdir -p "$(dirname "$MANIFEST_FILE")"
if [ ! -f "$MANIFEST_FILE" ]; then
	echo "{}" > "$MANIFEST_FILE"
fi

for NAME in $CORES; do
	printf "\n-------------------------------------------------------------------------\n"

	MODULE=$(jq -c --arg name "$NAME" '.[$name]' "$CORE_CONFIG")

	if [ -z "$MODULE" ] || [ "$MODULE" = "null" ]; then
		printf "Core '%s' not found in '%s'\n" "$NAME" "$CORE_CONFIG" >&2
		MARK_FAIL "$NAME" "config" "core not found in core.json"
		continue
	fi

	if ! echo "$MODULE" | jq -e --arg architecture "$TARGET_ARCH" \
		'(.architectures // []) as $architectures | ($architectures | length) == 0 or ($architectures | index($architecture) != null)' \
		>/dev/null; then
		SUPPORTED_ARCHITECTURES=$(echo "$MODULE" | jq -r '.architectures | join(", ")')
		printf "Skipping %s: supports %s, not %s\n" "$NAME" "$SUPPORTED_ARCHITECTURES" "$TARGET_ARCH"
		continue
	fi

	# Required keys
	DIR=$(echo "$MODULE" | jq -r '.directory')
	OUTPUT_LIST=$(echo "$MODULE" | jq -r '.output | if type=="string" then . else join(" ") end')
	SOURCE=$(echo "$MODULE" | jq -r '.source')
	SYMBOLS=$(echo "$MODULE" | jq -r '.symbols')

	# Optional submodule allowlist. Some repositories carry submodules the libretro
	# target never compiles, and a few of those point at hosts that no longer serve
	# them. Naming the ones a core actually needs keeps a dead dependency from
	# blocking a core that builds perfectly well without it. Omit it to take all.
	SUBMODULE_LIST=$(echo "$MODULE" | jq -r '.submodules // empty | if type=="string" then . else join(" ") end')
	SUBMODULES_DEFINED=$(echo "$MODULE" | jq -r 'has("submodules")')

	# Make skip: allow skipping the main 'make' phase entirely.
	MAKE_SKIP=$(echo "$MODULE" | jq -r '.make.skip // 0' 2>/dev/null)
	case "$MAKE_SKIP" in
		1) MAKE_SKIP=1 ;;
		*) MAKE_SKIP=0 ;;
	esac

	# Make keys (make.file is only required when make.skip=0)
	MAKE_FILE=$(echo "$MODULE" | jq -r '.make.file // ""')

	# Accept .make.args as either:
	# - array: ["A=B","C=D"]
	# - string: "A=B C=D"
	# - null/missing: empty
	MAKE_ARGS_TYPE=""
	MAKE_ARGS_STR=""
	MAKE_ARGS_FILE=""

	if [ "$MAKE_SKIP" -eq 0 ]; then
		MAKE_ARGS_TYPE=$(echo "$MODULE" | jq -r '(.make.args // empty) | type' 2>/dev/null || echo "")
	fi

	if [ "$MAKE_SKIP" -eq 0 ] && [ "$MAKE_ARGS_TYPE" = "array" ]; then
		MAKE_ARGS_FILE="$RUN_TMPDIR/.make_args.${NAME}.$$"
		: >"$MAKE_ARGS_FILE"
		echo "$MODULE" | jq -r '.make.args[]' >"$MAKE_ARGS_FILE" 2>/dev/null || :
		MAKE_ARGS_STR=$(tr '\n' ' ' <"$MAKE_ARGS_FILE" | sed 's/[[:space:]][[:space:]]*/ /g; s/[[:space:]]*$//')
	elif [ "$MAKE_SKIP" -eq 0 ] && [ "$MAKE_ARGS_TYPE" = "string" ]; then
		MAKE_ARGS_STR=$(echo "$MODULE" | jq -r '.make.args' 2>/dev/null)
	else
		MAKE_ARGS_STR=""
	fi

	MAKE_TARGET=""
	if [ "$MAKE_SKIP" -eq 0 ]; then
		MAKE_TARGET=$(echo "$MODULE" | jq -r '.make.target')
	fi

	# Verify required keys (make.file is only required when make.skip=0)
	if [ -z "$DIR" ] || [ -z "$OUTPUT_LIST" ] || [ -z "$SOURCE" ] || [ -z "$SYMBOLS" ]; then
		printf "Missing required configuration keys for '%s' in '%s'\n" "$NAME" "$CORE_CONFIG" >&2
		MARK_FAIL "$NAME" "config" "missing required keys: directory/output/source/symbols"
		continue
	fi

	if [ "$MAKE_SKIP" -eq 0 ] && [ -z "$MAKE_FILE" ]; then
		printf "Missing required configuration key for '%s': make.file (and make.skip is not set)\n" "$NAME" >&2
		MARK_FAIL "$NAME" "config" "missing required key: make.file (set make.skip=1 to disable)"
		continue
	fi

	BRANCH=$(echo "$MODULE" | jq -r '.branch // ""')
	PRE_MAKE=$(echo "$MODULE" | jq -c '.commands["pre-make"] // []')
	POST_MAKE=$(echo "$MODULE" | jq -c '.commands["post-make"] // []')
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
		MARK_FAIL "$NAME" "git" "failed to resolve remote hash"
		continue
	fi

	printf "Remote hash: %s\n" "$REMOTE_HASH"
	printf "Cached hash: %s\n" "$CACHED_HASH"
	[ -n "$CACHED_DIR" ] && printf "Cached dir:  %s\n" "$CACHED_DIR"
	[ "$CORE_PURGE_FLAG" -eq 1 ] && printf "purge: enabled for this core\n"

	ZIP_NAME=$(DECIDE_ZIP_NAME "$OUTPUT_LIST" "$NAME")

	# If directory changed since last time, remove the stale one
	if [ -n "$CACHED_DIR" ] && [ "$CACHED_DIR" != "$DIR" ]; then
		SAFE_RM_DIR "$BUILD_DIR/$CACHED_DIR"
	fi

	# If PURGE is set, delete the repo folder now
	if [ "$PURGE" -eq 1 ] || [ "$CORE_PURGE_FLAG" -eq 1 ]; then
		printf "Purging core repo directory: %s\n" "$CORE_DIR"
		rm -rf "$CORE_DIR"
	fi

	# Skip when up to date
	if [ "$FORCE" -eq 0 ] && [ "$PURGE" -eq 0 ] && [ "$CORE_PURGE_FLAG" -eq 0 ] && \
	   [ "$CACHED_HASH" = "$REMOTE_HASH" ] && [ -f "$RETRO_DIR/$ZIP_NAME" ]; then
		printf "Core '%s' is up to date (hash: %s). Skipping build.\n" "$NAME" "$REMOTE_HASH"
		jq --arg name "$NAME" --arg hash "$REMOTE_HASH" --arg dir "$DIR" \
		   '(.[$name] = {"hash":$hash,"dir":$dir})' "$CACHE_FILE" >"$CACHE_FILE.tmp" && mv "$CACHE_FILE.tmp" "$CACHE_FILE"
		continue
	fi

	# Populate submodules, honouring the optional allowlist from core.json.
	INIT_SUBMODULES() {
		[ "$SUBMODULES_DEFINED" = "true" ] && [ -z "$SUBMODULE_LIST" ] && return 0
		if [ -n "$SUBMODULE_LIST" ]; then
			# shellcheck disable=SC2086
			git submodule update --init --recursive "$@" $SUBMODULE_LIST
		else
			git submodule update --init --recursive "$@"
		fi
	}

	BEEN_CLONED=0
	if [ ! -d "$CORE_DIR" ]; then
		printf "Core '%s' not found\n\n" "$DIR"
		# Clone
		if [ "$LATEST" -eq 1 ]; then
			GC_CMD="git clone --progress --quiet --recurse-submodules -j$MAKE_CORES $SOURCE $CORE_DIR"
		elif [ -n "$BRANCH" ] && echo "$BRANCH" | grep -qE '^[0-9a-f]{7,40}$'; then
			# Deliberately no --recurse-submodules when pinning a commit. Cloning would
			# lay the submodules out as the default branch wants them, and the checkout
			# below then fails whenever the pinned commit moved, renamed or vendored one
			# of them. The submodule update that follows the checkout populates them
			# against the pin instead, which is the layout we actually want.
			GC_CMD="git clone --progress --quiet $SOURCE $CORE_DIR"
		else
			GC_CMD="git clone --progress --quiet --recurse-submodules -j$MAKE_CORES"
			[ -n "$BRANCH" ] && GC_CMD="$GC_CMD -b $BRANCH"
			GC_CMD="$GC_CMD $SOURCE $CORE_DIR"
		fi
		eval "$GC_CMD" || { printf "Failed to clone %s\n" "$SOURCE" >&2; RECORD_FAILURE "$NAME" "git" "clone failed"; continue; }

		# Enter repo to init submodules and optional commit checkout
		cd "$CORE_DIR" || { printf "Failed to enter %s\n" "$CORE_DIR" >&2; RECORD_FAILURE "$NAME" "fs" "failed to enter core dir after clone"; continue; }

		if [ "$LATEST" -eq 0 ] && [ -n "$BRANCH" ] && echo "$BRANCH" | grep -qE '^[0-9a-f]{7,40}$'; then
			git fetch --all || { printf "Failed to fetch in %s\n" "$CORE_DIR" >&2; RECORD_FAILURE "$NAME" "git" "fetch failed"; continue; }
			git checkout --detach "$BRANCH" || { printf "Failed to checkout %s\n" "$BRANCH" >&2; RECORD_FAILURE "$NAME" "git" "checkout commit failed"; continue; }
		fi

		INIT_SUBMODULES || {
			printf "Failed to update submodules for %s\n" "$NAME" >&2
			RECORD_FAILURE "$NAME" "git" "submodule update failed after clone"
			continue
		}

		cd - >/dev/null 2>&1
		printf "\n"
		BEEN_CLONED=1
	fi

	# Enter repo for update and build
	cd "$CORE_DIR" || { printf "Failed to enter %s\n" "$CORE_DIR" >&2; RECORD_FAILURE "$NAME" "fs" "failed to enter core dir"; continue; }

	# Ensure submodules are present
	INIT_SUBMODULES || {
		printf "Failed to update submodules for %s\n" "$NAME" >&2
		RECORD_FAILURE "$NAME" "git" "submodule update failed"
		continue
	}

	if [ "$BEEN_CLONED" -eq 0 ] && [ "$FORCE" -eq 0 ]; then
		if [ "$LATEST" -eq 1 ]; then
			printf "Updating '%s' to remote HEAD (latest)\n" "$NAME"
			git fetch --quiet origin || { printf "  fetch failed for '%s'\n" "$NAME" >&2; RECORD_FAILURE "$NAME" "git" "fetch failed (latest)"; continue; }
			git reset --hard origin/HEAD || { printf "  reset failed for '%s'\n" "$NAME" >&2; RECORD_FAILURE "$NAME" "git" "reset --hard origin/HEAD failed (latest)"; continue; }
			git submodule sync --quiet
			INIT_SUBMODULES --quiet || { printf "  submodule update failed for '%s'\n" "$NAME" >&2; RECORD_FAILURE "$NAME" "git" "submodule update failed (latest)"; continue; }
		elif [ -n "$BRANCH" ] && echo "$BRANCH" | grep -qE '^[0-9a-f]{7,40}$'; then
			printf "Repository already cloned. Fetching updates and checking out commit '%s'\n" "$BRANCH"
			git fetch --all || { printf "Failed to fetch updates for '%s'\n" "$NAME" >&2; RECORD_FAILURE "$NAME" "git" "fetch failed"; continue; }
			git checkout --detach "$BRANCH" || { printf "Failed to checkout commit '%s' for '%s'\n" "$BRANCH" "$NAME" >&2; RECORD_FAILURE "$NAME" "git" "checkout commit failed"; continue; }
		else
			printf "Updating '%s' to remote HEAD\n" "$NAME"
			git fetch --quiet origin || { printf "  fetch failed for '%s'\n" "$NAME" >&2; RECORD_FAILURE "$NAME" "git" "fetch failed"; continue; }
			git reset --hard origin/HEAD || { printf "  reset failed for '%s'\n" "$NAME" >&2; RECORD_FAILURE "$NAME" "git" "reset --hard origin/HEAD failed"; continue; }
			git submodule sync --quiet
			INIT_SUBMODULES --quiet || { printf "  submodule update failed for '%s'\n" "$NAME" >&2; RECORD_FAILURE "$NAME" "git" "submodule update failed"; continue; }
		fi
	fi

	# Verify local hash matches remote hash after clone or update
	LOCAL_HASH=$(git rev-parse --short HEAD | cut -c 1-7)
	if [ "$LOCAL_HASH" != "$REMOTE_HASH" ]; then
		printf "Warning: Local hash (%s) doesn't match remote hash (%s)\n" "$LOCAL_HASH" "$REMOTE_HASH" >&2
		RECORD_FAILURE "$NAME" "git" "local hash does not match expected remote hash"
		continue
	fi

	# Core worktrees are reusable caches, but generated build trees and patches
	# are target-specific. Refuse cleanup unless Git resolves this exact clone;
	# some recipes change the shell directory during setup.
	CORE_REAL=$(readlink -f "$CORE_DIR")
	CORE_TOP=$(git -C "$CORE_DIR" rev-parse --show-toplevel 2>/dev/null || true)
	CORE_TOP_REAL=""
	[ -n "$CORE_TOP" ] && CORE_TOP_REAL=$(readlink -f "$CORE_TOP")
	if [ -z "$CORE_REAL" ] || [ "$CORE_TOP_REAL" != "$CORE_REAL" ] || [ "$CORE_REAL" = "$BASE_DIR" ]; then
		printf "Refusing to clean invalid core worktree for %s: %s\n" "$NAME" "$CORE_TOP_REAL" >&2
		MARK_FAIL "$NAME" "clean" "core worktree root validation failed"
		RETURN_TO_BASE
		continue
	fi

	git -C "$CORE_DIR" reset --hard HEAD >/dev/null 2>&1 || {
		printf "Failed to reset build worktree for %s\n" "$NAME" >&2
		MARK_FAIL "$NAME" "clean" "failed to reset build worktree"
		RETURN_TO_BASE
		continue
	}
	git -C "$CORE_DIR" clean -fdx >/dev/null 2>&1 || {
		printf "Failed to clean build worktree for %s\n" "$NAME" >&2
		MARK_FAIL "$NAME" "clean" "failed to clean build worktree"
		RETURN_TO_BASE
		continue
	}
	if [ "$SUBMODULES_DEFINED" != "true" ] || [ -n "$SUBMODULE_LIST" ]; then
		git -C "$CORE_DIR" submodule foreach --quiet --recursive \
			'git reset --hard HEAD >/dev/null 2>&1 && git clean -fdx >/dev/null 2>&1' || {
			printf "Failed to clean submodules for %s\n" "$NAME" >&2
			MARK_FAIL "$NAME" "clean" "failed to clean submodules"
			RETURN_TO_BASE
			continue
		}
	fi
	cd "$CORE_DIR" || {
		printf "Failed to re-enter clean worktree for %s\n" "$NAME" >&2
		MARK_FAIL "$NAME" "clean" "failed to re-enter clean worktree"
		RETURN_TO_BASE
		continue
	}

	# A failed patch must leave the outer core loop before packaging.
	if ! APPLY_PATCHES "$NAME" "$CORE_DIR"; then
		printf "Failed to apply patches for %s\n" "$NAME" >&2
		MARK_FAIL "$NAME" "patch" "failed to apply patches"
		RETURN_TO_BASE
		continue
	fi

	START_WALL="$(NOW)"
	LOGFILE="$(dirname "$0")/build.log"

	# Per-core working directory starts at repo root, then pre-make can cd into subdirs (and we persist it).
	WORKDIR="$CORE_DIR"

	# Pre-make: logged + spinner, so it won't spew to terminal
	if [ "$PRE_MAKE" != "[]" ]; then
		if ! RUN_COMMANDS_LOGGED "pre-make" "$PRE_MAKE" "$LOGFILE"; then
			printf "Pre-make commands failed for %s (see build.log)\n" "$NAME" >&2
			RECORD_FAILURE "$NAME" "pre-make" "pre-make commands failed (see build.log)"
			continue
		fi
	fi

	# Make sure we are in the persisted WORKDIR for main make
	cd "$WORKDIR" || { printf "Failed to enter WORKDIR %s\n" "$WORKDIR" >&2; RECORD_FAILURE "$NAME" "fs" "failed to enter WORKDIR"; continue; }

	printf "Make Structure:"
	if [ "$MAKE_SKIP" -eq 1 ]; then
		printf "\n\tSKIP:\t1\n"
		printf "\tNOTE:\tSkipping main make step for '%s'\n" "$NAME"
		printf "SKIP: make phase disabled by make.skip=1 for %s\n" "$NAME" >>"$LOGFILE"
	else
		printf "\n\tFILE:\t%s" "$MAKE_FILE"
		printf "\n\tARCH:\t%s" "$TARGET_ARCH"
		printf "\n\tARGS:\t%s" "$MAKE_ARGS_STR"
		printf "\n\tTARGET: %s\n" "$MAKE_TARGET"
	fi

	START_TS=$(date +%s)
	BUILD_LABEL="Building $NAME started @ $START_WALL"

	if [ "$MAKE_SKIP" -eq 0 ]; then
		# Build make argv safely (no eval)
		set -- make -j"$MAKE_CORES" -f "$MAKE_FILE" \
			"CC=$TARGET_CC" "CXX=$TARGET_CXX" "AR=$TARGET_AR" "RANLIB=$TARGET_RANLIB" "STRIP=$STRIP"

		TRANSFORM_MAKE_ARG() {
			_a=$1

			case $_a in
				OVERRIDE_CC=*)
					printf '%s\n' "OVERRIDE_CC=$TARGET_CC $MAKE_ARCH"
					return 0
					;;
				OVERRIDE_CXX=*)
					printf '%s\n' "OVERRIDE_CXX=$TARGET_CXX $MAKE_ARCH"
					return 0
					;;
				OVERRIDE_LD=*)
					printf '%s\n' "OVERRIDE_LD=$TARGET_CXX $MAKE_ARCH"
					return 0
					;;
				CC=*) printf '%s\n' "CC=$TARGET_CC $MAKE_ARCH"; return 0 ;;
				CXX=*) printf '%s\n' "CXX=$TARGET_CXX $MAKE_ARCH"; return 0 ;;
				LD=*) printf '%s\n' "LD=$TARGET_CXX $MAKE_ARCH"; return 0 ;;
				AR=*) printf '%s\n' "AR=$TARGET_AR"; return 0 ;;
				RANLIB=*) printf '%s\n' "RANLIB=$TARGET_RANLIB"; return 0 ;;
				STRIP=*) printf '%s\n' "STRIP=$STRIP"; return 0 ;;
				WITH_DYNAREC=*) printf '%s\n' "WITH_DYNAREC=$TARGET_DYNAREC"; return 0 ;;
				LCPU=*) printf '%s\n' "LCPU=$TARGET_LCPU"; return 0 ;;
				HAVE_NEON=*)
					case "$TARGET_ARCH" in
						aarch64 | armhf) printf '%s\n' 'HAVE_NEON=1' ;;
						*) printf '%s\n' 'HAVE_NEON=0' ;;
					esac
					return 0
					;;
				HAVE_LTCG=*)
					case "$TARGET_ARCH" in
						aarch64 | armhf) printf '%s\n' 'HAVE_LTCG=1' ;;
						*) printf '%s\n' 'HAVE_LTCG=0' ;;
					esac
					return 0
					;;
				platform=aarch64* | platform=arm64*)
					printf '%s\n' "platform=$TARGET_PLATFORM"
					return 0
					;;
				platform=rpi* | platform=classic_arm*)
					case "$TARGET_ARCH" in
						x86_64 | x86 | riscv64) printf '%s\n' "platform=$TARGET_PLATFORM" ;;
						*) printf '%s\n' "$_a" ;;
					esac
					return 0
					;;
			esac

			printf '%s\n' "$_a"
		}

		# Append args from JSON
		if [ "$MAKE_ARGS_TYPE" = "array" ] && [ -n "$MAKE_ARGS_FILE" ] && [ -s "$MAKE_ARGS_FILE" ]; then
			while IFS= read -r _a; do
				[ -n "$_a" ] || continue
				_t=$(TRANSFORM_MAKE_ARG "$_a")
				[ -n "$_t" ] && set -- "$@" "$_t"
			done <"$MAKE_ARGS_FILE"
		elif [ -n "$MAKE_ARGS_STR" ]; then
			# shellcheck disable=SC2086
			for _a in $MAKE_ARGS_STR; do
				_t=$(TRANSFORM_MAKE_ARG "$_a")
				[ -n "$_t" ] && set -- "$@" "$_t"
			done
		fi

		# Add explicit make target if present
		if [ -n "$MAKE_TARGET" ] && [ "$MAKE_TARGET" != "null" ]; then
			set -- "$@" "$MAKE_TARGET"
		fi

		# Debug: log actual argv we will run
		printf "EXEC:" >>"$LOGFILE"
		for __x in "$@"; do
			printf " [%s]" "$__x" >>"$LOGFILE"
		done
		printf "\n" >>"$LOGFILE"

		# Run make with spinner; log all output
		if RUN_WITH_SPINNER_LOG "$BUILD_LABEL" "$LOGFILE" "$@"; then
			END_WALL="$(NOW)"
			printf "\nBuild succeeded: %s at %s\n" "$NAME" "$END_WALL"
		else
			FAIL_WALL="$(NOW)"
			printf "\nBuild FAILED: %s at %s - see %s\n" "$NAME" "$FAIL_WALL" "$LOGFILE" >&2
			printf '\a' 2>/dev/null || :

			MARK_FAIL "$NAME" "make" "make failed (see build.log)"
			RETURN_TO_BASE
			continue
		fi
	fi

	END_TS=$(date +%s)
	printf "Duration for '%s': %ds\n" "$NAME" "$((END_TS - START_TS))" >>"$LOGFILE"

	# Post-make: do NOT redirect, do NOT spinner (per your request)
	# Runs in WORKDIR and persists any cd changes as well.
	if [ "$POST_MAKE" != "[]" ]; then
		if ! RUN_COMMANDS "post-make" "$POST_MAKE"; then
			printf "Post-make commands failed for '%s'\n" "$NAME" >&2
			RECORD_FAILURE "$NAME" "post-make" "post-make commands failed"
			continue
		fi
	fi

	# Ensure we are in the final WORKDIR for output checks and packaging
	cd "$WORKDIR" || { printf "Failed to enter WORKDIR %s\n" "$WORKDIR" >&2; RECORD_FAILURE "$NAME" "fs" "failed to enter WORKDIR before packaging"; continue; }

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
		MARK_FAIL "$NAME" "outputs" "missing expected build outputs"
		RETURN_TO_BASE
		continue
	fi

	# Refuse to package anything that is not for the target. A core whose Makefile
	# ignores the cross compiler, or that is handed CC= on the make command line,
	# builds cleanly for the build host and would otherwise be zipped and indexed as
	# if it were fine. readelf is used rather than file(1) because a toolchain that
	# ships its own file(1) without a magic database makes that test pass silently.
	# The verdict is collected first and acted on below. Packaging has to be
	# skipped for real, or a good archive can be replaced by the wrong target.
	ARCH_FAIL=""
	for OUTFILE in $OUTPUTS; do
		[ -f "$OUTFILE" ] || continue
		OUT_MACHINE=$(readelf -h "$OUTFILE" 2>/dev/null | sed -n 's/^[[:space:]]*Machine:[[:space:]]*//p')
		if [ -z "$OUT_MACHINE" ]; then
			ARCH_FAIL="$(basename "$OUTFILE") is not a readable ELF object"
		elif [ "$OUT_MACHINE" != "$TARGET_MACHINE" ]; then
			ARCH_FAIL="$(basename "$OUTFILE") built for $OUT_MACHINE, not $TARGET_MACHINE"
		fi
	done

	if [ -n "$ARCH_FAIL" ]; then
		printf "\nRefusing to package '%s': %s\n" "$NAME" "$ARCH_FAIL" >&2
		MARK_FAIL "$NAME" "outputs" "$ARCH_FAIL"
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
	MOVE_FAILED=0
	for OUTFILE in $OUTPUTS; do
		mv "$OUTFILE" "$RETRO_DIR" || {
			printf "Failed to move '%s' for '%s' to '%s'\n" "$OUTFILE" "$NAME" "$RETRO_DIR" >&2
			MOVE_FAILED=1
			break
		}
	done
	if [ "$MOVE_FAILED" -ne 0 ]; then
		RECORD_FAILURE "$NAME" "packaging" "failed to move output(s) to core/"
		continue
	fi

	printf "\nIndexing and compressing outputs for '%s'\n" "$NAME"

	cd "$RETRO_DIR" || { printf "Failed to enter directory %s\n" "$RETRO_DIR" >&2; RECORD_FAILURE "$NAME" "packaging" "failed to enter core/"; continue; }

	[ -f "$ZIP_NAME" ] && rm -f "$ZIP_NAME"

	# Zip moved files by basename
	BASENAMES=""
	for OUTFILE in $OUTPUTS; do
		BASENAMES="$BASENAMES $(basename "$OUTFILE")"
	done
	# shellcheck disable=SC2086
	zip -q "$ZIP_NAME" $BASENAMES || { RECORD_FAILURE "$NAME" "packaging" "zip failed"; continue; }

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

	# Cache update only after outputs validated, moved, zipped, and indexed successfully
	jq --arg name "$NAME" --arg hash "$REMOTE_HASH" --arg dir "$DIR" \
	   '(.[$name] = {"hash":$hash,"dir":$dir})' "$CACHE_FILE" >"$CACHE_FILE.tmp" && mv "$CACHE_FILE.tmp" "$CACHE_FILE"

	# The manifest is the same record as the cache, except it is committed and shipped.
	# Without it the upstream commit a core was built from never leaves this machine, so
	# nothing downstream can tell an installed core from a newer one. Keyed by archive
	# name because that is what a release asset and an installed core have in common.
	MANIFEST_SHA=$(sha256sum "$ZIP_NAME" | cut -d' ' -f1)
	MANIFEST_SIZE=$(wc -c <"$ZIP_NAME" | tr -d ' ')

	jq --arg zip "$ZIP_NAME" --arg name "$NAME" --arg commit "$REMOTE_HASH" --arg architecture "$TARGET_ARCH" \
	   --slurpfile aarch64 "$BASE_DIR/data/manifest/aarch64.json" \
	   --arg source "$SOURCE" --arg sha "$MANIFEST_SHA" --arg size "$MANIFEST_SIZE" \
	   --arg built "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
	   '(.[$zip] = ((.[$zip] // $aarch64[0][$zip] // {}) +
	                {"core":$name,"commit":$commit,"source":$source,"sha256":$sha,
	                 "size":($size|tonumber),"built":$built,"architecture":$architecture}))' \
	   "$MANIFEST_FILE" >"$MANIFEST_FILE.tmp" && mv "$MANIFEST_FILE.tmp" "$MANIFEST_FILE"

	# After packaging: purge repo if requested, otherwise try cleaning build artifacts
	if [ "$PURGE" -eq 1 ] || [ "$CORE_PURGE_FLAG" -eq 1 ]; then
		printf "\nPurging core repo directory: %s\n" "$CORE_DIR"
		rm -rf -- "$CORE_DIR"
	else
		printf "\nCleaning build environment for '%s'\n" "$NAME"
		if [ "$MAKE_SKIP" -eq 1 ]; then
			printf "Skipping clean: make.skip=1 for '%s'\n" "$NAME"
		else
			(
				cd "$CORE_DIR" 2>/dev/null || exit 0

				# Prefer cleaning using the same makefile we built with
				make -j"$MAKE_CORES" -f "$MAKE_FILE" clean >/dev/null 2>&1 && exit 0

				# Fallback: common clean target
				make clean -j"$MAKE_CORES" >/dev/null 2>&1 && exit 0

				exit 0
			) || :
		fi
	fi

	RETURN_TO_BASE
done

(
	printf "<!DOCTYPE html>\n<html>\n<head>\n<title>MURCB - muOS RetroArch Core Builder</title>\n</head>\n<body>\n"
	printf "<pre style='font-size:2rem;margin-top:-5px;margin-bottom:-15px;'>MURCB - muOS RetroArch Core Builder</pre>\n"
	printf "<pre style='font-size:1rem;'>Currently only <span style='font-weight:800'>"
	printf "%s" "$TARGET_ARCH"
	printf "</span> builds for now!</pre>\n"
	printf "<hr>\n<pre>\n"
	[ -f "$RETRO_DIR/.index-extended" ] && cat "$RETRO_DIR/.index-extended" || printf "No cores available!\n"
	printf "</pre>\n</body>\n</html>\n"
) >"$RETRO_DIR/index.html"

# Write failure summary (if any failures were recorded)
FAIL_COUNT=$(awk 'NR>1{c++} END{print c+0}' "$FAIL_LOG" 2>/dev/null || echo 0)
FAIL_STAMP=$(date +"%Y-%m-%d_%H-%M-%S")
FAIL_SUMMARY="$BUILD_DIR/failed-cores-${TARGET_ARCH}-$FAIL_STAMP.tsv"
FAIL_LATEST="$BUILD_DIR/failed-cores-${TARGET_ARCH}-latest.tsv"

if [ "$FAIL_COUNT" -gt 0 ]; then
	cp "$FAIL_LOG" "$FAIL_SUMMARY" 2>/dev/null || :
	cp "$FAIL_LOG" "$FAIL_LATEST" 2>/dev/null || :
	printf "\n-------------------------------------------------------------------------\n"
	printf "Some cores failed (%s). Summary:\n" "$FAIL_COUNT" >&2
	printf "  %s\n" "$FAIL_LATEST" >&2
	printf "  %s\n" "$FAIL_SUMMARY" >&2
else
	# keep latest file in sync too (header only)
	cp "$FAIL_LOG" "$FAIL_LATEST" 2>/dev/null || :
fi

printf "\n-------------------------------------------------------------------------\n"
printf "All successful core builds are in '%s'\n\n" "$RETRO_DIR"
