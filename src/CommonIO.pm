package CommonIO;

use strict;
use warnings;
use utf8;

use Carp qw(confess);
use Data::Dumper;
use Encode qw(encode decode find_encoding FB_CROAK);
use Exporter qw(import);
use I18N::Langinfo qw(langinfo CODESET);
use POSIX qw(_exit);

our @EXPORT_OK = qw(
    append_file
    dying
    dumpU8
    log
    read_do
    read_file
    run_in_fork
    setLogFile
    setup_console
    write_do
    write_file
);

my $LOG_TARGET;

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
    my ($target) = @_;
    if (!defined $target) {
        $LOG_TARGET = undef;
        return;
    }

    my $spec = _parse_target($target);
    $spec->{eol} = 'lf' unless defined $spec->{eol} && length $spec->{eol};
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

sub _parse_target {
    my ($target) = @_;

    return {
        eol      => undef,
        encoding => undef,
        path     => $target,
    } unless ref $target;

    CommonIO::dying("target must be path string or hashref")
        unless ref($target) eq 'HASH';

    CommonIO::dying("target->{path} is required")
        unless defined $target->{path} && length $target->{path};

    return {
        eol      => $target->{eol},
        encoding => $target->{encoding},
        path     => $target->{path},
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

sub _render_write_data {
    my ($data, $eol) = @_;

    return _normalize_write_eol($data, $eol) unless ref $data;

    CommonIO::dying("Unsupported data type: " . ref($data))
        unless ref($data) eq 'ARRAY';

    my $nl = _line_ending($eol);
    return defined $nl ? join($nl, @$data) : join('', @$data);
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
    my ($target, $data) = @_;
    my $spec = _parse_target($target);
    my $text = _render_write_data($data, $spec->{eol});
    my $encoding = _encoding_name($spec->{encoding});
    my $bytes = encode($encoding, $text, FB_CROAK);
    _write_bytes($spec->{path}, $bytes, '>');
    return;
}

sub append_file {
    my ($target, $data) = @_;
    my $spec = _parse_target($target);
    my $text = _render_write_data($data, $spec->{eol});
    my $encoding = _encoding_name($spec->{encoding});
    my $bytes = encode($encoding, $text, FB_CROAK);
    _write_bytes($spec->{path}, $bytes, '>>');
    return;
}

sub read_file {
    my ($target) = @_;
    my $spec = _parse_target($target);
    my $encoding = _encoding_name($spec->{encoding});
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
    my ($data, %opts) = @_;
    my $dump = Data::Dumper->new([$data])
        ->Terse(1)
        ->Indent($opts{indent} // 1)
        ->Dump;
    $dump =~ s/\\x\{([0-9A-Fa-f]+)\}/chr(hex($1))/ge;
    return $dump;
}

sub setup_console {
    my ($encoding) = @_;
    my $name = _console_encoding_name($encoding);
    binmode STDOUT, ":encoding($name)"
        or CommonIO::dying("Cannot set STDOUT encoding to $name: $!");
    binmode STDERR, ":encoding($name)"
        or CommonIO::dying("Cannot set STDERR encoding to $name: $!");
    return $name;
}

sub write_do {
    my ($target, $data) = @_;
    my $dump = dumpU8($data, indent => 1);
    my $source = "use utf8;\n\n" . $dump;
    write_file($target, $source);
    return;
}

sub read_do {
    my ($target) = @_;
    my $spec = _parse_target($target);
    my $path = $spec->{path};
    my $data = do $path;
    CommonIO::dying("Failed to read $path: $@") if $@;
    CommonIO::dying("Failed to read $path: file not found or empty") unless defined $data;
    return $data;
}

1;
