# CPC emulator infrastructure smoke test (TS2-5)

Interim artefact.  Proves the headless Caprice32 screenshot chain works
end-to-end.  **Will be removed at TS3 phase exit** once the real CPC
regression test (`tests/00regression/minimal_cpc/`) lands.

## Contents

| File | Description |
|------|-------------|
| `smoke.sh` | Reproducible headless smoke-test script |
| `smoke.png` | Screenshot captured during TS2-5 verification |
| `README.md` | This file |

## What smoke.sh does

1. Starts a private Xvfb on `:99` (640×480×24).
2. Launches `cap32` (SDL x11 backend) with `tools/cpc-poc/poc.dsk`.
3. Sends autocmd: type `run"poc.` + Enter, wait (`CAP32_DELAY`), screenshot
   (`CAP32_SCRNSHOT`), exit (`CAP32_EXIT`).
4. Saves the screenshot as `actual.png` and exits 0.

## Invocation

```bash
# From the RAGE1 repo root:
bash tests/00regression/cpc-emulator-smoke/smoke.sh
# → tests/00regression/cpc-emulator-smoke/actual.png
```

Requires: `Xvfb`, `xdpyinfo`, `cap32` at `$CAP32DIR` (default
`~/src/cpc/caprice32`).  `actual.png` is gitignored.

## smoke.png

Captured on 2026-05-31 during TS2 verification on the development host.
Shows the `tools/cpc-poc/poc.dsk` output: RAGE1 CPC R3 PoC with
PNG-derived sprite data rendering in CPC Mode 1.
