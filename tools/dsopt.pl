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

# generate ordered btile lists for all screens and compute global number of unique btiles
my %global_btiles;
foreach my $s ( @screen_names ) {
    $all_screens{ $s }{'btile_list'} = [ sort keys %{ $all_screens{ $s }{'btile_count'} } ];
    foreach my $b ( @{ $all_screens{ $s }{'btile_list'} } ) {
        $global_btiles{ $b }++;
    }
}
printf "total unique btiles: %d\n", scalar( keys %global_btiles );

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

#print Dumper( \%all_screens ); exit;

# create the screen clusters

# For a given starting screen (screen A), create groups of N screens. Grouping algorithm:
# 1) Add A to the current group and mark it as USED
# 2) If the current group already has N elements, save current group and create a new empty current group
# 3) Get the first screen on screen A's list of screens sharing btiles with it (screen B), and which is not USED
# 4) Get the first screen on screen B's list of screens sharing btiles with it (screen C), and which is not USED
# 5) If no screens can be picked from 3) and 4), we have exhausted all screens, so END of algorithm
# 6) From B and C, pick the one which has the most btiles in common with A
# 7) Use the screen picked in 6) as the new screen A and repeat from step 1)
#
# The previous algorithm creates a screen grouping structure, and the only parameter is the screen
# we will use for starting the walk.  Given that the number of screens should not be very big, we
# can exhaustively explore all possible groupings (by repeating the algorithm using each of the
# screens as the starting one), and select the grouping that has the most shared btiles between
# screens.  For this, we need a "weight" function that analyzes a grouping structure and returns a
# value which we can use to sort them, and pick the one that maximizes btile sharing.  The weight
# function can be the number of unique btiles in the screen group (union of the btiles of all
# screens belonging to that group)
#
# This weight is calculated in a separate step.

my $max_screens_per_dataset = 5;

my %cluster_lists_by_start_screen;

foreach my $start_screen ( @screen_names ) {

    my @current_cluster = ();
    my %screen_is_used = ();
    my $screen_a = $start_screen;
    my $index;

    my $exit_loop = 0;
    do {
        # step 1
        # save current screen in current cluster
        push @current_cluster, $screen_a;
        $screen_is_used{ $screen_a }++;
#        printf "step 1: screen_a='%s'\n",$screen_a;
#        printf "cluster: [ %s ]\n", join( ", ", @current_cluster );
#        printf "used_screens: %d\n", scalar( keys %screen_is_used );
#        printf "number of clusters: %d\n", scalar( @{ $cluster_lists_by_start_screen{ $start_screen } } );

        # step 2
        # if cluster has max elements, save cluster and start a new one
        if ( scalar( @current_cluster ) == $max_screens_per_dataset ) {
            push @{ $cluster_lists_by_start_screen{ $start_screen }{'clusters'} }, [ @current_cluster ];
            @current_cluster = ();
        }

        # step 3
        # find the first unused screen B or undef if index is end of list
        my $screen_b;
        $index = 0;
        while ( ( $index < scalar( @{ $all_screens{ $screen_a }{'sharing_screens'} } ) )
            and defined( $screen_is_used{ $all_screens{ $screen_a }{'sharing_screens'}[ $index ] } ) ) {
            $index++;
        }
#        printf "step 3: screen_a='%s', size=%d, index=%d\n", $screen_a, scalar( @{$all_screens{ $screen_a }{'sharing_screens'}}), $index;
        $screen_b = (
            $index < scalar( @{ $all_screens{ $screen_a }{'sharing_screens'} } ) ?
            $all_screens{ $screen_a }{'sharing_screens'}[ $index ] :
            undef
        );
#        printf "step 3: screen_b='%s'\n", $screen_b || 'undef';

        # step 4
        # find the first unused screen C or undef if index is end of list
        my $screen_c;
        if ( defined( $screen_b ) ) {
            $index = 0;
            while ( ( $index < scalar( @{ $all_screens{ $screen_b }{'sharing_screens'} } ) )
                and defined( $screen_is_used{ $all_screens{ $screen_b }{'sharing_screens'}[ $index ] } ) ) {
                $index++;
            }
#            printf "step 4: screen_b='%s', size=%d, index=%d\n", $screen_b, scalar( @{$all_screens{ $screen_b }{'sharing_screens'}}), $index;
            $screen_c = (
                $index < scalar( @{ $all_screens{ $screen_b }{'sharing_screens'} } ) ?
                $all_screens{ $screen_b }{'sharing_screens'}[ $index ] :
                undef
            );
        }
#        printf "step 4: screen_c='%s'\n", $screen_c || 'undef';

        # step 6
        # pick the screen B or C that has the most common btiles with A
        # we reach here either with B and C defined, or only B defined
        if ( defined( $screen_c ) ) {
            if ( $all_screens{ $screen_a }{'shared_btile_count'}{ $screen_b } >
                $all_screens{ $screen_a }{'shared_btile_count'}{ $screen_c } ) {
                $screen_a = $screen_b;
            } else {
                $screen_a = $screen_c;
            }
        } elsif ( defined( $screen_b ) ) {
            $screen_a = $screen_b;
        } else {
            # step 5: end if no more screens found
            # don't forget to push the last (possibly incomplete) cluster!
            push @{ $cluster_lists_by_start_screen{ $start_screen }{'clusters'} }, [ @current_cluster ];
            $exit_loop++;
        }

    } while ( not $exit_loop );

    # calculate the weight of this cluster list as the number of shared btiles
    # between screens.  We walk all the groups, and for each screen in the
    # groups we increment a counter for all its btiles.  We then count the
    # number of btiles that have a count number >= 2, which means they are
    # shared between some screens.
    my $weight = 0;
    foreach my $cluster ( @{ $cluster_lists_by_start_screen{ $start_screen }{'clusters'} } ) {
        my %seen_btiles;
        foreach my $screen ( @$cluster ) {
            foreach my $btile ( @{ $all_screens{ $screen }{'btile_list'} } ) {
                $seen_btiles{ $btile }++;
            }
        }
        $weight += scalar( grep { $seen_btiles{ $_ } >= 2 } keys %seen_btiles );
    }
    $cluster_lists_by_start_screen{ $start_screen }{'weight'} = $weight;
}

#print Dumper( \%cluster_lists_by_start_screen );
my @sorted = sort { 
    $cluster_lists_by_start_screen{ $b }{'weight'}	# reverse order
    <=> 
    $cluster_lists_by_start_screen{ $a }{'weight'}
} keys %cluster_lists_by_start_screen;

printf "Most efficient clustering starts with screen '%s', and shares %d btiles\n",
    $sorted[0], $cluster_lists_by_start_screen{ $sorted[0] }{'weight'};
