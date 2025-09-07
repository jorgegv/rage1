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
use List::MoreUtils qw( zip natatime );

my $debug = $ENV{'DEBUG'} || undef;

sub debug {
     print shift if $debug;
}

my @zx_colours = qw( BLACK BLUE RED MAGENTA GREEN CYAN YELLOW WHITE );

sub between {
     my ( $what, $low, $high ) = @_;
     return ( ( $what <= $high ) and ( $what >= $low ) );
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
          border_colour sp pc num_extra_files present_banks loading_bar
          loading_bar_colour bank_load_delay start_delay preserve_state
          required_core_version timex_hires_colour entry_bank
          file_handle_address
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
     my $header = $data->{'header'};

     printf "NEX signature: %s\n", $header->{'signature'} eq 'Next' ? "Valid" : "Invalid";
     printf "NEX format version: %s\n", $header->{'version'};
     printf "RAM required: %s\n", $header->{'ram'} ? "1720k" : "768k";
     printf "Number of banks present: %d\n", $header->{'num_banks'};
     print  "Loading screen blocks:\n";
     printf "  Palette  : %s\n", $header->{'load_screen_blocks'} && 0x80 ? "Yes" : "No";
     printf "  Hi-Colour: %s\n", $header->{'load_screen_blocks'} && 0x10 ? "Yes" : "No";
     printf "  Hi-Res   : %s\n", $header->{'load_screen_blocks'} && 0x08 ? "Yes" : "No";
     printf "  Lo-Res   : %s\n", $header->{'load_screen_blocks'} && 0x04 ? "Yes" : "No";
     printf "  ULA      : %s\n", $header->{'load_screen_blocks'} && 0x02 ? "Yes" : "No";
     printf "  Layer2   : %s\n", $header->{'load_screen_blocks'} && 0x01 ? "Yes" : "No";
     printf "Border colour: 0x%02x (%s)\n", $header->{'border_colour'},
          $zx_colours[ $header->{'border_colour'} ];
     printf "SP register: 0x%04x (%d)\n", $header->{'sp'}, $header->{'sp'};
     printf "PC register: 0x%04x (%d)%s\n", $header->{'pc'}, $header->{'pc'},
          $header->{'pc'} ? '' : "- Don't run, just load";
     printf "Extra files: %d\n", $header->{'num_extra_files'};
     printf "Loading bar colour: %d\n", $header->{'loading_bar_colour'};
     printf "Bank loading delay: %d %s\n", $header->{'bank_load_delay'},
          $header->{'bank_load_delay'} ? "frames" : "(no delay)";
     printf "Start delay: %d %s\n", $header->{'start_delay'},
          $header->{'start_delay'} ? "frames" : "(no delay)";
     printf "Preserve Next state: %s\n", $header->{'preserve_state'} ? "Yes" : "No";
     printf "Required core version: %s\n", $header->{'required_core_version'};
     printf "Hi-Res colour: 0x%02x (%s)\n", $header->{'timex_hires_colour'},
          $zx_colours[ $header->{'timex_hires_colour'} >> 3 ];
     printf "Initial bank mapped at 0xc000: %d\n", $header->{'entry_bank'};
     printf "File handle address: 0x%04x (%d) %s\n", $header->{'file_handle_address'}, $header->{'file_handle_address'},
          ( $header->{'file_handle_address'} ?
               ( between( $header->{'file_handle_address'}, 0x0001, 0x3fff ) ?
                    " - File handle in BC" : '' )
          : "- NEX file closed by loader" );
     print  "Data available for banks:\n";

     my @banks = grep { $header->{'present_banks'}[ $_ ] } ( 0 .. 111 );
     my $it = natatime 20, @banks;
     while ( my @row = $it->() ) {
          print "  ", join( ", ", @row ), "\n";
     }
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
