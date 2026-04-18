package CommonIO;

use strict;
use warnings;
use utf8;

use Carp qw(confess);
use Data::Dumper;
use File::Basename qw(basename);
use File::Spec;
use Encode qw(encode decode find_encoding FB_CROAK);
use Exporter qw(import);
use I18N::Langinfo qw(langinfo CODESET);
use POSIX qw(_exit strftime);

our @EXPORT_OK = qw(
    append_file
    at
    dying
    dumpU8
    log
    read_do
    read_file
    run_in_fork
    setup_console
    write_do
    write_file
);

my $LOG_TARGET;

# Capture the caller script name here because caller() is valid at load time.
{
    die "LOGDIR environment variable is not set or empty\n"
        unless defined $ENV{LOGDIR} && length $ENV{LOGDIR};

    my $cals = CommonIO::at();
    my $top  = $cals->[0];
    my $base = defined $top ? $top->{file} : 'unknown';
    $base =~ s/\.[^.]+$//;

    my $ts = strftime('%m%d%H%M', localtime);
    my $lp = "$ENV{LOGDIR}/$base$ts.log";
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

sub _print_console_line {
    my ($line) = @_;
    my $encoding = eval {
        my $codeset = langinfo(CODESET);
        _encoding_name($codeset || 'UTF-8');
    } || 'UTF-8';
    my $bytes = encode($encoding, $line, FB_CROAK);
    binmode STDERR, ':raw';
    CORE::print STDERR $bytes;
    return;
}

sub log {
    my ($level, $msg) = @_;
    my $name = _normalize_log_level($level);
    $msg = '' unless defined $msg;
    my $line = "[$name] $msg";
    $line .= "\n" unless $line =~ /\n\z/;

    _print_console_line($line);

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

sub write_file {
    my ($path, $text) = @_;
    my $spec = _parse_path($path, qw(path encoding eol));
    my $rendered_text = _render_write_text($text, $spec->{eol});
    my $encoding = _file_encoding_name($spec->{encoding});
    my $bytes = encode($encoding, $rendered_text, FB_CROAK);
    _write_bytes($spec->{path}, $bytes, '>');
    return;
}

sub append_file {
    my ($path, $text) = @_;
    my $spec = _parse_path($path, qw(path encoding eol));
    my $rendered_text = _render_write_text($text, $spec->{eol});
    my $encoding = _file_encoding_name($spec->{encoding});
    my $bytes = encode($encoding, $rendered_text, FB_CROAK);
    _write_bytes($spec->{path}, $bytes, '>>');
    return;
}

sub read_file {
    my ($path) = @_;
    my $spec = _parse_path($path, qw(path encoding eol));
    my $encoding = _file_encoding_name($spec->{encoding});
    open my $fh, '<:raw', $spec->{path} or CommonIO::dying("Cannot read $spec->{path}: $!");
    local $/;
    my $bytes = <$fh>;
    close $fh or CommonIO::dying("Cannot close $spec->{path}: $!");
    CommonIO::dying("Cannot read $spec->{path}: file not found or empty") unless defined $bytes;
    my $text = decode($encoding, $bytes, FB_CROAK);
    $text = _normalize_read_eol($text, $spec->{eol});
    return wantarray ? _split_lines($text) : $text;
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

sub setup_console {
    my ($encoding) = @_;
    my $console_encoding = _console_encoding_name($encoding);
    binmode STDOUT, ":encoding($console_encoding)"
        or CommonIO::dying("Cannot set STDOUT encoding to $console_encoding: $!");
    binmode STDERR, ":encoding($console_encoding)"
        or CommonIO::dying("Cannot set STDERR encoding to $console_encoding: $!");
    return $console_encoding;
}

sub write_do {
    my ($path, $var) = @_;
    my $spec = _parse_path($path, qw(path));
    my $dump = dumpU8($var, indent => 1);
    my $text = "use utf8;\n\n" . $dump;
    write_file($spec->{path}, $text);
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

1;
