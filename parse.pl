#!/usr/bin/perl

use Text::CSV;
use strict;
use warnings FATAL => 'all';
use DateTime::Format::ISO8601;

sub panic($) {
    print "@_\n";
    exit 1;
}
sub usage() {
    panic "Usage: $0 csv_file";
}

# Turn "1235" into "Mo-We,Fr"
sub abbrevs($) {
    my ($daynums) = @_; # ex: 1235, 8 for NH
    my @dayAbbrev = ( 'ERROR', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su', 'PH' );
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
                    $ret .= $dayAbbrev[$start] . '-' . $dayAbbrev[$cur] . ',';
                } else {
                    $ret .= $dayAbbrev[$cur] . ',';
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

sub rule_for_day_of_week($$$)
{
    my ($day_of_week, $opening, $ref_all_openings) = @_;
    my @all_openings = @$ref_all_openings;
    my $rule = "";

    return $rule;
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
            my @del_indexes = ();
            for ( my $idx = 0; $idx <= $#all_openings; $idx++ ) {
                my $opening = $all_openings[$idx];
                my @dates = @{$dayhash{$opening}};
                my $numdates = @dates;
                #print "$office_name $day_of_week $opening $numdates dates: @dates\n";
                if ($numdates == 1) {
                    # ignore special cases for now
                    #print "Ignoring $opening on " . $dates[0] . "\n";
                    unshift @del_indexes, $idx; # unshift is push_front, so we reverse the order, for the delete
                }
            }
            # Delete ignored cases
            foreach my $item (@del_indexes) {
                splice(@all_openings, $item, 1);
            }
            my $num_openings = @all_openings;
            if ($num_openings > 1) {
                print "WARNING: $office_name $day_of_week has multiple outcomes: @all_openings\n";
                foreach my $opening (@all_openings) {
                    my @dates = @{$dayhash{$opening}};
                    print "   $opening on @dates\n";
                }
            }
            foreach my $opening (@all_openings) {
                my $rule = rule_for_day_of_week($day_of_week, $opening, \@all_openings);
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
                my $daynums = $days_for{$rule}{$opening};
                if (defined $daynums) {
                    $full_list .= "$rule " . abbrevs($daynums) . " $opening;";
                    undef $days_for{$rule}{$opening};
                }
            }
        }
        $full_list =~ s/;$//;

        print "$office_name=$full_list\n";
    }
}
main();
