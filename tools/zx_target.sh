#!/bin/bash
################################################################################
##
## RAGE1 - Retro Adventure Game Engine, release 1
## (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
## 
## This code is published under a GNU GPL license version 3 or later.  See
## LICENSE file in the distribution for details.
## 
################################################################################

DEFAULT_ZX_TARGET=48

V=$(grep -P '^\s+ZX_TARGET' build/game_data/game_config/*.gdata 2>/dev/null|head -1|awk '{print $2}')

echo ${V:-$DEFAULT_ZX_TARGET}
