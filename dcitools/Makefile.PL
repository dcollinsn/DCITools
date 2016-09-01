use 5.006;
use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME             => 'DCITools',
    AUTHOR           => q{Dan Collins <DCOLLINS@cpan.org>},
    VERSION_FROM     => 'lib/DCITools.pm',
    ABSTRACT_FROM    => 'lib/DCITools.pm',
    LICENSE          => 'gpl_2',
    PL_FILES         => {},
    MIN_PERL_VERSION => 5.006,
    CONFIGURE_REQUIRES => {
        'ExtUtils::MakeMaker' => 0,
    },
    BUILD_REQUIRES => {
        'Test::More' => 0,
    },
    PREREQ_PM => {
        'Moose' => 0,
        'WWW::Mechanize' => 0,
        'WWW::Scripter' => 0,
    },
    dist  => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean => { FILES => 'DCITools-*' },
);
