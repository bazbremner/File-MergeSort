#!/usr/bin/perl

use 5.006;
use warnings;
use strict;

use Test::More 'no_plan';

BEGIN { use_ok('IO::File') };         # test 1
BEGIN { use_ok('File::MergeSort') };  # test 2

my @files = qw( t/1 t/2 t/3 t/4 t/5 t/6);
my $coderef = sub { my $line = shift; substr($line,0,2); };

my $m;
eval {
    $m = File::MergeSort->new( \@files, $coderef );
};

ok( ref $m eq 'File::MergeSort'); # test 3

my $in_lines = 0;

foreach my $file ( @files ) {
    open F, "< $file" or die "Unable to open test file $file: $!";
    while (<F>) { $in_lines++ };
    close F or die "Problems closing test file, $file: $!";
}

my $d;

eval {
    $d = $m->dump("t/output");
};

ok($d eq $in_lines); # test 4

my $out_lines = 0;

open F, "< t/output" or die "Unable to open test output: $!";
while (<F>) { $out_lines++ };
close F or die "Problems closing test output: $!";

ok($d eq $out_lines); # test 5

if (-f "t/output") {
    unlink "t/output" or die "Unable to unlink test output: $!";
}

eval {
    $m = File::MergeSort->new( \@files, $coderef );
};


# Check data being returned by next_line really is in sorted order.

my $i = 0;
my $last;

while ( my $line = $m->next_line() ) {
    my $key = $coderef->( $line );
    ok( $key ge $last) if $i > 1;
    $last = $key;
    $i++;
}

ok($i eq $out_lines );
