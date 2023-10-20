#!/usr/bin/env perl

use Modern::Perl;

use File::Basename;
use Data::Dumper;

scalar( @ARGV ) or
    die "usage: ".basename( $0 )." <dump_files>\n";

# load screen data from dump files
my %all_screens;
foreach my $file ( @ARGV ) {
    my $VAR1;
    eval `cat "$file"`;
    foreach my $screen_name ( keys %$VAR1 ) {
        $all_screens{ $screen_name } = $VAR1->{ $screen_name };
    }
}

#print Dumper( \%screens );

# crunch data

# generate global ordered screen list
my @screen_names = sort keys %all_screens;

# generate ordered btile lists for all screens
foreach my $s ( @screen_names ) {
    $all_screens{ $s }{'btile_list'} = [ sort keys %{ $all_screens{ $s }{'btile_count'} } ];
}

# all_screens{ $s } = {
#   btile_count => { btile_name => count, btile_name => count, ...},
#   btile_list => [ btile_name, btile_name, ... ],
# }

#print Dumper( \%all_screens );

# generate bidimensional symmetric matrix with the number of common btiles of each screen with each
# other
foreach my $src ( @screen_names ) {
    foreach my $dst ( @screen_names ) {
        $all_screens{ $src }{'shared_btile_count'}{ $dst } = 0;
        foreach my $k ( keys %{ $all_screens{ $src }{'btile_count'} } ) {
            if ( defined( $all_screens{ $dst }{'btile_count'}{ $k } ) ) {
                $all_screens{ $src }{'shared_btile_count'}{ $dst }++;
            }
        }
    }
}

# all_screens{ $s } = {
#   btile_count => { btile_name => count, btile_name => count, ... },
#   btile_list => [ btile_name, btile_name, ... ],
#   shared_btile_count => { btile_name1 => count, btile_name2 => count, ... },
# }

#print Dumper( \%all_screens );

# for each screen, generate a sorted list of the other screens, in
# descending order of number of common btiles.  The first element of this
# lists is _always_ the current screen (each screen has 100% of btiles in
# common with itself) so we discard it.
foreach my $screen ( @screen_names ) {
    $all_screens{ $screen }{'sharing_screens'} = [
        sort {
            $all_screens{ $screen }{'shared_btile_count'}{ $b } <=> $all_screens{$screen}{'shared_btile_count'}{ $a }
        } @screen_names
    ];
    # discard the first, it's always itself
    shift @{ $all_screens{ $screen }{'sharing_screens'} };
}

# all_screens{ $s } = {
#   btile_count => { btile_name => count, btile_name => count, ... },
#   btile_list => [ btile_name, btile_name, ... ],
#   shared_btile_count => { screen_name1 => count, screen_name2 => count, ... },
#   sharing_screens => [ screen_name1, screen_name2, ... ],
# }

print Dumper( \%all_screens );

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
