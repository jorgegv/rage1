# Debugging with Fuse

You can include debugger commands for Fuse debug window in a file called
debug_script.cfg stored at the same directory as the project Makefile.  When
using the `make debug` target, FUSE will start with the debug window active
and the commands in the debug script added.

Comments can be introduced starting with a # and up to end of line. Blank
lines can also be inserted and will be ignored.

You can also use symbolic addresses (public symbols extracted from main.map file)
if you quote them between curly braces; they will be translated to the
corresponding addresses before passing them to the debugger. Like this:

Example `debug_script.cfg`:

```
# program start
br $8184

# bank switching routine
br 32769

# symbolic program start
br {_main}
br {_init_program}
```

The expressions in brackets may be just simple symbols, or may have the
syntax `{symbol+offset}` or `{symbol-offset}`. `offset` can be specified as
a decimal number, or in hex by prefixing it with `0x` or `$`. Examples:

```
br {_main+12}		# set breakpoint at _main+12 bytes
br {_main+0x0c}		# same
br {_main-$2f}		# set breakpoint at _main-0x2f bytes

```

This feature allows you to set break points in the middle of functions. 
Just open the `.c.lis` file which will be generated during compilation, and
there you will find the generated ASM annotated with your C source and the
byte offsets at the left.  You can use those offsets to calculate the offset
you want from the beginning of the function you want to set the breakpoint
into.
