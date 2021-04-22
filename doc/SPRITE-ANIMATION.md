# SPRITE MOVEMENT AND ANIMATION

## Design

- There is a global sprite graphics table.  Each sprite graphic is
  referenced by its index into this table in order to access sprite graphics
  info (data: NUM_SPRITES, all_sprites[])

- Each sprite has a global table of frames.  Frames are stored in SP1 sprite
  column format, and include all frames for all animation sequences (data:
  uint8_t num_frames, uint8_t **frames)

- Each sprite has a table of animation sequences (data: uint8_t
  num_sequences, uint8_t *sequences)

- Each animation sequence is a table of ints, which represent the frame
  number (indexing into the sprite's global frame table) at each moment of
  the animation.  Only animation frames are stored here, not delays or
  anything time related.  This makes it easy to reuse animations with the
  same frame sequence at different speeds or with different delays (data:
  uint8_t num_frames, uint8_t *frame_number)

- Whenever a sprite is to be used (e.g. hero, enemies), a uint8_t identifier
  is used for the sprite graphics to use. Animation delays between frames
  and between animation cycles are specified here (not with the sprite
  graphics)
