#!/usr/bin/env perl

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
my %btile_name_to_index;
my @screens;
my %screen_name_to_index = ( '__NO_SCREEN__', 0 );
my @sprites;
my %sprite_name_to_index;
my $hero;
my $all_items;
my $game_config;

my $c_file = 'game_data.c';
my $h_file = 'game_data.h';

# dump file for internal state
my $dump_file = 'internal_state.dmp';

# output lines for each of the files
my @c_lines;
my @h_lines;
my @asm_lines;

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
            if ( $line =~ /^PNG_DATA\s+(.*)$/ ) {
                my $args = $1;
                my $vars = {
                    map { my ($k,$v) = split( /=/, $_ ); lc($k), $v }
                    split( /\s+/, $args )
                };
                my $data = png_to_pixels_and_attrs(
                    $vars->{'file'},
                    $vars->{'xpos'}, $vars->{'ypos'},
                    $vars->{'width'}, $vars->{'height'},
                );
                $cur_btile->{'pixels'} = $data->{'pixels'};
                $cur_btile->{'png_attr'} = $data->{'attrs'};
                next;
            }
            if ( $line =~ /^END_BTILE$/ ) {
                validate_and_compile_btile( $cur_btile );
                my $index = scalar( @btiles );
                push @btiles, $cur_btile;
                $btile_name_to_index{ $cur_btile->{'name'} } = $index;
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
            if ( $line =~ /^REAL_PIXEL_WIDTH\s+(\d+)$/ ) {
                $cur_sprite->{'real_pixel_width'} = $1;
                next;
            }
            if ( $line =~ /^REAL_PIXEL_HEIGHT\s+(\d+)$/ ) {
                $cur_sprite->{'real_pixel_height'} = $1;
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
            if ( $line =~ /^PNG_DATA\s+(.*)$/ ) {
                my $args = $1;
                my $vars = {
                    map { my ($k,$v) = split( /=/, $_ ); lc($k), $v }
                    split( /\s+/, $args )
                };
                my $fgcolor = uc( $vars->{'fgcolor'} );
                push @{$cur_sprite->{'pixels'}}, @{ pick_pixel_data_by_color_from_png(
                    $vars->{'file'}, $vars->{'xpos'}, $vars->{'ypos'}, $vars->{'width'}, $vars->{'height'}, $fgcolor,
                    ( $vars->{'hmirror'} || 0 ), ( $vars->{'vmirror'} || 0 )
                    ) };
                push @{$cur_sprite->{'png_attr'}}, @{ attr_data_from_png(
                    $vars->{'file'}, $vars->{'xpos'}, $vars->{'ypos'}, $vars->{'width'}, $vars->{'height'},
                    ( $vars->{'hmirror'} || 0 ), ( $vars->{'vmirror'} || 0 )
                    ) };
                next;
            }
            if ( $line =~ /^PNG_MASK\s+(.*)$/ ) {
                my $args = $1;
                my $vars = {
                    map { my ($k,$v) = split( /=/, $_ ); lc($k), $v }
                    split( /\s+/, $args )
                };
                my $maskcolor = uc( $vars->{'maskcolor'} );
                push @{$cur_sprite->{'mask'}}, @{ pick_pixel_data_by_color_from_png(
                    $vars->{'file'}, $vars->{'xpos'}, $vars->{'ypos'}, $vars->{'width'}, $vars->{'height'}, $maskcolor,
                    ) };
                next;
            }
            if ( $line =~ /^ATTR\s+(.+)$/ ) {
                push @{$cur_sprite->{'attr'}}, $1;
                next;
            }
            if ( $line =~ /^SEQUENCE\s+(.*)$/ ) {
                my $args = $1;
                my $vars = {
                    map { my ($k,$v) = split( /=/, $_ ); lc($k), $v }
                    split( /\s+/, $args )
                };
                my $index = defined( $cur_sprite->{'sequences'} ) ? scalar( @{ $cur_sprite->{'sequences'} } ) : 0 ;
                push @{ $cur_sprite->{'sequences'} }, $vars;
                $cur_sprite->{'sequence_name_to_index'}{ $vars->{'name'} } = $index;
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
                my $item = {
                    map { my ($k,$v) = split( /=/, $_ ); lc($k), $v }
                    split( /\s+/, $args )
                };
                my $index = scalar( @{ $cur_screen->{'btiles'} } );
                push @{ $cur_screen->{'btiles'} }, $item;
                $cur_screen->{'btile_name_to_index'}{ $item->{'name'} } = $index;
                next;
            }
            if ( $line =~ /^OBSTACLE\s+(\w.*)$/ ) {
                # ARG1=val1 ARG2=va2 ARG3=val3...
                my $args = "$1 TYPE=OBSTACLE";
                my $item = {
                    map { my ($k,$v) = split( /=/, $_ ); lc($k), $v }
                    split( /\s+/, $args )
                };
                my $index = scalar( @{ $cur_screen->{'btiles'} } );
                push @{ $cur_screen->{'btiles'} }, $item;
                $cur_screen->{'btile_name_to_index'}{ $item->{'name'} } = $index;
                next;
            }
            if ( $line =~ /^ENEMY\s+(\w.*)$/ ) {
                # ARG1=val1 ARG2=va2 ARG3=val3...
                my $args = $1;
                push @{ $cur_screen->{'enemies'} }, {
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
            if ( $line =~ /^BACKGROUND\s+(\w.*)$/ ) {
                # ARG1=val1 ARG2=va2 ARG3=val3...
                my $args = $1;
                $cur_screen->{'background'} = {
                    map { my ($k,$v) = split( /=/, $_ ); lc($k), $v }
                    split( /\s+/, $args )
                };
                next;
            }
            if ( $line =~ /^DEFINE\s+(\w.*)$/ ) {
                # ARG1=val1 ARG2=va2 ARG3=val3...
                my $args = $1;
                my $item = {
                    map { my ($k,$v) = split( /=/, $_ ); lc($k), $v }
                    split( /\s+/, $args )
                };
                $cur_screen->{'digraphs'}{ $item->{'digraph'} } = $item;
                next;
            }
            if ( $line =~ /^SCREEN_DATA\s+"(.*)"$/ ) {
                push @{ $cur_screen->{'screen_data'} }, $1;
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
            if ( $line =~ /^SPRITE\s+(\w+)$/ ) {
                $hero->{'sprite'} = $1;
                next;
            }
            if ( $line =~ /^SEQUENCE_UP\s+(\w+)$/ ) {
                $hero->{'sequence_up'} = $1;
                next;
            }
            if ( $line =~ /^SEQUENCE_DOWN\s+(\w+)$/ ) {
                $hero->{'sequence_down'} = $1;
                next;
            }
            if ( $line =~ /^SEQUENCE_LEFT\s+(\w+)$/ ) {
                $hero->{'sequence_left'} = $1;
                next;
            }
            if ( $line =~ /^SEQUENCE_RIGHT\s+(\w+)$/ ) {
                $hero->{'sequence_right'} = $1;
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
                foreach my $a ( split( /\s+/, $args ) ) {
                    $a =~ s/^\s*//g;	# remove leading and trailing blanks
                    $a =~ s/\s*$//g;
                    my ($k,$v) = split( /=/, $a );
                    $game_config->{'game_functions'}{ lc($k) } = $v;
                }
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
            if ( $line =~ /^(GAME_AREA|LIVES_AREA|INVENTORY_AREA|DEBUG_AREA)\s+(\w.*)$/ ) {
                # ARG1=val1 ARG2=va2 ARG3=val3...
                my ( $directive, $args ) = ( $1, $2 );
                $game_config->{ lc( $directive ) } = {
                    map { my ($k,$v) = split( /=/, $_ ); lc($k), $v }
                    split( /\s+/, $args )
                };
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

# Loads a PNG file
# Returns a ref to a list of refs to lists of pixels
# i.e. each pixel can addressed as $png->[y][x]
my $png_file_cache;
sub load_png_file {
    my $file = shift;

    # if data exists in cache for the file, just return it
    if ( exists( $png_file_cache->{ $file } ) ) {
        return $png_file_cache->{ $file };
    }

    # ..else, build it...
    my $command = sprintf( "pngtopam '%s' | pamtable", $file );
    my @pixel_lines = `$command`;
    chomp @pixel_lines;
    my @pixels = map {			# for each line...
        s/(\d+)/sprintf("%02X",$1)/ge;	# replace decimals by upper hex equivalent
        s/ //g;				# remove spaces
       [ split /\|/ ];			# split each pixel data by '|' and return listref of pixels
    } @pixel_lines;

    # ...store in cache for later use...
    $png_file_cache->{ $file } = \@pixels;

    # ..and return it
    return \@pixels;
}

# extracts pixel data from a PNG file
sub pick_pixel_data_by_color_from_png {
    my ( $file, $xpos, $ypos, $width, $height, $hex_fgcolor, $hmirror, $vmirror ) = @_;
    my $png = load_png_file( $file );
    my @pixels = map {
        join( "",
            map {
                $_ eq $hex_fgcolor ? "##" : "..";		# filter color
                } @$_[ $xpos .. ( $xpos + $width - 1 ) ]	# select cols
        )
    } @$png[ $ypos .. ( $ypos + $height - 1 ) ];		# select rows
    if ( $hmirror ) {
        my @tmp = map { scalar reverse } @pixels;
        @pixels = @tmp;
    }
    if ( $vmirror ) {
        my @tmp = reverse @pixels;
        @pixels = @tmp;
    }
    return \@pixels;
}

# calculates best attributes for a 8x8 cell out of PNG data
my %zx_colors = (
    '000000' => 'BLACK',
    '0000C0' => 'BLUE',
    '00C000' => 'GREEN',
    '00C0C0' => 'CYAN',
    'C00000' => 'RED',
    'C000C0' => 'MAGENTA',
    'C0C000' => 'YELLOW',
    'C0C0C0' => 'WHITE',
    '0000FF' => 'BLUE',
    '00FF00' => 'GREEN',
    '00FFFF' => 'CYAN',
    'FF0000' => 'RED',
    'FF00FF' => 'MAGENTA',
    'FFFF00' => 'YELLOW',
    'FFFFFF' => 'WHITE',
);

sub extract_colors_from_cell {
    my ( $png, $xpos, $ypos ) = @_;
    my %histogram;
    foreach my $x ( $xpos .. ( $xpos + 7 ) ) {
        foreach my $y ( $ypos .. ( $ypos + 7 ) ) {
            my $pixel_color = $png->[$y][$x];
            $histogram{$pixel_color}++;
        }
    }
    my @l = sort { $histogram{ $a } > $histogram{ $b } } keys %histogram;
    if (scalar( @l ) > 2 ) {
        foreach my $e ( 3 .. $#l ) {
            printf STDERR "Warning: color #%s (%s)  detected but ignored\n",
                $l[$e], $zx_colors{ $l[$e] };
        }
    }
    my $bg = $l[0];
    my $fg = $l[1];
    # if one of them is black, it is preferred as bg color, swap them if needed
    if ( $fg eq '000000' ) {
        my $tmp = $bg;
        $bg = $fg;
        $fg = $tmp;
    }
    return { 'bg' => $bg, 'fg' => $fg };
}

sub extract_attr_from_cell {
    my ( $png, $xpos, $ypos ) = @_;
    my $colors = extract_colors_from_cell( $png, $xpos, $ypos );
    my ( $bg, $fg ) = map { $colors->{$_} } qw( bg fg );
    my $attr = sprintf "INK_%s | PAPER_%s", $zx_colors{ $fg }, $zx_colors{ $bg };
    if ( ( $fg =~ /FF/ ) or ( $bg =~ /FF/ ) ) { $attr .= " | BRIGHT"; }
    return $attr;
}

sub attr_data_from_png {
    my ( $file, $xpos, $ypos, $width, $height, $hmirror, $vmirror ) = @_;
    my $png = load_png_file( $file );
    my @attrs;
    # extract attr from cells left-right, top-bottom order
    my $y = $ypos;
    while ( $y < ( $ypos + $height ) ) {
        my $x = $xpos;
        while ( $x < ( $xpos + $width ) ) {
            push @attrs, extract_attr_from_cell( $png, $x, $y );
            $x += 8;
        }
        $y += 8;
    }
    my $c_width = $width / 8;
    my $c_height = $height / 8;
    if ( $hmirror ) {
        my @tmp;
        foreach my $c ( ( $c_width - 1 ) .. 0 ) {	# columns: reverse order
            foreach my $r ( 0 .. ( $c_height - 1 ) ) {	# rows: direct order
                push @tmp, $attrs[ $r * $c_width + $c ];
            }
        }
        @attrs = @tmp;
    }
    if ( $vmirror ) {
        my @tmp;
        foreach my $c ( 0 .. ( $c_width - 1 ) ) {	# columns: direct order
            foreach my $r ( ( $c_height - 1 ) .. 0 ) {	# rows: reverse order
                push @tmp, $attrs[ $r * $c_width + $c ];
            }
        }
        @attrs = @tmp;
    }
    return \@attrs;
}

sub png_to_pixels_and_attrs {
    my ( $file, $xpos, $ypos, $width, $height ) = @_;
    my $png = load_png_file( $file );

    # extract color and pixel data from cells left-right, top-bottom order
    my @colors;
    my @pixels;
    my $y = $ypos;
    while ( $y < ( $ypos + $height ) ) {
        my $x = $xpos;
        while ( $x < ( $xpos + $width ) ) {
            my $c = extract_colors_from_cell( $png, $x, $y );
            push @colors, $c;
            push @pixels, pick_pixel_data_by_color_from_png( $file, $x, $y, 8, 8, $c->{'fg'} );
            $x += 8;
        }
        $y += 8;
    }

    # we need to rearrange pixel data
    my @pixel_data_lines;
    my $nrows = $height / 8;
    my $ncols = $width / 8;
    foreach my $r ( 0 .. ( $nrows - 1 ) ) {
        foreach my $l ( 0 .. 7 ) {
            my $pixel_data_line;
            foreach my $c ( 0 .. ( $ncols - 1 ) ) {
                $pixel_data_line .= $pixels[ $r * $ncols + $c ][ $l ];
            }
            push @pixel_data_lines, $pixel_data_line;
        }
    }

    return {
            'pixels'	=> \@pixel_data_lines,
            'attrs'	=> attr_data_from_png( $file, $xpos, $ypos, $width, $height ),
    };
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
    defined( $tile->{'attr'} ) or defined( $tile->{'png_attr'} ) or
        die "Btile '$tile->{name}' has no ATTR or PNG_ATTRS\n";
    my $num_attrs = $tile->{'rows'} * $tile->{'cols'};
    if ( defined( $tile->{'attr'} ) ) {
        ( scalar( @{$tile->{'attr'}} ) == $num_attrs ) or
            die "Btile '$tile->{name}' should have $num_attrs ATTR elements\n";
    } else {
        ( scalar( @{$tile->{'png_attr'}} ) == $num_attrs ) or
            die "Btile '$tile->{name}' should have $num_attrs elements in PNG_ATTR\n";
    }
    ( scalar( @{$tile->{'pixels'}} ) == $tile->{'rows'} * 8 ) or
        die "Btile '$tile->{name}' should have ".( $tile->{'rows'} * 8 )." PIXELS elements\n";
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

sub generate_btile {
    my $tile = shift;
    my $cur_char = 0;
    my @char_names;
    push @c_lines, sprintf( "// Big tile '%s'\n\n", $tile->{'name'} );
    push @c_lines, sprintf( "uint8_t btile_%s_tile_data[%d] = {\n%s\n};\n",
        $tile->{'name'},
        scalar( map { @$_ } @{ $tile->{'pixel_bytes'} } ),
        join( ", ",
            map { '0x'.sprintf('%02x',$_) }
            map { @$_ }
            @{ $tile->{'pixel_bytes'} }
        ) );
    push @c_lines, sprintf( "uint8_t *btile_%s_tiles[%d] = { %s };\n",
        $tile->{'name'},
        scalar( map { @$_ } @{ $tile->{'pixel_bytes'} } ) / 8,
        join( ', ',
            map { sprintf( "&btile_%s_tile_data[%d]", $tile->{'name'}, $_ ) }
            grep { ( $_ % 8 ) == 0 }
            ( 0 .. ( $tile->{'rows'} * $tile->{'cols'} * 8 - 1 ) )
        ) );
    # manually specified attrs have preference over PNG ones
    my $attrs = ( $tile->{'attr'} || $tile->{'png_attr'} );
    push @c_lines, sprintf( "uint8_t btile_%s_attrs[%d] = { %s };\n",
        $tile->{'name'},
        scalar( @{ $attrs } ),
        join( ', ', @{ $attrs } ) );
    push @c_lines, sprintf( "struct btile_s btile_%s = { %d, %d, &btile_%s_tiles[0], &btile_%s_attrs[0] };\n",
        $tile->{'name'},
        $tile->{'rows'},
        $tile->{'cols'},
        $tile->{'name'},
        $tile->{'name'} );
    push @c_lines, sprintf( "\n// End of Big tile '%s'\n\n", $tile->{'name'} );
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

    # if the sprite has no 'sequence_delay' parameter, define as 0
    if ( not defined( $sprite->{'sequence_delay'} ) ) {
        $sprite->{'sequence_delay'} = 0;
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
    my $sprite = shift;
    my $sprite_rows = $sprite->{'rows'};
    my $sprite_cols = $sprite->{'cols'};
    my $sprite_frames = $sprite->{'frames'};
    my $sprite_name = $sprite->{'name'};

    my $cur_char = 0;
    my @char_names;
    push @c_lines, sprintf( "// Sprite '%s'\n// Pixel and mask data ordered by column (required by SP1)\n\n", $sprite->{'name'} );

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
    push @c_lines, sprintf( "uint8_t sprite_%s_data[] = {\n%s\n};\n",
        $sprite->{'name'},
        join( ",\n", map { join( ", ", map { sprintf( "0x%02x", $_ ) } @{$_} ) } @groups_of_2m ) );

    # output list of pointers to frames
    my @frame_offsets;
    my $ptr = 16;	# initial frame: 8 bytes pixel + 8 bytes mask for the top blank row
    foreach ( 0 .. ( $sprite->{'frames'} - 1 ) ) {
        push @frame_offsets, $ptr;
        $ptr += 16 * ( $sprite->{'rows'} + 1 ) * $sprite->{'cols'};
    }
    push @c_lines, sprintf( "uint8_t *sprite_%s_frames[] = {\n%s\n};\n",
        $sprite_name,
        join( ",\n", 
            map { sprintf( "\t&sprite_%s_data[%d]", $sprite_name, $_ ) }
            @frame_offsets
        ) );

    # output list of animation sequences
    if ( scalar( @{ $sprite->{'sequences'} } ) ) {
        push @c_lines, join( "", map {
            sprintf( "uint8_t sprite_%s_sequence_%s[%d] = { %s };\n",
                $sprite_name, $_->{'name'}, scalar( @{ $_->{'frame_list'} } ), join( ',', @{ $_->{'frame_list'} } ) );
        } @{ $sprite->{'sequences'} } );
        push @c_lines, sprintf( "struct animation_sequence_s sprite_%s_sequences[%d] = {\n\t",
            $sprite_name, scalar( @{ $sprite->{'sequences'} } ) );
        push @c_lines, join( ",\n\t", map {
            sprintf( "{ %d, &sprite_%s_sequence_%s[0] }", scalar( @{ $_->{'frame_list'} } ), $sprite_name, $_->{'name'} );
        } @{ $sprite->{'sequences'} } );
        push @c_lines, "\n};\n\n";
    }

    push @c_lines, sprintf( "// End of Sprite '%s'\n\n", $sprite_name );
}

######################################
## Map Screen functions
######################################

sub validate_and_compile_screen {
    my $screen = shift;
    defined( $screen->{'name'} ) or
        die "Screen has no NAME\n";
    defined( $screen->{'hero'} ) or
        die "Screen '$screen->{name}' has no Hero\n";

    # check each enemy
    foreach my $s ( @{$screen->{'enemies'}} ) {
        # set initial flags
        $s->{'initial_flags'} = join( " | ", 0,
            map { "F_ENEMY_" . uc($_) }
            grep { $s->{$_} }
            qw( bounce change_sequence_horiz change_sequence_vert )
            );
        # define default animation sequences if none given
        if ( not defined( $s->{'sequence_a'} ) ) {
            $s->{'sequence_a'} = 'Main';
        }
        if ( not defined( $s->{'sequence_b'} ) ) {
            $s->{'sequence_b'} = 'Main';
        }
        if ( not defined( $s->{'initial_sequence'} ) ) {
            $s->{'initial_sequence'} = 'Main';
        }
    }

    # compile SCREEN_DATA lines
    compile_screen_data( $screen );

    ( scalar( @{$screen->{'btiles'}} ) > 0 ) or
        die "Screen '$screen->{name}' has no Btiles\n";
}

# SCREEN_DATA and DEFINE compilation
sub compile_screen_data {
    my $screen = shift;

    # map: digraph -> btile, type, row, col
    # this has been previously generated via the DEFINE directives
    my $screen_digraphs = $screen->{'digraphs'};
    my $screen_digraph_counters;

    # DATA and DEST arrays (see MAP-SCREEN-DATA-DESIGN.md)
    my $screen_data;
    my $screen_dest;
    # list of btiles generated from the SCREEN_DATA
    my @screen_btiles;

    # if no SCREEN_DATA lines exist, nothing to compile, return
    return if not defined( $screen->{'screen_data'} );

    # check that there are the right number of rows and columns according to GAME_AREA
    my $game_area_width = $game_config->{'game_area'}{'right'} - $game_config->{'game_area'}{'left'} + 1;
    my $game_area_height = $game_config->{'game_area'}{'bottom'} - $game_config->{'game_area'}{'top'} + 1;
    my $game_area_top = $game_config->{'game_area'}{'top'};
    my $game_area_left = $game_config->{'game_area'}{'left'};
    ( scalar( @{ $screen->{'screen_data'} } ) == $game_area_height ) or
        die "Screen '$screen->{name}': there must be exactly $game_area_height SCREEN_DATA lines\n";
    foreach my $sd ( @{ $screen->{'screen_data'} } ) {
        ( length( $sd ) == ( 2 * $game_area_width ) ) or
            die "Screen '$screen->{name}': SCREEN_DATA lines must be exactly ".( 2 * $game_area_height )." characters long\n";
    }

    # populate the DEST array
    foreach my $r ( 0 .. ( $game_area_height - 1 ) ) {
        foreach my $c ( 0 .. ( $game_area_width - 1 ) ) {
            $screen_dest->[ $r ][ $c ] = '  ';
        }
    }

    # populate the DATA array
    my $row = 0;
    foreach my $sd ( @{$screen->{'screen_data'}} ) {
        $screen_data->[$row++] = [ ( $sd =~ m/.{2}/g ) ];
    }

    # process the DATA array
    foreach my $r ( 0 .. ( $game_area_height - 1 ) ) {
        foreach my $c ( 0 .. ( $game_area_width - 1 ) ) {

            # ignore the cell if there is no tile in input data
            next if ( $screen_data->[ $r ][ $c ] eq '  ' );

            # there is a tile in DATA, so process it
            my $data_dg = $screen_data->[ $r ][ $c ];
            my $dest_dg = $screen_dest->[ $r ][ $c ];

            # if there is no tile in DEST, this is the first time we see the tile
            if ( $dest_dg eq '  ' ) {

                # make sure there is a tile DEFINEd with that digraph
                ( defined( $screen_digraphs->{ $data_dg } ) ) or
                    die "Screen '$screen->{name}': digraph '$data_dg' is undefined\n";

                # "paint" the tile in the DEST array
                my $btile = $btiles[ $btile_name_to_index{ $screen_digraphs->{ $data_dg }{'btile'} } ];
                foreach my $i ( 0 .. ( $btile->{'rows'} - 1 ) ) {
                    foreach my $j ( 0 .. ( $btile->{'cols'} - 1 ) ) {
                        $screen_dest->[ $r + $i ][ $c + $j ] = $data_dg;
                    }
                }

                # ...and add the tile to the tile list - we add a generated name
                push @screen_btiles, { 
                    name => sprintf( "%s_%03d",
                        $screen_digraphs->{ $data_dg }{'name'},
                        ( $screen_digraph_counters->{ $screen_digraphs->{ $data_dg }{'name'} }++ || 1 )
                        ),
                    btile => $screen_digraphs->{ $data_dg }{'btile'},
                    type => $screen_digraphs->{ $data_dg }{'type'},
                    row => $game_area_top + $r,
                    col => $game_area_left + $c,
                    active => 1,
                };

            # else if there is a tile in DEST and it is different from the one in DATA...
            } elsif ( $dest_dg ne $data_dg ) {

                # die: we do not allow overlapping btiles (for the moment)
                die "Screen '$screen->{name}': overlapping btiles at row=$r, col=$c\n";

            # and finally, if the tile in DEST and DATA match, ignore since it's correct (they should match)
            }
        }
    }

    # finally, check that both DATA and DEST array elements match one by one
    foreach my $r ( 0 .. ( $game_area_height - 1 ) ) {
        foreach my $c ( 0 .. ( $game_area_width - 1 ) ) {
            ( $screen_data->[ $r ][ $c ] eq $screen_dest->[ $r ][ $c ] ) or
                die "Screen '$screen->{name}': mismatching btiles at row=$r, col=$c\n";
        }
    }

    # at this point, all is correct and we have the list of btiles generated
    # from the SCREEN_DATA and DEFINE lines.  Add then to the general btile
    # list for the screen.
    push @{ $screen->{'btiles'} }, @screen_btiles;

}


sub generate_screen_sprite_initialization_code {
    my $screen = shift;
    my $enemies = $screen->{'enemies'};
    push @c_lines, sprintf( "\t// Screen '%s' - Enemy sprite initialization\n", $screen->{'name'} );
    my $enemy_num = 0;
    foreach my $enemy ( @$enemies ) {
        my $sprite = $sprites[ $sprite_name_to_index{ $enemy->{'sprite'} } ];

        push @c_lines, sprintf( "\t// Sprite '%s'\n", $sprite->{'name'} );

        # generate code for initializing SP1 structure
        push @c_lines, sprintf( "\tm->enemy_data.enemies[%d].sprite = s = sp1_CreateSpr(SP1_DRAW_MASK2LB, SP1_TYPE_2BYTE, %d, %d, %d );\n",
            $enemy_num,
            $sprite->{'rows'} + 1,	# height in chars including blank bottom row
            0,				# left column graphic offset
            0,				# plane
        );
        foreach my $ac ( 1 .. ($sprite->{'cols'} - 1) ) {
            push @c_lines, sprintf( "\tsp1_AddColSpr(s, SP1_DRAW_MASK2, %d, %d, %d );\n",
                0,					# type
                ( $sprite->{'rows'} + 1 ) * 16 * $ac,	# nth column graphic offset
                0,					# plane
            );
        }
        push @c_lines, sprintf( "\tsp1_AddColSpr(s, SP1_DRAW_MASK2RB, 0, 0, 0);\n" );	# empty rightmost column

        # optimize SP1 for xthresh and vthresh
        if ( defined( $sprite->{'real_pixel_width'} ) ) {
            my $xthresh = ( 8 - ( $sprite->{'real_pixel_width'} % 8 ) + 1 ) % 8;
            if ( $xthresh > 1 ) {
                push @c_lines, sprintf( "\ts->xthresh = %d;\n", $xthresh );
            }
        }
        if ( defined( $sprite->{'real_pixel_height'} ) ) {
            my $ythresh = ( 8 - ( $sprite->{'real_pixel_height'} % 8 ) + 1 ) % 8;
            if ( $ythresh > 1 ) {
                push @c_lines, sprintf( "\ts->ythresh = %d;\n", $ythresh );
            }
        }

        # if there is a COLOR element in the enemy, set enemy color
        if ( defined( $enemy->{'color'} ) ) {
            push @c_lines, sprintf( "\tsprite_attr_param.attr = %s;\n", $enemy->{'color'} );
            push @c_lines, sprintf( "\tsprite_attr_param.attr_mask = 0xF8;\n" );
            push @c_lines, sprintf( "\tsp1_IterateSprChar( s, sprite_set_cell_attributes );\n" );
        }

        push @c_lines, sprintf( "\t// End of Sprite '%s'\n\n", $sprite->{'name'} );
        $enemy_num++;
    }
    push @c_lines, sprintf( "\t// Screen '%s' - End of Sprite initialization\n\n", $screen->{'name'} );
}

sub generate_screen {
    my $screen_num = shift;
    my $screen = $screens[ $screen_num ];

    # screen tiles
    if ( scalar( @{$screen->{'btiles'}} ) ) {
        push @c_lines, sprintf( "// Screen '%s' btile data\n", $screen->{'name'} );
        push @c_lines, sprintf( "struct btile_pos_s screen_%s_btile_pos[ %d ] = {\n",
            $screen->{'name'},
            scalar( @{$screen->{'btiles'}} ) );
        push @c_lines, join( ",\n", map {
                sprintf("\t{ TT_%s, %d, %d, &btile_%s, %s }", uc($_->{'type'}), $_->{'row'}, $_->{'col'}, $_->{'btile'}, ( $_->{'active'} ? 'F_BTILE_ACTIVE' : 0 ) )
            } @{$screen->{'btiles'}} );
        push @c_lines, "\n};\n\n";
    }

    # screen enemies
    if ( scalar( @{$screen->{'enemies'}} ) ) {
        push @c_lines, sprintf( "// Screen '%s' enemy data\n", $screen->{'name'} );
        push @c_lines, sprintf( "struct enemy_info_s screen_%s_enemies[ %d ] = {\n",
            $screen->{'name'},
            scalar( @{$screen->{'enemies'}} ) );
        push @c_lines, join( ",\n", map {
                sprintf( "\t{ %s, %d, %s, { { %d, %d }, { %d, %d, %d, %d } }, { %d, %d, %d, %d }, { %s, %d, %d, .data.%s={ %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d } }, %s }",
                    # SP1 sprite pointer, will be initialized later
                    'NULL',

                    # index into global sprite graphics table
                    $sprite_name_to_index{ $_->{'sprite'} },

                    # color for the sprite
                    $_->{'color'},

                    # animation_data: delay_data values
                    $_->{'animation_delay'}, ( $_->{'sequence_delay'} || 0 ),
                    # animation_data: current values (initial)
                    # sequence number
                    $sprites[ $sprite_name_to_index{ $_->{'sprite'} } ]{'sequence_name_to_index'}{ $_->{'initial_sequence'} },
                    0,0,0, # sequence_counter, frame_delay_counter, sequence_delay_counter: will be initialized later

                    # position_data
                    0,0,0,0,				# position gets reset on initialization

                    # movement_data
                    sprintf( 'ENEMY_MOVE_%s', uc( $_->{'movement'} ) ),	# movement type
                    $_->{'speed_delay'},
                    0,				# initial delay counter
                    lc( $_->{'movement'} ),
                    $_->{'xmin'}, $_->{'xmax'},
                    $_->{'ymin'}, $_->{'ymax'},
                    $_->{'dx'}, $_->{'dy'},
                    $_->{'initx'}, $_->{'inity'},
                    $_->{'dx'}, $_->{'dy'},
                    $sprites[ $sprite_name_to_index{ $_->{'sprite'} } ]{'sequence_name_to_index'}{ $_->{'sequence_a'} },
                    $sprites[ $sprite_name_to_index{ $_->{'sprite'} } ]{'sequence_name_to_index'}{ $_->{'sequence_b'} },

                    # initial flags
                    $_->{'initial_flags'},
                 )
            } @{$screen->{'enemies'}} );
        push @c_lines, "\n};\n\n";
    }

    # screen items
    if ( scalar( @{$screen->{'items'}} ) ) {
        push @c_lines, sprintf( "// Screen '%s' item data\n", $screen->{'name'} );
        push @c_lines, sprintf( "struct item_location_s screen_%s_items[ %d ] = {\n",
            $screen->{'name'},
            scalar( @{$screen->{'items'}} ) );
        push @c_lines, join( ",\n", map {	# real item id is 0x1 << item_index
                sprintf( "\t{ %d, %d, %d }", $_->{'item_index'}, $_->{'row'}, $_->{'col'} )
            } @{$screen->{'items'}} );
        push @c_lines, "\n};\n\n";
    }

    # hot zones
    if ( scalar( @{$screen->{'hotzones'}} ) ) {
        push @c_lines, sprintf( "// Screen '%s' hot zone data\n", $screen->{'name'} );
        push @c_lines, sprintf( "struct hotzone_info_s screen_%s_hotzones[ %d ] = {\n",
            $screen->{'name'},
            scalar( @{$screen->{'hotzones'}} ) );
        push @c_lines, join( ",\n", map {
                my $x    = ( defined( $_->{'x'} ) ? $_->{'x'} : $_->{'col'} * 8 );
                my $y    = ( defined( $_->{'y'} ) ? $_->{'y'} : $_->{'row'} * 8 );
                my $xmax = $x + ( defined( $_->{'pix_width'} ) ? $_->{'pix_width'} : $_->{'width'} * 8 ) - 1;
                my $ymax = $y + ( defined( $_->{'pix_height'} ) ? $_->{'pix_height'} : $_->{'height'} * 8 ) - 1;
                sprintf( "\t{ .position = { %d, %d, %d, %d }, %s }",
                    $x, $y, $xmax, $ymax,
                    ( $_->{'active'} ? 'F_HOTZONE_ACTIVE' : 0 ),
                )
            } @{ $screen->{'hotzones'} } );
        push @c_lines, "\n};\n\n";
    }

}

###################################
## Hero functions
###################################

sub validate_and_compile_hero {
    my $hero = shift;
    defined( $hero->{'name'} ) or
        die "Hero has no NAME\n";
    defined( $hero->{'sprite'} ) or
        die "Hero has no SPRITE\n";
    defined( $hero->{'sequence_up'} ) or
        die "Hero has no SEQUENCE_UP\n";
    defined( $hero->{'sequence_down'} ) or
        die "Hero has no SEQUENCE_DOWN\n";
    defined( $hero->{'sequence_left'} ) or
        die "Hero has no SEQUENCE_LEFT\n";
    defined( $hero->{'sequence_right'} ) or
        die "Hero has no SEQUENCE_RIGHT\n";
    defined( $hero->{'animation_delay'} ) or
        die "Hero has no ANIMATION_DELAY\n";
    defined( $hero->{'lives'} ) or
        die "Hero has no LIVES\n";
    defined( $hero->{'hstep'} ) or
        die "Hero has no HSTEP\n";
    defined( $hero->{'vstep'} ) or
        die "Hero has no VSTEP\n";
}

sub generate_hero {
    my $num_lives 	= $hero->{'lives'}{'num_lives'};
    my $lives_tile	= $hero->{'lives'}{'btile'};
    my $sprite		= $hero->{'sprite'};
    my $num_sprite	= $sprite_name_to_index{ $hero->{'sprite'} };
    my $sequence_up	= $sprites[ $num_sprite ]{'sequence_name_to_index'}{ $hero->{'sequence_up'} };
    my $sequence_down	= $sprites[ $num_sprite ]{'sequence_name_to_index'}{ $hero->{'sequence_down'} };
    my $sequence_left	= $sprites[ $num_sprite ]{'sequence_name_to_index'}{ $hero->{'sequence_left'} };
    my $sequence_right	= $sprites[ $num_sprite ]{'sequence_name_to_index'}{ $hero->{'sequence_right'} };
    my $delay		= $hero->{'animation_delay'};
    my $hstep		= $hero->{'hstep'};
    my $vstep		= $hero->{'vstep'};
    push @h_lines, <<EOF_HERO1
/////////////////////////////
// Hero definition
/////////////////////////////

#define	HERO_SPRITE_NUM_GRAPHIC		$num_sprite
#define	HERO_SPRITE_SEQUENCE_UP		$sequence_up
#define	HERO_SPRITE_SEQUENCE_DOWN	$sequence_down
#define	HERO_SPRITE_SEQUENCE_LEFT	$sequence_left
#define	HERO_SPRITE_SEQUENCE_RIGHT	$sequence_right
#define	HERO_SPRITE_ANIMATION_DELAY	$delay
#define	HERO_MOVE_HSTEP			$hstep
#define	HERO_MOVE_VSTEP			$vstep
#define	HERO_NUM_LIVES			$num_lives
#define	HERO_LIVES_BTILE		(btile_${lives_tile})

EOF_HERO1
;
}

sub generate_bullets {
    my $max_bullets = $hero->{'bullet'}{'max_bullets'};
    push @c_lines, <<EOF_BULLET4
//////////////////////////////
// Bullets definition
//////////////////////////////

struct bullet_state_data_s bullet_state_data[ $max_bullets ] = {
EOF_BULLET4
;

    push @c_lines, join( ",\n", ( "\t{ NULL, { 0, 0, 0, 0 }, 0, 0, 0, 0 }" ) x 4 );
    push @c_lines, "\n};\n\n";
}

########################
## Item functions
########################

sub generate_items {
    push @c_lines, <<EOF_ITEMS1
///////////////////////
// Global items table
///////////////////////

struct item_info_s all_items[16] = {
EOF_ITEMS1
;
    push @c_lines, join( ",\n",
        map {
            exists( $all_items->{ $_ } ) ?
                sprintf( "\t{ \"%s\", &btile_%s, 0x%04x, F_ITEM_ACTIVE }",
                    $all_items->{ $_ }{'name'},
                    $all_items->{ $_ }{'btile'},
                    ( 0x1 << $all_items->{ $_ }{'item_index'} )
                    ) :
                "\t{ NULL, NULL, 0, 0 }"
            } ( 0 .. 15 )
    );

    push @c_lines, <<EOF_ITEMS2

};

EOF_ITEMS2
;

}

sub generate_game_functions {
    push @h_lines, "// game config\n";

    push @h_lines, join( "\n", 
        map {
            sprintf( "void %s(void);", $game_config->{'game_functions'}{ $_ } )
        } keys %{ $game_config->{'game_functions'} } );
    push @h_lines, "\n\n";

    push @h_lines, join( "\n", 
        map {
            sprintf( "#define RUN_GAME_FUNC_%-18s (%s)", uc($_), $game_config->{'game_functions'}{ $_ } )
        } keys %{ $game_config->{'game_functions'} }
    );

    push @h_lines, "\n\n";
}

sub generate_game_areas {
    # output game areas
    push @c_lines, "// screen areas\n";
    push @c_lines, "\n" . join( "\n", map {
        sprintf( "struct sp1_Rect %s = { %s_TOP, %s_LEFT, %s_WIDTH, %s_HEIGHT };",
            $_, ( uc( $_ ) ) x 4 )
        } qw( game_area lives_area inventory_area debug_area )
    ) . "\n";

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
                warn sprintf( "Screen '%s': undefined sprite '%s'\n", $screen->{'name'}, $sprite->{'name'} );
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
            if ( not defined( $btile->{'btile'} ) ) {
                warn sprintf( "Screen '%s': %s has no associated btile attribute\n", $screen->{'name'}, $btile->{'type'} );
                $errors++;
                next;
            }
            if ( not $is_valid_btile{ $btile->{'btile'} } ) {
                warn sprintf( "Screen '%s': undefined btile '%s'\n", $screen->{'name'}, $btile->{'btile'} );
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
                warn sprintf( "Screen '%s': undefined btile for item '%s'\n", $screen->{'name'}, $item->{'name'} );
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

# this function is called from main
sub run_consistency_checks {
    my $errors = 0;
    $errors += check_screen_sprites_are_valid;
    $errors += check_screen_btiles_are_valid;
    $errors += check_screen_items_are_valid;
    die sprintf( "*** %d errors were found in configuration\n", $errors )
        if ( $errors );
}

#############################
## General Output Functions
#############################

sub generate_c_header {
    push @c_lines, <<EOF_HEADER
///////////////////////////////////////////////////////////
//
// Game data - automatically generated with datagen.pl
//
///////////////////////////////////////////////////////////

#include <arch/spectrum.h>

#include "rage1/map.h"
#include "rage1/sprite.h"
#include "rage1/debug.h"
#include "rage1/hero.h"
#include "rage1/game_state.h"
#include "rage1/bullet.h"
#include "rage1/enemy.h"

#include "game_data.h"

EOF_HEADER
;
}

sub generate_tiles {
    push @c_lines, <<EOF_TILES
////////////////////////////
// Big Tile definitions
////////////////////////////

EOF_TILES
;
    foreach my $tile ( @btiles ) { generate_btile( $tile ); }

}

sub generate_sprites {
    push @c_lines, <<EOF_SPRITES
////////////////////////////
// Sprite definitions
////////////////////////////

EOF_SPRITES
;
    foreach my $sprite ( @sprites ) { generate_sprite( $sprite ); }

    # output global sprite graphics table
    my $num_sprites = scalar( @sprites );
    push @c_lines, "// Global sprite graphics table\n";
    push @c_lines, "struct sprite_graphic_data_s all_sprite_graphics[ $num_sprites ] = {\n\t";
    push @c_lines, join( ",\n\n\t", map {
        my $sprite = $_;
        sprintf( "{ .width = %d, .height = %d,\n\t.frame_data.num_frames = %d,\n\t.frame_data.frames = &sprite_%s_frames[0],\n\t.sequence_data.num_sequences = %d,\n\t.sequence_data.sequences = %s }",
            $_->{'cols'} * 8, $_->{'rows'} * 8,
            $_->{'frames'}, $_->{'name'},
            scalar( @{ $sprite->{'sequences'} } ),	# number of animation sequences
            ( scalar( @{ $sprite->{'sequences'} } ) ? sprintf( "&sprite_%s_sequences[0]", $_->{'name'}) : 'NULL' ) ),
    } @sprites );
    push @c_lines, "\n};\n\n";
}

sub generate_screens {
    push @c_lines, <<EOF_SCREENS
////////////////////////////
// Screen definitions
////////////////////////////

EOF_SCREENS
;
    foreach my $screen_num ( 0 .. ( scalar( @screens ) - 1 ) ) { generate_screen( $screen_num ); }
    
}

sub generate_map {
    # output global map data structure
    push @c_lines, <<EOF_MAP
////////////////////////////
// Map definition
////////////////////////////

// main game map
EOF_MAP
;
    push @c_lines, sprintf( "struct map_screen_s map[ MAP_NUM_SCREENS ] = {\n" );

    push @c_lines, join( ",\n", map {
            sprintf( "\t// Screen '%s'\n\t{\n", $_->{'name'} ) .
            sprintf( "\t\t.btile_data = { %d, %s },\t// btile_data\n",
                scalar( @{$_->{'btiles'}} ), ( scalar( @{$_->{'btiles'}} ) ? sprintf( 'screen_%s_btile_pos', $_->{'name'} ) : 'NULL' ) ) .
            sprintf( "\t\t.enemy_data = { %d, %s },\t// enemy_data\n",
                scalar( @{$_->{'enemies'}} ), ( scalar( @{$_->{'enemies'}} ) ? sprintf( 'screen_%s_enemies', $_->{'name'} ) : 'NULL' ) ) .
            sprintf( "\t\t.hero_data = { %d, %d },\t// hero_data\n",
                $_->{'hero'}{'startup_xpos'}, $_->{'hero'}{'startup_ypos'} ) .
            sprintf( "\t\t.item_data = { %d, %s },\t// item_data\n",
                scalar( @{$_->{'items'}} ), ( scalar( @{$_->{'items'}} ) ? sprintf( 'screen_%s_items', $_->{'name'} ) : 'NULL' ) ) .
            sprintf( "\t\t.hotzone_data = { %d, %s },\t// hotzone_data\n",
                scalar( @{$_->{'hotzones'}} ), ( scalar( @{$_->{'hotzones'}} ) ? sprintf( 'screen_%s_hotzones', $_->{'name'} ) : 'NULL' ) ) .
            ( defined( $_->{'background'} ) ?
                sprintf( "\t\t.background_data = { %s, %d, { %d, %d, %d, %d } },\t// background_data\n",
                    sprintf( "&btile_%s", $_->{'background'}{'btile'} ),
                    ( defined( $_->{'background'}{'probability'} ) ? $_->{'background'}{'probability'} : 255 ),
                    $_->{'background'}{'row'}, $_->{'background'}{'col'},
                    $_->{'background'}{'width'}, $_->{'background'}{'height'}
                ) :
                "\t\t.background_data = { NULL, 0, { 0,0,0,0 } },\t// background_data\n" ) .
            "\t\t.flow_data.rule_tables.enter_screen = { 0, NULL },\n" .
            "\t\t.flow_data.rule_tables.exit_screen = { 0, NULL },\n" .
            "\t\t.flow_data.rule_tables.game_loop = { 0, NULL },\n" .
            "\t}"
        } @screens );
    push @c_lines, "\n};\n\n";
}

sub generate_bullet_sprites_initialization {
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
    push @c_lines, <<EOF_BULLET1
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
    push @c_lines, sprintf( "\tbullet_state_data[i].sprite = bs = sp1_CreateSpr(SP1_DRAW_MASK2LB, SP1_TYPE_2BYTE, %d, %d, %d );\n",
        $sprite->{'rows'} + 1,	# height in chars including blank bottom row
        0,				# left column graphic offset
        0,				# plane
    );
    foreach my $ac ( 1 .. ($sprite->{'cols'} - 1) ) {
        push @c_lines, sprintf( "\tsp1_AddColSpr(bs, SP1_DRAW_MASK2, %d, %d, %d );\n",
            0,					# type
            ( $sprite->{'rows'} + 1 ) * 16 * $ac,	# nth column graphic offset
            0,					# plane
        );
    }
    push @c_lines, sprintf( "\tsp1_AddColSpr(bs, SP1_DRAW_MASK2RB, 0, 0, 0);\n" );	# empty rightmost column

    # optimize SP1 for xthresh and vthresh
    if ( defined( $sprite->{'real_pixel_width'} ) ) {
        my $xthresh = ( 8 - ( $sprite->{'real_pixel_width'} % 8 ) + 1 ) % 8;
        if ( $xthresh > 1 ) {
            push @c_lines, sprintf( "\tbs->xthresh = %d;\n", $xthresh );
        }
    }
    if ( defined( $sprite->{'real_pixel_height'} ) ) {
        my $ythresh = ( 8 - ( $sprite->{'real_pixel_height'} % 8 ) + 1 ) % 8;
        if ( $ythresh > 1 ) {
            push @c_lines, sprintf( "\tbs->ythresh = %d;\n", $ythresh );
        }
    }

    push @c_lines, <<EOF_BULLET6
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

sub generate_h_header {
    push @h_lines, <<GAME_DATA_H_1
#ifndef _GAME_DATA_H
#define _GAME_DATA_H

#include <stdint.h>
#include <games/sp1.h>

GAME_DATA_H_1
;
}

sub generate_h_ending {
    push @h_lines, <<GAME_DATA_H_3
#endif // _GAME_DATA_H
GAME_DATA_H_3
;
}

sub generate_header_file {
    my $num_screens = scalar( @screens );
    my $max_items = scalar( keys %$all_items );
    my $all_items_mask = 0;
    my $mask = 1;
    foreach my $i ( 1 .. $max_items ) {
        $all_items_mask += $mask;
        $mask <<= 1;
    }

    push @h_lines, <<GAME_DATA_H_2
// global map data structure - autogenerated by datagen tool into
// game_data.c
#define MAP_NUM_SCREENS $num_screens
extern struct map_screen_s map[];

// global items table
#define INVENTORY_MAX_ITEMS $max_items
#define INVENTORY_ALL_ITEMS_MASK $all_items_mask
extern struct item_info_s all_items[];

// a pre-filled hero_info_s struct for game reset
// generated by datagen.pl in game_data.c
extern struct hero_info_s hero_startup_data;

void init_bullet_sprites(void);

// auxiliary pointers
GAME_DATA_H_2
;

    # output auxiliary data pointers
    foreach my $btile ( @btiles ) {
        push @h_lines, sprintf( "extern struct btile_s btile_%s;\n", $btile->{'name'} );
    }
    foreach my $sprite ( @sprites ) {
        push @h_lines, sprintf( "extern uint8_t sprite_%s_data[];\n", $sprite->{'name'} );
        push @h_lines, sprintf( "extern uint8_t *sprite_%s_frames[];\n", $sprite->{'name'} );
    }

    push @h_lines, "\n// game configuration data\n";
    push @h_lines, sprintf( "#define MAP_INITIAL_SCREEN %d\n", $screen_name_to_index{ $game_config->{'screen'}{'initial'} } );
    push @h_lines, sprintf( "#define DEFAULT_BG_ATTR ( %s )\n", $game_config->{'default_bg_attr'} );

    push @h_lines, "\n// sound effect constants\n";
    foreach my $effect ( keys %{$game_config->{'sounds'}} ) {
        push @h_lines, sprintf( "#define SOUND_%s %s\n", uc( $effect ), $game_config->{'sounds'}{ $effect } );
    }

    # output definitions for screen areas
    push @h_lines, "\n" . join( "\n", map {
            "// " .uc( $_ ). " definitions\n" .
            sprintf( "#define %s_TOP	%d\n", uc( $_ ), $game_config->{ $_ }{'top'} ) .
            sprintf( "#define %s_LEFT	%d\n", uc( $_ ), $game_config->{ $_ }{'left'} ) .
            sprintf( "#define %s_BOTTOM	%d\n", uc( $_ ), $game_config->{ $_ }{'bottom'} ) .
            sprintf( "#define %s_RIGHT	%d\n", uc( $_ ), $game_config->{ $_ }{'right'} ) .
            sprintf( "#define %s_WIDTH	( %s_RIGHT - %s_LEFT + 1 )\n", uc( $_ ), uc( $_ ), uc( $_ ) ) .
            sprintf( "#define %s_HEIGHT	( %s_BOTTOM - %s_TOP + 1 )\n", uc( $_ ), uc( $_ ), uc( $_ ) ) .
            sprintf( "extern struct sp1_Rect %s;\n", $_ )
        } qw( game_area lives_area inventory_area debug_area )
    );

}

# this function is called from main
sub generate_game_data {

    # generate header lines for all output files
    generate_c_header;
    generate_h_header;

    # generate data - each function is free to add lines to the .c or .h
    # file
    generate_tiles;
    generate_sprites;
    generate_screens;
    generate_map;
    generate_hero;
    generate_bullets;
    generate_bullet_sprites_initialization;
    generate_items;
    generate_game_areas;

    generate_header_file;
    generate_game_functions;

    # generate ending lines if needed
    generate_h_ending;
}

sub output_game_data {
    my $output_fh;

    # output .c file
    open( $output_fh, ">", $c_file ) or
        die "Could not open $c_file for writing\n";
    print $output_fh join( "", @c_lines );
    close $output_fh;

    # output .h file
    open( $output_fh, ">", $h_file ) or
        die "Could not open $h_file for writing\n";
    print $output_fh join( "", @h_lines );
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
generate_game_data;
output_game_data;

# dump internal data if required to do so
dump_internal_data
    if ( $opt_c );
