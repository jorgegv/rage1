# minimal_cpc game_src

Intentionally empty of custom C/ASM: the G8 engine-driven minimal_cpc supplies
NO custom main() or game functions. The full RAGE1 engine (engine/src/main.c
plus the platform-neutral banked_code/common game-loop sources) provides the
entry point and game loop; this directory exists only so `make config`'s
`cp -r .../game_src/*` step has something to copy.

The R4 static-render demo (its own main_cpc.c + pre-baked sprite assets) was
retired when G8 replaced the static demo with the real engine loop.
