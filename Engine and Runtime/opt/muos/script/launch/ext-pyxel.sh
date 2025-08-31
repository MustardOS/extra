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

SETUP_SDL_ENVIRONMENT

HOME="$(GET_VAR "device" "board/home")"
export HOME

if [ "$(GET_VAR "config" "boot/device_mode")" -eq 1 ]; then
	SDL_HQ_SCALER=2
	SDL_ROTATION=0
	SDL_BLITTER_DISABLED=1
else
	SDL_HQ_SCALER="$(GET_VAR "device" "sdl/scaler")"
	SDL_ROTATION="$(GET_VAR "device" "sdl/rotation")"
	SDL_BLITTER_DISABLED="$(GET_VAR "device" "sdl/blitter_disabled")"
fi

SDL_JOYSTICK_DEVICE="/dev/input/js0"

export SDL_HQ_SCALER SDL_ROTATION SDL_BLITTER_DISABLED SDL_JOYSTICK_DEVICE

# Check if "pyxel" is already installed
if ! /usr/bin/python3 -c "import pyxel" 2>/dev/null; then
	/opt/muos/extra/muxmessage 0 "$(printf "Installing Pyxel Libraries\n\nPlease wait...")"
	/usr/bin/python3 -m ensurepip --upgrade --user
	/usr/bin/python3 -m pip install -U pyxel pip --user
fi

/opt/muos/script/mux/track.sh "$NAME" "$CORE" "$FILE" start

python3 -m pyxel play "$FILE"

/opt/muos/script/mux/track.sh "$NAME" "$CORE" "$FILE" stop

unset SDL_HQ_SCALER SDL_ROTATION SDL_BLITTER_DISABLED

