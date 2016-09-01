use 5.006;
use strict;
use warnings;
use Module::Build;

my $builder = Module::Build->new(
    module_name         => 'DCITools',
    license             => 'gpl_2',
    dist_author         => q{Dan Collins <DCOLLINS@cpan.org>},
    dist_version_from   => 'lib/DCITools.pm',
    release_status      => 'stable',
    configure_requires => {
        'Module::Build' => 0,
    },
    build_requires => {
        'Test::More' => 0,
    },
    requires => {
        'Moose' => 0,
        'WWW::Mechanize' => 0,
        'WWW::Scripter' => 0,
    },
    add_to_cleanup     => [ 'DCITools-*' ],
    create_makefile_pl => 'traditional',
);

$builder->create_build_script();
