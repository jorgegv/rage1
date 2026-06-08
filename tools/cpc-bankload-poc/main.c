// RAGE1 cpc-banked disk-loader PoC  (Stage B7 step 8a, risk R-DL1)
//
// Validates: can AMSDOS firmware file I/O transfer a file into the 0x4000
// paging window while an expansion RAM bank (Config 4-7) is mapped there?
// (doc/multiplatform-plan/cpc-banked-disk-loader.md §2/§6 R-DL1.)
//
// IMPORTANT — firmware calling convention (discovered via the PoC):
// a z88dk +cpc C program's CRT takes over the firmware's alternate register
// set + the 0x0038 ISR vector at startup (cpc_crt0.asm cpc_enable_process_exx_set),
// so a DIRECT `call 0xBC77` to a firmware routine crashes.  Firmware routines
// must be reached through z88dk's `firmware` interposer (call firmware / defw
// <addr>), which restores the firmware register environment around the call.
// (The real cpc-banked asmloader is pure ASM at cold boot, running in NATIVE
// firmware state before any CRT takeover, so it will not need the interposer.)
//
// Method (firmware reached via the interposer):
//   A. page RAM 5 into 0x4000, zero the first 256 bytes, restore Config 0.
//   B. CAS IN OPEN our own disc file "POC"; page RAM 5; CAS IN DIRECT the file
//      body into 0x4000 (-> RAM 5); restore Config 0; CAS IN CLOSE.
//   C. page RAM 5 back; scan 0x4000..0x7FFF for an 8-byte signature embedded in
//      this program (hence in the file body).  Found => firmware wrote RAM 5.
//
// Result via direct screen writes (firmware TXT text is invisible after RUN):
//   PASS -> solid bright screen (0xFF) ; FAIL -> blank (0x00).

int main(void) {
    __asm
        EXTERN firmware

        ;; --- step A: zero RAM 5 [0x4000..0x40FF] ---
        ld   a,0xC5            ;; 0xC0 (GA RAMR cmd) | config 5 -> RAM 5 @ 0x4000
        ld   bc,0x7F00
        out  (c),a
        ld   hl,0x4000
        ld   de,0x4001
        ld   bc,0x00FF
        ld   (hl),0x00
        ldir
        ld   a,0xC0            ;; config 0 (base map)
        ld   bc,0x7F00
        out  (c),a

        ;; --- step B: CAS IN OPEN "POC" (via the firmware interposer) ---
        ld   b,3
        ld   hl,poc_fname
        ld   de,0x8000         ;; 2K firmware input buffer (page C, stays mapped)
        call firmware
        defw 0xBC77            ;; cas_in_open
        jp   nc,poc_fail

        ld   a,0xC5            ;; page RAM 5 into 0x4000
        ld   bc,0x7F00
        out  (c),a
        ld   hl,0x4000
        call firmware
        defw 0xBC83            ;; cas_in_direct -> file body into 0x4000 (RAM 5)
        push af
        ld   a,0xC0            ;; restore config 0
        ld   bc,0x7F00
        out  (c),a
        call firmware
        defw 0xBC7A            ;; cas_in_close
        pop  af
        jp   nc,poc_fail

        ;; --- step C: scan RAM 5 [0x4000..0x7FFF] for the signature ---
        ld   a,0xC5
        ld   bc,0x7F00
        out  (c),a
        ld   hl,0x4000
poc_scan:
        push hl
        ld   de,poc_sig
        ld   b,8
poc_cmp:
        ld   a,(de)
        cp   (hl)
        jr   nz,poc_cmp_no
        inc  hl
        inc  de
        djnz poc_cmp
        pop  hl
        ld   a,0xC0
        ld   bc,0x7F00
        out  (c),a
        jp   poc_pass
poc_cmp_no:
        pop  hl
        inc  hl
        ld   a,h
        cp   0x80
        jr   nz,poc_scan
        ld   a,0xC0
        ld   bc,0x7F00
        out  (c),a
        jp   poc_fail

        ;; --- visual result ---
poc_pass:
        ld   d,0xFF            ;; solid bright = PASS
        jr   poc_fill
poc_fail:
        ld   d,0x00            ;; blank = FAIL
poc_fill:
        ld   hl,0xC000
poc_fill_loop:
        ld   (hl),d
        inc  hl
        ld   a,h
        cp   0x00
        jr   nz,poc_fill_loop
        di
poc_hang:
        jr   poc_hang

poc_fname:
        defm "POC"
poc_sig:
        defb 0xDE,0xAD,0xBE,0xEF,0x12,0x34,0x56,0x78
    __endasm;
    return 0;
}
