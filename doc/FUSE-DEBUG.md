# Debugging with Fuse

You can include debugger commands for Fuse debug window in a file called
debug_script.cfg stored at the same directory as the project Makefile.  When
using the `make debug` target, FUSE will start with the debug window active
and the commands in the debug script added.

The file can also contain lines starting with #, which will be interpreted
as comments.

Example `debug_script.cfg`:

```
# program start
br $8184
# bank switching routine
br 32769
```
