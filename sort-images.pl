#! /usr/bin/env perl

use warnings FATAL => 'all';
use File::Find;
use File::Path;
use File::Basename;
use Cwd;

sub getDateForFile {
    my ($filename) = @_;
    my $size = -s $filename;
    print "$filename ($size)";
    if ($size > 0) {
        my $createDate = `exiftool -CreateDate "$filename"`;
        chop ($createDate);
        if ($createDate =~ /: (\d[\d: ]*\d)$/) {
            $createDate = $1;
            $createDate =~ s/ /-/;
            print " ($createDate)";
        } else {
            print " (no date)";
        }
    }
    print "\n";
}

sub enumerated {
    my $filename = $File::Find::name;
    if (-f $filename) {
        if ($filename =~ /(.*\/)([^\/]*)/) {
            my $path = $1;
            my $leaf = $2;
            if ($leaf =~ /jpe?g$/i) {
                getDateForFile ($filename);
            } elsif ($leaf =~ /icloud$/i) {
                # get the leaf name from the file
                # brctl download `/usr/libexec/PlistBuddy -c Print:NSURLNameKey .IMG_9215.jpeg.icloud`
                my $nameKey = `/usr/libexec/PlistBuddy -c Print:NSURLNameKey $filename`;
                chop ($nameKey);

                $filename = "$path$nameKey";
                print "DOWNLOAD - ";

                # download the file, and then wait for it
                system ("brctl download $nameKey");
                while (! -f $filename) {
                    sleep (1);
                }

                # now process it
                getDateForFile ($filename);
            }
        }
    }
}

# get the destination for all the files

# enumerate all the files in the current sub-tree
$File::Find::follow=1;
my %options = ( wanted => \&enumerated,
    follow             => 1,
    follow_skip        => 2);

find(\%options, ".");
