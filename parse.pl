#!/usr/bin/perl

use strict;
use Text::CSV;
use warnings FATAL => 'all';
use DateTime::Format::ISO8601;
use v5.14;     # using the + prototype for show_array, new to v5.14
use POSIX qw(strftime);

my $debug_me = 'NONE'; # TODO pass on command line?
my $file_start_date; # get it from the input file so that time passing doesn't break unittests

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

sub month_name($) {
    state @monthNames = ( 'ERROR', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec' );
    return $monthNames[shift];
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

sub fast_parse_datetime($) {
    my ($date) = @_;
    # Since we always have year-month-day, we can be much faster than the full parser
    # parse_datetime: 83s. custom regexp: 66s.
    # return DateTime::Format::ISO8601->parse_datetime($date);
    if ($date =~ /^([0-9]{4})-([0-9]+)-([0-9]+)$/) {
        return DateTime->new(
                year       => $1,
                month      => $2,
                day        => $3);
    }
    return undef;
}

my %cache = ();

sub get_day_of_week($) {
    my ($date) = @_;
    my $entry = $cache{$date};
    return $entry if defined $entry;

    my $dt = fast_parse_datetime($date);
    my $day_of_week = $dt->day_of_week; # 1-7 (Monday is 1)
    # Jours fériés
    if ($date eq "2020-11-01" || $date eq "2020-11-11" || $date eq "2020-12-25" || $date eq "2021-01-01") {
        $day_of_week = 8;
    }

    $cache{$date} = $day_of_week;

    return $day_of_week;
}

sub get_year($) {
    return (shift =~ /^([0-9]{4})/) ? $1 : undef;
}

sub get_month($) {
   return (shift =~ /^[0-9]{4}-([0-9]+)-/) ? $1 : undef;
}

# Previous month, 1-based.  previous_month(1) == 12
sub previous_month($) {
    my ($month) = @_;
    return ($month + 10) % 12 + 1;
}

# Next month, 1-based.  next_month(12) == 1
sub next_month($) {
    my ($month) = @_;
    return $month % 12 + 1;
}

sub get_week_number($) {
    my ($date) = @_;
    my $dt = fast_parse_datetime($date);
    return $dt->week;
}

sub year_for_all($) {
    my $ref_dates = shift;
    my @dates = @$ref_dates;
    return undef if $#dates < 2; # Not enough
    #print "Dates:"; show_array(@dates);
    my $year = get_year($dates[0]);
    foreach my $date (@dates) {
        my $y = get_year($date);
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
    return () if $#date_sets != 1;
    my @years = ();
    my %seen_years = ();
    for my $i ( 0 .. $#date_sets ) {
        my @dates = @{$date_sets[$i]};
        my $year = year_for_all(\@dates);
        return () unless defined $year;
        return () if defined $seen_years{$year};
        $seen_years{$year} = 1;

        state $currentyear = get_year($file_start_date);
        $year = "" if ($year == ($currentyear + 1)); # Assume next year's hours will stay
        push @years, $year;
    }
    #print STDERR "Year split: " . @date_sets . "\n";
    return @years;
}

sub month_for_all($) {
    my $ref_dates = shift;
    my @dates = @$ref_dates;
    return undef if $#dates < 2; # Not enough
    #print "Dates:"; show_array(@dates);
    my $month = get_month($dates[0]);
    foreach my $date (@dates) {
        my $m = get_month($date);
        return undef if ($month ne $m);
    }
    #print "all in month=$month\n";
    return $month;
}

# If the input array has dates in one month in [0] and other months in [1]
# then return [ 'MonthName', '' ]
sub try_month_exception($$) {
    my ($ref_dates, $ref_openings) = @_;
    my @date_sets = @$ref_dates;
    return () if $#date_sets != 1;
    my @openings = @$ref_openings;
    my @rules = ();
    my $date_set_number;
    my $exception_month;
    for my $i ( 0 .. $#date_sets ) {
        my @dates = @{$date_sets[$i]};
        my $month = month_for_all(\@dates);
        if (defined $month) {
            return () if defined $date_set_number; # only one
            $date_set_number = $i;
            my $year = year_for_all(\@dates);
            die "@dates has $month but no year?" unless defined $year; # surely same month = same year
            push @rules, "$year " . month_name($month);
            $exception_month = $month;
        } else {
            push @rules, '';
        }
    }
    return () if not defined $date_set_number;
    die if not defined $exception_month; # they are defined together
    # Check that the other date set has no date in that month
    my $other_date_set = 1 - $date_set_number; # 0->1, 1->0
    foreach my $date (@{$date_sets[$other_date_set]}) {
        return () if get_month($date) eq $exception_month;
    }
    return @rules;
}

# The future changes will be set when running the script again later.
sub delete_future_changes($$) {
    my ($ref_dates, $ref_openings) = @_;
    my @date_sets = @$ref_dates;
    my @all_openings = @$ref_openings;

    # Determine min-max range for each set
    my @min = ();
    my @max = ();
    my $last_index; # which range starts last i.e. the one with the max min :)
    my $last_min;
    for my $i ( 0 .. $#date_sets ) {
        my @dates = @{$date_sets[$i]};
        foreach my $date (@dates) {
            if (!defined $max[$i] || $max[$i] lt $date) {
                $max[$i] = $date;
            }
            if (!defined $min[$i] || $min[$i] gt $date) {
                $min[$i] = $date;
            }
        }
        if (!defined $last_min || $last_min lt $min[$i]) {
            $last_min = $min[$i];
            $last_index = $i;
        }
    }

    # Check all other sets are before last_min
    for my $i ( 0 .. $#date_sets ) {
        next if $i == $last_index;
        my @dates = @{$date_sets[$i]};
        foreach my $date (@dates) {
            return (0, \@date_sets, \@all_openings) if ($date gt $last_min);
        }
    }

    # Yes => delete last_index
    splice(@all_openings, $last_index, 1);
    splice(@date_sets, $last_index, 1);
    #print STDERR "REMOVED " . $last_index . "\n";
    return (1, \@date_sets, \@all_openings);
}

# Return 1 if all dates in the $1 array are the $2th "weekday" of the month.
# $2 is 1 for first "weekday" of the month (e.g. first saturday)
# $2 is -1 for last "weekday" of the month (e.g. last saturday)
sub same_weekday_of_month_for_all($$) {
    my ($ref_dates, $which) = @_;
    my @dates = @$ref_dates;
    return 0 if $#dates < 2; # Not enough
    state $file_dt = fast_parse_datetime($file_start_date);
    my $current_month;
    if ($which == -1) {
        $current_month = previous_month($file_dt->month);
    } else {
        # Do we expect to see the Nth "weekday" for this month, or is it in the past already?
        $current_month = $file_dt->weekday_of_month <= $which ? previous_month($file_dt->month) : $file_dt->month;
    }
    for my $date (@dates) {
        my $dt = fast_parse_datetime($date);
        # last week of the month?
        #say "  $which: $date has weekday_of_month: " . $dt->weekday_of_month;
        if (($which == -1 && $dt->month != $dt->clone()->add(days => 7)->month)
          || ($which > 0 && $dt->weekday_of_month == $which)) {
            if (next_month($current_month) == $dt->month) {
                $current_month = $dt->month;
            } else {
                return 0;
            }
        } else {
            return 0;
        }
    }
    return 1;
}

# If the input array always has last-weekday-of-month in [0] and everything else in [1] (or vice-versa)
# then return [ '[-1]', '' ], but the [-1] has to be generated AFTER...
sub try_same_weekday_of_month($$) {
    my ($ref_dates, $which) = @_;
    my @date_sets = @$ref_dates;
    my @rules;
    my %seen; # keys 0 and 1
    for my $i ( 0 .. $#date_sets ) {
        my $all_same_week = 1;
        my @dates = @{$date_sets[$i]};
        my $yes = same_weekday_of_month_for_all(\@dates, $which);
        return () if defined $seen{$yes};
        $seen{$yes} = 1;
        push @rules, $yes ? "[$which]" : "";
    }
    return @rules;
}

# If the input array has [2020-11-07 2020-11-21 ...] and [2020-10-31 2020-11-14 ...]
# then return [ 'week 1-53/2', 'week 2-53/2' ]
sub try_alternating_weeks($$) {
    my ($ref_dates, $ref_openings) = @_;
    my @date_sets = @$ref_dates;
    my @openings = @$ref_openings;
    my %found_odd_even = (); # $Even => 0; $Odd => 0
    #my %found_odd_even_prev_year = (); # $Even => 0; $Odd => 0
    my @ret;

    # Enum :)
    state $None = -1;
    state $Even = 0;
    state $Odd = 1;
    state @str = ( 'week 02-53/2', 'week 01-53/2' ); # 0=even, 1=odd

    for my $i ( 0 .. $#date_sets ) {
        my @dates = @{$date_sets[$i]};

        my $year;
        my $prev_year;
        my $state_prev_year;

        # Check if all weeks are even, or all odd
        my $state = $None;
        for my $date (@dates) {
            my ($y, $week_number) = get_week_number($date);
            my $new_state = ($week_number % 2);
            if ($state == $None) {
                $state = $new_state;
                $year = $y;
                $prev_year = $y;
                #say " first state $state";
            } else {
                #say " next week number " . $week_number . " $y new state " . $new_state;
                if ($new_state != $state) {
                    # changed over the year?
                    if ($y != $year) {
                        last; # Don't look at next year yet, just like in try_chronological_change
#                         return () if $found_odd_even_prev_year{$state};
#                         $found_odd_even_prev_year{$state} = 1;
#                         $state_prev_year = $state;
#                         $year = $y;
#                         $state = $new_state;
                    } else {
                        return ();
                    }
                }
            }
        }
        #say "state=$state";
        die if $state == $None; # surely dates isn't empty?
        return () if $found_odd_even{$state};
        $found_odd_even{$state} = 1;

        # Disabled, only look at current year
        if (0 and defined $state_prev_year) {
            # Next year is the general rule, prev year is an override, so it comes second.
            # The '|' is an internal syntax, split up before outputting OSM rules
            if ($openings[$i] eq 'off') {
                push @ret, "IGNORE|$prev_year " . $str[$state_prev_year];
            } else {
                push @ret, $str[$state] . "|$prev_year " . $str[$state_prev_year];
            }
        } else {
            push @ret, ($openings[$i] eq 'off') ? "IGNORE" : $str[$state];
        }
    }

    # We know there are more than one date_sets (in caller) and
    # 3+ would fail the found_odd_even test. So there must be 2 exactly.
    return @ret;
}

# Main function for the core logic of this script.
# Called for one day of week at a time
# @date_sets : N sets of dates that have the same opening hours
# @openings : those N sets of openings (not much used here)
# Returns N sets of OSM rules
sub rules_for_day_of_week($$$) {
    my ($day_of_week, $ref_dates, $ref_openings) = @_;

    my @temp_date_sets = @$ref_dates;
    #print day_of_week_name($day_of_week) . ": date sets\n"; show_array(@temp_date_sets);

    my @rules;
    @rules = try_year_split($ref_dates);
    return (\@rules, $ref_openings) if ($#rules >= 0);

    my $success = 0;
    while ($#temp_date_sets > 0) {
        ($success, $ref_dates, $ref_openings) = delete_future_changes($ref_dates, $ref_openings);
        last if (!$success);
        @temp_date_sets = @$ref_dates;
    }
    my @date_sets = @$ref_dates;

    my $num_sets = @date_sets;
    if ($num_sets == 1) {
        # Stable opening times -> single rule for that day
        push @rules, "";
        return (\@rules, $ref_openings);
    }

    @rules = try_year_split($ref_dates);
    return (\@rules, $ref_openings) if ($#rules >= 0);

    @rules = try_alternating_weeks($ref_dates, $ref_openings);
    return (\@rules, $ref_openings) if ($#rules >= 0);

    for my $which(-1, 1 .. 4) {
        # -1 = last "weekday" of month, 1 = first "weekday" of month...
        @rules = try_same_weekday_of_month($ref_dates, $which);
        return (\@rules, $ref_openings) if ($#rules >= 0);
    }

    @rules = try_month_exception($ref_dates, $ref_openings);
    return (\@rules, $ref_openings) if ($#rules >= 0);

    for my $i (0..$#date_sets) {
        push @rules, "ERROR-" . $i;
    }
    return (\@rules, $ref_openings);
}

sub write_rule($$$) {
    my ($rule, $daynums, $opening) = @_;
    my $str = "";
    $str = "$rule " if ($rule !~ /^\[/); # year or week number
    $str .= abbrevs($daynums);
    $str .= "$rule" if ($rule =~ /^\[/); # e.g. [-1]
    $str .= " $opening; ";
    return $str;
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
        die unless defined $date;
        $file_start_date = $date if (!defined $file_start_date or $date lt $file_start_date);
        my $opening = $row->[3];
        if ($row->[4] ne '') {
            $opening .= "," . $row->[4];
        }
        if ($row->[5] ne '') {
            $opening .= "," . $row->[5];
        }
        die "unsupported: see line $line_nr" if ($row->[6] ne '');
        my $day_of_week = get_day_of_week($date);
        $opening = "off" if $opening =~ /^FERME$/ and $day_of_week != 8; # PH hack so it stays separate
        push @{$office_data{$office_id}{$day_of_week}{$opening}}, $date;
    }
    #print STDERR "Parsed $line_nr lines\n";

    # Aggregate the different opening hours for Mondays in different rules
    # The empty rule is the default one. But this allows for exceptions.
    my %office_times = (); # office => (day of week => (rule => times))
    # To group days (like "Mo-Fr"), the key here is the opening times like 09:00-12:00,14:00-16:30
    my %days_for_times = ();  # office => (rule => (times => day of week))

    foreach my $office_id (sort(keys %office_data)) {
        my $office_name = $office_names{$office_id};
        foreach my $day_of_week (sort keys %{$office_data{$office_id}}) {
            my %dayhash = %{$office_data{$office_id}{$day_of_week}};
            my $dow_name = day_of_week_name($day_of_week); # for debug
            my @all_openings = keys %dayhash;
            my @date_sets = ();
            my @del_indexes = ();
            for (my $idx = 0; $idx <= $#all_openings; $idx++) {
                my $opening = $all_openings[$idx];
                my @dates = sort @{$dayhash{$opening}};
                my $numdates = @dates;
                print STDERR "$office_name: $dow_name $opening $numdates dates: @dates\n" if ($office_id eq $debug_me);
                if ($numdates == 1 && $#all_openings > 0) {
                    # ignore single-day-exceptions for now
                    #print "$office_name: ignoring $opening on " . $dates[0] . "\n";
                    unshift @del_indexes, $idx; # unshift is push_front, so we reverse the order, for the delete
                } else {
                    push @date_sets, [ @dates ];
                }
            }
            # Delete ignored cases
            foreach my $item (@del_indexes) {
                splice(@all_openings, $item, 1);
            }
            #print day_of_week_name($day_of_week) . " date_sets:"; show_array(@date_sets);
            my ($ref_rules, $ref_openings) = rules_for_day_of_week($day_of_week, \@date_sets, \@all_openings);
            my @rules = @$ref_rules;
            @all_openings = @$ref_openings;
            if ($rules[0] eq "ERROR-0") {
                print STDERR "WARNING: $office_id:$office_name: $dow_name has multiple outcomes: @all_openings\n";
                foreach my $opening (@all_openings) {
                    my @dates = sort @{$dayhash{$opening}};
                    print STDERR "   $opening on @dates\n";
                }
            }
            for ( my $idx = 0; $idx <= $#all_openings; $idx++ ) {
                my $opening = $all_openings[$idx];
                my $rule = $rules[$idx];
                $office_times{$office_id}{$day_of_week}{$rule} = $opening;
                $days_for_times{$office_id}{$rule}{$opening} .= $day_of_week;
                print STDERR "$office_name: $dow_name idx=$idx rule=$rule opening=$opening\n" if ($office_id eq $debug_me);;
            }
        }
    }

    foreach my $office_id (sort(keys %office_times)) {
        my $office_name = $office_names{$office_id};
        my $full_list = "";
        my $specific_list = ""; # put "current year" stuff at the end
        my %times = %{$office_times{$office_id}};
        my %days_for = %{$days_for_times{$office_id}};
        foreach my $day_of_week (sort(keys %times)) {
            my %rules = %{$times{$day_of_week}};
            my $numrules = %rules;
            foreach my $rule (sort(keys %rules)) {
                next if $rule eq 'IGNORE';
                my $opening = $rules{$rule};
                print STDERR day_of_week_name($day_of_week) . " rule '$rule' opening $opening\n" if ($office_id eq $debug_me);
                my $daynums = $days_for{$rule}{$opening};
                if (defined $daynums) {
                    if ($rule eq "") {
                        if ($day_of_week == 8) {
                            $full_list .= "PH " . ($opening eq 'FERME' ? "off" : $opening) . "; ";
                        } elsif ($opening ne 'off') { # off is default anyway (except for PH)
                            $full_list .= abbrevs($daynums) . " $opening; ";
                        }
                    } else {
                        my @splitted = split /\|/, $rule;
                        my $main_rule = shift @splitted;
                        if ($main_rule ne 'IGNORE') {
                            $full_list .= write_rule($main_rule, $daynums, $opening);
                        }
                        # Move any other rule (e.g. 2020) to the end
                        foreach my $single_rule (@splitted) {
                            $specific_list .= write_rule($single_rule, $daynums, $opening);
                        }
                    }
                    # The first day of the week in a range like Mo-Fr prints it all
                    undef $days_for{$rule}{$opening};
                }
            }
            # Flush specific list for that day-of-week
            # This is to ensure PH is always last
            $full_list .= $specific_list;
            $specific_list = "";
        }
        $full_list =~ s/; $//;
        $full_list =~ s/; /\;/g if (length($full_list) > 255);
        $full_list =~ s/;PH off//g if (length($full_list) > 255); # Oh well...

        if (length($full_list) > 255) {
            print STDERR "ERROR: rule too long (" . length($full_list) . ") $office_id|$office_name|$full_list\n";
        } else {
            print "$office_id|$office_name|$full_list\n";
        }
    }
}
main();
