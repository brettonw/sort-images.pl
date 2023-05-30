#! /usr/bin/env perl

use warnings FATAL => 'all';
use strict;
use File::Find;
use File::Basename;
use File::Copy;
use File::Path qw(make_path);
use Cwd;
use Cwd 'abs_path';
use Digest::file qw(digest_file_hex);

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
if (! exists ($args->{"inputDir"})) {
    print STDERR "USAGE: sort-duplicates.pl --inputDir path/to/input\n";
    exit;
}
my $inputDir = abs_path ($args->{"inputDir"});
#$inputDir =~ s/ /\\ /g;
print STDERR "INPUT ($inputDir)\n";

my $exifTypes = {};
foreach my $exifType ("jpg", "jpeg", "gif", "mov", "heic", "png", "m4v", "heic") {
    $exifTypes->{$exifType} = $exifType;
}

sub detailFile {
    my ($filename) = @_;
    my $detail = { filename => $filename };
    if ((-f "$filename") && ($filename =~ /^(.*\/)([^\/]*)$/)) {
        $detail->{path} = $1;
        $detail->{leaf} = $2;
        $detail->{type} = lc (($detail->{leaf} =~ /\.([^\.]*)$/) && $1);
    }
    return $detail;
}

# resolve an icloud file and return the updated detail
sub resolveFile {
    my ($detail) = @_;

    if ($detail->{type} eq "icloud") {
        print STDERR "  (CLOUD) $detail->{leaf}";
        # get the leaf name from the plist file
        my $leaf = `/usr/libexec/PlistBuddy -c Print:NSURLNameKey "$detail->{filename}"`;
        chop ($leaf);
        my $type = lc (($leaf =~ /\.([^\.]*)$/) && $1);

        print STDERR "  -> (FILE) $leaf";

        if (exists ($exifTypes->{$type})){
            print STDERR "\n      DOWNLOAD ";

            # download the file, and then wait for it
            my $filename = "$detail->{path}/$leaf";
            system ("brctl download \"$filename\"");
            while (! -f $filename) {
                sleep (1);
                print STDERR ".";
            }
            print STDERR "\n";
            return detailFile ($filename);
        } else {
            print STDERR " - SKIP UNSUPPORTED TYPE IN CLOUD\n";
        }
    }
    return $detail;
}

my $enumeratedFiles = {};

sub enumerated {
    my $detail = detailFile ($File::Find::name);
    if (-d $detail->{filename}) {
        print STDERR "(DIRECTORY) $detail->{filename}\n";
    } elsif (exists ($detail->{leaf}) && ($detail->{leaf} ne ".DS_Store")) {
        # get the md5 hash of the resolved file as the basename
        $detail = resolveFile ($detail);
        my $hash = digest_file_hex($detail->{filename}, "MD5");

        # get the basename for this file
        my $basename = ($detail->{leaf} =~ /^\.?(\d{4}(-\d\d)+)/) && $1;
        my $id = ($detail->{leaf} =~ /$basename(Z?)(-\d)\./) ? $2 : "-0";
        my @basenameSplit = split (/-/, $basename);
        while (scalar (@basenameSplit) > 6) {
            pop (@basenameSplit);
        }
        $basename = join ("-", @basenameSplit);
        $id = "$basename$id";

        print STDERR "  File: ($id) $hash\n";

        # vivify
        if (! exists ($enumeratedFiles->{$hash})) {
            # vivify, and save the detail
            my $filesHash = $enumeratedFiles->{$hash} = {};
            $filesHash->{$id} = $detail;
        } else {
            my $filesHash = $enumeratedFiles->{$hash};

            # get the functional leaf name and save it
            $filesHash->{$id} = $detail;

            if (scalar (%$filesHash) > 1 ) {
                # we want to save only the lowest sort option
                my @files = sort keys %$filesHash;
                my $keepFileId = shift @files;
                my $keepDetail = $filesHash->{$keepFileId};
                print STDERR "    KEEP     - ($keepFileId) $keepDetail->{leaf}\n";

                foreach my $discardFileId (@files) {
                    my $discardDetail = $filesHash->{$discardFileId};
                    delete $filesHash->{$discardFileId};
                    print STDERR "    DISCARD  - ($discardFileId) $discardDetail->{leaf}\n";
                    unlink ($discardDetail->{filename});
                }
            } else{
                print STDERR "ERROR IN FILENAMES ($id = $detail->{leaf})\n";
            }
        }
    }
}

# enumerate all the files in the current sub-tree
my %options = (
    wanted => \&enumerated,
    follow             => 1,
    follow_skip        => 2
);
find(\%options, $inputDir);
