package RAGE::Datagen::Sprites;

################################################################################
##
## RAGE1 - Retro Adventure Game Engine, release 1
## (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
##
## This code is published under a GNU GPL license version 3 or later.  See
## LICENSE file in the distribution for details.
##
################################################################################
##
## RAGE::Datagen::Sprites — sprite validation/compilation and C emission for
## datagen (Task 6, Stage 2 extraction).  Moved verbatim from tools/datagen.pl;
## the shared globals live in the RAGE::Datagen::Context object ($ctx), threaded
## in as the first positional arg of each sub and reached as $ctx->{all_sprites},
## $ctx->{dataset_dependency}, $ctx->{c_dataset_lines} (the per-dataset C emit
## accumulator); the sibling helpers are imported (pixels_to_byte from Util,
## get_gfx_backend from BuildFeatures), and asset_backend() — which stays in
## datagen.pl because it is shared with the BTile emitter — is called as
## main::asset_backend( $ctx ).  Behaviour (and emitted bytes) is unchanged.
##
################################################################################

use strict;
use warnings;
use utf8;

use RAGE::Datagen::Util qw( pixels_to_byte );
use RAGE::Datagen::BuildFeatures qw( get_gfx_backend );

use Exporter 'import';
our @EXPORT_OK = qw( validate_and_compile_sprite generate_sprites );

sub validate_and_compile_sprite {
    my $ctx = shift;
    my $sprite = shift;
    defined( $sprite->{'name'} ) or
        die "Sprite has no NAME\n";
    defined( $sprite->{'rows'} ) or
        die "Sprite '$sprite->{name}' has no ROWS\n";
    defined( $sprite->{'cols'} ) or
        die "Sprite '$sprite->{name}' has no COLS\n";

    defined( $sprite->{'pixels'} ) or
        die "Sprite '$sprite->{name}' has no PIXELS\n";
#    defined( $sprite->{'attr'} ) or
#        die "Sprite '$sprite->{name}' has no ATTR\n";
    defined( $sprite->{'frames'} ) or
        die "Sprite '$sprite->{name}' has no FRAMES\n";
    defined( $sprite->{'mask'} ) or
        die "Sprite '$sprite->{name}' has no MASK\n";
    my $num_attrs = $sprite->{'rows'} * $sprite->{'cols'};
#    ( scalar( @{$sprite->{'attr'}} ) == $num_attrs ) or
#        die "Sprite should have $num_attrs ATTR elements\n";
    ( scalar( @{$sprite->{'pixels'}} ) == $sprite->{'rows'} * 8 * $sprite->{'frames'} ) or
        die "Sprite should have ".( $sprite->{'rows'} * 8 * $sprite->{'frames'} )." PIXELS elements\n";
    ( scalar( @{$sprite->{'mask'}} ) == $sprite->{'rows'} * 8 * $sprite->{'frames'} ) or
        die "Sprite should have ".( $sprite->{'rows'} * 8 * $sprite->{'frames'} )." MASK elements\n";
    foreach my $p ( @{$sprite->{'pixels'}} ) {
        ( length( $p ) == $sprite->{'cols'} * 2 * 8 ) or
            die "Sprite '$sprite->{name}': PIXELS line should be of length ".( $sprite->{'rows'} * 2 * 8 );
    }
    foreach my $p ( @{$sprite->{'mask'}} ) {
        ( length( $p ) == $sprite->{'cols'} * 2 * 8 ) or
            die "Sprite '$sprite->{name}': MASK line should be of length ".( $sprite->{'rows'} * 2 * 8 );
    }

    # compile PIXELS string data to numeric data for output
    my $cur_row = 0;
    my $byte_count = 0;
    foreach my $p ( @{$sprite->{'pixels'}} ) {
        my @parts = unpack("(A16)*", $p );
        my $cur_col = 0;
        foreach my $b ( @parts ) {
            push @{$sprite->{'pixel_bytes'}[ $cur_row * $sprite->{'cols'} + $cur_col++ ] },
                pixels_to_byte( $b );
            if ( not ( ++$byte_count % ( 8 * $sprite->{'cols'} ) ) ) { $cur_row++; }
        }
    }

    # compile MASK string data to numeric data for output
    $cur_row = 0;
    $byte_count = 0;
    foreach my $p ( @{$sprite->{'mask'}} ) {
        my @parts = unpack("(A16)*", $p );
        my $cur_col = 0;
        foreach my $b ( @parts ) {
            push @{$sprite->{'mask_bytes'}[ $cur_row * $sprite->{'cols'} + $cur_col++ ] },
                pixels_to_byte( $b );
            if ( not ( ++$byte_count % ( 8 * $sprite->{'cols'} ) ) ) { $cur_row++; }
        }
    }

    # Always define the sequence 'Main', with all frames in order, first to last
    my $index = ( defined( $sprite->{'sequences'} ) ? scalar( @{ $sprite->{'sequences'} } ) : 0 );
    push @{ $sprite->{'sequences'} },
        { 'name' => 'Main', 'frames' => join( ',', 0 .. ( $sprite->{'frames'} - 1 ) ) };
    if ( scalar( grep { $_->{'name'} eq 'Main' } @{ $sprite->{'sequences'} } ) != 1 ) {
        die "Sprite '$sprite->{name}': SEQUENCE name 'Main' is reserved and should not be used\n";
    }
    $sprite->{'sequence_name_to_index'}{'Main'} = $index;

    # if the sprite has no 'sequence_delay' parameter, define as 1 (minimum;
    # 0 means 256, which is 5 seconds!)
    if ( not defined( $sprite->{'sequence_delay'} ) ) {
        $sprite->{'sequence_delay'} = 1;
    }

    # compile animation sequences
    foreach my $seq ( @{ $sprite->{'sequences'} } ) {
        $seq->{'frame_list'} = [ split( /,/, $seq->{'frames'} ) ];
    }
}

# SP1 pixel format for a masked sprite:
#  * Column oriented
#  * Each column:
#    * 8 x (0xff,0x00) pairs (blank first row)
#    * 8 x (mask,byte) pairs x M chars of the column
#    * 8 x (0xff,0x00) pairs (blank last row)
#  * Repeat for N columns
sub generate_sprite {
    my ( $ctx, $sprite, $dataset ) = @_;
    my $sprite_rows = $sprite->{'rows'};
    my $sprite_cols = $sprite->{'cols'};
    my $sprite_frames = $sprite->{'frames'};
    my $sprite_name = $sprite->{'name'};

    my $using_jsp = ( get_gfx_backend( $ctx ) eq 'jsp' );

    push @{ $ctx->{c_dataset_lines}->{ $dataset } }, sprintf( "// Sprite '%s'\n// Pixel and mask data ordered by column (%s format)\n\n",
        $sprite->{'name'}, $using_jsp ? 'JSP' : 'SP1' );

    # Task 5: the platform asset backend owns the sprite frame byte layout.
    # ZX (SP1/JSP): column-major, leading/trailing blank rows, mask,pixel
    # interleaved, stride 16*(rows+1)*cols from offset 16 — byte-identical to the
    # historical output.  CPC mode 1: JSP-CPC packed bytes (RAGE::CPCGfx).
    my ( $data_bytes, $frame_offsets ) = main::asset_backend( $ctx )->sprite_frame_data( $sprite );

    # group data bytes by 16-byte lines for easier reading
    my @groups_of_2m;
    my $group_cnt = 0;
    my $byte_cnt = 0;
    foreach my $b ( @$data_bytes ) {
        push @{$groups_of_2m[ $group_cnt ]}, $b;
        $byte_cnt++;
        if ( not $byte_cnt % 16 ) {
            $group_cnt++;
        }
    }

    # output mask/pixel lines
    push @{ $ctx->{c_dataset_lines}->{ $dataset } }, sprintf( "uint8_t sprite_%s_data[] = {\n%s\n};\n",
        $sprite->{'name'},
        join( ",\n", map { join( ", ", map { sprintf( "0x%02x", $_ ) } @{$_} ) } @groups_of_2m ) );

    # output list of pointers to frames (offsets owned by the backend)
    push @{ $ctx->{c_dataset_lines}->{ $dataset } }, sprintf( "uint8_t *sprite_%s_frames[] = {\n%s\n};\n",
        $sprite_name,
        join( ",\n",
            map { sprintf( "\t&sprite_%s_data[%d]", $sprite_name, $_ ) }
            @$frame_offsets
        ) );

    # output list of animation sequences
    if ( scalar( @{ $sprite->{'sequences'} } ) ) {
        push @{ $ctx->{c_dataset_lines}->{ $dataset } }, join( "", map {
            sprintf( "uint8_t sprite_%s_sequence_%s[%d] = { %s };\n",
                $sprite_name, $_->{'name'}, scalar( @{ $_->{'frame_list'} } ), join( ',', @{ $_->{'frame_list'} } ) );
        } @{ $sprite->{'sequences'} } );
        push @{ $ctx->{c_dataset_lines}->{ $dataset } }, sprintf( "struct animation_sequence_s sprite_%s_sequences[%d] = {\n\t",
            $sprite_name, scalar( @{ $sprite->{'sequences'} } ) );
        push @{ $ctx->{c_dataset_lines}->{ $dataset } }, join( ",\n\t", map {
            sprintf( "{ %d, &sprite_%s_sequence_%s[0] }", scalar( @{ $_->{'frame_list'} } ), $sprite_name, $_->{'name'} );
        } @{ $sprite->{'sequences'} } );
        push @{ $ctx->{c_dataset_lines}->{ $dataset } }, "\n};\n\n";

    }

    push @{ $ctx->{c_dataset_lines}->{ $dataset } }, sprintf( "// End of Sprite '%s'\n\n", $sprite_name );
}

sub generate_sprites {
    my $ctx = shift;
    my $dataset = shift;

    # generate the list of dataset sprites, return immediately if empty
    my @dataset_sprites = map { $ctx->{all_sprites}[ $_ ] } @{ $ctx->{dataset_dependency}{ $dataset }{'sprites'} };
    return if not scalar( @dataset_sprites );

    push @{ $ctx->{c_dataset_lines}->{ $dataset } }, <<EOF_SPRITES

////////////////////////////
// Sprite definitions
////////////////////////////

EOF_SPRITES
;

    # generate the sprites
    foreach my $sprite ( @dataset_sprites ) { generate_sprite( $ctx, $sprite, $dataset ); }

    # output global sprite graphics table
    my $num_sprites = scalar( @dataset_sprites );
    push @{ $ctx->{c_dataset_lines}->{ $dataset } }, "// Dataset sprite graphics table\n";
    push @{ $ctx->{c_dataset_lines}->{ $dataset } }, "struct sprite_graphic_data_s all_sprite_graphics[ $num_sprites ] = {\n\t";
    push @{ $ctx->{c_dataset_lines}->{ $dataset } }, join( ",\n\n\t", map {
        my $sprite = $_;
        sprintf( "{ .width = %d, .height = %d,\n\t.frame_data.num_frames = %d,\n\t.frame_data.frames = &sprite_%s_frames[0],\n\t.sequence_data.num_sequences = %d,\n\t.sequence_data.sequences = %s }",
            $_->{'cols'} * 8, $_->{'rows'} * 8,
            $_->{'frames'}, $_->{'name'},
            scalar( @{ $sprite->{'sequences'} } ),	# number of animation sequences
            ( scalar( @{ $sprite->{'sequences'} } ) ? sprintf( "&sprite_%s_sequences[0]", $_->{'name'}) : 'NULL' ) ),
    } @dataset_sprites );
    push @{ $ctx->{c_dataset_lines}->{ $dataset } }, "\n};\n\n";
}

1;
