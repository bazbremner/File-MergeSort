package File::MergeSort;

use 5.006;     # 5.6.0
use strict;
use warnings;

use Carp;
use IO::File;

our $VERSION = '1.20';

my $have_io_zlib;

BEGIN {
    eval { require IO::Zlib; };
    unless ( $@ ) {
        require IO::Zlib;
        $have_io_zlib++;
    }
}

### PRIVATE METHODS

sub _open_file {
    my $self = shift;
    my $file = shift || croak 'No filename specified';

    my $fh;

    if ( $file =~ /[.](z|gz)$/ ) { # Files matching .z or .gz
        if ( $have_io_zlib ) {
            $fh = IO::Zlib->new( $file, 'rb' ) or croak "Failed to open file $file: $!";
        } else {
            croak 'IO::Zlib not available, cannot handle compressed files. Stopping';
        }
    } else {
        $fh = IO::File->new( $file, '<' ) or croak "Failed to open file $file: $!";
    }

    $self->{'open_files'}++;
    return $fh;
}

# Yes, I'm really closing filehandles, just trying to be consistent
# with the _open_file counterpart.
sub _close_file {
    my $self = shift;
    my $fh   = shift;

    $fh->close() or croak "Problems closing filehandle: $!";

    $self->{'open_files'}--;
    return 1;
}

sub _get_line {
    my $self = shift;
    my $fh   = shift || croak 'No filehandle supplied';

    my $line = <$fh>;

    return $line;
}

# Given a line of input and a code reference that extracts a value
# from the line, return an index value that can be used to compare the
# lines.
sub _get_index {
    my $self = shift;
    my $line = shift || croak 'No line supplied';

    my $code_ref = $self->{'index'};
    my $index    = $code_ref->( $line );

    if ( $index ) {
        return $index;
    } else {
        croak 'Unable to return an index. Stopping';
    }
}

### PUBLIC METHODS

sub new {
    my $class     = shift;
    my $files_ref = shift;      # ref to array of files.
    my $index_ref = shift;      # ref to sub that will extract index value from line

    unless ( ref $files_ref eq 'ARRAY' && @{ $files_ref } ) {
	croak 'Array reference of input files required';
    }

    unless ( ref $index_ref eq 'CODE' ) {
	croak 'Code reference required for merge key extraction';
    }

    my $self = { index      => $index_ref,
                 open_files => 0,
               };

    bless $self, $class;

    my @files;
    my $i = 0;
    foreach my $file ( @{ $files_ref } ) {
        my $fh  = $self->_open_file( $file );
        my $l   = $self->_get_line( $fh );
        my $idx = $self->_get_index( $l );

        my $f = { 'fh'    => $fh,
                  'line'  => $l,
                  'index' => $idx,
                  'pref'  => $i++, # preference: take the records from the files in the order specified.
                };

        push @files, $f;
    }

    # Now that the first records are complete for each file, sort them
    # by merge key then file order.  Create a sorted array of hashrefs
    # based on the index values of each file.
    $self->{'stack'} = [ sort {    $a->{'index'} cmp $b->{'index'}
                                || $a->{'pref'}  <=> $b->{'pref'}
                              } @files ];

    return $self;
}

sub next_line {
    my $self = shift;

    my $pick = shift @{ $self->{'stack'} };
    my $line = $pick->{'line'} || return;

    # Abandon sorting when there is only one file left.
    return $line if $self->{'open_files'} <= 1;

    # Re-populate invalidated data in the shifted structure, before
    # reinserting into stack.
    my $nextline = $self->_get_line( $pick->{'fh'} );

    if ( $nextline ) {
        $pick->{'line'}  = $nextline;
        $pick->{'index'} = $self->_get_index( $nextline );
    } else {
        $self->_close_file( $pick->{'fh'} );
    }

    # Re-organise the 'stack' structure to insert the newly fetched
    # data into the correct position for the next call. Since it
    # begins as a sorted array, and we only need to insert one element
    # in the appropriate position in the array, we can abandon the
    # loop as soon as we hit the right spot.
    # There may be room for optimisation here. Algorithms and/or tips
    # welcome.

    # Scan the array for the point where:

    # * The index of the element to insert is the less than than the
    # element in the array

    # ...or...

    # * The index of the element to insert is the same as that in the
    # array, but the preference of the element to insert is lower -
    # this is so that data is consistently fed in from the source
    # files in the order specified in the constuctor.

    # Previous behaviour can be had with last if $_->{'index'} ge $pick->{'index'};

    my $i = 0;

    foreach ( @{ $self->{'stack'} } ) {
        if (      $_->{'index'} gt $pick->{'index'}
             || ( $_->{'index'} eq $pick->{'index'} && $pick->{'pref'} <= $_->{'pref'} )
           ) {
            last;
        }
        $i++;
    }

    # And stuff the fresh data in the appropriate place.
    splice @{ $self->{'stack'} }, $i, 0, $pick;

    return $line;
}

# Dump the contents of the file to either STDOUT (default).
sub dump {
    my $self = shift;
    my $file = shift; # optional

    my $lines = 0;

    if ( $file ) {
        open my $fh, '>',  $file or croak "Unable to create output file $file: $!";

        while ( my $line = $self->next_line() ) {
            print $fh $line;
	    $lines++;
        }

        close $fh or croak "Problems closing output file $file: $!";
    } else {
        while ( my $line = $self->next_line() ) {
            print $line;
	    $lines++;
        }
    }

    return $lines;
}

1;

__END__

=head1 NAME

File::MergeSort - Mergesort ordered files.

=head1 SYNOPSIS

 use File::MergeSort;

 # Create the MergeSort object.
 my $sort = File::MergeSort->new(
                [ $file_1, ..., $file_n ],  # Anonymous array of input files
                \&extract_function,         # Sub to extract merge key
                );

 # Retrieve the next line for processing
 my $line = $sort->next_line;
 print $line, "\n";

 # Dump remaining records in sorted order to a file.
 $sort->dump( $file );    # Omit $file to default to STDOUT

=head1 DESCRIPTION

File::MergeSort provides methods to merge and process a number of
B<pre-sorted> files into a single sorted output.

Merge keys are extracted from the input lines using a user defined
subroutine. Comparisons on the keys are done lexicographically.

If C<IO::Zlib> is installed, both plaintext and compressed (.z or .gz)
files are catered for.

File::MergeSort is a hopefully straightforward solution for situations
where one wishes to merge data files with presorted records. An
example might be application server logs which record events
chronologically from a cluster.

=head2 POINTS TO NOTE

=head3 ASCII order merging

Comparisons on the merge keys are carried out lexicographically. The
user should ensure that the subroutine used to extract merge keys
formats the keys if required so that they sort correctly.

Note that earlier versions (< 1.06) of File::MergeSort performed
numeric, not lexicographical comparisons.

=head3 IO::Zlib is optional

IO::Zlib is no longer a prerequisite.
If IO::Zlib is installed, File::MergeSort will use it to handle
compressed input files.

If IO::Zlib is not installed and compressed files are specified as
input files, File::MergeSort will raise an exception.

If you do not need to process compressed files, there is no longer any
need install IO::Zlib to use File::MergeSort.

=head2 DETAILS

The user is expected to supply a list of file pathnames and a function
to extract an index value from each record line (the merge key).

By calling the "next_line" or "dump" function, the user can retrieve
the records in an ordered manner.

As arguments, File::MergeSort takes a reference to an anonymous array
of file paths/names and a reference to a subroutine that extracts a
merge key from a line.

The anonymous array of the filenames are the files to be sorted with
the subroutine determining the sort order.

For each file File::MergeSort opens the file using IO::File or
IO::Zlib for compressed files.  File::MergeSort handles mixed
compressed and uncompressed files seamlessly by detecting for files
with .z or .gz extensions.

When passed a line (a scalar, passed as the first and only argument,
$_[0]) from one of the files, the user supplied subroutine must return
the merge key for the line.

The records are then output in ascending order based on the merge
keys returned by the user supplied subroutine.
A stack is created based on the merge keys returned by the subroutine.

When the C<next_line> method is called, File::MergeSort returns the
line with the lowest merge key/value.

File::MergeSort then replenishes the stack, reads a new line from the
corresponding file and places it in the proper position for the next
call to C<next_line>.

If a simple merge is required, without any user processing of each
line read from the input files, the C<dump> method can be used to read
and merge the input files into the specified output file, or to STDOUT
if no file is specified.

=head1 CONSTRUCTOR

=over 4

=item new( ARRAY_REF, CODE_REF );

Create a new C<File::MergeSort> object.

There are two required arguments:

A reference to an array of files to read from.
These files can be either plaintext, or compressed.
Any file with a .gz or .z suffix will be opened using C<IO::Zlib>.

A code reference. When called, the coderef should return the merge key
for a line, which is given as the only argument to that
subroutine/coderef.

=back

=head1 SUBROUTINES/METHODS

=over 4

=item next_line();

Returns the next line from the merged input files.

=item dump( [ FILENAME ] );

Reads and merges from the input files to FILENAME, or STDOUT if
FILENAME is not given, until all files have been exhausted.

Returns the number of lines output.

=back

=head1 EXAMPLES

  # This program looks at files found in /logfiles, returns the
  # records of the files sorted by the date in mm/dd/yyyy format

  use File::MergeSort;

  my $files = [ qw( logfiles/log_server_1.log
                    logfiles/log_server_2.log
                    logfiles/log_server_3.log
                ) ];

  my $sort = File::MergeSort->new( $files, \&index_sub );

  while (my $line = $sort->next_line) {
     # some operations on $line
  }

  sub index_sub {

    # Use this to extract a date of the form mm-dd-yyyy.

    my $line = shift;

    # Be cautious that only the date will be extracted.
    $line =~ /(\d{2})-(\d{2})-(\d{4})/;

    return "$3$1$2";  # Index is an integer, yyyymmdd
                      # Lower number will be read first.
  }



  # This slightly more compact example performs a simple merge of
  # several input files with fixed width merge keys into a single
  # output file.

  use File::MergeSort;

  my $files   = [ qw( input_1 input_2 input_3 ) ];
  my $extract = sub { substr($_[0], 15, 10 ) };  # To substr merge key out of line

  my $sort = File::MergeSort->new( $files, $extract );

  $sort->dump( "output_file" );

=head1 EXPORTS

Nothing: OO interface. See CONSTRUCTOR and METHODS.

=head1 AUTHOR

=head2 Original Author

Christopher Brown E<lt>ctbrown@cpan.orgE<gt>.

=head2 Maintainer

Barrie Bremner L<http://barriebremner.com/>.

=head2 Contributors

Laura Cooney.

=head1 LICENSE AND COPYRIGHT

 Copyright (c) 2001-2003 Christopher Brown
               2003-2010 Barrie Bremner

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 TODO

 + Implement a generic test/comparison function to replace text/numeric comparison.
 + Implement a configurable record separator.
 + Allow for optional deletion of duplicate entries.
 + Ensure input is really in correct sort order - currently upto the user.
 + Wishlist: allow filehandles rather than just files to be supplied as input and output (SREZIC)

=head1 SEE ALSO

L<perl>, L<IO::File>, L<IO::Zlib>,  L<Compress::Zlib>.

L<File::Sort> or L<Sort::Merge> as possible alternatives.

=cut
