#!/usr/bin/env perl

use Modern::Perl;

use File::Basename;
use Data::Dumper;

scalar( @ARGV ) or
    die "usage: ".basename( $0 )." <dump_files>\n";

# load screen data from dump files
my %screens;
foreach my $file ( @ARGV ) {
    my $VAR1;
    eval `cat "$file"`;
    foreach my $screen_name ( keys %$VAR1 ) {
        $screens{ $screen_name } = $VAR1->{ $screen_name };
    }
}

#print Dumper( \%screens );

# crunch data

# generate global ordered screen list
my @screen_names = sort keys %screens;

# generate ordered btile lists for all screens
foreach my $s ( @screen_names ) {
    $screens{ $s }{'btile_list'} = [ sort keys %{ $screens{ $s }{'btile_count'} } ];
}

print Dumper( \%screens );
