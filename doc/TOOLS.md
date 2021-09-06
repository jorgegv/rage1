# RAGE1 Tools

The following tools can be found in the `tools` directory:

* `datagen.pl`: the main DATAGEN tool which makes most of the heavy work of
  transforming Game Data files (`.gdata`) into C and ASM code that can be
  compiled and run.  See [DATAGEN.md](DATAGEN.md) for a detailed usage
  guide.

* `inverse.pl`: inverts PIXELS and MASK data in a `.gdata` file: a set pixel
  is translated to a reset one and viceversa.

* `memmap.pl`: parses a `.map` file and outputs either a dump of the symbol
  table for the program (`-s` option), or an approximate memory map with
  section names, base addresses and sizes (`-m`).  The `-m` option is quite
  useful to get a top view of the current memory map for your program, and
  quickly spot when you are getting tight on memory usage.  When using the
  stock `Makefile` from RAGE1, you can just run `make mem` after a sucessful
  build to run the tool in `-m` mode.

* `r1banktool.pl`: this the main tool for generating the memory bank
  configuration from the compiled datasets: it lays out the datasets into
  different banks taking care of the bank size; it generates the bank
  configuration and the BASIC loader that loads each bank where it belongs;
  and also it writes a `dataset_map` structure which is included in the main
  program section, which allows to map the banked datasets into main memory
  for regular usage.

* `r1datalink`: a tool to relocate a `.bin` file compiled with a $0000 ORG
  to any base address, using the relocation data output by the compiler. 
  This tool is currently not used because it was made obsolete by the
  `__orgit` trick by Dom.

* `r1size.sh`: analyzes the generated code in all sections of all object
  files (`*.o`) after a build, and reports on code, data and bss usage per
  file.  Very useful to identify optimization opportunities regarding code
  or data reduction.

* `r1sym.pl`: parses a `.map` file getting compilation symbols and their
  addresses, and then filters its input replacing occurrences of
  `{<symbol_name>}` with the hex addresses of the given symbol.  Very useful
  for creating debug scripts with symbolic names instead of pure hex
  addresses (see [FUSE-DEBUG.d](FUSE-DEBUG.md) for example use).

* `tapdump.pl`: dumps the detailed structure of a TAP file.  Useful to make
  sure you get what you want when creating TAP files.

* `vmirror.pl`: makes a vertical mirror of PIXELS and MASK data in a
  `.gdata` file: left becomes right and right becomes left.
