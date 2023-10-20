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

# generate bidimensional symmetric matrix with the number of common btiles of each screen with each
# other

# for each screen, generate a sorted list of the other screens, in descending order of number of
# common btiles

# For a given starting screen (screen A), create groups of N screens. Grouping algorithm:
# 1) Add A to the current group and mark it as USED
# 2) If the current group already has N elements, save current group and create a new empty current group
# 3) Get the first screen on screen A's list of screens sharing btiles with it (screen B), and which is not USED
# 4) Get the first screen on screen B's list of screens sharing btiles with it (screen C), and which is not USED
# 5) If no screens can be picked from 3) and 4), we have exhausted all screens, so END of algorithm
# 6) From B and C, pick the one which has the most btiles in common with A
# 7) Use the screen picked in 6) as the new screen A and repeat from step 1)

# The previous algorithm creates a screen grouping structure, and the only parameter is the screen
# we will use for starting the walk.  Given that the number of screens should not be very big, we
# can exhaustively explore all possible groupings (by repeating the algorithm using each of the
# screens as the starting one), and select the grouping that has the most shared btiles between
# screens.  For this, we need a "weight" function that analyzes a grouping structure and returns a
# value which we can use to sort them, and pick the one that maximizes btile sharing.  The weight
# function can be the number of unique btiles in the screen group (union of the btiles of all
# screens belonging to that group)
