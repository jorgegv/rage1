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

use Modern::Perl;
use Data::Dumper;
use File::Basename;
use List::MoreUtils qw( zip );

my $debug = 1;

sub debug {
     print shift if $debug;
}

sub parse_nex_file {
     my $file = shift;
     my $data;

     # open file and set it to binary mode for parsing
     open NEX,$file or return undef;
     binmode NEX;

     # get header and check
     my $header_block;
     if ( read( NEX, $header_block, 512, 0 ) != 512 ) {
          printf "** %s: header error, must be 512 bytes long\n", $file;
          return undef;
     }

     my @fields = qw( signature version ram num_banks load_screen_blocks
          border sp pc num_extra_files present_banks loading_bar
          loading_bar_color bank_load_delay start_delay preserve_state
          required_core_version timex_hires_color entry_bank
          file_handle_addr
     );
     my @values = unpack 'A4A4C4S3a112C5a3C2S', $header_block;
     my %header = zip @fields, @values;
     $header{'present_banks'} = [ unpack( 'C*', $header{'present_banks'} ) ];
     $header{'required_core_version'} = sprintf "%d.%d.%d", unpack( 'C*', $header{'required_core_version'} );
     debug( Dumper( \%header ));
     $data->{'header'} = \%header;

     close NEX;
     return $data;
}

sub output_nex_info {
     my $data = shift;
     debug( Dumper( $data ) );
}


##
## Main
##

if ( not scalar( @ARGV ) ) {
     say "usage: " .basename( $0 ). " <nex_file1> [nex_file2 ...]";
     exit 1;
}

foreach my $nex_file ( @ARGV ) {
     if ( -r $nex_file ) {
          my $nex_data = parse_nex_file( $nex_file );
          if ( $nex_data ) {
               output_nex_info( $nex_data );
          } else {
               say "** Error parsing $nex_file";
          }
     } else {
          say "** Could not find $nex_file, skipping...";
     }
}
