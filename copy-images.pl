#! /usr/bin/env perl

use warnings FATAL => 'all';
use strict;
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
$inputDir =~ s/\/*$//g;
if (! exists ($args->{"outputDir"})) {
    print STDERR "USAGE: sort-images.pl --inputDir path/to/input --outputDir path/to/output\n";
    exit;
}
my $outputDir = abs_path ($args->{"outputDir"});
$outputDir =~ s/\/*$//g;
print STDERR "INPUT ($inputDir)\nOUTPUT ($outputDir)\n";

sub enumerated {
    my $fullpathname = $File::Find::name;
    my $filename = $fullpathname;
    $filename =~ s/$inputDir\/?//;
    #print STDERR "(FIND) $filename\n";
    if ((-f "$fullpathname") && ($filename =~ /^(.*\/)([^\/]*)$/)) {
        my $path = $1;
        my $leaf = $2;
        my $type = lc (($leaf =~ /\.([^\.]*)$/) && $1);

        print STDERR "\n(TYPE $type) ";

        if ($type eq "icloud") {
            print STDERR "(CLOUD) $filename";
            # get the leaf name from the plist file
            my $leaf = `/usr/libexec/PlistBuddy -c Print:NSURLNameKey "$fullpathname"`;
            chop ($leaf);
            $type = lc (($leaf =~ /\.([^\.]*)$/) && $1);

            $filename = "$path$leaf";
            print STDERR "\n  -> (FILE) $filename";

            print STDERR " - DOWNLOAD ";

            # download the file, and then wait for it
            system ("brctl download \"$leaf\"");
            while (! -f $filename) {
                sleep (1);
                print STDERR ".";
            }
        } else {
            $filename = "$path$leaf";
            print STDERR "(FILE) $filename";
        }

        # check if the file has data
        my $size = -s $fullpathname;
        print STDERR " - ($size bytes)";
        if ($size > 0) {
            my $copyToPath = "$outputDir/$filename";
            print STDERR " -> $copyToPath\n";
            #move ($filename, $copyToPath);
            #copy ($filename, $copyToPath);
        } else {
            # remove the 0-size file?
            print STDERR " (empty file)\n";
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
