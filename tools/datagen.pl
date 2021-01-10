#!/usr/bin/perl

################################################################################
##
## RAGE1 - Retro Adventure Game Engine, release 1
## (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
## 
## This code is published under a GNU GPL license version 3 or later.  See
## LICENSE file in the distribution for details.
## 
################################################################################

use warnings;
use strict;
use utf8;

use Data::Dumper;
use List::MoreUtils qw( zip );
use Getopt::Std;

# global program state
# if you add any global variable here, don't forget to add a reference to it
# also in $all_state variable in dump_internal_state function at the end of
# the script
my @btiles;
my @screens;
my %screen_name_to_index = ( '__NO_SCREEN__', 0 );
my @sprites;
my %sprite_name_to_index;
my $hero;
my $all_items;
my $game_config;

my $c_file = 'game_data.c';
my $h_file = 'game_data.h';
my $output_fh;

# dump file for internal state
my $dump_file = 'internal_state.dmp';

##########################################
## Input data parsing and state machine
##########################################

sub read_input_data {
    # possible states: NONE, BTILE, SCREEN, SPRITE, HERO, GAME_CONFIG
    # initial state
    my $state = 'NONE';
    my $cur_btile = undef;
    my $cur_screen = undef;
    my $cur_sprite = undef;

    # read and process input
    my $num_line = 0;
    while (my $line = <>) {

        $num_line++;

        # cleanup the line
        chomp $line;
        $line =~ s/^\s*//g;		# remove leading blanks
        $line =~ s/\s*$//g;		# remove trailing blanks
        $line =~ s/\/\/.*$//g;		# remove comments (//...)
        next if $line eq '';		# ignore blank lines

        # process the line
        if ( $state eq 'NONE' ) {
            if ( $line =~ /^BEGIN_BTILE$/ ) {
                $state = 'BTILE';
                $cur_btile = undef;
                next;
            }
            if ( $line =~ /^BEGIN_SCREEN$/ ) {
                $state = 'SCREEN';
                $cur_screen = { btiles => [ ], items => [ ], hotzones => [ ], sprites => [ ] };
                next;
            }
            if ( $line =~ /^BEGIN_SPRITE$/ ) {
                $state = 'SPRITE';
                $cur_sprite = undef;
                next;
            }
            if ( $line =~ /^BEGIN_HERO$/ ) {
                if ( defined( $hero ) ) {
                    die "A HERO is already defined, there can be only one\n";
                }
                $state = 'HERO';
                $cur_sprite = undef;
                next;
            }
            if ( $line =~ /^BEGIN_GAME_CONFIG$/ ) {
                if ( defined( $game_config ) ) {
                    die "A GAME_CONFIG is already defined, there can be only one\n";
                }
                $state = 'GAME_CONFIG';
                next;
            }
            die "Syntax error:line $num_line: '$line' not recognized (global section)\n";

        } elsif ( $state eq 'BTILE' ) {

            if ( $line =~ /^NAME\s+(\w+)$/ ) {
                $cur_btile->{'name'} = $1;
                next;
            }
            if ( $line =~ /^ROWS\s+(\d+)$/ ) {
                $cur_btile->{'rows'} = $1;
                next;
            }
            if ( $line =~ /^COLS\s+(\d+)$/ ) {
                $cur_btile->{'cols'} = $1;
                next;
            }
            if ( $line =~ /^PIXELS\s+([\.#]+)$/ ) {
                push @{$cur_btile->{'pixels'}}, $1;
                next;
            }
            if ( $line =~ /^ATTR\s+(.+)$/ ) {
                push @{$cur_btile->{'attr'}}, $1;
                next;
            }
            if ( $line =~ /^PNG_PIXELS\s+(.*)$/ ) {
                my $args = $1;
                my $vars = {
                    map { my ($k,$v) = split( /=/, $_ ); lc($k), $v }
                    split( /\s+/, $args )
                };
                my $fgcolor = sprintf '%3d %3d %3d', map { oct( '0x'.$_ ) } unpack('A2A2A2', $vars->{'fgcolor'} );
                push @{$cur_btile->{'pixels'}}, @{ pixels_data_from_png(
                    $vars->{'file'}, $vars->{'xpos'}, $vars->{'ypos'}, $vars->{'width'}, $vars->{'height'}, $fgcolor,
                    ) };
                next;
            }
            if ( $line =~ /^END_BTILE$/ ) {
                validate_and_compile_btile( $cur_btile );
                push @btiles, $cur_btile;
                $state = 'NONE';
                next;
            }
            die "Syntax error:line $num_line: '$line' not recognized (BTILE section)\n";

        } elsif ( $state eq 'SPRITE' ) {

            if ( $line =~ /^NAME\s+(\w+)$/ ) {
                $cur_sprite->{'name'} = $1;
                next;
            }
            if ( $line =~ /^ROWS\s+(\d+)$/ ) {
                $cur_sprite->{'rows'} = $1;
                next;
            }
            if ( $line =~ /^COLS\s+(\d+)$/ ) {
                $cur_sprite->{'cols'} = $1;
                next;
            }
            if ( $line =~ /^FRAMES\s+(\d+)$/ ) {
                $cur_sprite->{'frames'} = $1;
                next;
            }
            if ( $line =~ /^PIXELS\s+([\.#]+)$/ ) {
                push @{$cur_sprite->{'pixels'}}, $1;
                next;
            }
            if ( $line =~ /^MASK\s+(.+)$/ ) {
                push @{$cur_sprite->{'mask'}}, $1;
                next;
            }
            if ( $line =~ /^PNG_PIXELS\s+(.*)$/ ) {
                my $args = $1;
                my $vars = {
                    map { my ($k,$v) = split( /=/, $_ ); lc($k), $v }
                    split( /\s+/, $args )
                };
                my $fgcolor = sprintf '%3d %3d %3d', map { oct( '0x'.$_ ) } unpack('A2A2A2', $vars->{'fgcolor'} );
                push @{$cur_sprite->{'pixels'}}, @{ pixels_data_from_png(
                    $vars->{'file'}, $vars->{'xpos'}, $vars->{'ypos'}, $vars->{'width'}, $vars->{'height'}, $fgcolor,
                    ) };
                next;
            }
            if ( $line =~ /^PNG_MASK\s+(.*)$/ ) {
                my $args = $1;
                my $vars = {
                    map { my ($k,$v) = split( /=/, $_ ); lc($k), $v }
                    split( /\s+/, $args )
                };
                my $maskcolor = sprintf '%3d %3d %3d', map { oct( '0x'.$_ ) } unpack('A2A2A2', $vars->{'maskcolor'} );
                push @{$cur_sprite->{'mask'}}, @{ pixels_data_from_png(
                    $vars->{'file'}, $vars->{'xpos'}, $vars->{'ypos'}, $vars->{'width'}, $vars->{'height'}, $maskcolor,
                    ) };
                next;
            }
            if ( $line =~ /^ATTR\s+(.+)$/ ) {
                push @{$cur_sprite->{'attr'}}, $1;
                next;
            }
            if ( $line =~ /^END_SPRITE$/ ) {
                validate_and_compile_sprite( $cur_sprite );
                $sprite_name_to_index{ $cur_sprite->{'name'}} = scalar( @sprites );
                push @sprites, $cur_sprite;
                $state = 'NONE';
                next;
            }
            die "Syntax error:line $num_line: '$line' not recognized (SPRITE section)\n";

        } elsif ( $state eq 'SCREEN' ) {

            if ( $line =~ /^NAME\s+(\w+)$/ ) {
                $cur_screen->{'name'} = $1;
                next;
            }
            if ( $line =~ /^DECORATION\s+(\w.*)$/ ) {
                # ARG1=val1 ARG2=va2 ARG3=val3...
                my $args = "$1 TYPE=DECORATION";
                push @{ $cur_screen->{'btiles'} }, {
                    map { my ($k,$v) = split( /=/, $_ ); lc($k), $v }
                    split( /\s+/, $args )
                };
                next;
            }
            if ( $line =~ /^OBSTACLE\s+(\w.*)$/ ) {
                # ARG1=val1 ARG2=va2 ARG3=val3...
                my $args = "$1 TYPE=OBSTACLE";
                push @{ $cur_screen->{'btiles'} }, {
                    map { my ($k,$v) = split( /=/, $_ ); lc($k), $v }
                    split( /\s+/, $args )
                };
                next;
            }
            if ( $line =~ /^SPRITE\s+(\w.*)$/ ) {
                # ARG1=val1 ARG2=va2 ARG3=val3...
                my $args = $1;
                push @{ $cur_screen->{'sprites'} }, {
                    map { my ($k,$v) = split( /=/, $_ ); lc($k), $v }
                    split( /\s+/, $args )
                };
                next;
            }
            if ( $line =~ /^HERO\s+(\w.*)$/ ) {
                # ARG1=val1 ARG2=va2 ARG3=val3...
                my $args = $1;
                $cur_screen->{'hero'} = {
                    map { my ($k,$v) = split( /=/, $_ ); lc($k), $v }
                    split( /\s+/, $args )
                };
                next;
            }
            if ( $line =~ /^ITEM\s+(\w.*)$/ ) {
                # ARG1=val1 ARG2=va2 ARG3=val3...
                my $args = $1;
                my $item = {
                    map { my ($k,$v) = split( /=/, $_ ); lc($k), $v }
                    split( /\s+/, $args )
                };
                push @{ $cur_screen->{'items'} }, $item;
                $all_items->{ $item->{'item_index'} } = $item;
                next;
            }
            if ( $line =~ /^HOTZONE\s+(\w.*)$/ ) {
                # ARG1=val1 ARG2=va2 ARG3=val3...
                my $args = $1;
                my $item = {
                    map { my ($k,$v) = split( /=/, $_ ); lc($k), $v }
                    split( /\s+/, $args )
                };
                my $index = scalar( @{ $cur_screen->{'hotzones'} } );
                push @{ $cur_screen->{'hotzones'} }, $item;
                $cur_screen->{'hotzone_name_to_index'}{ $item->{'name'} } = $index;
                next;
            }
            if ( $line =~ /^END_SCREEN$/ ) {
                validate_and_compile_screen( $cur_screen );
                $screen_name_to_index{ $cur_screen->{'name'}} = scalar( @screens );
                push @screens, $cur_screen;
                $state = 'NONE';
                next;
            }
            die "Syntax error:line $num_line: '$line' not recognized (SCREEN section)\n";

        } elsif ( $state eq 'HERO' ) {

            if ( $line =~ /^NAME\s+(\w+)$/ ) {
                $hero->{'name'} = $1;
                next;
            }
            if ( $line =~ /^LIVES\s+(\w.*)$/ ) {
                # ARG1=val1 ARG2=va2 ARG3=val3...
                my $args = $1;
                $hero->{'lives'} = {
                    map { my ($k,$v) = split( /=/, $_ ); lc($k), $v }
                    split( /\s+/, $args )
                };
                next;
            }
            if ( $line =~ /^HSTEP\s+(\d+)$/ ) {
                $hero->{'hstep'} = $1;
                next;
            }
            if ( $line =~ /^VSTEP\s+(\d+)$/ ) {
                $hero->{'vstep'} = $1;
                next;
            }
            if ( $line =~ /^ANIMATION_DELAY\s+(\d+)$/ ) {
                $hero->{'animation_delay'} = $1;
                next;
            }
            if ( $line =~ /^SPRITE_UP\s+(\w+)$/ ) {
                $hero->{'sprite_up'} = $1;
                next;
            }
            if ( $line =~ /^SPRITE_DOWN\s+(\w+)$/ ) {
                $hero->{'sprite_down'} = $1;
                next;
            }
            if ( $line =~ /^SPRITE_LEFT\s+(\w+)$/ ) {
                $hero->{'sprite_left'} = $1;
                next;
            }
            if ( $line =~ /^SPRITE_RIGHT\s+(\w+)$/ ) {
                $hero->{'sprite_right'} = $1;
                next;
            }
            if ( $line =~ /^BULLET\s+(\w.*)$/ ) {
                # ARG1=val1 ARG2=va2 ARG3=val3...
                my $args = $1;
                $hero->{'bullet'} = {
                    map { my ($k,$v) = split( /=/, $_ ); lc($k), $v }
                    split( /\s+/, $args )
                };
                next;
            }
            if ( $line =~ /^END_HERO$/ ) {
                validate_and_compile_hero( $hero );
                $state = 'NONE';
                next;
            }
            die "Syntax error:line $num_line: '$line' not recognized (HERO section)\n";

        } elsif ( $state eq 'GAME_CONFIG' ) {

            if ( $line =~ /^NAME\s+(\w+)$/ ) {
                $game_config->{'name'} = $1;
                next;
            }
            if ( $line =~ /^DEFAULT_BG_ATTR\s+(.*)$/ ) {
                $game_config->{'default_bg_attr'} = $1;
                next;
            }
            if ( $line =~ /^HERO\s+(\w.*)$/ ) {
                # ARG1=val1 ARG2=va2 ARG3=val3...
                my $args = $1;
                $game_config->{'hero'} = {
                    map { my ($k,$v) = split( /=/, $_ ); lc($k), $v }
                    split( /\s+/, $args )
                };
                next;
            }
            if ( $line =~ /^SCREEN\s+(\w.*)$/ ) {
                # ARG1=val1 ARG2=va2 ARG3=val3...
                my $args = $1;
                $game_config->{'screen'} = {
                    map { my ($k,$v) = split( /=/, $_ ); lc($k), $v }
                    split( /\s+/, $args )
                };
                next;
            }
            if ( $line =~ /^GAME_FUNCTIONS\s+(\w.*)$/ ) {
                # ARG1=val1 ARG2=va2 ARG3=val3...
                my $args = $1;
                $game_config->{'game_functions'} = {
                    map { my ($k,$v) = split( /=/, $_ ); lc($k), $v }
                    split( /\s+/, $args )
                };
                next;
            }
            if ( $line =~ /^SOUND\s+(\w.*)$/ ) {
                # ARG1=val1 ARG2=va2 ARG3=val3...
                my $args = $1;
                my $vars = {
                    map { my ($k,$v) = split( /=/, $_ ); lc($k), $v }
                    split( /\s+/, $args )
                };
                foreach my $k ( keys %$vars ) {
                    $game_config->{'sounds'}{ $k } = $vars->{ $k };
                }
                next;
            }
            if ( $line =~ /^END_GAME_CONFIG$/ ) {
                $state = 'NONE';
                next;
            }
            die "Syntax error:line $num_line: '$line' not recognized (GAME_CONFIG section)\n";

        } else {
            die "Unknown state '$state'\n";
        }
    }
}

sub pixels_data_from_png {
    my ($file, $xpos, $ypos, $width, $height, $hexcolor) = @_;
    # pngtopam game_data/btiles/btile.png | \
    # pamcut -top 8 -left 8 -height 16 -width 24 | \
    # pamtable| sed 's/  0   0   0/##/g'|sed 's/255 255 255/../g'|tr -d '|'
    my $command = sprintf "pngtopam %s | pamcut -top %d -left %d -height %d -width %d | pamtable",
        $file, $ypos, $xpos, $height, $width;
    my @pixels = `$command`;
    chomp @pixels;
    foreach (@pixels) { s/\Q$hexcolor\E/##/g; }
    foreach (@pixels) { s/\s*\d+\s+\d+\s+\d+/../g; }
    foreach (@pixels) { s/\|//g; }
    return \@pixels;
}


######################################
## BTile functions
######################################

sub validate_and_compile_btile {
    my $tile = shift;
    defined( $tile->{'name'} ) or
        die "Btile has no NAME\n";
    defined( $tile->{'rows'} ) or
        die "Btile '$tile->{name}' has no ROWS\n";
    defined( $tile->{'cols'} ) or
        die "Btile '$tile->{name}' has no COLS\n";
    defined( $tile->{'pixels'} ) or
        die "Btile '$tile->{name}' has no PIXELS\n";
    defined( $tile->{'attr'} ) or
        die "Btile '$tile->{name}' has no ATTR\n";
    my $num_attrs = $tile->{'rows'} * $tile->{'cols'};
    ( scalar( @{$tile->{'attr'}} ) == $num_attrs ) or
        die "Btile should have $num_attrs ATTR elements\n";
    ( scalar( @{$tile->{'pixels'}} ) == $tile->{'rows'} * 8 ) or
        die "Btile should have ".( $tile->{'rows'} * 8 )." PIXELS elements\n";
    foreach my $p ( @{$tile->{'pixels'}} ) {
        ( length( $p ) == $tile->{'cols'} * 2 * 8 ) or
            die "Btile PIXELS line should be of length ".( $tile->{'rows'} * 2 * 8 );
    }

    # compile pixel string data to numeric data for output
    my $cur_row = 0;
    my $byte_count = 0;
    foreach my $p ( @{$tile->{'pixels'}} ) {
        my @parts = unpack("(A16)*", $p );
        my $cur_col = 0;
        foreach my $b ( @parts ) {
            push @{$tile->{'pixel_bytes'}[ $cur_row * $tile->{'cols'} + $cur_col++ ] },
                pixels_to_byte( $b );
            if ( not ( ++$byte_count % ( 8 * $tile->{'cols'} ) ) ) { $cur_row++; }
        }
    }
}

sub output_btile {
    my $tile = shift;
    my $cur_char = 0;
    my @char_names;
    printf $output_fh "// Big tile '%s'\n\n", $tile->{'name'};
    printf $output_fh "uint8_t btile_%s_tile_data[%d] = {\n%s\n};\n",
        $tile->{'name'},
        scalar( map { @$_ } @{ $tile->{'pixel_bytes'} } ),
        join( ", ",
            map { '0x'.sprintf('%02x',$_) }
            map { @$_ }
            @{ $tile->{'pixel_bytes'} }
        );
    printf $output_fh "uint8_t *btile_%s_tiles[%d] = { %s };\n",
        $tile->{'name'},
        scalar( map { @$_ } @{ $tile->{'pixel_bytes'} } ) / 8,
        join( ', ',
            map { sprintf "&btile_%s_tile_data[%d]", $tile->{'name'}, $_ }
            grep { ( $_ % 8 ) == 0 }
            ( 0 .. ( $tile->{'rows'} * $tile->{'cols'} * 8 - 1 ) )
        );
    printf $output_fh "uint8_t btile_%s_attrs[%d] = { %s };\n",
        $tile->{'name'},
        scalar( @{ $tile->{'attr'} } ),
        join( ', ', @{ $tile->{'attr'} } );
    printf $output_fh "struct btile_s btile_%s = { %d, %d, &btile_%s_tiles[0], &btile_%s_attrs[0] };\n",
        $tile->{'name'},
        $tile->{'rows'},
        $tile->{'cols'},
        $tile->{'name'},
        $tile->{'name'};
    printf $output_fh "\n// End of Big tile '%s'\n\n", $tile->{'name'};
}

#####################################
## Sprite functions
#####################################

sub validate_and_compile_sprite {
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
            die "Sprite PIXELS line should be of length ".( $sprite->{'rows'} * 2 * 8 );
    }
    foreach my $p ( @{$sprite->{'mask'}} ) {
        ( length( $p ) == $sprite->{'cols'} * 2 * 8 ) or
            die "Sprite MASK line should be of length ".( $sprite->{'rows'} * 2 * 8 );
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
}

# SP1 pixel format for a masked sprite:
#  * Column oriented
#  * Each column:
#    * 8 x (0xff,0x00) pairs (blank first row)
#    * 8 x (mask,byte) pairs x M chars of the column
#    * 8 x (0xff,0x00) pairs (blank last row)
#  * Repeat for N columns
sub output_sprite {
    my $sprite = shift;
    my $sprite_rows = $sprite->{'rows'};
    my $sprite_cols = $sprite->{'cols'};
    my $sprite_frames = $sprite->{'frames'};

    my $cur_char = 0;
    my @char_names;
    printf $output_fh "// Sprite '%s'\n// Pixel and mask data ordered by column (required by SP1)\n\n", $sprite->{'name'};

    # prepare mask and bytes lists
    my @col_bytes;
    my @mask_bytes;
    foreach my $frm ( 0 .. ( $sprite_frames - 1 ) ) {
        foreach my $col ( 0 .. ( $sprite_cols - 1 ) ) {
            push @col_bytes, (0) x 8;		# initial row with blank pixels and transparent mask
            push @mask_bytes, (0xff) x 8;
            foreach my $row ( 0 .. ( $sprite_rows - 1 ) ) {
                push @col_bytes, @{ $sprite->{'pixel_bytes'}[ ( $frm * $sprite_rows * $sprite_cols ) + $row * $sprite_cols + $col ] };
                push @mask_bytes,@{ $sprite->{'mask_bytes'}[ ( $frm * $sprite_rows * $sprite_cols ) + $row * $sprite_cols + $col ] };
            }
        }
    }
    push @col_bytes, (0) x 8;		# final row with blank pixels and transparent mask
    push @mask_bytes, (0xff) x 8;

    # group mask and pixel bytes by 16-byte lines for easier reading
    my @groups_of_2m;
    my $group_cnt = 0;
    my $byte_cnt = 0;
    foreach my $b ( zip( @mask_bytes, @col_bytes ) ) {
        push @{$groups_of_2m[ $group_cnt ]}, $b;
        $byte_cnt++;
        if ( not $byte_cnt % 16 ) {
            $group_cnt++;
        }
    }

    # output mask/pixel lines
    printf $output_fh "uint8_t sprite_%s_data[] = {\n%s\n};\n",
        $sprite->{'name'},
        join( ",\n", map { join( ", ", map { sprintf "0x%02x", $_ } @{$_} ) } @groups_of_2m );

    # output list of pointers to frames
    my @frame_offsets;
    my $ptr = 16;	# initial frame
    foreach ( 0 .. ( $sprite->{'frames'} - 1 ) ) {
        push @frame_offsets, $ptr;
        $ptr += 16 * ( $sprite->{'rows'} + 1 ) * $sprite->{'cols'};
    }
    printf $output_fh "uint8_t *sprite_%s_frames[] = {\n%s\n};\n",
        $sprite->{'name'},
#        $sprite->{'frames'},
        join( ",\n", 
            map { sprintf "\t&sprite_%s_data[%d]", $sprite->{'name'}, $_ }
            @frame_offsets
        );

    printf $output_fh "// End of Sprite '%s'\n\n", $sprite->{'name'};
}

######################################
## Map Screen functions
######################################

sub validate_and_compile_screen {
    my $screen = shift;
    defined( $screen->{'name'} ) or
        die "Screen has no NAME\n";
    ( scalar( @{$screen->{'btiles'}} ) > 0 ) or
        die "Screen '$screen->{name}' has no Btiles\n";
    defined( $screen->{'hero'} ) or
        die "Screen '$screen->{name}' has no Hero\n";

    # compile initial flags for each sprite
    foreach my $s ( @{$screen->{'sprites'}} ) {
        $s->{'initial_flags'} = join( " | ", 0,
            map { "F_SPRITE_" . uc($_) }
            grep { $s->{$_} }
            qw( bounce )
            );
    }

    # adjust hotzones
    foreach my $h ( @{ $screen->{'hotzones'} } ) {
        if ( $h->{'type'} eq 'END_OF_GAME' ) {
            $h->{'dest_screen'} = '__NO_SCREEN__';
            $h->{'dest_hero_x'} = 0;
            $h->{'dest_hero_y'} = 0;
        }
    }
}

sub output_screen_sprite_initialization_code {
    my ( $screen_num ) = @_;
    my $screen = $screens[ $screen_num ];
    my $sprites = $screen->{'sprites'};
    printf $output_fh "\t// Screen '%s' - Sprite initialization\n", $screen->{'name'};
    printf $output_fh "\tmap[%d].sprite_data.num_sprites = %d;\n\n", $screen_num, scalar( @$sprites );
    my $sprite_num = 0;
    foreach my $sprite ( map { $sprites[ $sprite_name_to_index{$_->{'name'}} ] } @$sprites ) {
        printf $output_fh "\t// Sprite '%s'\n", $sprite->{'name'};

        printf $output_fh "\tmap[%d].sprite_data.sprites[%d].sprite = s = sp1_CreateSpr(SP1_DRAW_MASK2LB, SP1_TYPE_2BYTE, %d, %d, %d );\n",
            $screen_num,
            $sprite_num,
            $sprite->{'rows'} + 1,	# height in chars including blank bottom row
            0,				# left column graphic offset
            0,				# plane
        ;
        foreach my $ac ( 1 .. ($sprite->{'cols'} - 1) ) {
            printf $output_fh "\tsp1_AddColSpr(s, SP1_DRAW_MASK2, %d, %d, %d );\n",
                0,					# type
                ( $sprite->{'rows'} + 1 ) * 16 * $ac,	# nth column graphic offset
                0,					# plane
            ;
        }
        printf $output_fh "\tsp1_AddColSpr(s, SP1_DRAW_MASK2RB, 0, 0, 0);\n";	# empty rightmost column
        printf $output_fh "\tSET_SPRITE_FLAG( map[%d].sprite_data.sprites[%d], F_SPRITE_ACTIVE );\n", $screen_num, $sprite_num;
        printf $output_fh "\t// End of Sprite '%s'\n\n", $sprite->{'name'};
        $sprite_num++;
    }
    printf $output_fh "\t// Screen '%s' - End of Sprite initialization\n\n", $screen->{'name'};
}

sub output_screen {
    my $screen = shift;

    # screen tiles
    if ( scalar( @{$screen->{'btiles'}} ) ) {
        printf $output_fh "// Screen '%s' btile data\n", $screen->{'name'};
        printf $output_fh "struct btile_pos_s screen_%s_btile_pos[ %d ] = {\n",
            $screen->{'name'},
            scalar( @{$screen->{'btiles'}});
        print $output_fh join( ",\n", map {
                sprintf("\t{ TT_%s, %d, %d, &btile_%s, %s }", uc($_->{'type'}), $_->{'row'}, $_->{'col'}, $_->{'name'}, 'F_BTILE_ACTIVE' )
            } @{$screen->{'btiles'}} );
        print $output_fh "\n};\n\n";
    }

    # screen sprites
    if ( scalar( @{$screen->{'sprites'}} ) ) {
        printf $output_fh "// Screen '%s' sprite data\n", $screen->{'name'};
        printf $output_fh "struct sprite_info_s screen_%s_sprites[ %d ] = {\n",
            $screen->{'name'},
            scalar( @{$screen->{'sprites'}});
        print $output_fh join( ",\n", map {
                sprintf("\t{ %s, %d, %d,{ %d, %s, %d, %d, %d }, { %d, %d }, { %s, %d, %d, .data.%s={ %d, %d, %d, %d, %d, %d, %d, %d, %d, %d } }, %s }",
                    # SP1 sprite pointer, will be initialized later
                    'NULL',

                    # sprite size: width, height
                    $sprites[ $sprite_name_to_index{ $_->{'name'} }]{'cols'} * 8,
                    $sprites[ $sprite_name_to_index{ $_->{'name'} }]{'rows'} * 8,

                    # animaton_data
                    $sprites[ $sprite_name_to_index{ $_->{'name'} }]{'frames'},
                    sprintf( "&sprite_%s_frames[0]", $_->{'name'} ),
                    $_->{'animation_delay'},
                    0,0,				# initial frame and delay counter

                    # position_data
                    0,0,				# position gets reset on initialization

                    # movement_data
                    sprintf( 'SPRITE_MOVE_%s', uc( $_->{'movement'} ) ),	# movement type
                    $_->{'speed_delay'},
                    0,				# initial delay counter
                    lc( $_->{'movement'} ),
                    $_->{'xmin'}, $_->{'xmax'},
                    $_->{'ymin'}, $_->{'ymax'},
                    $_->{'dx'}, $_->{'dy'},
                    $_->{'initx'}, $_->{'inity'},
                    $_->{'dx'}, $_->{'dy'},

                    # initial flags
                    $_->{'initial_flags'},
                 )
            } @{$screen->{'sprites'}} );
        print $output_fh "\n};\n\n";
    }

    # screen items
    if ( scalar( @{$screen->{'items'}} ) ) {
        printf $output_fh "// Screen '%s' item data\n", $screen->{'name'};
        printf $output_fh "struct item_location_s screen_%s_items[ %d ] = {\n",
            $screen->{'name'},
            scalar( @{$screen->{'items'}});
        print $output_fh join( ",\n", map {	# real item id is 0x1 << item_index
                sprintf( "\t{ %d, %d, %d }", $_->{'item_index'}, $_->{'row'}, $_->{'col'} )
            } @{$screen->{'items'}} );
        print $output_fh "\n};\n\n";
    }

    # hot zones
    if ( scalar( @{$screen->{'hotzones'}} ) ) {
        printf $output_fh "// Screen '%s' hot zone data\n", $screen->{'name'};
        printf $output_fh "struct hotzone_info_s screen_%s_hotzones[ %d ] = {\n",
            $screen->{'name'},
            scalar( @{$screen->{'hotzones'}});
        print $output_fh join( ",\n", map {
                sprintf( "\t{ HZ_TYPE_%s, %d, %d, %d, %d, %s, { %d, %d, %d } }", 
                    $_->{'type'},
                    $_->{'row'}, $_->{'col'},
                    $_->{'width'}, $_->{'height'},
                    ( $_->{'active'} ? 'F_HOTZONE_ACTIVE' : 0 ),
                    $screen_name_to_index{ $_->{'dest_screen'} },
                    $_->{'dest_hero_x'},$_->{'dest_hero_y'},
                )
            } @{ $screen->{'hotzones'} } );
        print $output_fh "\n};\n\n";
    }

}

###################################
## Hero functions
###################################

sub validate_and_compile_hero {
    my $hero = shift;
    defined( $hero->{'name'} ) or
        die "Hero has no NAME\n";
    defined( $hero->{'sprite_up'} ) or
        die "Hero has no SPRITE_UP\n";
    defined( $hero->{'sprite_down'} ) or
        die "Hero has no SPRITE_DOWN\n";
    defined( $hero->{'sprite_left'} ) or
        die "Hero has no SPRITE_LEFT\n";
    defined( $hero->{'sprite_right'} ) or
        die "Hero has no SPRITE_RIGHT\n";
    defined( $hero->{'animation_delay'} ) or
        die "Hero has no ANIMATION_DELAY\n";
    defined( $hero->{'lives'} ) or
        die "Hero has no LIVES\n";
    defined( $hero->{'hstep'} ) or
        die "Hero has no HSTEP\n";
    defined( $hero->{'vstep'} ) or
        die "Hero has no VSTEP\n";
    # all sprites must be the same size and have the same number of frames
    my $sprite_up = $sprites[ $sprite_name_to_index{ $hero->{'sprite_up'} } ];
    my $rows = $sprite_up->{'rows'};
    my $cols = $sprite_up->{'cols'};
    my $frames = $sprite_up->{'frames'};
    my @sprites = map {
        $sprites[ $sprite_name_to_index{ $hero->{ $_ } } ]
    } qw( sprite_up sprite_down sprite_left sprite_right);
    foreach my $s ( @sprites ) {
        ( $s->{'rows'}  == $rows ) or
            die "Hero sprites must all have the same number of ROWS\n";
        ( $s->{'cols'}  == $cols ) or
            die "Hero sprites must all have the same number of COLS\n";
        ( $s->{'frames'}  == $frames ) or
            die "Hero sprites must all have the same number of FRAMES\n";
    }
}

sub output_hero {
    my $num_lives 	= $hero->{'lives'}{'num_lives'};
    my $lives_tile	= $hero->{'lives'}{'btile'};
    my $num_frames	= $sprites[ $sprite_name_to_index{ $hero->{'sprite_up'} } ]{'frames'};
    my $width		= $sprites[ $sprite_name_to_index{ $hero->{'sprite_up'} } ]{'cols'} * 8;
    my $height		= $sprites[ $sprite_name_to_index{ $hero->{'sprite_up'} } ]{'rows'} * 8;
    my $sprite_up	= $hero->{'sprite_up'};
    my $sprite_down	= $hero->{'sprite_down'};
    my $sprite_left	= $hero->{'sprite_left'};
    my $sprite_right	= $hero->{'sprite_right'};
    my $delay		= $hero->{'animation_delay'};
    my $hstep		= $hero->{'hstep'};
    my $vstep		= $hero->{'vstep'};
    print $output_fh <<EOF_HERO1
/////////////////////////////
// Hero definition
/////////////////////////////

struct hero_info_s hero_startup_data = {
    NULL,		// sprite ptr - will be initialized at program startup
    $width, $height,	// width, height
    { 	$num_frames,
        &sprite_${sprite_up}_frames[0],
        &sprite_${sprite_down}_frames[0],
        &sprite_${sprite_left}_frames[0],
        &sprite_${sprite_right}_frames[0],
        $delay, 0, 0
        },	// animation
    { 0,0,0,0 },	// position - will be reset when entering a screen, including the first one
    { MOVE_NONE, $hstep, $vstep },	// movement
    0,		// flags
    $num_lives,	// lives
    &btile_${lives_tile}	// btile
};

EOF_HERO1
;
}

sub output_bullets {
    my $max_bullets = $hero->{'bullet'}{'max_bullets'};
    print $output_fh <<EOF_BULLET4
//////////////////////////////
// Bullets definition
//////////////////////////////

struct bullet_state_data_s bullet_state_data[ $max_bullets ] = {
EOF_BULLET4
;

    print $output_fh join( ",\n", ( "\t{ NULL, { 0, 0, 0, 0 }, 0, 0, 0, 0 }" ) x 4 );
    print $output_fh "\n};\n\n";
}

########################
## Item functions
########################

sub output_items {
    my $max_items = scalar( keys %$all_items );
    my $all_items_mask = 0;
    my $mask = 1;
    foreach my $i ( 1 .. $max_items ) {
        $all_items_mask += $mask;
        $mask <<= 1;
    }
    print $output_fh <<EOF_ITEMS1
///////////////////////
// Global items table
///////////////////////

uint8_t inventory_max_items = $max_items;
uint16_t inventory_all_items_mask = $all_items_mask;
struct item_info_s all_items[16] = {
EOF_ITEMS1
;
    print $output_fh join( ",\n",
        map {
            exists( $all_items->{ $_ } ) ?
                sprintf( "\t{ \"%s\", &btile_%s, 0x%04x, F_ITEM_ACTIVE }",
                    $all_items->{ $_ }{'name'},
                    $all_items->{ $_ }{'name'},
                    ( 0x1 << $all_items->{ $_ }{'item_index'} )
                    ) :
                "\t{ NULL, NULL, 0, 0 }"
            } ( 0 .. 15 )
    );

    print $output_fh <<EOF_ITEMS2

};

EOF_ITEMS2
;

}

sub output_game_config {
    print $output_fh "// game config\n";

    print $output_fh join( "\n", 
        map { sprintf "void %s(void);", $game_config->{'game_functions'}{ $_ } } 
        keys %{ $game_config->{'game_functions'} } );

    print $output_fh <<EOF_GAME_CONFIG1

struct game_config_s game_config = {
EOF_GAME_CONFIG1
;

    print $output_fh join( ",\n", 
        map { sprintf "\t.game_functions.%-16s = %s", "run_" . $_ , $game_config->{'game_functions'}{ $_ } || 'NULL' } 
        keys %{ $game_config->{'game_functions'} } );

    print $output_fh "\n};\n\n";
}

###################################
## Utility functions
###################################

# converts a 16-char long string of ## and .. into its 8 bit number
# MSB first
sub pixels_to_byte {
    my $pixels = shift;
    return -1 if ( length( $pixels ) != 16 );
    # yes 'oct' function in perl converts _binary_ strings to number
    return oct( '0b' . join( '', map { ( $_ eq '..' ? '0' : '1' ) } unpack("(A2)*", $pixels ) ) );
}

#################################
## Consistency Checks Functions
#################################

sub check_screen_sprites_are_valid {
    my $errors = 0;
    my %is_valid_sprite = map { $_->{'name'}, 1 } @sprites;
    foreach my $screen ( @screens ) {
        foreach my $sprite ( @{ $screen->{'sprites'} } ) {
            if ( not $is_valid_sprite{ $sprite->{'name'} } ) {
                warn sprintf "Screen '%s': undefined sprite '%s'\n", $screen->{'name'}, $sprite->{'name'};
                $errors++;
            }
        }
    }
    return $errors;
}

sub check_screen_btiles_are_valid {
    my $errors = 0;
    my %is_valid_btile = map { $_->{'name'}, 1 } @btiles;
    foreach my $screen ( @screens ) {
        foreach my $btile ( @{ $screen->{'btiles'} } ) {
            if ( not $is_valid_btile{ $btile->{'name'} } ) {
                warn sprintf "Screen '%s': undefined btile '%s'\n", $screen->{'name'}, $btile->{'name'};
                $errors++;
            }
        }
    }
    return $errors;
}

# items are btiles
sub check_screen_items_are_valid {
    my $errors = 0;
    my %is_valid_btile = map { $_->{'name'}, 1 } @btiles;
    foreach my $screen ( @screens ) {
        foreach my $item ( @{ $screen->{'items'} } ) {
            if ( not $is_valid_btile{ $item->{'name'} } ) {
                warn sprintf "Screen '%s': undefined btile for item '%s'\n", $screen->{'name'}, $item->{'name'};
                $errors++;
            }
        }
    }
    return $errors;
}

sub integer_in_range {
    my ( $value, $min, $max ) = @_;
    return ( ( $value >= $min ) and ( $value <= $max ) );
}

sub check_screen_hotzones_do_not_overlap {
    my $errors = 0;
    my $hero_center_x = $sprites[ $sprite_name_to_index{ $hero->{'sprite_up'} } ]{'cols'} * 8 / 2;
    my $hero_center_y = $sprites[ $sprite_name_to_index{ $hero->{'sprite_up'} } ]{'rows'} * 8 / 2;
    foreach my $screen ( @screens ) {
        my $org_hz_cnt = 0;
        foreach my $hz ( @{ $screen->{'hotzones'} } ) {
            $org_hz_cnt++;
            next if ( $hz->{'type'} ne 'WARP' );
            my $dest_x = $hz->{'dest_hero_x'} + $hero_center_x;
            my $dest_y = $hz->{'dest_hero_y'} + $hero_center_y;
            my $dest_screen = $hz->{'dest_screen'};
            my $dst_hz_cnt = 0;
            foreach my $dst_hz ( @{ $screens[ $screen_name_to_index{ $dest_screen } ]{'hotzones'} } ) {
                $dst_hz_cnt++;
                # for destination, all types of hotzones need to be checked, not just WARP zones
                if ( integer_in_range( $dest_x, $dst_hz->{'col'} * 8, ( ( $dst_hz->{'col'} + $dst_hz->{'height'} ) * 8 ) - 1 ) and
                        integer_in_range( $dest_y, $dst_hz->{'row'} * 8, ( ( $dst_hz->{'row'} + $dst_hz->{'width'} ) * 8 ) - 1 ) ) {
                    warn sprintf "Screen '%s': hotzone #%d destination coords overlap with hotzone #%d in Screen '%s'\n",
                        $screen->{'name'}, $org_hz_cnt, $dst_hz_cnt, $dest_screen;
                    $errors++;
                }
            }
        }
    }
    return $errors;
}

# this function is called from main
sub run_consistency_checks {
    my $errors = 0;
    $errors += check_screen_sprites_are_valid;
    $errors += check_screen_btiles_are_valid;
    $errors += check_screen_items_are_valid;
    $errors += check_screen_hotzones_do_not_overlap;
    die sprintf("*** %d errors were found in configuration\n", $errors )
        if ( $errors );
}

#############################
## General Output Functions
#############################

sub output_header {
    print $output_fh <<EOF_HEADER
///////////////////////////////////////////////////////////
//
// Game data - automatically generated with datagen.pl
//
///////////////////////////////////////////////////////////

#include <arch/spectrum.h>

#include "map.h"
#include "sprite.h"
#include "game_data.h"
#include "debug.h"
#include "hero.h"
#include "game_state.h"
#include "bullet.h"
#include "game_config.h"

EOF_HEADER
;
}

sub output_tiles {
    print $output_fh <<EOF_TILES
////////////////////////////
// Big Tile definitions
////////////////////////////

EOF_TILES
;
    foreach my $tile ( @btiles ) { output_btile( $tile ); }

}

sub output_sprites {
    print $output_fh <<EOF_SPRITES
////////////////////////////
// Sprite definitions
////////////////////////////

EOF_SPRITES
;
    foreach my $sprite ( @sprites ) { output_sprite( $sprite ); }

}

sub output_screens {
    print $output_fh <<EOF_SCREENS
////////////////////////////
// Screen definitions
////////////////////////////

EOF_SCREENS
;
    foreach my $screen ( @screens ) { output_screen( $screen ); }
    
}

sub output_map {
    # output global map data structure
    print $output_fh <<EOF_MAP
////////////////////////////
// Map definition
////////////////////////////

// main game map
EOF_MAP
;
    printf $output_fh "uint8_t map_num_screens = %d;\n", scalar( @screens );
    printf $output_fh "struct map_screen_s map[ %d ] = {\n", scalar( @screens );

    print $output_fh join( ",\n", map {
            sprintf( "\t// Screen '%s'\n\t{\n", $_->{'name'} ) .
            sprintf( "\t\t{ %d, %s },\t// btile_data\n", 
                scalar( @{$_->{'btiles'}} ), ( scalar( @{$_->{'btiles'}} ) ? sprintf( 'screen_%s_btile_pos', $_->{'name'} ) : 'NULL' ) ) .
            sprintf( "\t\t{ %d, %s },\t// sprite_data\n", 
                scalar( @{$_->{'sprites'}} ), ( scalar( @{$_->{'sprites'}} ) ? sprintf( 'screen_%s_sprites', $_->{'name'} ) : 'NULL' ) ) .
            sprintf( "\t\t{ %d, %d },\t// hero_data\n", 
                $_->{'hero'}{'startup_xpos'}, $_->{'hero'}{'startup_ypos'} ) .
            sprintf( "\t\t{ %d, %s },\t// item_data\n", 
                scalar( @{$_->{'items'}} ), ( scalar( @{$_->{'items'}} ) ? sprintf( 'screen_%s_items', $_->{'name'} ) : 'NULL' ) ) .
            sprintf( "\t\t{ %d, %s },\t// hotzone_data\n", 
                scalar( @{$_->{'hotzones'}} ), ( scalar( @{$_->{'hotzones'}} ) ? sprintf( 'screen_%s_hotzones', $_->{'name'} ) : 'NULL' ) ) .
            "\t}"
        } @screens );
    print $output_fh "\n};\n\n";
}

sub output_map_sprites_initialization {
    # output sprite creation code
    # this must be done after the map definition, since this function
    # loads the sprite data into every screen
    print $output_fh <<EOF_SPRITES2
//////////////////////////////////////
// Sprite initialization function
//////////////////////////////////////

void init_screen_sprite_tables(void) {
\tstruct sp1_ss *s;	// temporary storage

EOF_SPRITES2
;

    foreach my $s ( 0 .. (scalar( @screens ) - 1) ) {
        output_screen_sprite_initialization_code( $s );
    }

    print $output_fh <<EOF_SPRITES3

}

EOF_SPRITES3
;
}

sub output_hero_sprites_initialization {
    my $sprite = $sprites[ $sprite_name_to_index{ $hero->{'sprite_up'} } ];

    # output hero sprite creation code
    print $output_fh <<EOF_HERO2
//////////////////////////////////////
// Hero Sprites initialization function
//////////////////////////////////////

// This needs to be publicly accessible
// it is exported as extern in game_data.h
struct sp1_ss *hero_sprite;

void init_hero_sprites(void) {
    struct hero_info_s *h;

    h = &game_state.hero;

    // SP1 sprite data
EOF_HERO2
;
    printf $output_fh "\th->sprite = hero_sprite = sp1_CreateSpr(SP1_DRAW_MASK2LB, SP1_TYPE_2BYTE, %d, %d, %d );\n",
        $sprite->{'rows'} + 1,	# height in chars including blank bottom row
        0,				# left column graphic offset
        0,				# plane
    ;
    foreach my $ac ( 1 .. ($sprite->{'cols'} - 1) ) {
        printf $output_fh "\tsp1_AddColSpr(hero_sprite, SP1_DRAW_MASK2, %d, %d, %d );\n",
            0,					# type
            ( $sprite->{'rows'} + 1 ) * 16 * $ac,	# nth column graphic offset
            0,					# plane
        ;
    }
    printf $output_fh "\tsp1_AddColSpr(hero_sprite, SP1_DRAW_MASK2RB, 0, 0, 0);\n";	# empty rightmost column
    print $output_fh <<EOF_HERO3

}

EOF_HERO3
;
}

sub output_bullet_sprites_initialization {
    my $sprite = $sprites[ $sprite_name_to_index{ $hero->{'bullet'}{'sprite'} } ];
    my $sprite_name = $hero->{'bullet'}{'sprite'};
    my $width = $sprite->{'cols'} * 8;
    my $height = $sprite->{'rows'} * 8;
    my $max_bullets = $hero->{'bullet'}{'max_bullets'};
    my $dx = $hero->{'bullet'}{'dx'};
    my $dy = $hero->{'bullet'}{'dy'};
    my $delay = $hero->{'bullet'}{'delay'};
    my $reload_delay = $hero->{'bullet'}{'reload_delay'};

    # output bullet sprite creation code
    print $output_fh <<EOF_BULLET1
//////////////////////////////////////
// Bullet Sprites initialization function
//////////////////////////////////////

void init_bullet_sprites(void) {
    struct bullet_info_s *bi;
    struct sp1_ss *bs;
    uint8_t i;

    // SP1 sprite data
    i = $max_bullets;
    while ( i-- ) {
EOF_BULLET1
;
    printf $output_fh "\t\tbullet_state_data[i].sprite = bs = sp1_CreateSpr(SP1_DRAW_MASK2LB, SP1_TYPE_2BYTE, %d, %d, %d );\n",
        $sprite->{'rows'} + 1,	# height in chars including blank bottom row
        0,				# left column graphic offset
        0,				# plane
    ;
    foreach my $ac ( 1 .. ($sprite->{'cols'} - 1) ) {
        printf $output_fh "\tsp1_AddColSpr(bs, SP1_DRAW_MASK2, %d, %d, %d );\n",
            0,					# type
            ( $sprite->{'rows'} + 1 ) * 16 * $ac,	# nth column graphic offset
            0,					# plane
        ;
    }
    printf $output_fh "\tsp1_AddColSpr(bs, SP1_DRAW_MASK2RB, 0, 0, 0);\n";	# empty rightmost column
    print $output_fh <<EOF_BULLET6
    }

    // initialize remaining game_state.bullet struct fields
    bi = &game_state.bullet;
    bi->width = $width;
    bi->height = $height;
    bi->frames = &sprite_${sprite_name}_frames[0];
    bi->movement.dx = $dx;
    bi->movement.dy = $dy;
    bi->movement.delay = $delay;
    bi->num_bullets = $max_bullets;
    bi->bullets = &bullet_state_data[0];
    bi->reload_delay = $reload_delay;
    bi->reloading = 0;
}

EOF_BULLET6
;
}

sub output_header_file {
    print $output_fh <<GAME_DATA_H_1
#ifndef _GAME_DATA_H
#define _GAME_DATA_H

#include <stdint.h>
#include <games/sp1.h>

// global map data structure - autogenerated by datagen tool into
// game_data.c
extern uint8_t map_num_screens;
extern struct map_screen_s map[];

// global items table
extern uint8_t inventory_max_items;
extern uint16_t inventory_all_items_mask;
extern struct item_info_s all_items[];

// a pre-filled hero_info_s struct for game reset
// generated by datagen.pl in game_data.c
extern struct hero_info_s hero_startup_data;
extern struct sp1_ss *hero_sprite;

void init_screen_sprite_tables(void);
void init_hero_sprites(void);
void init_bullet_sprites(void);

// auxiliary pointers
GAME_DATA_H_1
;

    # output auxiliary data pointers
    foreach my $btile ( @btiles ) {
        printf $output_fh "extern struct btile_s btile_%s;\n", $btile->{'name'};
    }
    foreach my $sprite ( @sprites ) {
        printf $output_fh "extern uint8_t sprite_%s_data[];\n", $sprite->{'name'};
        printf $output_fh "extern uint8_t *sprite_%s_frames[];\n", $sprite->{'name'};
    }

    print $output_fh "\n// game configuration data\n";
    printf $output_fh "#define MAP_INITIAL_SCREEN %d\n", $game_config->{'screen'}{'initial'};
    printf $output_fh "#define DEFAULT_BG_ATTR ( %s )\n", $game_config->{'default_bg_attr'};

    print $output_fh "\n// sound effect constants\n";
    foreach my $effect ( keys %{$game_config->{'sounds'}} ) {
        printf $output_fh "#define SOUND_%s %d\n", uc( $effect ), $game_config->{'sounds'}{ $effect };
    }

    # end of header file
    print $output_fh "\n#endif // _GAME_DATA_H\n";


}

# this function is called from main
sub output_generated_data {
    # output .c file
    open( $output_fh, ">", $c_file ) or
        die "Could not open $c_file for writing\n";

    output_header;
    output_tiles;
    output_sprites;
    output_screens;
    output_map;
    output_hero;
    output_bullets;
    output_map_sprites_initialization;
    output_hero_sprites_initialization;
    output_bullet_sprites_initialization;
    output_items;
    output_game_config;

    close $output_fh;

    # output .h file
    open( $output_fh, ">", $h_file ) or
        die "Could not open $h_file for writing\n";

    output_header_file;;

    close $output_fh;

}

# creates a dump of internal data so that other tools (e.g.  FLOWGEN) can
# load it and use the parsed data. Use "-c" option to dump the internal data
sub dump_internal_data {
    open DUMP, ">$dump_file" or
        die "Could not open $dump_file for writing\n";

    my $all_state = {
        btiles			=> \@btiles,
        screens			=> \@screens,
        screen_name_to_index	=> \%screen_name_to_index,
        sprites			=> \@sprites,
        sprite_name_to_index	=> \%sprite_name_to_index,
        hero			=> $hero,
        all_items		=> $all_items,
        game_config		=> $game_config,
    };

    print DUMP Data::Dumper->Dump( [ $all_state ], [ 'all_state' ] );
    close DUMP;
}

#########################
## Main loop
#########################

our ( $opt_d, $opt_c );
getopts("d:c");
if ( defined( $opt_d ) ) {
    $c_file = "$opt_d/$c_file";
    $h_file = "$opt_d/$h_file";
    $dump_file = "$opt_d/$dump_file";
}

# read, validate and compile input
read_input_data;

# run consistency checks
run_consistency_checks;

# generate output
output_generated_data;

# dump internal data if required to do so
dump_internal_data
    if ( $opt_c );
