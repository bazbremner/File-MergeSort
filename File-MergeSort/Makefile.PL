use 5.006;
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile('NAME'         => 'File::MergeSort',
	      'VERSION_FROM' => 'MergeSort.pm', # finds $VERSION
	      'PREREQ_PM'    => { 'IO::File'   => '0',
				  'Test::More' => '0',
				},
	      ($] >= 5.005 ?    ## Add these new keywords supported since 5.005
	       ( ABSTRACT_FROM => 'MergeSort.pm', # retrieve abstract from module
		 AUTHOR        => 'Christopher Brown <Chris.Brown@cal.berkeley.edu>') : ()),
	     );
