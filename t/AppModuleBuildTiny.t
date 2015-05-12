use strict;
use warnings;
use Cwd;
use Test::More;
use Test::Exception;
use File::Temp qw/ tmpnam tempfile /;

use App::ModuleBuildTiny;

subtest 'dies on bad action' => sub {
    throws_ok { modulebuildtiny( undef ) } qr/No action given/, 'undef action';
    throws_ok { modulebuildtiny( '' ) } qr/No such action/,     'no action';
    throws_ok { modulebuildtiny( 'foo' ) } qr/No such action/,  'invalid action';
};

subtest 'uptodate handles missing destination' => sub {
    is( App::ModuleBuildTiny::uptodate( 'bad_file_name', {} ),
        undef,
        'bad_file_name handled' );
};

subtest 'valid actions' => sub {
    lives_and { is( modulebuildtiny( 'dist' ),    1 ) } 'valid actions - dist';
    is( -e cwd() . '/App-ModuleBuildTiny-' . $App::ModuleBuildTiny::VERSION . '.tar.gz', 1, 'dist created tarball' );
    lives_and { is( modulebuildtiny( 'distdir' ), '' ) }
        'valid actions - distdir';
    is( -e cwd() . '/App-ModuleBuildTiny-' . $App::ModuleBuildTiny::VERSION, 1, 'distdir created distribution files' );
    lives_and { is( modulebuildtiny( 'test' ), 0 ) } 'valid actions - test';
    lives_and { is( modulebuildtiny( 'run', 'ls' ), 0 ) } 'valid actions - run';
    lives_and { is( modulebuildtiny( 'listdeps' ), '' ) }
        'valid actions - listdeps';
    throws_ok { modulebuildtiny( 'regenerate' ) } qr/Can't call method "pod"/,
        'valid actions - regenerate';
    is( -e cwd() . '/Build.PL', 1, 'regenerate created Build.PL' );
    is( -e cwd() . '/MANIFEST', 1, 'regenerate created MANIFEST' );
    is( -e cwd() . '/META.json', 1, 'regenerate created META.json' );
    is( -e cwd() . '/META.yml', 1, 'regenerate created META.yml' );

    #
    # is(modulebuildtiny( 'shell', 'echo ls' ),     '', 'valid actions - shell');
};

subtest 'prereqs_for' => sub {
    my $meta = App::ModuleBuildTiny::get_meta();
    is( App::ModuleBuildTiny::prereqs_for( $meta, 'build', 'requires', 'Who::Knows', undef ),
        0,
        'prereqs_for zero for bad module and no default' );
    is( App::ModuleBuildTiny::prereqs_for( $meta, 'build', 'requires', 'Who::Knows', 1 ),
        1,
        'prereqs_for default for bad module' );
    is( App::ModuleBuildTiny::prereqs_for( $meta, 'runtime', 'requires', 'perl', 1 ),
        '5.010',
        'prereqs_for perl' );
};

subtest 'get_files' => sub {
    my %test_opts;
    $test_opts{regenerate}{MANIFEST} = 0;
    my $result = App::ModuleBuildTiny::get_files( %test_opts );

    my $expected = {
        'Changes' => '',
        'MANIFEST' => '',
        't/00-compile.t' => '',
        'script/mbtiny' => '',
        'README' => '',
        'lib/App/ModuleBuildTiny.pm' => '',
        'cpanfile' => '',
        'Build.PL' => '',
        'MANIFEST.SKIP' => '',
        't/release-kwalitee.t' => '',
        'META.json' => '',
        'LICENSE' => '',
        't/release-pod-syntax.t' => '',
        'META.yml' => ''
    };

    is_deeply( $result, $expected, 'get_files manifest read' );
    
    
    $test_opts{regenerate}{MANIFEST} = 1;
    $result = App::ModuleBuildTiny::get_files( %test_opts );
    $expected = <<'FILE_LIST';
Build.PL
Changes
LICENSE
MANIFEST
MANIFEST.SKIP
META.json
META.yml
README
cpanfile
lib/App/ModuleBuildTiny.pm
script/mbtiny
t/00-compile.t
t/release-kwalitee.t
t/release-pod-syntax.t
FILE_LIST

    is( "$result->{MANIFEST}\n", $expected, 'get_files manifest' );
};

subtest 'uptodate' => sub {
    is( App::ModuleBuildTiny::uptodate( 't/00-compile.t', 't/00-compile.t' ),
        1, 'uptodate same source and destination' );

    my $file = tmpnam();
    is( App::ModuleBuildTiny::uptodate( $file, 't/00-compile.t' ),
        undef, 'uptodate with new temp file' );

    is( App::ModuleBuildTiny::uptodate( 'does/not.exist', 't/00-compile.t' ),
        undef, 'uptodate with bad file' );
};

subtest 'find' => sub {
    is( App::ModuleBuildTiny::find( qr/\.t$/, '.' ), 3,
        'find test file count' );
    is( App::ModuleBuildTiny::find( qr/no_match/, '.' ),
        undef, 'find no match for regex' );
    is( App::ModuleBuildTiny::find( qr/\.t$/, 'doesnt_exist' ),
        undef, 'find dir does not exist' );
};

subtest 'mbt_version' => sub {
    no warnings 'redefine';
    {
        local *App::ModuleBuildTiny::find = sub { return $_[0] eq qr/\.PL$/; };
        is( App::ModuleBuildTiny::mbt_version('PL'),
            '0.039', 'mbt_version found .PL' );
    }
    {
        local *App::ModuleBuildTiny::find = sub { return $_[0] eq qr/\.xs$/; };
        is( App::ModuleBuildTiny::mbt_version('XS'),
            '0.036', 'mbt_version found .xs' );
    }
    is( App::ModuleBuildTiny::mbt_version(''), '0.019', 'mbt_version no dash' );

    is( App::ModuleBuildTiny::mbt_version('-'),
        '0.007', 'mbt_version base version' );
};

subtest 'get_meta' => sub {
    my $result = App::ModuleBuildTiny::get_meta();

    my $expected = {
        'version' => '0.009',
        'dynamic_config' => 0,
        'license' => [ 'perl_5' ],
        'provides' => {
            'App::ModuleBuildTiny' => {
                'file' => 'lib/App/ModuleBuildTiny.pm',
                'version' => '0.009'
            }
        },
        'abstract' => 'A standalone authoring tool for Module::Build::Tiny',
        'meta-spec' => {
            'version' => '2',
            'url' => 'http://search.cpan.org/perldoc?CPAN::Meta::Spec'
        },
        'release_status' => 'stable',
        'author' => [ 'Leon Timmermans <leont@cpan.org>' ],
        'resources' => {
            'repository' => {
                'type' => 'git',
                'url' => 'https://github.com/Leont/app-modulebuildtiny.git',
                'web' => 'https://github.com/Leont/app-modulebuildtiny/'
            },
            'x_IRC' => 'irc://irc.perl.org/#toolchain',
            'bugtracker' => {
                'web' => 'https://github.com/Leont/app-modulebuildtiny/issues'
            }
        },
        'prereqs' => {
            'test' => {
                'requires' => {
                    'Test::More' => '0'
                }
            },
            'runtime' => {
                'requires' => {
                    'perl' => '5.010',
                    'CPAN::Meta::Merge' => '0',
                    'CPAN::Meta::Prereqs::Filter' => '0',
                    'Module::CPANfile' => '0',
                    'File::Temp' => '0',
                    'File::Path' => '0',
                    'File::Slurper' => '0',
                    'Archive::Tar' => '0',
                    'Module::Metadata' => '0',
                    'Parse::CPAN::Meta' => '0',
                    'Exporter' => '5.57',
                    'Module::Runtime' => '0',
                    'Software::LicenseUtils' => '0',
                    'CPAN::Meta' => '0',
                    'JSON::PP' => '0',
                    'Getopt::Long' => '2.36'
                }
            },
            'develop' => {
                'requires' => {
                    'App::ModuleBuildTiny' => '0.009'
                }
            },
            'configure' => {
                'requires' => {
                    'Module::Build::Tiny' => '0.039'
                }
            }
        },
        'generated_by' => 'App::ModuleBuildTiny version 0.009',
        'name' => 'App-ModuleBuildTiny',
    };

    is_deeply( $result->as_struct(), $expected, 'get_meta App::ModuleBuildTiny' );

    my %test_opts;
    my $fh;
    ( $fh, $test_opts{mergefile} ) = tempfile( 'temp-XXXXX', SUFFIX => '.yml' );
    my $result_mergefile = App::ModuleBuildTiny::get_meta(%test_opts);
    is_deeply( $result_mergefile, $result, 'get_meta empty mergefile' );

    print $fh '---\nname: My-Distribution\nversion: 1.23\nresources:\n  homepage: "http://example.com/dist/My-Distribution"\n';
    close $fh;
    $result_mergefile = App::ModuleBuildTiny::get_meta( %test_opts );
    is_deeply( $result_mergefile, $result, 'get_meta empty mergefile' );
};

done_testing();
