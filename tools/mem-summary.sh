#!/bin/bash

GAME_MODE=$( grep BUILD_FEATURE_ZX_TARGET build/generated/features.h|awk '{print $2}'|sed 's/BUILD_FEATURE_ZX_TARGET_//g' )

if [ $GAME_MODE -eq 128 ]; then
	exec "$( dirname "$0")/mem-summary-128.sh"
fi

if [ $GAME_MODE -eq 48 ]; then
	exec "$( dirname "$0")/mem-summary-48.sh"
fi

