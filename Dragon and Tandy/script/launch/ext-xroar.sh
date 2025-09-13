#!/bin/sh

. /opt/muos/script/var/func.sh

NAME=$1
CORE=$2
FILE=${3%/}

(
    LOG_INFO "$0" 0 "Content Launch" "DETAIL"
    LOG_INFO "$0" 0 "NAME" "$NAME"
    LOG_INFO "$0" 0 "CORE" "$CORE"
    LOG_INFO "$0" 0 "FILE" "$FILE"
) &

GPTOKEYB="/opt/muos/share/emulator/gptokeyb/gptokeyb2"
XROAR_DIR="/opt/muos/share/emulator/xroar"

# Get the games's basename without the path
GAME_BASENAME=$(basename "${FILE%.*}")

# Construct the gptkfile by appending .gptk
GPTK_FILE="${GAME_BASENAME}.gptk"

LD_LIBRARY_PATH="$XROAR_DIR/libs:$LD_LIBRARY_PATH"
export LD_LIBRARY_PATH

HOME="$(GET_VAR "device" "board/home")"
export HOME

SETUP_SDL_ENVIRONMENT

SET_VAR "system" "foreground_process" "xroar"

case "$CORE" in
    xroar | ext-xroar) CORE="coco2bus" ;;
esac

/opt/muos/script/mux/track.sh "$NAME" "$CORE" "$FILE" start

XR_GPTK="$XROAR_DIR/gptk"
GPTK_SP="${XR_GPTK}/${GPTK_FILE}"

[ ! -f "$GPTK_SP" ] && GPTK_SP="${XR_GPTK}/xroar.gptk"
$GPTOKEYB "xroar" -c "$GPTK_SP" &

$XROAR_DIR/xroar -c "$XROAR_DIR/xroar.conf" -default-machine "$CORE" "$FILE"

killall -q gptokeyb2

/opt/muos/script/mux/track.sh "$NAME" "$CORE" "$FILE" stop

unset SDL_HQ_SCALER SDL_ROTATION SDL_BLITTER_DISABLED
