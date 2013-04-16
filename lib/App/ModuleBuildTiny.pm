package App::ModuleBuildTiny;

use 5.010;
use strict;
use warnings FATAL => 'all';
our $VERSION = '0.001';

use Exporter 5.57 'import';
our @EXPORT = qw/modulebuildtiny/;

use Archive::Tar;
use Carp qw/croak/;
use CPAN::Meta;
use ExtUtils::Manifest qw/maniread fullcheck mkmanifest manicopy/;
use File::Find::Rule qw/find/;
use File::Path qw/mkpath rmtree/;
use File::Slurp qw/write_file/;
use Getopt::Long qw/GetOptionsFromArray/;
use Hash::Diff qw/left_diff/;
use Module::Metadata;
use Perl::PrereqScanner;
use Version::Requirements;

sub files {
	my ($dir, $pattern) = @_;
	return find(file => name => $pattern, in => $dir);
}

sub modulebuildtiny {
	my ($action, @arguments) = @_;
	my $verbose = 0;
	GetOptionsFromArray(\@arguments, verbose => \$verbose);
	local $ExtUtils::Manifest::Quiet = !$verbose;

	for ($action) {
		when (undef) {
			croak 'No action given';
		}
		when ('buildpl') {
			write_file('Build.PL', "use Module::Build::Tiny;\nBuild_PL();\n");
		}
		when ('dist') {
			my ($metafile) = grep { -e $_ } qw/META.json META.yml/ or croak 'No META information provided';
			my $meta = CPAN::Meta->load_file($metafile);
			my $manifest = maniread() or croak 'No MANIFEST found';
			my @files = keys %{$manifest};
			my $arch = Archive::Tar->new;
			$arch->add_files(@files);
			$_->mode($_->mode & ~oct 22) for $arch->get_files;
			my $release_name = $meta->name . '-' . $meta->version;
			print "tar xjf $release_name.tar.gz @files\n" if $verbose > 0;
			$arch->write("$release_name.tar.gz", COMPRESS_GZIP, $release_name);
		}
		when ('distdir') {
			my ($metafile) = grep { -e $_ } qw/META.json META.yml/ or croak 'No META information provided';
			my $meta = CPAN::Meta->load_file($metafile);
			my $manifest = maniread() or croak 'No MANIFEST found';
			my $release_name = $meta->name . '-' . $meta->version;
			mkpath($release_name, $verbose, oct '755');
			manicopy($manifest, $release_name, 'cp');
		}
		when ('manifest') {
			my @default_skips = qw{_build_params \.git/ \.gitignore .*\.swp .*~ .*\.tar\.gz MYMETA\..* MANIFEST.bak ^Build$};
			writefile('MANIFEST.SKIP', join "\n", @default_skips) if not -e 'MANIFEST.SKIP';
			mkmanifest();
		}
		when ('distcheck') {
			my ($missing, $extra) = fullcheck();
			croak "Missing on filesystem: @{$missing}" if @{$missing};
			croak "Missing in MANIFEST: @{$extra}" if @{$extra}
		}
		when ('meta') {
			my $filename = shift @arguments;
			my $data = Module::Metadata->new_from_file($filename, collect_pod => 1);
			my ($abstract) = $data->pod('NAME') =~ / \A \s+ \S+ \s? - \s? (.+?) \s* \z /x;
			my $author = [ map { / \A \s* (.+?) \s* \z /x } grep { /\S/ } split /\n/, $data->pod('AUTHOR') ];
			(my $distname = $data->name) =~ s/::/-/;

			my $scanner = Perl::PrereqScanner->new;
			my ($requires, $build_requires) = map { Version::Requirements->new } 1 .. 2;
			for my $file (files('lib', '*.pm'), files('bin')) {
				$requires->add_requirements($scanner->scan_file($file));
			}
			for my $file (files('t', '*.t'), files('t/lib', '*.pm')) {
				$build_requires->add_requirements($scanner->scan_file($file));
			}

			my %metahash = (
				name => $distname,
				version => $data->version($data->name)->stringify,
				author => $author,
				abstract => $abstract,
				dynamic_config => 0,
				license => 'perl_5',
				prereqs => {
					runtime => { requires => $requires->as_string_hash },
					build => { requires => left_diff($build_requires->as_string_hash, $requires->as_string_hash) },
					configure => { requires => { 'Module::Build::Tiny' => 0.008 } },
				},
				release_status => 'stable',
			);
			my $meta = CPAN::Meta->create(\%metahash);
			$meta->save('META.json');
			$meta->save('META.yml', { version => 1.4 });
		}
		when ('clean') {
			rmtree('blib', $verbose);
		}
		when ('realclean') {
			rmtree($_, $verbose) for qw/blib Build _build_params MYMETA.yml MYMETA.json/;
		}
		default {
			die "No such action '$action' known\n";
		}
	}
	return;
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
