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

# reads a file and returns its bytes as a list of values 0-255.  Optionally,
# an offset and size can be specified and the data extarcted from the file
# will only be in that range
# returns: list of bytes with file data
sub file_to_bytes {
    my ( $f, $offset, $size ) = @_;

    open DATA, $f or
        die "Could not open $f for reading\n";
    binmode DATA;
    my $data;

    if ( defined( $offset ) and defined( $size ) ) {
        seek( DATA, $offset, 0 );
        if ( read( DATA, $data, $size ) != $size ) {
            die "Error: could not read $size bytes from $f, offset $offset\n";
        }
    } else {
        { local $/; $data = <DATA>; }
    }

    close DATA;
    return unpack('C*', $data );
}

# reads a file, compresses its bytes with ZX0 and returns them as a list of
# values 0-255.  Optionally, an offset and size can be specified and the
# data extracted from the file will only be in that range
# returns: list of bytes with compressed file data in ZX0 format
sub file_to_compressed_bytes {
    my ( $f, $offset, $size ) = @_;

    # get the bytes and write them to a temporary file
    my @bytes = file_to_bytes( $f, $offset, $size );
    open( DATA, ">/tmp/bytes.dat" ) or
        die "Error: could not open temporary /tmp/bytes.dat for writing\n";
    binmode DATA;
    print DATA pack( "C*", @bytes );
    close DATA;

    # compress the temporary, then return the compressed bytes
    system( "z88dk-zx0 -f /tmp/bytes.dat" );
    if ( $? == -1 ) {
        die "Could not execute z88dk-zx0\n";
    } elsif ( $? & 127 ) {
        die "Error executing z88dk-zx0\n";
    }
    return file_to_bytes( '/tmp/bytes.dat.zx0' );
}

1;
