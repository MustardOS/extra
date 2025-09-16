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

HOME="$(GET_VAR "device" "board/home")"
export HOME

SETUP_SDL_ENVIRONMENT

DRASTIC_BIN="drastic"
SET_VAR "system" "foreground_process" "$DRASTIC_BIN"

EMUDIR="/opt/muos/share/emulator/drastic-legacy"

chmod +x "$EMUDIR"/$DRASTIC_BIN
cd "$EMUDIR" || exit

/opt/muos/script/mux/track.sh "$NAME" "$CORE" "$FILE" start

GPTOKEYB "$DRASTIC_BIN"
HOME="$EMUDIR" SDL_ASSERT=always_ignore ./$DRASTIC_BIN "$FILE"

/opt/muos/script/mux/track.sh "$NAME" "$CORE" "$FILE" stop

unset SDL_HQ_SCALER SDL_ROTATION SDL_BLITTER_DISABLED
