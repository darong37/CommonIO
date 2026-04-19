package CommonIO;

use strict;
use warnings;
use utf8;

use Carp qw(confess);
use Data::Dumper;
use Data::Printer escape_chars => 'none';
use File::Basename qw(basename);
use File::Spec;
use Encode qw(encode decode find_encoding is_utf8 FB_CROAK);
use Exporter qw(import);
use I18N::Langinfo qw(langinfo CODESET);
use POSIX qw(_exit strftime);

our @EXPORT_OK = qw(
    at
    dec
    dp
    dying
    dumpU8
    log
    out_file
    read_do
    read_file
    run_in_fork
    write_do
);

my %_out_counts;
my $_out_pid = $$;

END {
    if ($$ == $_out_pid) {
        # Future: report written files and write counts here.
        %_out_counts = ();
    }
}

my $LOG_TARGET;

# Capture the caller script name here because caller() is valid at load time.
{
    die "LOGDIR environment variable is not set or empty\n"
        unless defined $ENV{LOGDIR} && length $ENV{LOGDIR};

    die "LOGDIR directory does not exist: $ENV{LOGDIR}\n"
        unless -d $ENV{LOGDIR};

    my $cals = CommonIO::at();
    my $top  = $cals->[0];
    my $base = defined $top ? $top->{file} : 'unknown';
    $base =~ s/\.[^.]+$//;

    my $ts = strftime('%m%d%H%M', localtime);
    my $lp = "$ENV{LOGDIR}/$base$ts.log";

    # Verify the log file is writable before the first log() call.
    open my $fh, '>>', $lp or die "Cannot open log file $lp: $!\n";
    close $fh;

    $LOG_TARGET = { path => $lp, encoding => 'UTF-8', eol => 'lf' };
}

sub dying {
    my ($msg) = @_;
    CommonIO::log('error', $msg);
    confess $msg;
}

sub run_in_fork {
    my ($code) = @_;
    my $pid = fork();
    CommonIO::dying("fork failed: $!") unless defined $pid;
    if ($pid == 0) {
        eval { $code->() };
        my $err = $@;
        if ($err) {
            CommonIO::log('error', $err);
            _exit(1);
        }
        _exit(0);
    }
    waitpid($pid, 0);
    CommonIO::dying('confirm failed') if $? != 0;
    return;
}

sub at {
    my @raw;
    my $dep = 0;
    while (1) {
        my @c = caller($dep);
        last unless @c;
        my ($file, $line, $sub) = @c[1, 2, 3];
        $dep++;
        next if $file =~ /\bCommonIO\.pm$/;
        # caller()[3] is the sub that called this frame, not the one executing here.
        push @raw, {
            file       => basename($file),
            path       => File::Spec->rel2abs($file),
            line       => $line,
            subroutine => defined $sub ? $sub : 'main::',
        };
    }
    my @frames = reverse @raw;
    # Guard against empty stack (e.g., called from string eval with no script frames).
    return \@frames unless @frames;

    # find topmost .pl as level 0; fall back to topmost frame
    my $top = 0;
    for my $i (0 .. $#frames) {
        if ($frames[$i]{file} =~ /\.pl$/i) {
            $top = $i;
            last;
        }
    }
    return [@frames[$top .. $#frames]];
}

sub _normalize_log_level {
    my ($level) = @_;
    $level = 'info' unless defined $level && length $level;
    my $key = lc $level;
    return 'DEBUG' if $key eq 'debug';
    return 'INFO'  if $key eq 'info';
    return 'WARN'  if $key eq 'warn' || $key eq 'warning';
    return 'ERROR' if $key eq 'error';
    CommonIO::dying("Unsupported log level: $level");
}

sub setLogFile {
    my ($path) = @_;
    if (!defined $path) {
        $LOG_TARGET = undef;
        return;
    }

    my $spec = _parse_path($path, qw(path eol));
    $spec->{eol}      = 'lf'    unless defined $spec->{eol}      && length $spec->{eol};
    $spec->{encoding} = 'UTF-8';
    $LOG_TARGET = $spec;
    return $LOG_TARGET->{path};
}

sub _log_file_bytes {
    my ($bytes) = @_;
    return unless $LOG_TARGET;
    open my $fh, '>>:raw', $LOG_TARGET->{path} or do {
        CORE::print STDERR "Cannot write $LOG_TARGET->{path}: $!\n";
        return;
    };
    CORE::print {$fh} $bytes or CORE::print STDERR "Cannot write $LOG_TARGET->{path}: $!\n";
    close $fh or CORE::print STDERR "Cannot close $LOG_TARGET->{path}: $!\n";
    return;
}

sub log {
    my ($level, $msg) = @_;
    my $name = _normalize_log_level($level);
    $msg = '' unless defined $msg;
    my $line = "[$name] $msg";
    $line .= "\n" unless $line =~ /\n\z/;

    print STDERR $line;

    if ($LOG_TARGET) {
        my $text = _normalize_write_eol($line, $LOG_TARGET->{eol});
        my $encoding = _encoding_name($LOG_TARGET->{encoding});
        my $bytes = encode($encoding, $text, FB_CROAK);
        _log_file_bytes($bytes);
    }

    return $line;
}

sub _encoding_name {
    my ($encoding) = @_;
    $encoding = 'UTF-8' unless defined $encoding && length $encoding;
    my $encoder = find_encoding($encoding)
        or CommonIO::dying("Unknown encoding: $encoding");
    return $encoder->name;
}

sub _file_encoding_name {
    my ($encoding) = @_;
    $encoding = 'UTF-8' unless defined $encoding && length $encoding;
    my $key = uc $encoding;
    $key =~ s/[^A-Z0-9]//g;
    return 'UTF-8' if $key eq 'UTF8';
    return 'CP932' if $key eq 'CP932';
    CommonIO::dying("Unsupported file encoding: $encoding (use UTF-8 or CP932)");
}

sub _console_encoding_name {
    my ($encoding) = @_;

    if (!defined $encoding || !length $encoding) {
        my $codeset = langinfo(CODESET);
        $encoding = $codeset if defined $codeset && length $codeset;
        $encoding ||= 'UTF-8';
    }

    my $key = uc $encoding;
    $key =~ s/[^A-Z0-9]//g;

    return 'UTF-8' if $key eq 'UTF8';
    return 'CP932' if $key eq 'CP932';
    return 'CP932' if $key eq 'SJIS';
    return 'CP932' if $key eq 'SHIFTJIS';

    CommonIO::dying("Unsupported console encoding: $encoding");
}

sub _assert_allowed_path_keys {
    my ($path, @allowed_keys) = @_;
    return unless ref($path) eq 'HASH';

    my %allowed = map { $_ => 1 } @allowed_keys;
    for my $key (keys %{$path}) {
        CommonIO::dying("Unsupported path option: $key")
            unless $allowed{$key};
    }
    return;
}

sub _parse_path {
    my ($path, @allowed_keys) = @_;
    @allowed_keys = qw(path encoding eol) unless @allowed_keys;

    return {
        eol      => undef,
        encoding => undef,
        path     => $path,
    } unless ref $path;

    CommonIO::dying("path must be path string or hashref")
        unless ref($path) eq 'HASH';
    _assert_allowed_path_keys($path, @allowed_keys);

    CommonIO::dying("path->{path} is required")
        unless defined $path->{path} && length $path->{path};

    return {
        eol      => $path->{eol},
        encoding => $path->{encoding},
        path     => $path->{path},
    };
}

sub _normalize_write_eol {
    my ($text, $eol) = @_;
    $eol = 'lf' unless defined $eol && length $eol;
    return $text if $eol eq 'preserve';

    my $nl;
    if ($eol eq 'lf') {
        $nl = "\n";
    } elsif ($eol eq 'crlf') {
        $nl = "\r\n";
    } else {
        CommonIO::dying("Unknown write eol mode: $eol");
    }

    $text =~ s/\r\n|\r|\n/$nl/g;
    return $text;
}

sub _normalize_read_eol {
    my ($text, $eol) = @_;
    $eol = 'preserve' unless defined $eol && length $eol;
    return $text if $eol eq 'preserve';
    CommonIO::dying("Unknown read eol mode: $eol") unless $eol eq 'lf';
    $text =~ s/\r\n|\r/\n/g;
    return $text;
}

sub _line_ending {
    my ($eol) = @_;
    $eol = 'lf' unless defined $eol && length $eol;
    return undef if $eol eq 'preserve';
    return "\n"   if $eol eq 'lf';
    return "\r\n" if $eol eq 'crlf';
    CommonIO::dying("Unknown write eol mode: $eol");
}

sub _render_write_text {
    my ($text, $eol) = @_;

    return _normalize_write_eol($text, $eol) unless ref $text;

    CommonIO::dying("Unsupported text type: " . ref($text))
        unless ref($text) eq 'ARRAY';

    my $nl = _line_ending($eol);
    return defined $nl ? join($nl, @$text) : join('', @$text);
}

sub _split_lines {
    my ($text) = @_;
    return () unless length $text;
    return split /\n/, $text, -1;
}

sub _write_bytes {
    my ($path, $bytes, $mode) = @_;
    $mode ||= '>';
    open my $fh, $mode . ':raw', $path or CommonIO::dying("Cannot write $path: $!");
    print {$fh} $bytes or CommonIO::dying("Cannot write $path: $!");
    close $fh or CommonIO::dying("Cannot close $path: $!");
    return;
}

sub _is_raw_encoding {
    my ($enc) = @_;
    return defined $enc && lc($enc) eq 'raw';
}

sub _encode_and_write {
    my ($spec, $text, $mode) = @_;
    if (_is_raw_encoding($spec->{encoding})) {
        _write_bytes($spec->{path}, $text, $mode);
        return;
    }
    my $rendered = _render_write_text($text, $spec->{eol});
    my $enc      = _file_encoding_name($spec->{encoding});
    my $bytes    = encode($enc, $rendered, FB_CROAK);
    _write_bytes($spec->{path}, $bytes, $mode);
    return;
}

sub out_file {
    my ($first, @rest) = @_;

    my ($mode, $path_arg, $text);
    if (defined $first && ($first eq '>' || $first eq '>>' || $first eq '?')) {
        $mode     = $first;
        $path_arg = $rest[0];
        $text     = $rest[1];
    } else {
        $mode     = '?';
        $path_arg = $first;
        $text     = $rest[0];
    }

    my $spec = _parse_path($path_arg, qw(path encoding eol));
    my $key  = $spec->{path};

    CommonIO::dying("path must not be a mode character: $key")
        if $key eq '>' || $key eq '>>' || $key eq '?';

    my $actual_mode;
    if ($mode eq '>') {
        $actual_mode = '>';
    } elsif ($mode eq '>>') {
        $actual_mode = '>>';
    } else {
        $actual_mode = (exists $_out_counts{$key} && $_out_counts{$key} > 0)
            ? '>>' : '>';
    }

    _encode_and_write($spec, $text, $actual_mode);
    $_out_counts{$key}++;
    return;
}

sub read_file {
    my ($path) = @_;
    my $spec = _parse_path($path, qw(path encoding eol));
    open my $fh, '<:raw', $spec->{path} or CommonIO::dying("Cannot read $spec->{path}: $!");
    local $/;
    my $bytes = <$fh>;
    close $fh or CommonIO::dying("Cannot close $spec->{path}: $!");
    CommonIO::dying("Cannot read $spec->{path}: file not found or empty") unless defined $bytes;

    if (_is_raw_encoding($spec->{encoding})) {
        CommonIO::dying("read_file with encoding=>raw does not support list context")
            if wantarray;
        return $bytes;
    }

    my $text = decode(_file_encoding_name($spec->{encoding}), $bytes, FB_CROAK);
    $text = _normalize_read_eol($text, $spec->{eol});
    return wantarray ? _split_lines($text) : $text;
}

sub dec {
    my ($data) = @_;
    return $data unless defined $data;
    return $data if is_utf8($data);
    my $text = eval { decode('UTF-8', $data, FB_CROAK) };
    return defined $text ? $text : $data;
}

sub dp {
    my @args = @_;
    return unless @args;
    # np() captures the raw UTF-8 bytes without printing; write to a raw
    # duplicate of STDERR to avoid double-encoding with any encoding layer.
    my $out = (@args == 1 && ref $args[0])
        ? &np($args[0])
        : &np(\@args);
    open my $raw_err, '>>&', \*STDERR or return;
    binmode $raw_err, ':raw';
    print {$raw_err} $out;
    close $raw_err;
    return;
}

sub dumpU8 {
    my ($var, %opts) = @_;
    my $dump = Data::Dumper->new([$var])
        ->Terse(1)
        ->Indent($opts{indent} // 1)
        ->Dump;
    $dump =~ s/\\x\{([0-9A-Fa-f]+)\}/chr(hex($1))/ge;
    return $dump;
}

sub _setup_console {
    my $console_encoding = _console_encoding_name();
    binmode STDOUT, ":encoding($console_encoding)"
        or die "Cannot set STDOUT encoding to $console_encoding: $!\n";
    binmode STDERR, ":encoding($console_encoding)"
        or die "Cannot set STDERR encoding to $console_encoding: $!\n";
    return $console_encoding;
}

sub write_do {
    my ($path, $var) = @_;
    my $spec = _parse_path($path, qw(path));
    my $dump = dumpU8($var, indent => 1);
    my $text = "use utf8;\n\n" . $dump;
    _encode_and_write({ path => $spec->{path}, encoding => 'UTF-8', eol => 'lf' }, $text, '>');
    return;
}

sub read_do {
    my ($path) = @_;
    my $spec = _parse_path($path, qw(path));
    my $file_path = $spec->{path};
    my $var = do $file_path;
    CommonIO::dying("Failed to read $file_path: $@") if $@;
    CommonIO::dying("Failed to read $file_path: file not found or empty") unless defined $var;
    return $var;
}

BEGIN { _setup_console() }

1;
