package App::ModuleBuildTiny::Utils;

use 5.014;
use warnings;
our $VERSION = '0.042';

use Encode 2.11 qw/FB_CROAK STOP_AT_PARTIAL/;
use PerlIO::encoding;
use Carp;

use Exporter 5.57 'import';
our @EXPORT_OK = qw(
  require_module
  write_text
  write_binary
  read_binary
);

# START: Copied from Module::Runtime
BEGIN {
    *_WORK_AROUND_HINT_LEAKAGE =
      "$]" < 5.011 && !( "$]" >= 5.009004 && "$]" < 5.010001 )
      ? sub() { 1 }
      : sub() { 0 };
    *_WORK_AROUND_BROKEN_MODULE_STATE =
      "$]" < 5.009 ? sub() { 1 } : sub() { 0 };
}

BEGIN {
    if (_WORK_AROUND_BROKEN_MODULE_STATE) {
        eval q{
	sub App::ModuleBuiltTiny::Utils::__GUARD__::DESTROY {
		delete $INC{$_[0]->[0]} if @{$_[0]};
	}
	1;
};
        die $@ if $@ ne "";
    }
}

our $module_name_rx = qr/[A-Z_a-z][0-9A-Z_a-z]*(?:::[0-9A-Z_a-z]+)*/;

sub _is_string($) {
	my($arg) = @_;
	return defined($arg) && ref(\$arg) eq "SCALAR";
}

sub is_module_name($) { _is_string($_[0]) && $_[0] =~ /\A$module_name_rx\z/o }

sub check_module_name($) {
	unless(&is_module_name) {
		die +(_is_string($_[0]) ? "`$_[0]'" : "argument").
			" is not a module name\n";
	}
}


sub module_notional_filename($) {
	&check_module_name;
	my($name) = @_;
	$name =~ s!::!/!g;
	return $name.".pm";
}

sub require_module($) {

    # Localise %^H to work around [perl #68590], where the bug exists
    # and this is a satisfactory workaround.  The bug consists of
    # %^H state leaking into each required module, polluting the
    # module's lexical state.
    local %^H if _WORK_AROUND_HINT_LEAKAGE;
    if (_WORK_AROUND_BROKEN_MODULE_STATE) {
        my $notional_filename = &module_notional_filename;
        my $guard             = bless( [$notional_filename],
            "App::ModuleBuiltTiny::Utils::__GUARD__" );
        my $result = CORE::require($notional_filename);
        pop @$guard;
        return $result;
    }
    else {
        return scalar( CORE::require(&module_notional_filename) );
    }
}

# END: Copied from Module::Runtime

# START: Copied from File::Slurper

sub read_binary {
    my $filename = shift;

    # This logic is a bit ugly, but gives a significant speed boost
    # because slurpy readline is not optimized for non-buffered usage
    open my $fh, '<:unix', $filename or croak "Couldn't open $filename: $!";
    if ( my $size = -s $fh ) {
        my $buf;
        my ( $pos, $read ) = 0;
        do {
            defined( $read = read $fh, ${$buf}, $size - $pos, $pos )
              or croak "Couldn't read $filename: $!";
            $pos += $read;
        } while ( $read && $pos < $size );
        return ${$buf};
    }
    else {
        return do { local $/; <$fh> };
    }
}

use constant {
    CRLF_DEFAULT    => $^O eq 'MSWin32',
    HAS_UTF8_STRICT => scalar do {
        local $@;
        eval { require PerlIO::utf8_strict }
    },
};

sub _text_layers {
    my ( $encoding, $crlf ) = @_;
    $crlf = CRLF_DEFAULT if $crlf && $crlf eq 'auto';

    if ( HAS_UTF8_STRICT && $encoding =~ /^utf-?8\b/i ) {
        return $crlf ? ':unix:utf8_strict:crlf' : ':unix:utf8_strict';
    }
    else {
       # non-ascii compatible encodings such as UTF-16 need encoding before crlf
        return $crlf
          ? ":raw:encoding($encoding):crlf"
          : ":raw:encoding($encoding)";
    }
}

sub write_text {
    my ( $filename, undef, $encoding, $crlf ) = @_;
    $encoding ||= 'utf-8';
    my $layer = _text_layers( $encoding, $crlf );

    local $PerlIO::encoding::fallback = STOP_AT_PARTIAL | FB_CROAK;
    open my $fh, ">$layer", $filename or croak "Couldn't open $filename: $!";
    print $fh $_[1] or croak "Couldn't write to $filename: $!";
    close $fh or croak "Couldn't write to $filename: $!";
    return;
}

sub write_binary {
    my $filename = $_[0];
    open my $fh, ">:raw", $filename or croak "Couldn't open $filename: $!";
    print $fh $_[1] or croak "Couldn't write to $filename: $!";
    close $fh or croak "Couldn't write to $filename: $!";
    return;
}

# END: copied from File::Slurper

1;
