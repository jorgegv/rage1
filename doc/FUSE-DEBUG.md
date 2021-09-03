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
