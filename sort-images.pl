#! /usr/bin/env perl

use warnings FATAL => 'all';
use File::Find;
use File::Path;
use File::Basename;
use Cwd;

my @dateTags = (
    "CreateDate",
    "DateCreated",
    "DateTimeCreated",
    "ContentCreateDate",
    "MediaCreateDate",
    "TrackCreateDate",
    "GpsDateTime",
    "GpsDateStamp"
);
sub getDateForFile {
    my ($filename) = @_;
    my $size = -s $filename;
    print STDERR " ($size)";
    if ($size > 0) {
        my $dateValues = {};
        foreach my $dateTag (@dateTags) {
            my $exifDate = `exiftool -$dateTag "$filename" 2> /dev/null`;
            chop ($exifDate);
            if (length ($exifDate) > 0) {
                $dateValues->{$dateTag} = $exifDate;
            }
        }

        # if we got dates...
        if (scalar (%$dateValues) > 0) {
            foreach my $dateTag (sort keys %$dateValues)
            {
                my $date = $dateValues->{$dateTag};
                $date =~ s/^[^:]*:\s*//;
                my @dateComponents = split (/[: ]/, $date);
                $date = join ('-', @dateComponents);
                print STDERR " ($dateTag -> $date)";
            }
        } else {
            print STDERR " (no date)";
        }
    }
}

sub enumerated {
    my $filename = $File::Find::name;
    if (-f $filename) {
        if ($filename =~ /(.*\/)([^\/]*)/) {
            my $path = $1;
            my $leaf = $2;
            if (($leaf =~ /jpe?g$/i) || ($leaf =~ /heic$/i) || ($leaf =~ /mov$/i)) {
                print STDERR "$filename";
                getDateForFile ($filename);
            } elsif ($leaf =~ /icloud$/i) {
                # get the leaf name from the plist file
                my $leaf = `/usr/libexec/PlistBuddy -c Print:NSURLNameKey $filename`;
                chop ($leaf);

                $filename = "$path$leaf";
                print STDERR "$filename";
                if (($leaf =~ /jpe?g$/i) || ($leaf =~ /heic$/i) || ($leaf =~ /mov$/i)) {
                    print STDERR " - DOWNLOAD ";

                    # download the file, and then wait for it
                    system ("brctl download $leaf");
                    while (! -f $filename) {
                        sleep (1);
                        print STDERR ".";
                    }
                    print STDERR " - ";

                    # now process it
                    getDateForFile ($filename);
                } else {
                    print STDERR " - SKIP UNSUPPORTED TYPE IN CLOUD";
                }
            } else {
                print STDERR "$filename - SKIP UNSUPPORTED TYPE";
            }

            print STDERR "\n";
        }
    }
}

# read the arguments
my $defaultArgKey = "inputDir";
my $argKey = $defaultArgKey;
my $args = {};
$args->{$defaultArgKey} = ".";
foreach my $arg (@ARGV) {
    if ($arg =~ s/^--//) {
        $argKey = $arg;
    } else {
        # put the value into the args hash with the existing key
        $args->{$argKey} = $arg;
        $argKey = $defaultArgKey;
    }
}

# get the destination for all the files
my $inputDir = $args->{"inputDir"};
if (! exists ($args->{"outputDir"})) {
    print STDERR "USAGE: sort-images.pl --inputDir path/to/input --outputDir path/to/output\n";
    exit;
}
my $outputDir = $args->{"outputDir"};
print STDERR "INPUT ($inputDir)\nOUTPUT ($outputDir)\n";

# enumerate all the files in the current sub-tree
$File::Find::follow=1;
my %options = ( wanted => \&enumerated,
    follow             => 1,
    follow_skip        => 2);

find(\%options, $inputDir);
