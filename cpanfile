requires 'Archive::Tar';
requires 'CPAN::Meta';
requires 'CPAN::Meta::Merge';
requires 'Exporter', '5.57';
requires 'File::Path';
requires 'File::Slurper';
requires 'File::Temp';
requires 'Getopt::Long', '2.36';
requires 'JSON::PP';
requires 'Module::CPANfile';
requires 'Module::Metadata';
requires 'Module::Runtime';
requires 'Parse::CPAN::Meta';
requires 'Software::LicenseUtils';
requires 'perl', '5.010';

on configure => sub {
    requires 'Module::Build::Tiny', '0.039';
};

on test => sub {
    requires 'Test::More';
};
