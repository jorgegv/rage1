# tests/datagen — datagen.pl behavioural regression tests

End-to-end tests that exercise individual `datagen.pl` mechanisms by
dropping transient fixture files into an existing test game, running
`make build-<game>`, and asserting properties of the generated headers
or final TAP.

Each test is self-contained: it creates its own fixtures, runs a real
build, asserts, then cleans up the fixtures on exit (including on
failure, via `trap cleanup EXIT`).

Tests:

- `test_patch_game_config.sh` — A2-5. Asserts that
  `PATCH_GAME_CONFIG` with a `BEGIN_CPC_COLOR_MAP`-only override
  builds cleanly, leaves non-patched shared fields verbatim
  (LIVES_AREA, etc.), and parses the CPC block without error
  (dropped on ZX as expected; consumed by CPC builds in Phase A5+).
  See `doc/multiplatform-plan/README.md` §5.11 and
  `doc/multiplatform-plan/assets.md` §1.4 / Phase A2.

Run a single test:

    bash tests/datagen/test_patch_game_config.sh

The 00regression suite (`tests/00regression/`) covers visual /
screenshot-level regressions. This directory covers datagen-internal
behaviour that doesn't show up at the screenshot level.
