# Z88DK Docker image with RAGE1 tools

Files in this directory are used for generating and publishing a specialized
Docker image which contains the current Z88DK version and additional tools
needed for compiling games using RAGE1.

Usage:

Move to the directory above your game (where RAGE1 and your game repo exist)
and run:

```
docker run -v ${PWD}:/src/ -it zxjogv/rage1-z88dk /bin/bash
```

From this point you are inside the container and you'll see your game
and the RAGE1 directories. You can now move into RAGE1 directory and issue a
`make build target_game=../your_game` to build your game as usual.
