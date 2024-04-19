#!/usr/bin/env perl

use Modern::Perl;

use List::Util qw( sum zip );
use Data::Dumper;

my $num_bins = 3;
my $bin_size = 16384;

my @dataset_sizes = qw(
    5039
    5254
    4374
    3811
    3783
    2888
    4224
    3161
    3847
    4840
    2593
    2958
);

( sum( @dataset_sizes ) <= $bin_size * $num_bins ) or
    die "** Datasets sizes are greater than the maximum size ".($bin_size * $num_bins)."\n";

# prepare data structure
my $elem_index = 0;
my @sizes = map { { 'index' => $elem_index++, 'size' => $_ } } @dataset_sizes;

# First-Fit - sort the input list for different results
sub do_algo_first_fit {
    my @elements = @_;
    my @bins;
    my $current_bin = 0;
    my $current_free = $bin_size;
    foreach my $elem ( @elements ) {
        if ( $elem->{'size'} > $current_free ) {
            $current_free = $bin_size;
            $current_bin++;
        }
        push @{ $bins[ $current_bin ] }, $elem;
        $current_free -= $elem->{'size'};
    }
    return @bins;

}

# show results of different algos

my @results;

@results = do_algo_first_fit( @sizes );
print "First-Fit:\n";
foreach my $bin ( @results ) {
    printf "  [ %s ] - ", join( ", ", map { $_->{'index'} } @$bin );
    printf "Free: %d\n", $bin_size - sum map { $_->{'size'} } @$bin;
}
print "\n";

@results = do_algo_first_fit( sort { $a->{'size'} <=> $b->{'size'} } @sizes );
print "Sorted ASC First-Fit:\n";
foreach my $bin ( @results ) {
    printf "  [ %s ] - ", join( ", ", map { $_->{'index'} } @$bin );
    printf "Free: %d\n", $bin_size - sum map { $_->{'size'} } @$bin;
}
print "\n";

@results = do_algo_first_fit( sort { $b->{'size'} <=> $a->{'size'} } @sizes );
print "Sorted DESC First-Fit:\n";
foreach my $bin ( @results ) {
    printf "  [ %s ] - ", join( ", ", map { $_->{'index'} } @$bin );
    printf "Free: %d\n", $bin_size - sum map { $_->{'size'} } @$bin;
}
print "\n";

