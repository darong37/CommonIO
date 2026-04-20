use strict;
use warnings;
use utf8;

use Test::More;
use File::Path qw(remove_tree);
use Encode ();
use File::Basename qw(basename);

use CommonIO qw(
    at dec dp dying dumpU8 log out_file pathcli read_do read_file
    run_in_fork write_do
);

my $TMP = '/tmp/spool/commonio-test';

sub cleanup {
    remove_tree($TMP) if -d $TMP;
}

cleanup();
mkdir '/tmp/spool' unless -d '/tmp/spool';
mkdir $TMP or die "Cannot create $TMP: $!";


subtest 'read_file rejects unsupported encoding' => sub {
    my $f = "$TMP/enc_r.txt";
    out_file('>', $f, 'test');
    eval { read_file({ path => $f, encoding => 'EUC-JP' }) };
    like $@, qr/Unsupported file encoding/i, 'EUC-JP is rejected on read';
};

subtest 'read_file returns scalar text' => sub {
    my $f = "$TMP/read_scalar.txt";
    out_file('>', $f, "hello world");
    my $text = read_file($f);
    is $text, "hello world", 'scalar text matches';
};

subtest 'read_file returns line array' => sub {
    my $f = "$TMP/read_lines.txt";
    out_file('>', $f, "line1\nline2\nline3");
    my @lines = read_file($f);
    is scalar @lines, 3, 'three lines';
    is $lines[0], 'line1', 'first line ok';
    is $lines[2], 'line3', 'third line ok';
};

subtest 'read_file normalizes CRLF to LF with eol=>lf' => sub {
    my $f = "$TMP/read_crlf.txt";
    open my $fh, '>:raw', $f or die;
    print {$fh} "line1\r\nline2\r\n";
    close $fh;
    my $text = read_file({ path => $f, eol => 'lf' });
    unlike $text, qr/\r/, 'no CR after normalization';
    like $text, qr/line1\nline2/, 'LF present';
};

subtest 'read_file normalizes to CRLF with eol=>crlf' => sub {
    my $f = "$TMP/read_crlf_mode.txt";
    open my $fh, '>:raw', $f or die;
    print {$fh} "line1\nline2\r\nline3\r";
    close $fh;
    my $text = read_file({ path => $f, eol => 'crlf' });
    is $text, "line1\r\nline2\r\nline3\r\n", 'all line endings normalized to CRLF';
};

subtest 'read_file throws on missing file' => sub {
    eval { read_file("$TMP/no_such_file.txt") };
    like $@, qr/Cannot read/, 'exception on missing file';
};

subtest 'read_file reads CP932 file' => sub {
    my $f = "$TMP/read_cp932.txt";
    out_file('>', { path => $f, encoding => 'cp932' }, "テスト");
    my $text = read_file({ path => $f, encoding => 'cp932' });
    is $text, 'テスト', 'CP932 round-trip ok';
};

subtest 'read_file with hash path spec' => sub {
    my $f = "$TMP/read_hash.txt";
    out_file('>', { path => $f, encoding => 'utf8', eol => 'lf' }, "ハッシュpath");
    my $text = read_file({ path => $f, encoding => 'utf8', eol => 'lf' });
    like $text, qr/ハッシュpath/, 'hash path spec works';
};

subtest 'write_do / read_do round-trip hash' => sub {
    my $f = "$TMP/data.do";
    my $orig = { key => 'val', num => 42 };
    write_do($f, $orig);
    my $got = read_do($f);
    is ref($got), 'HASH', 'got hashref';
    is $got->{key}, 'val', 'key matches';
    is $got->{num}, 42, 'num matches';
};

subtest 'write_do / read_do round-trip array' => sub {
    my $f = "$TMP/arr.do";
    my $orig = ['a', 'b', 'c'];
    write_do($f, $orig);
    my $got = read_do($f);
    is ref($got), 'ARRAY', 'got arrayref';
    is $got->[0], 'a', 'first element ok';
    is $got->[2], 'c', 'third element ok';
};

subtest 'write_do / read_do preserves Unicode' => sub {
    my $f = "$TMP/unicode.do";
    write_do($f, { msg => '日本語テスト' });
    my $got = read_do($f);
    is $got->{msg}, '日本語テスト', 'Unicode preserved';
};

subtest 'write_do ignores encoding option' => sub {
    my $f = "$TMP/do_enc.do";
    write_do({ path => $f, encoding => 'cp932' }, { x => 1 });
    my $got = read_do($f);
    is $got->{x}, 1, 'write_do ignores encoding option';
};

subtest 'write_do ignores eol option' => sub {
    my $f = "$TMP/do_eol.do";
    write_do({ path => $f, eol => 'crlf' }, { x => 1 });
    my $got = read_do($f);
    is $got->{x}, 1, 'write_do ignores eol option';
};

subtest 'read_do throws on missing file' => sub {
    eval { read_do("$TMP/no_such.do") };
    like $@, qr/file not found or empty|Failed to read/, 'exception on missing file';
};

subtest 'read_do throws on syntax error file' => sub {
    my $f = "$TMP/syntax_err.do";
    out_file('>', $f, 'this is not valid perl $$$');
    eval { read_do($f) };
    like $@, qr/Failed to read/, 'syntax error triggers exception';
};

subtest 'read_do ignores encoding option' => sub {
    my $f = "$TMP/read_do_enc.do";
    write_do($f, { ok => 1 });
    my $got = read_do({ path => $f, encoding => 'cp932' });
    is $got->{ok}, 1, 'read_do ignores encoding option';
};

subtest 'read_do ignores eol option' => sub {
    my $f = "$TMP/read_do_eol.do";
    write_do($f, { ok => 1 });
    my $got = read_do({ path => $f, eol => 'lf' });
    is $got->{ok}, 1, 'read_do ignores eol option';
};

subtest 'dumpU8 preserves Unicode characters' => sub {
    my $dump = dumpU8({ word => '漢字' });
    like $dump, qr/漢字/, 'Unicode not escaped';
    unlike $dump, qr/\\x\{/, 'no \\x{} escapes';
};

subtest 'dumpU8 with indent=>0 produces one line' => sub {
    my $dump = dumpU8(['x', 'y'], indent => 0);
    unlike $dump, qr/\n/, 'no newline with indent 0';
};

subtest 'BEGIN auto-runs: STDOUT has encoding layer' => sub {
    my @layers = PerlIO::get_layers(STDOUT);
    ok grep( { /^encoding/ } @layers ), 'STDOUT has encoding layer';
};

subtest 'BEGIN auto-runs: STDERR has encoding layer' => sub {
    my @layers = PerlIO::get_layers(STDERR);
    ok grep( { /^encoding/ } @layers ), 'STDERR has encoding layer';
};

subtest 'run_in_fork executes code in child' => sub {
    my $f = "$TMP/fork_result.txt";
    unlink $f if -f $f;
    run_in_fork(sub {
        out_file('>', $f, '子プロセス実行');
    });
    ok -f $f, 'file created by child';
    my $text = read_file($f);
    like $text, qr/子プロセス実行/, 'child wrote correct content';
};

subtest 'run_in_fork throws when child throws' => sub {
    eval {
        run_in_fork(sub {
            die "子プロセスエラー\n";
        });
    };
    like $@, qr/confirm failed/, 'parent throws on child failure';
};

subtest 'pathcli with string path returns path_spec' => sub {
    my $spec = pathcli('>', '/tmp/foo.txt');
    is $spec->{path},     '/tmp/foo.txt',       'path ok';
    is $spec->{encoding}, 'utf8',               'default encoding utf8';
    is $spec->{eol},      'lf',                 'default eol lf';
    like $spec->{layer},  qr/>:encoding\(utf8\)/, 'layer contains mode and encoding';
};

subtest 'pathcli with hash path returns path_spec' => sub {
    my $spec = pathcli('<', { path => '/tmp/bar.txt', encoding => 'cp932', eol => 'crlf' });
    is $spec->{path},     '/tmp/bar.txt', 'path ok';
    is $spec->{encoding}, 'cp932',        'encoding cp932';
    is $spec->{eol},      'crlf',         'eol crlf';
    like $spec->{layer},  qr/<:encoding\(cp932\)/, 'layer ok';
};

subtest 'pathcli resolves ? to > on first call' => sub {
    my $f = "$TMP/pathcli_q.txt";
    my $spec = pathcli('?', $f);
    like $spec->{layer}, qr/>:/, 'first ? resolves to >';
};

subtest 'pathcli resolves ? to >> on second call' => sub {
    my $f = "$TMP/pathcli_q2.txt";
    out_file('>', $f, 'seed');
    my $spec = pathcli('?', $f);
    like $spec->{layer}, qr/>>:/, 'second ? resolves to >>';
};

subtest 'pathcli rejects mode character in path' => sub {
    for my $bad ('>', '>>', '?') {
        eval { pathcli('>', $bad) };
        like $@, qr/mode character/i, "path '$bad' is rejected";
    }
};

subtest 'at returns callers arrayref' => sub {
    my $callers = at();
    is ref($callers), 'ARRAY', 'returns arrayref';
    ok @$callers > 0, 'at least one frame';
};

subtest 'at level 0 has required keys' => sub {
    my $callers = at();
    my $top = $callers->[0];
    ok defined $top->{file},       'file defined';
    ok defined $top->{path},       'path defined';
    ok defined $top->{line},       'line defined';
    ok defined $top->{subroutine}, 'subroutine defined';
};

subtest 'at file is basename of path' => sub {
    my $callers = at();
    my $top = $callers->[0];
    is $top->{file}, basename($top->{path}), 'file is basename of path';
};

subtest 'at excludes CommonIO internal frames' => sub {
    my $callers = at();
    for my $frame (@$callers) {
        unlike $frame->{file}, qr/CommonIO\.pm$/, "no CommonIO frame: $frame->{file}";
    }
};

subtest 'at level 0 is test script' => sub {
    my $callers = at();
    like $callers->[0]{file}, qr/commonio\.t$/, 'level 0 is test script';
};

subtest 'CommonIO dies with empty LOGDIR' => sub {
    local $ENV{LOGDIR} = '';
    my $out = `$^X -Isrc -e 'use CommonIO' 2>&1`;
    isnt $?, 0, 'exits non-zero with empty LOGDIR';
    like $out, qr/LOGDIR/i, 'error mentions LOGDIR';
};

subtest 'CommonIO dies with unset LOGDIR' => sub {
    local $ENV{LOGDIR};
    delete $ENV{LOGDIR};
    my $out = `$^X -Isrc -e 'use CommonIO' 2>&1`;
    isnt $?, 0, 'exits non-zero with unset LOGDIR';
    like $out, qr/LOGDIR/i, 'error mentions LOGDIR';
};

subtest 'CommonIO dies when LOGDIR directory does not exist' => sub {
    my $out = `LOGDIR=/nonexistent/path $^X -Isrc -e 'use CommonIO' 2>&1`;
    isnt $?, 0, 'exits non-zero when LOGDIR dir missing';
    like $out, qr/LOGDIR directory does not exist/i, 'error mentions missing directory';
};

subtest 'log returns formatted line' => sub {
    my $line = log('info', '戻り値テスト');
    like $line, qr/\[INFO\] 戻り値テスト/, 'log returns formatted line string';
};

subtest 'log writes to auto-determined file in LOGDIR' => sub {
    my $logdir = $ENV{LOGDIR};
    ok defined $logdir && length $logdir, 'LOGDIR is set';
    log('info', 'auto-log-test-line');
    my @files = sort { (stat($b))[9] <=> (stat($a))[9] } glob("$logdir/commonio*.log");
    ok @files > 0, 'log file exists in LOGDIR';
    my $text = read_file($files[0]);
    like $text, qr/auto-log-test-line/, 'log content written to file';
};

subtest 'log file name matches commonio+8digit+.log' => sub {
    my @files = sort { (stat($b))[9] <=> (stat($a))[9] } glob("$ENV{LOGDIR}/commonio*.log");
    ok @files > 0, 'log file found';
    like $files[0], qr|/commonio\d{8}\.log$|, 'filename format: basename+MMDDHHMM.log';
};

subtest 'log file is UTF-8 encoded' => sub {
    log('debug', '自動ログUTF8確認');
    my @files = sort { (stat($b))[9] <=> (stat($a))[9] } glob("$ENV{LOGDIR}/commonio*.log");
    open my $fh, '<:raw', $files[0] or die;
    local $/;
    my $bytes = <$fh>;
    close $fh;
    my $text = Encode::decode('UTF-8', $bytes);
    like $text, qr/自動ログUTF8確認/, 'log file is valid UTF-8';
};

subtest 'dying logs error to auto file and throws' => sub {
    eval { dying('自動ログエラー確認') };
    like $@, qr/自動ログエラー確認/, 'dying throws message';
    my @files = sort { (stat($b))[9] <=> (stat($a))[9] } glob("$ENV{LOGDIR}/commonio*.log");
    my $text = read_file($files[0]);
    like $text, qr/\[ERROR\] 自動ログエラー確認/, 'error written to auto log file';
};

subtest 'out_file first call overwrites existing file' => sub {
    my $f = "$TMP/out_first.txt";
    open my $fh, '>:utf8', $f or die "Cannot create $f: $!";
    print {$fh} 'initial';
    close $fh;
    out_file($f, 'replaced');
    is read_file($f), 'replaced', 'first call overwrites';
};

subtest 'out_file second call appends' => sub {
    my $f = "$TMP/out_second.txt";
    out_file($f, "first\n");
    out_file($f, "second\n");
    my $text = read_file($f);
    like $text, qr/first\nsecond/, 'second call appends';
};

subtest 'out_file third call also appends' => sub {
    my $f = "$TMP/out_third.txt";
    out_file($f, "a\n");
    out_file($f, "b\n");
    out_file($f, "c\n");
    my $text = read_file($f);
    like $text, qr/a\nb\nc/, 'third call appends after second';
};

subtest 'out_file different paths are independent' => sub {
    my $f1 = "$TMP/out_path1.txt";
    my $f2 = "$TMP/out_path2.txt";
    out_file($f1, 'path1-first');
    out_file($f2, 'path2-first');
    out_file($f1, '-path1-second');
    is read_file($f1), 'path1-first-path1-second', 'path1 counts independently';
    is read_file($f2), 'path2-first',              'path2 counts independently';
};

subtest 'out_file accepts hash path with encoding and eol' => sub {
    my $f = "$TMP/out_hash.txt";
    out_file({ path => $f, encoding => 'utf8', eol => 'lf' }, "ハッシュ\n");
    out_file({ path => $f, encoding => 'utf8', eol => 'lf' }, "追記\n");
    my $text = read_file($f);
    like $text, qr/ハッシュ\n追記/, 'hash path spec works with out_file';
};

subtest 'out_file scalar text is not changed by eol' => sub {
    my $f = "$TMP/out_scalar_eol.txt";
    out_file('>', { path => $f, encoding => 'utf8', eol => 'crlf' }, "a\nb\n");
    open my $fh, '<:raw', $f or die;
    local $/;
    my $raw = <$fh>;
    close $fh;
    is $raw, "a\nb\n", 'scalar text is written as-is';
};

subtest 'out_file child process does not clear parent counts' => sub {
    my $f = "$TMP/out_fork.txt";
    out_file($f, "parent-first\n");
    run_in_fork(sub {
        out_file($f, "child\n");
    });
    out_file($f, "parent-second\n");
    my $text = read_file($f);
    like $text, qr/parent-first\nchild\nparent-second/, 'parent appends after fork';
};

subtest 'dec warns guess_encoding for non-UTF8 bytes' => sub {
    my $cp932_bytes = Encode::encode('CP932', 'テスト');
    my $warned = '';
    local $SIG{__WARN__} = sub { $warned .= $_[0] };
    my $out = dec($cp932_bytes);
    like $warned, qr/guess_encoding/i, 'warn includes guess_encoding';
    is $out, $cp932_bytes, 'original bytes returned unchanged';
};

subtest 'dec warns guess_encoding: unknown for unrecognizable bytes' => sub {
    my $bad = "\x80\x81\x82\x83\x84\x85";
    my $warned = '';
    local $SIG{__WARN__} = sub { $warned .= $_[0] };
    dec($bad);
    like $warned, qr/guess_encoding/i, 'warn includes guess_encoding';
};

subtest 'out_file with mode > always overwrites' => sub {
    my $f = "$TMP/out_mode_overwrite.txt";
    out_file('>', $f, "first\n");
    out_file('>', $f, "second\n");
    is read_file($f), "second\n", 'mode > overwrites each time';
};

subtest 'out_file with mode >> always appends' => sub {
    my $f = "$TMP/out_mode_append.txt";
    out_file('>>', $f, "first\n");
    out_file('>>', $f, "second\n");
    like read_file($f), qr/first\nsecond/, 'mode >> appends each time';
};

subtest 'out_file with mode ? is overwrite then append' => sub {
    my $f = "$TMP/out_mode_q.txt";
    out_file('?', $f, "first\n");
    out_file('?', $f, "second\n");
    like read_file($f), qr/first\nsecond/, 'mode ? appends from 2nd call';
};

subtest 'out_file rejects path that is a mode character' => sub {
    eval { out_file({ path => '>', encoding => 'utf8' }, 'text') };
    like $@, qr/mode character/i, 'path => > is rejected';

    eval { out_file({ path => '>>' }, 'text') };
    like $@, qr/mode character/i, 'path => >> is rejected';

    eval { out_file({ path => '?' }, 'text') };
    like $@, qr/mode character/i, 'path => ? is rejected';
};

subtest 'out_file with encoding=>raw writes bytes as-is' => sub {
    my $f      = "$TMP/out_raw.bin";
    my $bytes  = "\x80\x81\x82";
    out_file('>', { path => $f, encoding => 'raw' }, $bytes);
    open my $fh, '<:raw', $f or die;
    local $/;
    my $got = <$fh>;
    close $fh;
    is $got, $bytes, 'raw bytes written without encoding';
};

subtest 'read_file with encoding=>raw returns bytes as-is' => sub {
    my $f     = "$TMP/read_raw.bin";
    my $bytes = "\x80\x81\x82";
    out_file('>', { path => $f, encoding => 'raw' }, $bytes);
    my $got   = read_file({ path => $f, encoding => 'raw' });
    is $got, $bytes, 'raw bytes read without decoding';
};

subtest 'read_file with encoding=>raw in list context dies' => sub {
    my $f = "$TMP/read_raw_list.bin";
    out_file('>', { path => $f, encoding => 'raw' }, "data");
    eval { my @lines = read_file({ path => $f, encoding => 'raw' }) };
    like $@, qr/list context/i, 'list context with raw encoding dies';
};

sub _capture_dp {
    my $code = shift;
    my $f = "$TMP/dp_cap.txt";
    open my $saved_err, '>&', \*STDERR or die "dup STDERR: $!";
    open STDERR, '>:utf8', $f or die "redirect STDERR: $!";
    $code->();
    open STDERR, '>&', $saved_err or die "restore STDERR: $!";
    return '' unless -s $f;
    open my $fh, '<:utf8', $f or die "read dp_cap: $!";
    local $/;
    return <$fh>;
}

subtest 'dp with no args outputs nothing' => sub {
    my $out = _capture_dp(sub { dp() });
    is $out, '', 'no output for dp()';
};

subtest 'dp with single ref passes ref directly' => sub {
    my $out = _capture_dp(sub { dp({ a => 1 }) });
    like $out, qr/\{/, 'hashref passed directly: hash notation in output';
};

subtest 'dp with scalar wraps in arrayref' => sub {
    my $out = _capture_dp(sub { dp('hello') });
    like $out, qr/\[/, 'scalar wrapped in arrayref: array notation in output';
};

subtest 'dp with multiple args wraps in arrayref' => sub {
    my $out = _capture_dp(sub { dp(1, 2, 3) });
    like $out, qr/\[/, 'multiple args wrapped in arrayref: array notation in output';
};

subtest 'dp with kanji does not die' => sub {
    ok eval { _capture_dp(sub { dp(['日本語', '漢字']) }); 1 }, 'kanji arrayref does not die';
};

subtest 'dec converts UTF-8 bytes to Perl string' => sub {
    my $bytes = Encode::encode('UTF-8', '日本語');
    my $text  = dec($bytes);
    ok Encode::is_utf8($text), 'result has UTF-8 flag';
    is $text, '日本語', 'decoded correctly';
};

subtest 'dec passes through already-decoded Perl string' => sub {
    my $str = '日本語';
    my $out = dec($str);
    is $out, $str, 'unchanged';
    ok Encode::is_utf8($out), 'still has UTF-8 flag';
};

subtest 'dec passes through ASCII string' => sub {
    my $out = dec('hello');
    is $out, 'hello', 'ASCII unchanged';
};

subtest 'dec returns original on invalid UTF-8' => sub {
    my $bad = "\x80\x81";
    my $out = dec($bad);
    is $out, $bad, 'invalid UTF-8 returned as-is';
};

subtest 'dec returns undef for undef input' => sub {
    my $out = dec(undef);
    ok !defined $out, 'undef in, undef out';
};

cleanup();

done_testing();
