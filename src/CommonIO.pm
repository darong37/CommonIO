package CommonIO;

use strict;
use warnings;
use utf8;

use Carp qw(confess);
use Data::Dumper;
use Data::Printer escape_chars => 'none';
use File::Basename qw(basename);
use File::Spec;
use Encode qw(encode decode is_utf8 FB_CROAK);
use Encode::Guess;
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
    pathcli
    read_do
    read_file
    run_in_fork
    write_do
);

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

my %OUT_COUNTS;
my $OUT_PID = $$;

END {
    if ($$ == $OUT_PID) {
        # Future: report written files and write counts here.
        %OUT_COUNTS = ();
    }
}

my $LOGDIR;
my $LOGFILE;

# Capture the caller script name here because caller() is valid at load time.
BEGIN {
    my $console_encoding = langinfo(CODESET) || 'UTF-8';
    binmode STDOUT, ":encoding($console_encoding)"
        or die "Cannot set STDOUT encoding to $console_encoding: $!\n";
    binmode STDERR, ":encoding($console_encoding)"
        or die "Cannot set STDERR encoding to $console_encoding: $!\n";

    $LOGDIR = $ENV{LOGDIR} || die "LOGDIR environment variable is not set or empty\n";
    die "LOGDIR directory does not exist: $LOGDIR\n" unless -d $LOGDIR;

    my $cals = at();
    my $top  = $cals->[0];
    my $base = defined $top ? $top->{file} : 'unknown';
    $base =~ s/\.[^.]+$//;

    my $ts = strftime('%m%d%H%M', localtime);
    $LOGFILE = "$LOGDIR/$base$ts.log";
}

sub dying {
    my ($msg) = @_;
    &log('error', $msg);
    confess $msg;
}

sub run_in_fork {
    my ($code) = @_;
    my $pid = fork();
    dying("fork failed: $!") if !defined $pid;
    if ($pid == 0) {
        eval { $code->() };
        my $err = $@;
        if ($err) {
            &log('error', $err);
            _exit(1);
        }
        _exit(0);
    }
    waitpid($pid, 0);
    dying('confirm failed') if $? != 0;
    return;
}

sub log {
    my ($level, $msg) = @_;
    $level = 'info' unless defined $level && length $level;
    my $key = lc $level;
    my $name = $key eq 'debug' ? 'DEBUG'
        : $key eq 'info' ? 'INFO'
        : $key eq 'warn' || $key eq 'warning' ? 'WARN'
        : $key eq 'error' ? 'ERROR'
        : dying("Unsupported log level: $level");
    $msg = '' unless defined $msg;
    my $line = "[$name] $msg";
    $line .= "\n" unless $line =~ /\n\z/;

    print STDERR $line;

    out_file($LOGFILE, $line) if $LOGFILE;

    return $line;
}

sub pathcli {
    my ($mode, $path) = @_;

    my $path_text = ref($path) eq 'HASH' ? ($path->{path} // '') : $path;

    dying("path must not be a mode character: $path_text")
        if $path_text eq '>' || $path_text eq '>>' || $path_text eq '?';

    if ($mode eq '?') {
        $mode = $OUT_COUNTS{$path_text} ? '>>' : '>';
    }

    dying("Unsupported mode: $mode") if $mode ne '<' && $mode ne '>' && $mode ne '>>';

    return {
        eol      => 'lf',
        encoding => 'utf8',
        layer    => $mode . ':encoding(utf8)',
        path     => $path,
    } unless ref $path;

    dying("path must be path string or hashref") if ref($path) ne 'HASH';

    dying("path->{path} is required") if !defined $path->{path} || !length $path->{path};

    my $encoding = defined $path->{encoding} && length $path->{encoding}
        ? lc $path->{encoding}
        : 'utf8';

    dying("Unsupported file encoding: $encoding (use utf8, cp932, or raw)")
        if $encoding !~ /\A(?:utf8|cp932|raw)\z/;

    return {
        eol      => defined $path->{eol} && length $path->{eol} ? lc $path->{eol} : 'lf',
        encoding => $encoding,
        layer    => $mode . ($encoding eq 'raw' ? ':raw' : ':encoding(' . $encoding . ')'),
        path     => $path->{path},
    };
}

sub out_file {
    my @args = @_;

    my $mode = (@args && ($args[0] eq '>' || $args[0] eq '>>' || $args[0] eq '?'))
        ? shift @args
        : '?';
    my ($path, $content) = @args;
    my $spec = pathcli($mode, $path);
    my $text = $content;

    if (ref $content) {
        dying("Unsupported content type: " . ref($content)) if ref($content) ne 'ARRAY';
        my $nl = $spec->{eol} eq 'lf' ? "\n"
            : $spec->{eol} eq 'crlf' ? "\r\n"
            : dying("Unknown write eol mode: $spec->{eol}");
        $text = join($nl, @$content);
    }

    open my $fh, $spec->{layer}, $spec->{path}
        or dying("Cannot write $spec->{path}: $!");
    print {$fh} $text or dying("Cannot write $spec->{path}: $!");
    close $fh or dying("Cannot close $spec->{path}: $!");
    $OUT_COUNTS{$spec->{path}}++;
    return;
}

sub read_file {
    my ($path) = @_;
    my $spec = pathcli('<', $path);
    open my $fh, $spec->{layer}, $spec->{path}
        or dying("Cannot read $spec->{path}: $!");
    local $/;
    my $text = <$fh>;
    close $fh or dying("Cannot close $spec->{path}: $!");
    dying("Cannot read $spec->{path}: file not found or empty") if !defined $text;

    if ($spec->{encoding} eq 'raw') {
        dying("read_file with encoding=>raw does not support list context") if wantarray;
        return $text;
    }

    if ($spec->{eol} eq 'lf') {
        $text =~ s/\r\n|\r/\n/g;
    } elsif ($spec->{eol} eq 'crlf') {
        $text =~ s/\r\n|\r|\n/\r\n/g;
    } else {
        dying("Unknown read eol mode: $spec->{eol}");
    }

    return $text unless wantarray;
    return () unless length $text;
    return split(/\r?\n/, $text, -1);
}

sub dec {
    my ($data) = @_;
    return $data unless defined $data;
    return $data if is_utf8($data);
    my $text = eval { decode('utf8', $data, FB_CROAK) };
    return $text if defined $text;
    my $guess = Encode::Guess->guess($data);
    if (ref $guess) {
        warn "guess_encoding: " . $guess->name . "\n";
    } else {
        warn "guess_encoding: unknown\n";
    }
    return $data;
}

sub dp {
    my @args = @_;
    return unless @args;
    my $out = (@args == 1 && ref $args[0])
        ? &np($args[0])
        : &np(\@args);
    print STDERR $out;
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

sub write_do {
    my ($path, $var) = @_;
    my $do_path = ref($path) eq 'HASH' ? $path->{path} : $path;
    my $dump = dumpU8($var, indent => 1);
    my $text = "use utf8;\n\n" . $dump;
    out_file('>', $do_path, $text);
    return;
}

sub read_do {
    my ($path) = @_;
    my $spec = pathcli('<', $path);
    my $do_path = $spec->{path};
    my $var = do $do_path;
    dying("Failed to read $do_path: $@") if $@;
    dying("Failed to read $do_path: file not found or empty") if !defined $var;
    return $var;
}

1;
