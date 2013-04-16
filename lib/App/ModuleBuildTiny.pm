package App::ModuleBuildTiny;

use strict;
use warnings FATAL => 'all';
our $VERSION = '0.001';

use Exporter 5.57 'import';
our @EXPORT = qw/modulebuildtiny/;

use Archive::Tar;
use Carp qw/croak/;
use CPAN::Meta;
use ExtUtils::Manifest qw/maniread fullcheck mkmanifest manicopy/;
use File::Basename qw/basename/;
use File::Path qw/mkpath rmtree/;
use File::Spec::Functions qw/catfile rel2abs/;
use Getopt::Long qw/GetOptionsFromArray/;
use Module::CPANfile;
use Module::Metadata;

sub write_file {
	my ($filename, $mode, $content) = @_;
	open my $fh, ">:$mode", $filename or die "Could not open $filename: $!\n";;
	print $fh $content;
}

my %actions = (
	buildpl => sub {
		write_file('Build.PL', "use Module::Build::Tiny;\nBuild_PL();\n");
	},
	dist => sub {
		my %opts = @_;
		my ($metafile) = grep { -e $_ } qw/META.json META.yml/ or croak 'No META information provided';
		my $meta = CPAN::Meta->load_file($metafile);
		my $manifest = maniread() or croak 'No MANIFEST found';
		my @files = keys %{$manifest};
		my $arch = Archive::Tar->new;
		$arch->add_files(@files);
		$_->mode($_->mode & ~oct 22) for $arch->get_files;
		my $release_name = $meta->name . '-' . $meta->version;
		print "tar xjf $release_name.tar.gz @files\n" if $opts{verbose} > 0;
		$arch->write("$release_name.tar.gz", COMPRESS_GZIP, $release_name);
	},
	distdir => sub {
		my %opts = @_;
		local $ExtUtils::Manifest::Quiet = !$opts{verbose};
		my ($metafile) = grep { -e $_ } qw/META.json META.yml/ or croak 'No META information provided';
		my $meta = CPAN::Meta->load_file($metafile);
		my $manifest = maniread() or croak 'No MANIFEST found';
		my $release_name = $meta->name . '-' . $meta->version;
		mkpath($release_name, $opts{verbose}, oct '755');
		manicopy($manifest, $release_name, 'cp');
	},
	manifest => sub {
		my %opts = @_;
		local $ExtUtils::Manifest::Quiet = !$opts{verbose};
		my @default_skips = qw{_build_params \.git/ \.gitignore .*\.swp .*~ .*\.tar\.gz MYMETA\..* MANIFEST.bak ^Build$};
		writefile('MANIFEST.SKIP', join "\n", @default_skips) if not -e 'MANIFEST.SKIP';
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
		my $distname = basename(rel2abs('.'));
		$distname =~ s/(?:^(?:perl|p5)-|[\-\.]pm$)//x;
		my $filename = catfile('lib', split '-', $distname).'.pm';

		my $data = Module::Metadata->new_from_file($filename, collect_pod => 1);
		my ($abstract) = $data->pod('NAME') =~ / \A \s+ \S+ \s? - \s? (.+?) \s* \z /x;
		my $author = [ map { / \A \s* (.+?) \s* \z /x } grep { /\S/ } split /\n/, $data->pod('AUTHOR') ];

		my $prereqs = Module::CPANfile->load('cpanfile')->prereq_specs;

		my %metahash = (
			name => $distname,
			version => $data->version($data->name)->stringify,
			author => $author,
			abstract => $abstract,
			dynamic_config => 0,
			license => 'perl_5',
			prereqs => $prereqs,
			release_status => 'stable',
		);
		my $meta = CPAN::Meta->create(\%metahash);
		$meta->save('META.json');
		$meta->save('META.yml', { version => 1.4 });
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

sub modulebuildtiny {
	my ($action, @arguments) = @_;
	GetOptionsFromArray(\@arguments, \my %opts);

	croak 'No action given' unless defined $action;
	my $call = $actions{$action};
	croak "No such action '$action' known\n" if not $call;
	return $call->(%opts, arguments => \@arguments);
}

1;



=pod

=head1 NAME

App::ModuleBuildTiny - A standalone authoring tool for Module::Build::Tiny

=head1 VERSION

version 0.001

=head1 AUTHOR

Leon Timmermans <leont@cpan.org>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2011 by Leon Timmermans.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut


__END__

#ABSTRACT: a standalone authoring tool for Module::Build::Tiny
