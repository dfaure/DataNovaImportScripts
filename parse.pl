#!/usr/bin/perl

use strict;
use Text::CSV;
use warnings FATAL => 'all';
use DateTime::Format::ISO8601;
use Class::Struct;
use v5.14;     # using the + prototype for show_array, new to v5.14
use POSIX qw(strftime);

my $debug_me = defined $ENV{'DEBUGREF'} ? $ENV{'DEBUGREF'} : 'NONE';
my $skip_old = not defined $ENV{'KEEPOLD'};
my $file_start_date; # get it from the input file so that time passing doesn't break unittests
my $file_dt; # same, parsed

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
    my ($daynums) = @_; # ex: 1235, 8 for PH
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
    if ($date =~ /-01-01$/ ||
        $date eq '2021-04-05' || # paques (easter)
        $date =~ /-05-01$/ ||
        $date =~ /-05-08$/ ||
        $date eq '2021-05-13' || # ascension
        $date eq '2021-05-24' || # pentecote
        $date =~ /-07-14$/ ||
        $date =~ /-08-15$/ ||
        $date =~ /-11-01$/ ||
        $date =~ /-11-11$/ ||
        $date =~ /-12-25$/) {
        $day_of_week = 8;
    }
    die if get_year($date) == 2022; # TODO update list of public holidays above

    $cache{$date} = $day_of_week;

    return $day_of_week;
}

sub get_year($) {
    return (shift =~ /^([0-9]{4})/) ? $1 : undef;
}

sub get_month($) {
   return (shift =~ /^[0-9]{4}-([0-9]+)-/) ? $1 : undef;
}

sub get_day($) {
   return (shift =~ /^[0-9]{4}-[0-9]+-([0-9]+)$/) ? $1 : undef;
}

# Return e.g. "2020 Dec 24" for 2020-12-24. Could be done faster.
sub full_day_name($) {
    my ($date) = @_;
    return get_year($date) . ' ' . month_name(get_month($date)) . ' ' . get_day($date);
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

# https://perldoc.perl.org/Class::Struct
use Class::Struct Rules => {
    dates_sets => '@',
    selectors => '@',
    openings => '@',
    day_exceptions => '%'
};
#sub has_rule {
#    my $self = shift;
#    return scalar @{$self->{'Rules::selectors'}} >= 1;
#}

# https://perldoc.perl.org/Class::Struct
use Class::Struct Context => {
    office_id => '$',
    office_name => '$',
    day_of_week => '$'
};

sub debug_step($$$) {
    my ($context, $func, $rules) = @_;
    my @selectors = @{$rules->selectors};
    my @openings = @{$rules->openings};

    if ($context->office_id eq $debug_me) {
        print "$func\n";
        print "  Selectors:\n"; show_array(@selectors);
        print "  Openings:\n"; show_array(@openings);
        print "  Day exceptions:\n";
        my %day_exceptions = %{$rules->day_exceptions};
        foreach my $key (keys %day_exceptions) {
            print "    $key: " . $day_exceptions{$key} . "\n";
        }
    }
}

sub check_consistency($$$) {
    my ($context, $func, $rules) = @_;
    my @selectors = @{$rules->selectors};
    my @openings = @{$rules->openings};

    debug_step($context, $func, $rules);
    if ((scalar @selectors) != (scalar @openings)) {
        my $dow_name = day_of_week_name($context->day_of_week);
        print STDERR "ERROR: " . $context->office_id . ":" . $context->office_name . ": $dow_name: ".
                     "$func: different number of selectors and openings: " . (scalar @selectors) . " selectors " . (scalar @openings) . " openings\n";
        show_array(@selectors);
        print "Openings:\n"; show_array(@openings);
        die; # Adjust when we'll get data sets without any PH
    }
}

sub year_for_all($) {
    my $ref_dates = shift;
    my @dates = @$ref_dates;
    return undef if scalar @dates < 3; # Not enough
    #print "Dates:\n"; show_array(@dates);
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
    my ($rules) = @_;
    my @date_sets = @{$rules->dates_sets};
    return 0 if scalar @date_sets != 2;
    my @years = ();
    my %seen_years = ();
    for my $i ( 0 .. $#date_sets ) {
        my @dates = @{$date_sets[$i]};
        my $year = year_for_all(\@dates);
        return 0 unless defined $year;
        return 0 if defined $seen_years{$year};
        $seen_years{$year} = 1;

        state $currentyear = get_year($file_start_date);
        $year = "" if ($year == ($currentyear + 1)); # Assume next year's hours will stay
        push @years, $year;
    }
    #print STDERR "Year split: " . @date_sets . "\n";
    #show_array(@years);
    $rules->selectors(\@years); # assign

    return 1;
}

# If the input array has a single day in one date_set, and everything in the other
# then define an exception for that single day, and a "" rule for the other set.
# Returns 1 on success
sub try_single_day_exception($$) {
    my ($context, $rules) = @_;
    my @date_sets = @{$rules->dates_sets};
    # only tested with 2 and 3, and it gets very long otherwise
    return 0 if scalar @date_sets < 2 or scalar @date_sets > 3;
    my @openings = @{$rules->openings};
    my @deleted_openings = ();
    my $two_days = 0;
    my $off_index = -1;
    my %day_exceptions = ();
    for my $i ( 0 .. $#date_sets ) {
        my @dates = @{$date_sets[$i]};
        my $opening = $openings[$i];
        #print "" . (scalar @dates) . " dates\n";
        if (scalar @dates == 1) {
            die if defined $day_exceptions{$opening}; # aren't openings unique in date_sets? If not, the next line overwrites...
            $day_exceptions{$opening} = $dates[0];
            unshift @deleted_openings, $i; # unshift is push_front, so we reverse the order, for the delete
            $off_index = $i if ($opening eq 'off');
        } elsif (scalar @dates == 2) {
            # An exception for two days. Do this only once to avoid too long rules.
            return 0 if ($two_days > 0);
            $day_exceptions{$opening} = $dates[0] . ',' . $dates[1];
            unshift @deleted_openings, $i;
            $two_days = 1;
            $off_index = $i if ($opening eq 'off');
        }
    }

    # Special case for public holidays
    # We want a default "PH: off" rule, if at least one PH is off.
    if ($context->day_of_week == 8) {
        if (defined $day_exceptions{'off'}) {
            delete($day_exceptions{'off'});
        } else {
            # Which one should we pick as default rule?
            # Any one would do, but we need reliable results...
            $rules->openings(['ERROR']); # assign
            push @openings, 'ERROR';
        }
    }

    $rules->day_exceptions(\%day_exceptions); # assign
    foreach my $del_idx (@deleted_openings) {
        if ($context->office_id eq $debug_me) {
            if ($context->day_of_week == 8 and $off_index == $del_idx) {
                print STDERR "NOT deleting at index $del_idx\n";
            } else {
                print STDERR "Deleting at index $del_idx\n";
            }
        }

        next if ($context->day_of_week == 8 and $off_index == $del_idx);
        splice(@openings, $del_idx, 1);
        splice(@date_sets, $del_idx, 1);
    }
    $rules->openings(\@openings); # assign
    $rules->dates_sets(\@date_sets); # assign
    return 1;
}

sub month_for_all($) {
    my $ref_dates = shift;
    my @dates = @$ref_dates;
    return undef if scalar @dates < 3; # Not enough
    #print "Dates:\n"; show_array(@dates);
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
sub try_month_exception($) {
    my ($rules) = @_;
    my @date_sets = @{$rules->dates_sets};
    return 0 if scalar @date_sets != 2;
    my @openings = @{$rules->openings};
    my @selectors = ();
    my $date_set_number;
    my $exception_month;
    for my $i ( 0 .. $#date_sets ) {
        my @dates = @{$date_sets[$i]};
        my $month = month_for_all(\@dates);
        if (defined $month) {
            return 0 if defined $date_set_number; # only one
            $date_set_number = $i;
            my $year = year_for_all(\@dates);
            die "@dates has $month but no year?" unless defined $year; # surely same month = same year
            push @selectors, "$year " . month_name($month);
            $exception_month = $month;
        } else {
            push @selectors, '';
        }
    }
    return 0 if not defined $date_set_number;
    die if not defined $exception_month; # they are defined together
    # Check that the other date set has no date in that month
    my $other_date_set = 1 - $date_set_number; # 0->1, 1->0
    foreach my $date (@{$date_sets[$other_date_set]}) {
        return 0 if get_month($date) eq $exception_month;
    }
    $rules->selectors(\@selectors); # assign
    return 1;
}

# The future changes will be set when running the script again later.
sub delete_future_changes($$) {
    my ($context, $rules) = @_;
    my @date_sets = @{$rules->dates_sets};
    my $abort = 0;

    # Determine min-max range for each set
    my @min = (); # TODO REMOVE, SIMPLIFY
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
        # 2 would work too, if try_single_day_exception handles all 2-days-exceptions,
        # but it leads to final rules too long, see two_two_days_exceptions.csv.
        return $abort if (scalar @dates <= 1);
        foreach my $date (@dates) {
            return $abort if ($date gt $last_min);
        }
    }

    # Yes => delete last_index
    splice(@{$rules->openings}, $last_index, 1);
    splice(@{$rules->dates_sets}, $last_index, 1);
    print STDERR "Deleted future changes" . $last_index . "\n" if ($context->office_id eq $debug_me);
    return 1;
}

# Return 1 if all dates in the $1 array are the $2th "weekday" of the month.
# $2 is 1 for first "weekday" of the month (e.g. first saturday)
# $2 is -1 for last "weekday" of the month (e.g. last saturday)
sub same_weekday_of_month_for_all($$) {
    my ($ref_dates, $which) = @_;
    my @dates = @$ref_dates;
    return 0 if scalar @dates < 3; # Not enough
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
    my ($which, $rules) = @_;
    my @date_sets = @{$rules->dates_sets};
    my @selectors;
    my %seen; # keys 0 and 1
    for my $i ( 0 .. $#date_sets ) {
        my $all_same_week = 1;
        my @dates = @{$date_sets[$i]};
        my $yes = same_weekday_of_month_for_all(\@dates, $which);
        return 0 if defined $seen{$yes};
        $seen{$yes} = 1;
        push @selectors, $yes ? "[$which]" : "";
    }
    $rules->selectors(\@selectors); # assign
    return 1;
}

# If the input array has [2020-11-07 2020-11-21 ...] and [2020-10-31 2020-11-14 ...]
# then return [ 'week 1-53/2', 'week 2-53/2' ]
sub try_alternating_weeks($) {
    my ($rules) = @_;
    my @date_sets = @{$rules->dates_sets};
    return 0 if (scalar @date_sets == 0);
    my @openings = @{$rules->openings};
    my %found_odd_even = (); # $Even => 0; $Odd => 0
    #my %found_odd_even_prev_year = (); # $Even => 0; $Odd => 0
    my @selectors;

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
#                         return 0 if $found_odd_even_prev_year{$state};
#                         $found_odd_even_prev_year{$state} = 1;
#                         $state_prev_year = $state;
#                         $year = $y;
#                         $state = $new_state;
                    } else {
                        return 0;
                    }
                }
            }
        }
        #say "state=$state";
        die if $state == $None; # surely dates isn't empty?
        return 0 if $found_odd_even{$state};
        $found_odd_even{$state} = 1;

        # Disabled, only look at current year
        if (0 and defined $state_prev_year) {
            # Next year is the general rule, prev year is an override, so it comes second.
            # The '|' is an internal syntax, split up before outputting OSM rules
            if ($openings[$i] eq 'off') {
                push @selectors, "IGNORE|$prev_year " . $str[$state_prev_year];
            } else {
                push @selectors, $str[$state] . "|$prev_year " . $str[$state_prev_year];
            }
        } else {
            push @selectors, ($openings[$i] eq 'off') ? "IGNORE" : $str[$state];
        }
    }

    # We know there are more than one date_sets (in caller) and
    # 3+ would fail the found_odd_even test. So there must be 2 exactly.
    $rules->selectors(\@selectors);
    return 1;
}

# Main function for the core logic of this script.
# Called for one day of week at a time
# $day_of_week : 1 for Monday, 2 for Tuesday etc. -- mostly for debug output
# @date_sets : N sets of dates that have the same opening hours
# @openings : those N sets of openings (not much used here)
# Returns N sets of OSM rules and the corresponding opening hours, plus M single-day exceptions
sub rules_for_day_of_week($$$) {
    my ($context, $ref_dates, $ref_openings) = @_;

    #print day_of_week_name($context->day_of_week) . ": date sets\n"; show_array(@$ref_dates);

    my %day_exceptions = ();

    my $rules = Rules->new( openings => $ref_openings, dates_sets => $ref_dates );

    if (try_year_split($rules)) {
        check_consistency($context, "After try_year_split", $rules);
        return $rules;
    }

    my $success = 0;

    if (try_single_day_exception($context, $rules)) {
        debug_step($context, "After try_single_day_exception", $rules);
    }

    while (scalar @{$rules->dates_sets} > 1) {
        $success = delete_future_changes($context, $rules);
        last if (!$success);
        debug_step($context, "After delete_future_changes", $rules);
    }

    my @date_sets = @{$rules->dates_sets};
    if (scalar @date_sets == 1) {
        # Stable opening times -> single rule for that day
        push @{$rules->selectors}, "";
        return $rules;
    }

    if (try_year_split($rules)) {
        check_consistency($context, "After try_year_split", $rules);
        return $rules;
    }

    if (try_alternating_weeks($rules)) {
        check_consistency($context, "After try_alternating_weeks", $rules);
        return $rules;
    }

    for my $which(-1, 1 .. 4) {
        # -1 = last "weekday" of month, 1 = first "weekday" of month...
        return $rules if (try_same_weekday_of_month($which, $rules));
    }

    if (try_month_exception($rules)) {
        check_consistency($context, "After try_month_exception", $rules);
        return $rules;
    }

    for my $i (0..$#date_sets) {
        push @{$rules->selectors}, "ERROR-" . $i;
    }
    return $rules;
}

sub write_rule($$$) {
    my ($rule, $daynums, $opening) = @_;
    if ($rule =~ /^[0-9]{4} [a-zA-Z]+ [0-9]{2}/) { # rule with a specific date, don't output the weekday
        return "$rule $opening; ";
    }
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

    my $today = DateTime->now->ymd;

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
        next if ($skip_old and $date lt $today);
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
        $opening = "off" if $opening =~ /^FERME$/;
        push @{$office_data{$office_id}{$day_of_week}{$opening}}, $date;
    }
    $file_dt = fast_parse_datetime($file_start_date);
    #print STDERR "Parsed $line_nr lines\n";

    # Aggregate the different opening hours for Mondays in different rules
    # The empty rule is the default one. But this allows for exceptions.
    my %office_times = (); # office => (day of week => (rule => times))
    # To group days (like "Mo-Fr"), the key here is the opening times like 09:00-12:00,14:00-16:30
    my %days_for_times = ();  # office => (rule => (times => day of week))
    # To group single-day exceptions with the same opening hours
    my %day_exceptions = (); # office => (times => days)

    foreach my $office_id (sort(keys %office_data)) {
        my $office_name = $office_names{$office_id};
        my %one_office_data = %{$office_data{$office_id}};
        foreach my $day_of_week (sort keys %one_office_data) {
            my $context = Context->new( office_id => $office_id, office_name => $office_name, day_of_week => $day_of_week );
            my %dayhash = %{$one_office_data{$day_of_week}};
            my $dow_name = day_of_week_name($day_of_week); # for debug
            my @all_openings = keys %dayhash;
            my @date_sets = ();
            for (my $idx = 0; $idx <= $#all_openings; $idx++) {
                my $opening = $all_openings[$idx];
                my @dates = sort @{$dayhash{$opening}};
                push @date_sets, [ @dates ];
            }
            if ($office_id eq $debug_me) {
                print STDERR "$office_name: $dow_name date_sets:\n";
                foreach my $opening (@all_openings) {
                    my @dates = sort @{$dayhash{$opening}};
                    print STDERR "   $opening on @dates\n";
                }
            }
            my $rules = rules_for_day_of_week($context, \@date_sets, \@all_openings);
            my @selectors = @{$rules->selectors};
            @all_openings = @{$rules->openings};
            #print STDERR "$office_name: $dow_name " . (scalar @selectors) . " selectors " . (scalar @all_openings) . " openings\n";
            if ((scalar @selectors) == 0) {
                print STDERR "ERROR: $office_id:$office_name: $dow_name has no rules at all. @all_openings\n";
                die; # Adjust when we'll get data sets without any PH
            }
            check_consistency($context, "Return value from rules_for_day_of_week", $rules);
            if ($selectors[0] eq "ERROR-0") {
                print STDERR "WARNING: $office_id:$office_name: $dow_name has multiple outcomes: @all_openings\n";
                foreach my $opening (@all_openings) {
                    my @dates = sort @{$dayhash{$opening}};
                    print STDERR "   $opening on @dates\n";
                }
            }
            for ( my $idx = 0; $idx <= $#all_openings; $idx++ ) {
                my $opening = $all_openings[$idx];
                my $selector = $selectors[$idx];
                $office_times{$office_id}{$day_of_week}{$selector} = $opening;
                $days_for_times{$office_id}{$selector}{$opening} .= $day_of_week;
                print STDERR "$office_name: $dow_name idx=$idx selector=$selector opening=$opening\n" if ($office_id eq $debug_me);;
            }
            my %local_day_exceptions = %{$rules->day_exceptions};
            foreach my $opening (keys %local_day_exceptions) {
                push @{$day_exceptions{$office_id}{$opening}}, split(',', $local_day_exceptions{$opening});
            }
        }
        # Assume "PH off" when there are no PH in the next 3 months, for stability
        if (!defined($one_office_data{8})) {
            $office_times{$office_id}{8}{''} = 'off';
            $days_for_times{$office_id}{''}{'off'} .= '8';
        }
    }

    foreach my $office_id (sort(keys %office_times)) {
        my $office_name = $office_names{$office_id};
        my $full_list = "";
        my $specific_list = ""; # put "current year" stuff at the end
        my %times = %{$office_times{$office_id}};
        my %days_for = %{$days_for_times{$office_id}};
        foreach my $day_of_week (sort(keys %times)) {
            my %selectors = %{$times{$day_of_week}};
            my $numselectors = %selectors;
            foreach my $selector (sort(keys %selectors)) {
                next if $selector eq 'IGNORE';
                my $opening = $selectors{$selector};
                print STDERR day_of_week_name($day_of_week) . " selector '$selector' opening $opening\n" if ($office_id eq $debug_me);
                my $daynums = $days_for{$selector}{$opening};
                if (defined $daynums) {
                    if ($selector eq "") {
                        if ($day_of_week == 8) {
                            $full_list .= "PH $opening; ";
                        } elsif ($opening ne 'off') { # off is default anyway (except for PH)
                            $full_list .= abbrevs($daynums) . " $opening; ";
                        }
                    } else {
                        my @splitted = split /\|/, $selector;
                        my $main_selector = shift @splitted;
                        if ($main_selector ne 'IGNORE') {
                            $full_list .= write_rule($main_selector, $daynums, $opening);
                        }
                        # Move any other selector (e.g. 2020) to the end
                        foreach my $single_selector (@splitted) {
                            $specific_list .= write_rule($single_selector, $daynums, $opening);
                        }
                    }
                    # The first day of the week in a range like Mo-Fr prints it all, except PH
                    $daynums =~ s/[1-7]*//g;
                    if ($daynums eq '') {
                        undef $days_for{$selector}{$opening};
                    } else {
                        $days_for{$selector}{$opening} = $daynums;
                    }
                }
            }
            # Flush specific list for that day-of-week
            # This is to ensure PH is always last
            $full_list .= $specific_list;
            $specific_list = "";
        }
        if (defined $day_exceptions{$office_id}) {
            my %local_day_exceptions = %{$day_exceptions{$office_id}};
            foreach my $opening (sort(keys %local_day_exceptions)) {
                my @days = @{$local_day_exceptions{$opening}};
                foreach my $day (sort @days) {
                    $full_list .= full_day_name($day) . ",";
                }
                $full_list =~ s/,$/ $opening; /; # Remove last comma, add opening hours
            }
        }

        $full_list =~ s/; $//;

        # Try hard to fit in under 255 characters. Someone told me. Not mentioned in the spec though.
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
