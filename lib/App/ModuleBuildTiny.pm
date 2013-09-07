package App::ModuleBuildTiny;

use 5.008;
use strict;
use warnings FATAL => 'all';
our $VERSION = '0.001';

use Exporter 5.57 'import';
our @EXPORT = qw/modulebuildtiny/;

use Archive::Tar;
use Carp qw/croak/;
use Config;
use CPAN::Meta;
use ExtUtils::Manifest qw/maniread fullcheck mkmanifest manicopy/;
use File::Basename qw/basename/;
use File::Path qw/mkpath rmtree/;
use File::Spec::Functions qw/catfile rel2abs/;
use Getopt::Long qw/GetOptionsFromArray/;
use Module::CPANfile;
use Module::Metadata;

sub write_file {
	my ($filename, $content) = @_;
	open my $fh, ">:raw", $filename or die "Could not open $filename: $!\n";;
	print $fh $content;
	close $fh;
	return;
}

sub get_meta {
	if (-e 'META.json') {
		return CPAN::Meta->load_file('META.json');
	}
	else {
		my $distname = basename(rel2abs('.'));
		$distname =~ s/(?:^(?:perl|p5)-|[\-\.]pm$)//x;
		my $filename = catfile('lib', split /-/, $distname).'.pm';

		my $data = Module::Metadata->new_from_file($filename, collect_pod => 1);
		my ($abstract) = $data->pod('NAME') =~ / \A \s+ \S+ \s? - \s? (.+?) \s* \z /x;
		my $author = [ map { / \A \s* (.+?) \s* \z /x } grep { /\S/ } split /\n/, $data->pod('AUTHOR') ];

		my $prereqs = -f 'cpanfile' ? Module::CPANfile->load('cpanfile')->prereq_specs : {};

		my %metahash = (
			name => $distname,
			version => $data->version($data->name)->stringify,
			author => $author,
			abstract => $abstract,
			dynamic_config => 0,
			license => 'perl_5',
			prereqs => $prereqs,
			release_status => 'stable',
			generated_by => "App::ModuleBuildTiny version $VERSION",
		);
		return CPAN::Meta->create(\%metahash);
	}
}

my %actions = (
	buildpl => sub {
		write_file('Build.PL', "use Module::Build::Tiny;\nBuild_PL();\n");
	},
	prepare => sub {
		my %opts = @_;
		dispatch('buildpl', %opts) if not -e 'Build.PL';
		dispatch('meta', %opts);
		dispatch('manifest', %opts);
	},
	dist => sub {
		my %opts = @_;
		dispatch('prepare', %opts);
		my $manifest = maniread() or croak 'No MANIFEST found';
		my @files = keys %{$manifest};
		my $arch = Archive::Tar->new;
		$arch->add_files(@files);
		$_->mode($_->mode & ~oct 22) for $arch->get_files;
		print "tar czf $opts{release}.tar.gz @files\n" if ($opts{verbose} || 0) > 0;
		$arch->write("$opts{release}.tar.gz", COMPRESS_GZIP, $opts{release});
	},
	distdir => sub {
		my %opts = @_;
		dispatch('prepare', %opts);
		local $ExtUtils::Manifest::Quiet = !$opts{verbose};
		my $manifest = maniread() or croak 'No MANIFEST found';
		mkpath($opts{release}, $opts{verbose}, oct '755');
		manicopy($manifest, $opts{release}, 'cp');
	},
	test => sub {
		my %opts = @_;
		dispatch('distdir', %opts);
		my $extra = (grep { /release/ } @{ $opts{arguments} }) ? 'RELEASE_TESTING=1' : '';
		system("cd '$opts{release}'; '$Config{perlpath}' Build.PL; ./Build; AUTHOR_TESTING=1 $extra ./Build test");
		rmtree($opts{release}, 0);
	},
	manifest => sub {
		my %opts = @_;
		local $ExtUtils::Manifest::Quiet = !$opts{verbose};
		my @default_skips = qw{_build_params \.git/ \.gitignore .*\.swp .*~ .*\.tar\.gz MYMETA\..* MANIFEST.bak ^Build$};
		write_file('MANIFEST.SKIP', join "\n", @default_skips) if not -e 'MANIFEST.SKIP';
		mkmanifest();
	},
	distcheck => sub {
		my %opts = @_;
		local $ExtUtils::Manifest::Quiet = !$opts{verbose};
		my ($missing, $extra) = fullcheck();
		croak "Missing on filesystem: @{$missing}" if @{$missing};
		croak "Missing in MANIFEST: @{$extra}" if @{$extra}
	},
	meta => sub {
		my %opts = @_;
		$opts{meta}->save('META.json');
		$opts{meta}->save('META.yml', { version => 1.4 });
	},
	listdeps => sub {
		my %opts = @_;
		my @reqs = map { $opts{meta}->effective_prereqs->requirements_for($_, 'requires')->required_modules } qw/configure build test runtime/;
		print "$_\n" for sort @reqs;
	},
	clean => sub {
		my %opts = @_;
		rmtree('blib', $opts{verbose});
	},
	realclean => sub {
		my %opts = @_;
		rmtree($_, $opts{verbose}) for qw/blib Build _build_params MYMETA.yml MYMETA.json/;
	},
);

sub dispatch {
	my ($action, %options) = @_;
	my $call = $actions{$action};
	croak "No such action '$action' known\n" if not $call;
	return $call->(%options);
}

sub modulebuildtiny {
	my ($action, @arguments) = @_;
	GetOptionsFromArray(\@arguments, \my %opts);
	croak 'No action given' unless defined $action;
	my $meta = get_meta();
	return dispatch($action, %opts, arguments => \@arguments, meta => $meta, release => $meta->name . '-' . $meta->version);
}

1;



=pod

=head1 NAME

App::ModuleBuildTiny - A standalone authoring tool for Module::Build::Tiny

=head1 VERSION

version 0.001

=head1 SEE ALSO

=over 4

=item * Dist::Zilla

=item * App::scan_prereqs_cpanfile

=back

=head1 AUTHOR

Leon Timmermans <leont@cpan.org>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2011 by Leon Timmermans.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut


__END__

#ABSTRACT: a standalone authoring tool for Module::Build::Tiny
