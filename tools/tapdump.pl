#!/usr/bin/perl

use strict;
use warnings;
use utf8;
use Data::Dumper;

# returns the file bytes as an array
sub read_file_bytes {
    my $file = shift;
    my @bytes;

    open my $binfile, $file or
        die "Could not open $file for reading\n";
    binmode $binfile;

    my $bindata;
    while ( read( $binfile, $bindata, 1024 ) ) {
        push @bytes, unpack("C*", $bindata )
    }

    close $binfile;
    return \@bytes;
}

my %block_type = (
    0	=> 'HEADER',
    255	=> 'DATA',
);

my %data_type = (
    0	=> 'PROGRAM',
    1	=> 'NUMVAR',
    2	=> 'STRVAR',
    3	=> 'CODE',
);

sub output_data_block_info {
    my ( $flag, $data ) = @_;

    my $block_type = $block_type{ $flag } || 'UNKNOWN';

    if ( $block_type eq 'HEADER' ) {
        my $data_type = $data_type{ $data->[0] } || 'UNKNOWN';
        my $filename = join( "", map { chr( $_ ) } @$data[ 1 .. 10 ] );
        my $length = $data->[ 11 ] + 256 * $data->[ 12 ];
        if ( $data_type eq 'PROGRAM' ) {
            my $auto_start = $data->[ 13 ] + 256 * $data->[ 14 ];
            my $program_length = $data->[ 15 ] + 256 * $data->[ 16 ];
            printf "  Header block: Type = %s, File Name = \"%s\", Length = %d, Autostart = %d, Program Length = %d\n",
                $data_type, $filename, $length, $auto_start, $program_length;
        }
        if ( $data_type eq 'NUMVAR' ) {
            my $var_name = @$data[ 13 .. 14 ];
            printf "  Header block:  Type = %s, File Name = \"%s\", Length = %d, Variable Name = %s\n",
                $data_type, $filename, $length, $var_name;
        }
        if ( $data_type eq 'STRVAR' ) {
            my $var_name = @$data[ 13 .. 14 ];
            printf "  Header block: Type = %s, File Name = \"%s\", Length = %d, Variable Name = %s\n",
                $data_type, $filename, $length, $var_name;
        }
        if ( $data_type eq 'CODE' ) {
            my $start_address = $data->[ 13 ] + 256 * $data->[ 14 ];
            printf "  Header block: Type = %s, File Name = \"%s\", Length = %d, Start Address = %d (0x%04X)\n",
                $data_type, $filename, $length, $start_address, $start_address;
        }
    } elsif ( $block_type eq 'DATA' ) {
        printf "  Data block: Size = %d\n",
            scalar( @$data );
    }
    print "\n";
}

###
### Main program
###

( scalar( @ARGV ) == 1 ) or
    die "usage: $0 <file.tap>\n";

my $bytes = read_file_bytes( $ARGV[0] );
my $file_size = scalar( @$bytes );

my $num_block = 0;
my $pos = 0;
while ( $pos < $file_size ) {
    my $savepos = $pos;
    my $size = $bytes->[ $pos++ ] + 256 * $bytes->[ $pos++ ];
    my $flag = $bytes->[ $pos++ ];
    my $data = [ @$bytes[ $pos .. ( $pos + $size - 2 - 1 ) ] ];
    $pos += $size - 2;
    my $cksum = $bytes->[ $pos++ ];
    printf( "Block %d: pos = %d, size = %d, flag = %d, cksum = %d\n",
        $num_block++,
        $savepos, $size, $flag, $cksum
    );
    output_data_block_info( $flag, $data );
}
