package App::ModuleBuildTiny;

use 5.008;
use strict;
use warnings FATAL => 'all';
our $VERSION = '0.002';

use Exporter 5.57 'import';
our @EXPORT = qw/modulebuildtiny/;

use Archive::Tar;
use Carp qw/croak/;
use Config;
use CPAN::Meta;
use ExtUtils::Manifest qw/maniskip/;
use File::Basename qw/basename dirname/;
use File::Copy qw/copy/;
use File::Find qw/find/;
use File::Path qw/mkpath rmtree/;
use File::Spec::Functions qw/catfile abs2rel rel2abs/;
use File::Temp qw/tempdir/;
use Getopt::Long;
use JSON::PP;
use Module::CPANfile;
use Module::Metadata;

sub write_file {
	my ($filename, $content) = @_;
	open my $fh, '>:raw', $filename or die "Could not open $filename: $!\n";
	print $fh $content or croak "Couldn't write to $filename: $!";
	close $fh or croak "Couldn't write to $filename: $!";
	return;
}

sub prereqs_for {
	my ($meta, $phase, $type, $module, $default) = @_;
	return $meta->effective_prereqs->requirements_for($phase, $type)->requirements_for_module($module) || $default || 0;
}

sub get_files {
	my %opts = @_;
	my %files;
	my $skip = maniskip;
	find({ 
		no_chdir => 1,
		wanted => sub {
			my $name = abs2rel($_, '.');
			$files{$name} = $name if -f $name and not $skip->($name);
		},
	}, '.');
	
	$files{'Build.PL'} ||= do {
		my $minimum_mbt  = prereqs_for($opts{meta}, qw/configure requires Module::Build::Tiny/);
		my $minimum_perl = prereqs_for($opts{meta}, qw/runtime requires perl 5.006/);
		\"use $minimum_perl;\nuse Module::Build::Tiny $minimum_mbt;\nBuild_PL();\n";
	};
	$files{'META.json'} ||= \$opts{meta}->as_string;
	$files{'META.yml'} ||= \$opts{meta}->as_string({ version => 1.4 });
	$files{MANIFEST} ||= \join "\n", keys %files;

	return \%files;
}

sub get_meta {
	if (-e 'META.json' and -M 'META.json' < -M 'cpanfile') {
		return CPAN::Meta->load_file('META.json', { lazy_validation => 0 });
	}
	else {
		my $distname = basename(rel2abs('.'));
		$distname =~ s/(?:^(?:perl|p5)-|[\-\.]pm$)//x;
		my $filename = catfile('lib', split /-/, $distname) . '.pm';

		my $data = Module::Metadata->new_from_file($filename, collect_pod => 1);
		my ($abstract) = $data->pod('NAME') =~ / \A \s+ \S+ \s? - \s? (.+?) \s* \z /x;
		my $authors = [ map { / \A \s* (.+?) \s* \z /x } grep { /\S/ } split /\n/, $data->pod('AUTHOR') ];
		my $version = $data->version($data->name)->stringify;

		my $prereqs = -f 'cpanfile' ? Module::CPANfile->load('cpanfile')->prereq_specs : {};
		$prereqs->{configure}{requires}{'Module::Build::Tiny'} ||= Module::Metadata->new_from_module('Module::Build::Tiny')->version->stringify;

		my %metahash = (
			name           => $distname,
			version        => $version,
			author         => $authors,
			abstract       => $abstract,
			dynamic_config => 0,
			license        => ['perl_5'],
			prereqs        => $prereqs,
			release_status => $version =~ /_|-TRIAL$/ ? 'testing' : 'stable',
			generated_by   => "App::ModuleBuildTiny version $VERSION",
		);
		return CPAN::Meta->create(\%metahash, { lazy_validation => 0 });
	}
}

my $parser = Getopt::Long::Parser->new(config => [qw/require_order pass_through gnu_compat/]);

my %actions = (
	dist => sub {
		my %opts    = @_;
		my $arch    = Archive::Tar->new;
		my $content = get_files(%opts);
		for my $filename (keys %{$content}) {
			if (ref $content->{$filename}) {
				$arch->add_data($filename, ${ $content->{$filename} });
			}
			else {
				$arch->add_files($filename);
			}
		}
		$_->mode($_->mode & ~oct 22) for $arch->get_files;
		printf "tar czf $opts{name}.tar.gz %s\n", join ' ', keys %{$content} if ($opts{verbose} || 0) > 0;
		$arch->write("$opts{name}.tar.gz", COMPRESS_GZIP, $opts{name});
	},
	distdir => sub {
		my %opts = @_;
		mkpath($opts{name}, $opts{verbose}, oct '755');
		my $content = get_files(%opts);
		for my $filename (keys %{$content}) {
			my $target = catfile($opts{name}, $filename);
			mkpath(dirname($target)) if not -d dirname($target);
			if (ref $content->{$filename}) {
				write_file($target, ${ $content->{$filename} });
			}
			else {
				copy($filename, $target);
			}
		}
	},
	test => sub {
		my %opts = (@_, author => 1);
		my $name = tempdir(CLEANUP => 1);
		dispatch('distdir', %opts, name => $name);
		$parser->getoptionsfromarray($opts{arguments}, \%opts, qw/release! author!/);
		my $env = join ' ', map { $opts{$_} ? uc($_) . '_TESTING=1' : () } qw/release author automated/;
		system "cd '$name'; '$Config{perlpath}' Build.PL; ./Build; $env ./Build test";
	},
	run => sub {
		my %opts = @_;
		my $name = tempdir(CLEANUP => 1);
		dispatch('distdir', %opts, name => $name);
		my $command = @{ $opts{arguments} } ? join ' ', @{ $opts{arguments} } : $ENV{SHELL};
		system "cd '$name'; '$Config{perlpath}' Build.PL; ./Build; $command";
	},
	listdeps => sub {
		my %opts = @_;
		$parser->getoptionsfromarray($opts{arguments}, \%opts, qw/json/);
		if (!$opts{json}) {
			print "$_\n" for sort map { $opts{meta}->effective_prereqs->requirements_for($_, 'requires')->required_modules } qw/configure build test runtime/;
		}
		else {
			my $hash = $opts{meta}->effective_prereqs->as_string_hash;
			print JSON::PP->new->ascii->pretty->encode($hash);
		}
	},
	generate => sub {
		my %opts = @_;
		my $content = get_files(%opts);
		my @files = @{ $opts{arguments} };
		for my $filename (@files) {
			mkpath(dirname($filename)) if not -d dirname($filename);
			write_file($filename, ${ $content->{$filename} }) if ref $content->{$filename};
		}
	}
);

sub dispatch {
	my ($action, %options) = @_;
	my $call = $actions{$action};
	croak "No such action '$action' known\n" if not $call;
	return $call->(%options);
}

sub modulebuildtiny {
	my ($action, @arguments) = @_;
	$parser->getoptionsfromarray(\@arguments, \my %opts, 'verbose!');
	croak 'No action given' unless defined $action;
	my $meta = get_meta();
	return dispatch($action, %opts, arguments => \@arguments, meta => $meta, name => $meta->name . '-' . $meta->version);
}

1;

=head1 NAME

App::ModuleBuildTiny - A standalone authoring tool for Module::Build::Tiny

=head1 VERSION

version 0.002

=head1 DESCRIPTION

App::ModuleBuild contains the implementation of the L<mbtiny> tool.

=head1 FUNCTIONS

=over 4

=item * modulebuildtiny($action, @arguments)

This function runs a modulebuildtiny command. It expects at least one argument: the action. It may receive additional ARGV style options, the only one defined for all actions is C<verbose>.

The actions are documented in the L<mbtiny> documentation.

=back

=head1 SEE ALSO

=over 4

=item * Dist::Zilla

=item * scan_prereqs_cpanfile

=item * cpan_upload

=item * perl-reversion

=back

=head1 AUTHOR

Leon Timmermans <leont@cpan.org>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2011 by Leon Timmermans.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut

=begin Pod::Coverage

write_file
get_meta
dispatch
get_files
prereqs_for

=end Pod::Coverage

