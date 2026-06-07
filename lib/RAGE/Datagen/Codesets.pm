package RAGE::Datagen::Codesets;

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
## RAGE::Datagen::Codesets — the home/banked C headers, the global codeset
## data + per-codeset headers and function tables, the custom-function tables,
## the binary-data items and the tracker (songs / sound-effects) emitters, for
## datagen (Task 6, Stage 2 extraction).  Moved verbatim from tools/datagen.pl;
## the only edits are the mechanical scaffold bindings: the shared globals are
## reached via their RAGE::Datagen::Context aliases ($main::game_config,
## @main::c_game_data_lines, @main::h_game_data_lines, @main::c_banked_data_128_lines,
## @main::c_tracker_cpc_lines, $main::c_dataset_lines, $main::asm_dataset_lines,
## $main::c_codeset_lines, $main::asm_codeset_lines, %main::dataset_dependency,
## %main::codeset_functions_by_codeset, @main::all_codeset_functions,
## @main::codeset_valid_banks, @main::check_custom_functions,
## @main::action_custom_functions, $main::dataset_base_address,
## $main::codeset_base_address and $main::build_dir).
##
## file_to_bytes, file_to_compressed_bytes (RAGE::FileUtils) and
## arkos2_convert_song_to_asm, arkos2_convert_effects_to_asm,
## arkos2_count_sound_effects (RAGE::Arkos2) are loaded into main:: by datagen.pl
## (those modules have no `package` line), so they are called as main::NAME().
## uniq (List::MoreUtils), basename (File::Basename) and move / copy (File::Copy)
## are imported here.  Behaviour (and emitted bytes) is unchanged.
##
## Exported: generate_c_home_header, generate_c_banked_header,
## generate_c_banked_data_128_header, generate_global_codeset_data,
## generate_codeset_headers, generate_codeset_functions,
## generate_custom_function_tables, generate_binary_data_items,
## generate_tracker_data.  all_codesets_except_home is module-private (only
## called by generate_codeset_headers and generate_codeset_functions).
##
################################################################################

use strict;
use warnings;
use utf8;

# scaffold aliases (RAGE::Datagen::Context) populated at runtime by datagen.pl;
# silence the benign "used only once" check for these main:: globals.
no warnings 'once';

use List::MoreUtils qw( uniq );
use File::Basename;
use File::Copy;

use Exporter 'import';
our @EXPORT_OK = qw(
    generate_c_home_header generate_c_banked_header
    generate_c_banked_data_128_header generate_global_codeset_data
    generate_codeset_headers generate_codeset_functions
    generate_custom_function_tables generate_binary_data_items
    generate_tracker_data
);

sub generate_c_home_header {
    push @main::c_game_data_lines, <<EOF_HEADER

//////////////////////////////////////////////////////////////////////////
//
// Game data for the Home bank - automatically generated with datagen.pl
//
//////////////////////////////////////////////////////////////////////////

// G7: route the ZX <arch/spectrum.h> through the platform shim (byte-identical
// on ZX; provides inert INK_/PAPER_ on CPC).  <sound/bit.h> (ZX beeper BEEPFX_*
// constants) is ZX-only — guard it for CPC (CPC audio is Phase AU4).
#include "rage1/platform.h"
#if defined( BUILD_FEATURE_PLATFORM_ZX48 ) || defined( BUILD_FEATURE_PLATFORM_ZX128 )
#include <sound/bit.h>
#endif
#include "rage1/gfx.h"

#include "rage1/inventory.h"
#include "rage1/game_state.h"
#include "rage1/codeset.h"

#include "game_data.h"

EOF_HEADER
;
}

sub generate_c_banked_header {
    my $dataset	= shift;

    my $num_btiles	= scalar( @{ $main::dataset_dependency{ $dataset }{'btiles'} } );
    my $num_sprites	= scalar( @{ $main::dataset_dependency{ $dataset }{'sprites'} } );
    my $num_flow_rules	= scalar( @{ $main::dataset_dependency{ $dataset }{'rules'} } );
    my $num_screens	= scalar( @{ $main::dataset_dependency{ $dataset }{'screens'} } );

    my $all_btiles_ptr		= ( $num_btiles ?	'_all_btiles'		: '0' );
    my $all_sprites_ptr		= ( $num_sprites ?	'_all_sprite_graphics'	: '0' );
    my $all_flow_rules_ptr	= ( $num_flow_rules ?	'_all_flow_rules'	: '0' );
    my $all_screens_ptr		= ( $num_screens ?	'_all_screens'		: '0' );

    if ( $dataset =~ /^\d+$/ ) {
        push @{ $main::c_dataset_lines->{ $dataset } }, <<EOF_HEADER
///////////////////////////////////////////////////////////////////////////
//
// Game data for the High banks - automatically generated with datagen.pl
//
////////////////////////////////&//////////////////////////////////////////

// G7: route the ZX <arch/spectrum.h> through the platform shim (byte-identical
// on ZX; provides inert INK_/PAPER_ on CPC).  <sound/bit.h> (ZX beeper BEEPFX_*
// constants) is ZX-only — guard it for CPC (CPC audio is Phase AU4).
#include "rage1/platform.h"
#if defined( BUILD_FEATURE_PLATFORM_ZX48 ) || defined( BUILD_FEATURE_PLATFORM_ZX128 )
#include <sound/bit.h>
#endif

#include "rage1/map.h"
#include "rage1/sprite.h"
#include "rage1/debug.h"
#include "rage1/hero.h"
#include "rage1/game_state.h"
#include "rage1/bullet.h"
#include "rage1/enemy.h"
#include "rage1/flow.h"
#include "rage1/dataset.h"

// This _must_ be included - Datasets may reference assets from the home dataset!
#include "game_data.h"

EOF_HEADER
;

        push @{ $main::asm_dataset_lines->{ $dataset } }, <<EOF_HEADER
        org	$main::dataset_base_address
EOF_HEADER
;
    }

    push @{ $main::asm_dataset_lines->{ $dataset } }, <<EOF_HEADER2
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Asset index for this bank - This structure must be the first data item
;; generated in the bank: it contains pointers to the rest of the bank data
;; items!
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

        section	data_compiler

extern	_all_btiles
extern	_all_sprite_graphics
extern	_all_flow_rules
extern	_all_screens

public	_all_assets_dataset_$dataset

_all_assets_dataset_$dataset:
    dw	$num_btiles		;; .num_btiles
    dw	$all_btiles_ptr		;; .all_btiles
    db	$num_sprites		;; .num_sprite_graphics
    dw	$all_sprites_ptr	;; .all_sprite_graphics
    db	$num_flow_rules		;; .num_flow_rules
    dw	$all_flow_rules_ptr	;; .all_flow_rules
    db	$num_screens		;; .num_screens
    dw	$all_screens_ptr	;; .all_screens

EOF_HEADER2
;
}

## CODESET information
sub generate_global_codeset_data {
    push @main::h_game_data_lines, <<EOF_CODESET_1

//////////////////////////////////////////
// CODESET DEFINITIONS
//////////////////////////////////////////

EOF_CODESET_1
;
    push @main::h_game_data_lines, sprintf( "#define	NUM_CODESETS	%d\n\n", scalar( grep { "$_" ne 'home' } keys %main::codeset_functions_by_codeset ) );
    push @main::c_game_data_lines, <<EOF_CODESET_3

//////////////////////////////////////////
// CODESET DEFINITIONS
//////////////////////////////////////////

EOF_CODESET_3
;

    my @non_home_codeset_functions = grep { $_->{'codeset'} ne 'home' } @main::all_codeset_functions;

    if ( scalar( @non_home_codeset_functions ) and ( $main::game_config->{'zx_target'} ne '48' ) ) {
        push @main::c_game_data_lines, "// global codeset functions table\n";
        push @main::h_game_data_lines, "// global indexes of codeset functions\n";

        push @main::c_game_data_lines, sprintf( "struct codeset_function_info_s all_codeset_functions[ %d ] = { \n",
            scalar( @non_home_codeset_functions )
        );
        my $index = 0;
        foreach my $function ( @non_home_codeset_functions ) {
            push @main::c_game_data_lines,  sprintf( "\t{ .bank_num = %d, .local_function_num = %d },\n",
                $main::codeset_valid_banks[ $function->{'codeset'} ],
                $function->{'local_index'},
            );
            push @main::h_game_data_lines, sprintf( "#define CODESET_FUNCTION_%s	(%d)\n",
                uc( $function->{'name'} ),
                $index,
            );
            $index++;
        }
        push @main::c_game_data_lines, "};\n";
        push @main::h_game_data_lines, "\n";
    } else {
        push @main::c_game_data_lines, "// No codesets defined\n";
        push @main::h_game_data_lines, "// No codesets defined\n";
    }

    # Add the function call macros to the global game_data header file.
    # All codeset functions must be called via call macros.  If in 128K
    # mode, they will generate a call to codeset_call_function(), and if in
    # 48K mode they will be resolved to a regular function call

    push @main::h_game_data_lines, "// codeset function call macros for each function\n";
    foreach my $function ( @main::all_codeset_functions ) {
        my $macro;
        if ( ( $main::game_config->{'zx_target'} eq '48' ) or ( $function->{'codeset'} eq 'home' ) ) {
            # macros for 48K mode
            push @main::h_game_data_lines, sprintf(
                "#define CALL_CODESET_FUNCTION_%-30s  (%s())\n",
                uc( $function->{'name'} ) . '()',
                $function->{'name'},
            );
        } else {
            # macros for 128K mode
            push @main::h_game_data_lines, sprintf(
                "#define CALL_CODESET_FUNCTION_%-30s  (codeset_call_function( CODESET_FUNCTION_%s ))\n",
                uc( $function->{'name'} ) . '()',
                uc( $function->{'name'} ),
            );
        }
        $function->{'codeset_function_call_macro'} = sprintf(
            'CALL_CODESET_FUNCTION_%s()', uc( $function->{'name'} )
        );
    }

    push @main::h_game_data_lines, <<EOF_CODESET_2

//////////////////////////////////////////
// END OF CODESET DEFINITIONS
//////////////////////////////////////////

EOF_CODESET_2
;

    push @main::c_game_data_lines, <<EOF_CODESET_4

//////////////////////////////////////////
// END OF CODESET DEFINITIONS
//////////////////////////////////////////

EOF_CODESET_4
;
}

sub all_codesets_except_home {
    # codesets used by functions
    my @function_codesets = grep { "$_" ne 'home' } keys %main::codeset_functions_by_codeset;

    # codesets used by binary items
    my @blob_codesets = grep { "$_" ne 'home' } map { $_->{'codeset'} } @{ $main::game_config->{'binary_data'} };

    # all unique codesets except 'home'
    my @all_codesets = uniq @function_codesets, @blob_codesets;

#    print Dumper( \@all_codesets );
    return @all_codesets;
}

sub generate_codeset_headers {

    foreach my $codeset ( all_codesets_except_home ) {

        # add the needed source lines to the C and ASM files for this
        # codeset: the main codeset_assets_s struct at the beginning, the
        # function table and e.g.  tiles used by these functions
        push @{ $main::asm_codeset_lines->{ $codeset } }, <<EOF_CODESET_LINES_MAIN_ASM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; We need this ASM file to force the linking of the codeset_assets_s
;; structure exactly at start of the binary (0xC000)
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

	section	code_compiler
	org	$main::codeset_base_address

extern	_codeset_functions
public	_all_codeset_assets

_all_codeset_assets:
	dw	0			;; .game_state
	dw	0			;; .banked_assets
	dw	0			;; .home_assets
EOF_CODESET_LINES_MAIN_ASM
;

        push @{ $main::c_codeset_lines->{ $codeset } }, <<EOF_CODESET_LINES_MAIN
#include <stdlib.h>

#include "features.h"

#include "rage1/codeset.h"

#include "game_data.h"

EOF_CODESET_LINES_MAIN
;

    }
}

sub generate_codeset_functions {

    # If in 128K mode, for each codeset except 'home' codeset we create the
    # needed data structures.  If we are in 48K mode, there will be no
    # codesets besides 'home' so this will not run
    foreach my $codeset ( all_codesets_except_home ) {
        next if not defined( $main::codeset_functions_by_codeset{ $codeset } );
        my $num_codeset_functions = scalar( @{ $main::codeset_functions_by_codeset{ $codeset } } );
        if ( $num_codeset_functions ) {
            # add extern codeset function declarations
            push @{ $main::c_codeset_lines->{ $codeset } }, "// codeset functions table\n";
            foreach my $function ( @{ $main::codeset_functions_by_codeset{ $codeset } } ) {
                push @{ $main::c_codeset_lines->{ $codeset } }, sprintf( "extern void %s( void );\n", $function->{'name'} );
            }

            # add the codeset function table
            push @{ $main::asm_codeset_lines->{ $codeset } }, "	db	$num_codeset_functions			;; .num_functions\n";
            push @{ $main::asm_codeset_lines->{ $codeset } }, "	dw	_codeset_functions	;; .functions\n";
            push @{ $main::c_codeset_lines->{ $codeset } }, "codeset_function_t codeset_functions[ $num_codeset_functions ] = {\n";
            foreach my $function ( @{ $main::codeset_functions_by_codeset{ $codeset } } ) {
                push @{ $main::c_codeset_lines->{ $codeset } }, sprintf( "\t&%s,\n", $function->{'name'} );
            }
            push @{ $main::c_codeset_lines->{ $codeset } }, "};\n\n";
        }
    }
}

sub generate_custom_function_tables {
    # generate 'custom' type check function prototypes ('home' codeset)
    if ( scalar( @main::check_custom_functions ) ) {

        push @main::h_game_data_lines, "// Check custom functions table\n";
        push @main::h_game_data_lines, "extern check_custom_function_t check_custom_functions[];\n\n";
        push @main::h_game_data_lines, "// Check custom function prototypes\n";

        push @main::c_game_data_lines, "// Check custom functions table\n";
        push @main::c_game_data_lines, sprintf( "check_custom_function_t check_custom_functions[ %d ] = {\n",
            scalar( @main::check_custom_functions )
        );
        foreach my $f ( @main::check_custom_functions ) {
            # all check functions must accept a single 1-byte param, even if they ignore it
            push @main::h_game_data_lines, sprintf( "uint8_t %s( %s );\n", $f->{'function'}, 'uint8_t param' );
            push @main::c_game_data_lines, sprintf( "\t%s,\n", $f->{'function'} );
        }
        push @main::h_game_data_lines, "\n";
        push @main::c_game_data_lines, "};\n\n";
    }
    # generate 'custom' type action function prototypes ('home' codeset)
    if ( scalar( @main::action_custom_functions ) ) {

        push @main::h_game_data_lines, "// Action custom functions table\n";
        push @main::h_game_data_lines, "extern action_custom_function_t action_custom_functions[];\n\n";
        push @main::h_game_data_lines, "// Action custom function prototypes\n";

        push @main::c_game_data_lines, "// Action custom function table\n";
        push @main::c_game_data_lines, sprintf( "action_custom_function_t action_custom_functions[ %d ] = {\n",
            scalar( @main::action_custom_functions )
        );
        foreach my $f ( @main::action_custom_functions ) {
            push @main::h_game_data_lines, sprintf( "void %s( %s );\n", $f->{'function'}, ( $f->{'uses_param'} ? 'uint8_t param' : 'void' ) );
            push @main::c_game_data_lines, sprintf( "\t%s,\n", $f->{'function'} );
        }
        push @main::h_game_data_lines, "\n";
        push @main::c_game_data_lines, "};\n\n";
    }
    # generate 'crumb_action' type function prototypes ('home' codeset)
    push @main::h_game_data_lines, "// Crumb actions functions table\n";
    foreach my $function ( grep { lc( $_->{'type'} ) eq 'crumb_action' } @{ $main::codeset_functions_by_codeset{'home'} } ) {
        push @main::h_game_data_lines, sprintf( "extern void %s(  struct crumb_info_s *c );\n", $function->{'name'} );
    }
}

sub generate_binary_data_items {
    # return if no binary_data instances
    return if ( not defined( $main::game_config->{'binary_data'} ) or not scalar( @{ $main::game_config->{'binary_data'} } ) );

    # general data
    push @main::h_game_data_lines, "// extern declarations for binary data items\n";
    push @main::c_game_data_lines, "//////////////////////////////////////////\n";
    push @main::c_game_data_lines, "// BINARY DATA ITEMS\n";
    push @main::c_game_data_lines, "//////////////////////////////////////////\n\n";

    # process each of the binary blobs and generate its code
    foreach my $item ( @{ $main::game_config->{'binary_data'} } ) {

        # first, generate .h and .c lines for the binary. Later we'll place them
        # where they belong, depending on 48 or 128 mode

        my ( @h_lines, @c_lines );
        # slurp binary data from file into byte list, taking COMPRESS into account
        my @bytes;
        if ( $item->{'compress'} ) {
            @bytes = main::file_to_compressed_bytes( "$main::build_dir/$item->{'file'}", $item->{'offset'}, $item->{'size'} );
        } else {
            @bytes = main::file_to_bytes( "$main::build_dir/$item->{'file'}", $item->{'offset'}, $item->{'size'} );
        }

        # generate extern declaration
        push @h_lines, sprintf( "extern uint8_t %s[];\n", $item->{'symbol'} );

        # generate data definition
        push @c_lines, sprintf( "// binary data item '%s'%s\n", $item->{'symbol'}, ( $item->{'compress'} ? ' (ZX0 compressed)': '' ) );
        push @c_lines, sprintf( "uint8_t %s[ %d ] = {\n", $item->{'symbol'}, scalar( @bytes ) );

        my @byte16_groups;	# group in 16-byte-or-less pieces for easier reading/checking
        push @byte16_groups, [ splice @bytes, 0, 16 ]  while @bytes;
        push @c_lines, join( ",\n", map { "\t" . join( ", ", map { sprintf( "0x%02x", $_ ) } @{ $_ } ) } @byte16_groups );

        push @c_lines, "\n};\n\n";

        # ...now place the generated code where it belongs
        if ( $main::game_config->{'zx_target'} eq '48' ) {
            # logic for 48K mode - easy, all into game_data.c and .h. CODESET setting is ignored
            push @main::h_game_data_lines, @h_lines;
            push @main::c_game_data_lines, @c_lines;
        } else {
            # logic for 128K mode - store the binary data into the specified CODESET or home if none specified
            my $codeset = defined( $item->{'codeset'} ) ? $item->{'codeset'} : 'home';
            push @main::h_game_data_lines, @h_lines;
            if ( $codeset eq 'home' ) {
                push @main::c_game_data_lines, @c_lines;
            } else {
                push @{ $main::c_codeset_lines->{ $codeset } }, @c_lines;
            }
        }
    }

    push @main::h_game_data_lines, "\n";
    push @main::c_game_data_lines, "//////////////////////////////////////////\n";
    push @main::c_game_data_lines, "// END OF BINARY DATA ITEMS\n";
    push @main::c_game_data_lines, "//////////////////////////////////////////\n";

}

sub generate_c_banked_data_128_header {
    push @main::c_banked_data_128_lines,<<EOF_BANKED_128_HEADING
#include <stdint.h>
#include <stdlib.h>

EOF_BANKED_128_HEADING
;
}

sub generate_tracker_data {
    # tracker songs
    if ( defined( $main::game_config->{'tracker'} ) ) {

        # AU5: on CPC-flat there is no banking. The song/FX byte-array .asm
        # files and the all_songs/all_sound_effects tables must land where the
        # cpc-flat build globs them: the song .asm into the top-level
        # generated/ dir ($(GENERATED_DIR)/*.asm) and the C table into
        # game_data_tracker_cpc.c ($(GENERATED_DIR)/*.c). On ZX128 they keep
        # going into generated/banked/128/ as before (byte-identical). $trk is
        # the C-table accumulator; $trk_dir is the song/FX .asm destination dir.
        # The .aks -> .asm conversion (lib/RAGE/Arkos2.pm) is TARGET-AGNOSTIC,
        # so ZX and CPC reference the SAME tracker_song_*.asm bytes (AU5-5).
        my $is_cpc = ( defined( $main::game_config->{'platform'} ) and
                       $main::game_config->{'platform'} =~ /^cpc/ );
        my $trk = $is_cpc ? \@main::c_tracker_cpc_lines : \@main::c_banked_data_128_lines;
        my $trk_dir = $is_cpc
            ? "$main::build_dir/generated"
            : "$main::build_dir/generated/banked/128";

        if ( $is_cpc ) {
            # CPC tracker data is its own top-level TU; give it a header.
            push @{ $trk }, "#include <stdint.h>\n";
            push @{ $trk }, "#include <stdlib.h>\n\n";
        }

        push @main::h_game_data_lines, "/////////////////////\n";
        push @main::h_game_data_lines, "// Tracker songs\n";
        push @main::h_game_data_lines, "/////////////////////\n\n";

        push @{ $trk }, "//////////////////////////////////\n";
        push @{ $trk }, "// Tracker songs data and table\n";
        push @{ $trk }, "//////////////////////////////////\n\n";

        # output the songs data

        foreach my $song ( @{ $main::game_config->{'tracker'}{'songs'} } ) {
            my $symbol_name = "tracker_song_" . $song->{'name'};

            # generate extern declaration for later use in C file
            push @{ $trk }, sprintf( "extern uint8_t %s[];\n", $symbol_name );

            # generate song ID in header file
            push @main::h_game_data_lines, sprintf( "#define TRACKER_SONG_%s\t%d\n",
                uc( $song->{'name'} ), $song->{'song_index'} );

            # generate song ASM file and put it in place for compilation
            if ( $main::game_config->{'tracker'}{'type'} eq 'arkos2' ) {
                # for Arkos2, convert it into asm format with the official tool if it is in AKS format
                my $asm_file;
                if ( $song->{'file'} =~ m/\.asm$/i ) {
                    $asm_file = "$main::build_dir/$song->{'file'}";
                } elsif ( $song->{'file'} =~ m/\.aks$/i ) {
                    $asm_file = main::arkos2_convert_song_to_asm( "$main::build_dir/$song->{'file'}", $symbol_name );
                } else {
                    die "Arkos songs can only be in AKS or ASM format\n";
                }
                my $dest_asm_file = "$trk_dir/" . basename( $asm_file );
                move( $asm_file, $dest_asm_file ) or
                    die "Could not rename $asm_file to $dest_asm_file\n";
            }
            if ( $main::game_config->{'tracker'}{'type'} eq 'vortex2' ) {
                # vortex2 is ZX-only (rejected on CPC at validation); 128 path.
                # for Vortex2, copy the binary .PT3 file and add an ASM shim to include the binary as-is
                copy( "$main::build_dir/$song->{'file'}", "$main::build_dir/generated/banked/128" ) or
                    die "Could not copy $main::build_dir/$song->{'file'} to $main::build_dir/generated/banked/128\n";
                my $dest_asm_file = sprintf( "$main::build_dir/generated/banked/128/vortex2_song_%s.asm", $symbol_name );
                my $bin_basename = basename( "$main::build_dir/$song->{'file'}" );
                open ASM, ">$dest_asm_file" or
                    die "Could not write to $dest_asm_file\n";
                printf ASM "SECTION data_compiler\nPUBLIC _%s\n_%s:\nBINARY \"%s\"\n", $symbol_name, $symbol_name, $bin_basename;
                close ASM;
            }
        }
        if ( defined( $main::game_config->{'tracker'}{'in_game_song'} ) ) {
            push @main::h_game_data_lines, sprintf( "#define TRACKER_IN_GAME_SONG\tTRACKER_SONG_%s\n",
                uc( $main::game_config->{'tracker'}{'in_game_song'} ) );
        }

        # now output the songs table
        push @{ $trk }, "\n// songs table\n";
        push @{ $trk }, sprintf( "uint8_t *all_songs[ %d ] = {\n",
            scalar( @{ $main::game_config->{'tracker'}{'songs'} } ) );
        foreach my $song ( @{ $main::game_config->{'tracker'}{'songs'} } ) {
            my $symbol_name = "tracker_song_" . $song->{'name'};
            push @{ $trk }, sprintf( "\t&%s[0],\n", $symbol_name );
        }
        push @{ $trk }, "};\n";

        # output sound effects table and constants
        if ( defined( $main::game_config->{'tracker'}{'fxtable'} ) ) {
            # generate song ASM file and put it in place for compilation
            # the extern declaration for this is already in tracker.h
            my $asm_file;
            if ( $main::game_config->{'tracker'}{'fxtable'}{'file'} =~ m/\.asm$/i ) {
                $asm_file = "$main::build_dir/$main::game_config->{'tracker'}{'fxtable'}{'file'}";
            } elsif ( $main::game_config->{'tracker'}{'fxtable'}{'file'} =~ m/\.aks$/i ) {
                $asm_file = main::arkos2_convert_effects_to_asm( "$main::build_dir/$main::game_config->{'tracker'}{'fxtable'}{'file'}", 'all_sound_effects' );
            } else {
                die "Arkos sound FX can only be in AKS or ASM format\n";
            }
            my $dest_asm_file = "$trk_dir/" . basename( $asm_file );

            my $effects_count = main::arkos2_count_sound_effects( $asm_file );
            push @main::h_game_data_lines, sprintf( "#define TRACKER_SOUNDFX_NUM_EFFECTS %d\n", $effects_count );

            move( $asm_file, $dest_asm_file ) or
                die "Could not rename $asm_file to $dest_asm_file\n";
        }
        if ( defined( $main::game_config->{'tracker'}{'fx_channel'} ) ) {
            push @main::h_game_data_lines, sprintf( "#define TRACKER_SOUNDFX_CHANNEL %d\n",
                $main::game_config->{'tracker'}{'fx_channel'} );
        }
        if ( defined( $main::game_config->{'tracker'}{'fx_volume'} ) ) {
            push @main::h_game_data_lines, sprintf( "#define TRACKER_SOUNDFX_VOLUME %d\n",
                $main::game_config->{'tracker'}{'fx_volume'} );
        }

    }
}

1;
