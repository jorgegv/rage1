# CODESET TIPS

- For custom game functions which reside in low memory, just drop them in
  `game_src` directory, and define them in the GAME_CONFIG section.

- If you want to pur custom game functions in a CODESET, you must do the
  following:
  - Create a low memory stub that will just call the CODESET function. Drop
    this function in `game_src`
  - Create the codeset function and drop it into `game_src/codeset_0.src`
    directory
  - Define both functions in the GAME_CONFIG section. Don't forget to add
    the CODESET parameter and the PARAM signature for the CODESET function.
