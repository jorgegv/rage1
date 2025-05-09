#!/usr/bin/perl

use Modern::Perl;

use Data::Dumper;

open( my $in, $ARGV[0] )
    or die "Could not open $ARGV[0]\n";
my $data;
my $size = read( $in, $data, 1024*1024 );
close $in;

#printf "File: %s\n", $ARGV[0];
#printf "Size: %d bytes\n", $size;

#print Dumper( $data );


my @bytes = unpack( 'C*', $data );
my $previous = 0;
foreach my $byte ( @bytes ) {
    print pack( 'C', ( $byte ^ $previous ) );
    $previous = $byte;
}
