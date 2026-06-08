# engine/banked_code/cpc-banked/

CPC-6128-banked counterpart of `engine/banked_code/128/`.

This directory holds the engine sources that compile into the cpc-banked
**banked-code** binary (resident in RAM 4, mapped into the `0x4000` swap window
on demand — see `doc/multiplatform-plan/banking.md` §6 and
`doc/multiplatform-plan/management/cpc-banked-bringup.md` DC3-A).

Per DC3-A (measure-and-iterate) the ZX128 `lowmem`/`banked` split is mirrored
here as the starting point: build, measure page-A usage, then offload more
`lowmem -> banked/codeset` sources if the resident page-A budget is exceeded.

Status: created in Stage B6 step 7 as structural scaffolding. The make
variables `BANKED_CODE_*_CPC_BANKED` (in `Makefile.common`) already discover any
sources placed here. The actual banked-code compilation/link target and the
first real banked sources land in Stage B7 (real bank binaries + asmloader).
