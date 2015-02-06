requires 'Archive::Tar';
requires 'CPAN::Meta';
requires 'CPAN::Meta::Merge';
requires 'Exporter', '5.57';
requires 'File::Path';
requires 'File::Temp';
requires 'Getopt::Long', '2.36';
requires 'JSON::PP';
requires 'Module::CPANfile';
requires 'Module::Metadata';
requires 'Parse::CPAN::Meta';
requires 'perl', '5.010';

on configure => sub {
    requires 'Module::Build::Tiny', '0.039';
};

on test => sub {
    requires 'Test::More';
};
