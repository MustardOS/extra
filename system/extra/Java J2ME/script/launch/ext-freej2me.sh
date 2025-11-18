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

FREEJ2ME_DIR="$MUOS_SHARE_DIR/emulator/freej2me"

SETUP_SDL_ENVIRONMENT

HOME="$FREEJ2ME_DIR"
export HOME

XDG_CONFIG_HOME="$HOME/.config"
export XDG_CONFIG_HOME

cd "$FREEJ2ME_DIR" || exit

SET_VAR "system" "foreground_process" "java"

case "$CORE" in
    *128)
        WIDTH=128
        HEIGHT=128
        ;;
    *176)
        WIDTH=176
        HEIGHT=208
        ;;
    *240)
        WIDTH=240
        HEIGHT=320
        ;;
    *320)
        WIDTH=320
        HEIGHT=240
        ;;
    *640)
        WIDTH=640
        HEIGHT=360
        ;;
    *) exit 0 ;;
esac

TIMIDITY_CFG="./timidity/timidity.cfg" JAVA_TOOL_OPTIONS="-Djava.util.prefs.systemRoot=./java/system -Djava.util.prefs.userRoot=./java/user -Djava.awt.headless=true -Dsun.jnu.encoding=UTF-8 -Dfile.encoding=UTF-8 -Djava.library.path=/opt/zulu/lib" /opt/zulu/bin/java -jar ./freej2me-sdl.jar "$FILE" "$WIDTH" "$HEIGHT" 100

