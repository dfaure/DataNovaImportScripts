#!/usr/bin/perl

use Text::CSV;
use strict;
use warnings FATAL => 'all';
use DateTime::Format::ISO8601;
use v5.14;     # using the + prototype for show_array, new to v5.14
use POSIX qw(strftime);

sub panic($) {
    print "@_\n";
    exit 1;
}
sub usage() {
    panic "Usage: $0 csv_file";
}

# Debugging of arrays, from https://perldoc.perl.org/perllol
sub show_array(+) {
       require Dumpvalue;
       state $prettily = new Dumpvalue::
                           tick        => q("),
                           compactDump => 1,
                           veryCompact => 1, ;
       dumpValue $prettily @_;
}

sub day_of_week_name($) {
    state @dayAbbrev = ( 'ERROR', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su', 'PH' );
    return $dayAbbrev[shift];
}

# Turn "1235" into "Mo-We,Fr"
sub abbrevs($) {
    my ($daynums) = @_; # ex: 1235, 8 for NH
    my $ret = "";
    my @digits = split(//, $daynums);
    push @digits, 9; # so that 8 gets processed
    my $cur;
    my $start;
    # Collapse consecutive days
    foreach my $daynum (@digits) {
        if ($daynum < 8 and defined $cur and $daynum == $cur+1) {
            ++$cur;
        } else {
            if (defined $cur) {
                if ($start < $cur) {
                    $ret .= day_of_week_name($start) . '-' . day_of_week_name($cur) . ',';
                } else {
                    $ret .= day_of_week_name($cur) . ',';
                }
            }
            $cur = $daynum;
            $start = $daynum;
        }
    }
    $ret =~ s/,$//;
    return $ret;
}

sub get_day_of_week($) {
    my ($date) = @_;
    my $dt = DateTime::Format::ISO8601->parse_datetime($date);
    my $day_of_week = $dt->day_of_week; # 1-7 (Monday is 1)
    # Jours fériés
    if ($date eq "2020-11-11" || $date eq "2020-12-25" || $date eq "2021-01-01") {
        $day_of_week = 8;
    }
    return $day_of_week;
}

sub year_for_all($) {
    my $ref_dates = shift;
    my @dates = @$ref_dates;
    #print "Dates:"; show_array(@dates);
    my $year = $1 if ($dates[0] =~ /^([0-9]{4})/);
    foreach my $date (@dates) {
        my $y = $1 if ($date =~ /^([0-9]{4})/);
        return undef if ($year ne $y);
    }
    #print "all in year= $year\n";
    return $year;
}

# If the input array has 2020 for all dates in [0] and 2021 for all dates in [1]
# then return [ '2020', '' ]
sub try_year_split($) {
    my ($ref_dates) = @_;
    my @date_sets = @$ref_dates;
    my @years = ();
    for my $i ( 0 .. $#date_sets ) {
        my @dates = @{$date_sets[$i]};
        my $year = year_for_all(\@dates);
        return () unless defined $year;
        state $currentyear = strftime "%Y", localtime;
        $year = "" if ($year == ($currentyear + 1)); # Assume next year's hours will stay
        push @years, $year;
    }
    return @years;
}

sub rules_for_day_of_week($$) {
    my ($day_of_week, $ref_dates) = @_;
    my @date_sets = @$ref_dates;  # unused
    my $num_sets = @date_sets;
    if ($num_sets == 1) {
        # Stable opening times -> single rule for that day
        return ( "" );
    }

    #print "Date sets:"; show_array(@date_sets);
    my @rules = try_year_split($ref_dates);
    return @rules if ($#rules >= 0);
    #return "" if ($num_dates >= 7); # Wins by majority

    for my $i (0..$#date_sets) {
        push @rules, "ERROR-" . $i;
    }
    return @rules;
}

sub parse_args() {
    my $csv_file;
    while (my $arg = shift(@ARGV)) {
        if (!$csv_file) {
            $csv_file = $arg;
        } else {
            usage();
        }
    }
    usage() unless $csv_file;
    return ($csv_file);
}

sub main() {
    my $csv_file = parse_args();
    open my $fh, "$csv_file" or panic "Cannot open $csv_file: $!";
    my $csv = Text::CSV->new({ binary => 1, sep_char => ';' });
    my $line_nr = 0;

    # Group lines by post office
    # Then group by day of week, so we can see what all Mondays look like etc.
    # Then group by opening time for that day of week, before trying to merge, so we can see what's usual and what's rare
    my %office_data = (); # office => (day_of_week => (times => [dates]))
    my %office_names = (); # office_id => name

    while (my $row = $csv->getline($fh)) {
        $line_nr++;
        my $office_id = $row->[0];
        next if ($office_id =~ /^#/); # Skip header row
        my $name = $row->[1];
        die unless defined $name;
        $office_names{$office_id} = $name;
        my $date = $row->[2];
        my $opening = $row->[3];
        if ($row->[4] ne '') {
            $opening .= "," . $row->[4];
        }
        if ($row->[5] ne '') {
            $opening .= "," . $row->[5];
        }
        die "unsupported: see line $line_nr" if ($row->[6] ne '');
        $opening = "off" if $opening =~ /^FERME$/;
        my $day_of_week = get_day_of_week($date);
        push @{$office_data{$office_id}{$day_of_week}{$opening}}, $date;
    }
    print "Parsed $line_nr lines\n";

    # Aggregate the different opening hours for Mondays in different rules
    # The empty rule is the default one. But this allows for exceptions.
    my %office_times = (); # office => (day of week => (rule => times))
    # To group days (like "Mo-Fr"), the key here is the opening times like 09:00-12:00,14:00-16:30
    my %days_for_times = ();  # office => (rule => (times => day of week))

    foreach my $office_id (sort(keys %office_data)) {
        my $office_name = $office_names{$office_id};
        foreach my $day_of_week (sort keys %{$office_data{$office_id}}) {
            my %dayhash = %{$office_data{$office_id}{$day_of_week}};
            my @all_openings = keys %dayhash;
            my @date_sets = ();
            my @del_indexes = ();
            for (my $idx = 0; $idx <= $#all_openings; $idx++) {
                my $opening = $all_openings[$idx];
                my @dates = @{$dayhash{$opening}};
                my $numdates = @dates;
                #print "$office_name $day_of_week $opening $numdates dates: @dates\n";
                if ($numdates == 1) {
                    # ignore special cases for now
                    #print "Ignoring $opening on " . $dates[0] . "\n";
                    unshift @del_indexes, $idx; # unshift is push_front, so we reverse the order, for the delete
                } else {
                    push @date_sets, [ sort @dates ];
                }
            }
            # Delete ignored cases
            foreach my $item (@del_indexes) {
                splice(@all_openings, $item, 1);
            }
            #print day_of_week_name($day_of_week) . " date_sets:"; show_array(@date_sets);
            my @rules = rules_for_day_of_week($day_of_week, \@date_sets);
            if ($rules[0] eq "ERROR-0") {
                print "WARNING: $office_name $day_of_week has multiple outcomes: @all_openings\n";
                foreach my $opening (@all_openings) {
                    my @dates = @{$dayhash{$opening}};
                    print "   $opening on @dates\n";
                }
            }
            for ( my $idx = 0; $idx <= $#all_openings; $idx++ ) {
                my $opening = $all_openings[$idx];
                my $rule = $rules[$idx];
                $office_times{$office_id}{$day_of_week}{$rule} = $opening;
                $days_for_times{$office_id}{$rule}{$opening} .= $day_of_week;
                #print "$office_name $day_of_week rule=$rule opening=$opening\n";
            }
        }
    }

    foreach my $office_id (sort(keys %office_times)) {
        my $office_name = $office_names{$office_id};
        my $full_list = "";
        my %times = %{$office_times{$office_id}};
        my %days_for = %{$days_for_times{$office_id}};
        foreach my $day_of_week (sort(keys %times)) {
            my %rules = %{$times{$day_of_week}};
            foreach my $rule (sort(keys %rules)) {
                my $opening = $rules{$rule};
                #say "rule $rule opening $opening";
                my $daynums = $days_for{$rule}{$opening};
                if (defined $daynums) {
                    $full_list .= "$rule " if ($rule ne "");
                    $full_list .= abbrevs($daynums) . " $opening; ";
                    # The first day of the week in a range like Mo-Fr prints it all
                    undef $days_for{$rule}{$opening};
                }
            }
        }
        $full_list =~ s/; $//;

        print "$office_id|$office_name|$full_list\n";
    }
}
main();
