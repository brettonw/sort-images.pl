#! /usr/bin/env perl

use warnings FATAL => 'all';
use File::Find;
use File::Basename;
use File::Copy;
use File::Path qw(make_path);
use Cwd;
use Cwd 'abs_path';
use File::stat;
use Time::Piece;

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
my $inputDir = abs_path ($args->{"inputDir"});
#$inputDir =~ s/ /\\ /g;
if (! exists ($args->{"outputDir"})) {
    print STDERR "USAGE: sort-images.pl --inputDir path/to/input --outputDir path/to/output\n";
    exit;
}
my $outputDir = abs_path ($args->{"outputDir"});
#$outputDir =~ s/ /\\ /g;
print STDERR "INPUT ($inputDir)\nOUTPUT ($outputDir)\n";

# the exif tags to look for in the order of authority - i.e. what is most likely to be correct
my @dateTags = (
    "CreateDate",
    "DateTimeCreated",
    "DateTimeOriginal",
    "DateCreated",
    "ContentCreateDate",
    "MediaCreateDate",
    "TrackCreateDate",
    "GpsDateTime",
    "GpsDateStamp",
    "FileModifyDate"
);

sub resolveFile {
    my ($path, $leaf, $type) = @_;

    # ensure the path exists
    make_path($path);

    # add a counter while the file exists
    my $result = "$path$leaf.$type";
    my $index = 0;
    while (-f $result) {
        ++$index;
        $result = "$path$leaf-$index.$type";
    }
    return $result;
}

sub pathFromDate {
    my ($date, $leaf, $type) = @_;
    # 2020-02-26-15-32-40
    if (length ($date) >= 10) {
        my @dateComponents = split (/-/, $date);
        my $subPath = join ('/', $dateComponents[0], $dateComponents[1]);
        return resolveFile ("$outputDir/$subPath/", $date, $type);
    } else {
        return resolveFile ("$outputDir/$date/", $leaf, $type);
    }
}

sub getDateForFile {
    my ($filename, $leaf, $type) = @_;

    # check if the file has data
    my $size = -s $filename;
    print STDERR " ($size)";
    if ($size > 0) {
        # look for useful dates in the exif data
        foreach my $dateTag (@dateTags) {
            my $date = `exiftool -$dateTag "$filename" 2> /dev/null`;
            chop ($date);
            if (length ($date) > 0) {
                # we got a date of some sort... process it and move the file
                $date =~ s/^[^:]*:\s*//;
                $date = join ('-', split (/[: ]/, $date));
                print STDERR " ($dateTag -> $date)";
                my $copyToPath = pathFromDate ($date, $leaf, $type);
                print STDERR "\n  -> (MOVE TO) $copyToPath\n";
                move ($filename, $copyToPath);
                #copy ($filename, $copyToPath);
                return;
            }
        }

        print STDERR " (NO DATE)\n";

        #my $filetime = localtime (stat($filename)->mtime);
        #my $date = $filetime->ymd ("-") . "-" . $filetime->hms ("-");
        #print STDERR " (FileCreateDate -> $date)";
        #my $copyToPath = pathFromDate ($date, $leaf, $type);
        #print STDERR "\n  -> (MOVE TO) $copyToPath\n";
        #move ($filename, $copyToPath);
    } else {
        # remove the 0-size file?
        print STDERR " (empty file)\n";
    }
}

my $exifTypes = {};
foreach my $exifType ("jpg", "jpeg", "gif", "mov", "heic", "png") {
    $exifTypes->{$exifType} = $exifType;
}

sub enumerated {
    my $filename = $File::Find::name;
    if ((-f "$filename") && ($filename =~ /^(.*\/)([^\/]*)$/)) {
        my $path = $1;
        my $leaf = $2;
        my $type = lc (($leaf =~ /\.([^\.]*)$/) && $1);

        print STDERR "\n";

        if (exists ($exifTypes->{$type})){
            print STDERR "(FILE) $filename";
            getDateForFile ($filename, $leaf, $type);
        } elsif ($type eq "icloud") {
            print STDERR "(CLOUD) $filename";
            # get the leaf name from the plist file
            my $leaf = `/usr/libexec/PlistBuddy -c Print:NSURLNameKey "$filename"`;
            chop ($leaf);
            $type = lc (($leaf =~ /\.([^\.]*)$/) && $1);

            $filename = "$path$leaf";
            print STDERR "\n  -> (FILE) $filename";

            if (exists ($exifTypes->{$type})){
                print STDERR " - DOWNLOAD ";

                # download the file, and then wait for it
                system ("brctl download \"$leaf\"");
                while (! -f $filename) {
                    sleep (1);
                    print STDERR ".";
                }
                print STDERR " - ";

                # now process it
                getDateForFile ($filename, $leaf, $type);
            } else {
                print STDERR " - SKIP UNSUPPORTED TYPE IN CLOUD\n";
            }
        } else {
            print STDERR "(SKIP) $filename - UNSUPPORTED TYPE\n";
        }
    } else {
        print STDERR "(DIRECTORY) $filename\n";
    }
}

# enumerate all the files in the current sub-tree
my %options = (
    wanted => \&enumerated,
    follow             => 1,
    follow_skip        => 2
);
find(\%options, $inputDir);
