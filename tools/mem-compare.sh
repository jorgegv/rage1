#!/bin/bash
#
# SP1 vs JSP memory-footprint comparison, 128K target.
#
# Builds games/default (SP1) and games/default_jsp (JSP) — the same 128K
# game bar the sprite engine — runs 'make mem' for each, prints both
# reports, then a per-section difference summary for banks 5,2,0.
#
# This is a comparison driver, not a per-spritelib memory script. The
# Makefile 'mem-compare' target invokes it.

ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
cd "$ROOT" || exit 1

# bring z88dk into PATH (harmless if already done)
[ -f env.sh ] && source env.sh >/dev/null 2>&1

GREEN='\e[42m\e[37;1m'
RESET='\e[0m'

TMP="$( mktemp -d )"
trap 'rm -rf "$TMP"' EXIT

strip_ansi() { sed -r 's/\x1b\[[0-9;]*m//g'; }

build_and_mem() {   # $1 = game dir, $2 = raw report file
    make clean >/dev/null 2>&1
    if ! make build target_game="$1" >/dev/null 2>&1; then
        echo "ERROR: build failed for $1" >&2
        exit 1
    fi
    make -s mem 2>/dev/null > "$2"
}

echo "Building games/default (SP1, 128K) ..."
build_and_mem games/default "$TMP/sp1.raw"
echo "Building games/default_jsp (JSP, 128K) ..."
build_and_mem games/default_jsp "$TMP/jsp.raw"

strip_ansi < "$TMP/sp1.raw" > "$TMP/sp1.txt"
strip_ansi < "$TMP/jsp.raw" > "$TMP/jsp.txt"

echo
echo "================= SP1 build — games/default ================="
cat "$TMP/sp1.raw"
echo "=============== JSP build — games/default_jsp ==============="
cat "$TMP/jsp.raw"

# --- per-section difference (banks 5,2,0) ---
# section size = last field of the section's row;
# headline figure (TOTAL/FREE) = second field of the row.
sect() { grep -m1 -E "^  $2 " "$1" | awk '{print $NF}'; }
hdln() { grep -m1 -E "^  $2 " "$1" | awk '{print $2}'; }

row() {   # $1 = label, $2 = sp1 value, $3 = jsp value
    local d="-"
    [ -n "$2" ] && [ -n "$3" ] && d=$(( $2 - $3 ))
    printf "  %-14s %9s %9s %11s\n" "$1" "${2:--}" "${3:--}" "$d"
}

# JSP's 'code' section address span contains the embedded intstk + jspdata
# reserved holes; subtract them so 'code' is real machine code, directly
# comparable to SP1's 'code'. With this the SP1-JSP column sums to the
# TOTAL delta.
JI=$( sect "$TMP/jsp.txt" intstk )
JD=$( sect "$TMP/jsp.txt" jspdata )
JC=$(( $( sect "$TMP/jsp.txt" code ) - JI - JD ))

echo
echo -e "${GREEN}   SP1 vs JSP MEMORY DIFFERENCE  (banks 5,2,0, 128K)   ${RESET}"
echo
printf "  %-14s %9s %9s %11s\n" SECTION SP1 JSP "SP1 - JSP"
for s in screen databuf heap startup data bss; do
    row "$s" "$( sect "$TMP/sp1.txt" "$s" )" "$( sect "$TMP/jsp.txt" "$s" )"
done
row code          "$( sect "$TMP/sp1.txt" code )"    "$JC"
row intstk        "$( sect "$TMP/sp1.txt" intstk )"  "$JI"
row "sprite data" "$( sect "$TMP/sp1.txt" sp1data )" "$JD"
echo "  --------------------------------------------------------"
TS=$( hdln "$TMP/sp1.txt" TOTAL ); TJ=$( hdln "$TMP/jsp.txt" TOTAL )
row TOTAL "$TS" "$TJ"
row FREE  "$( hdln "$TMP/sp1.txt" FREE )" "$( hdln "$TMP/jsp.txt" FREE )"
echo
echo "  ('code' is real machine code — JSP's figure excludes the embedded"
echo "  intstk + jspdata regions, shown as their own rows.)"
if [ -n "$TS" ] && [ -n "$TJ" ]; then
    echo
    echo -e "  ${GREEN} => JSP uses $(( TS - TJ )) bytes less than SP1 for the same game ${RESET}"
fi
echo
