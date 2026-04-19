use strict;
use warnings;
use utf8;

use Test::More;
use File::Path qw(remove_tree);
use Encode ();
use File::Basename qw(basename);

use CommonIO qw(
    append_file at dp dying dumpU8 log out_file read_do read_file
    run_in_fork setup_console write_do write_file
);

my $TMP = '/tmp/spool/commonio-test';

sub cleanup {
    remove_tree($TMP) if -d $TMP;
}

cleanup();
mkdir '/tmp/spool' unless -d '/tmp/spool';
mkdir $TMP or die "Cannot create $TMP: $!";


subtest 'write_file rejects unsupported encoding' => sub {
    my $f = "$TMP/enc.txt";
    eval { write_file({ path => $f, encoding => 'EUC-JP' }, 'test') };
    like $@, qr/Unsupported file encoding/i, 'EUC-JP is rejected';
};

subtest 'read_file rejects unsupported encoding' => sub {
    my $f = "$TMP/enc_r.txt";
    write_file($f, 'test');
    eval { read_file({ path => $f, encoding => 'EUC-JP' }) };
    like $@, qr/Unsupported file encoding/i, 'EUC-JP is rejected on read';
};

subtest 'append_file rejects unsupported encoding' => sub {
    my $f = "$TMP/enc_a.txt";
    write_file($f, 'base');
    eval { append_file({ path => $f, encoding => 'EUC-JP' }, 'test') };
    like $@, qr/Unsupported file encoding/i, 'EUC-JP is rejected on append';
};

subtest 'write_file writes UTF-8 text' => sub {
    my $f = "$TMP/write_utf8.txt";
    write_file($f, "日本語テキスト\n");
    my $text = read_file($f);
    like $text, qr/日本語テキスト/, 'UTF-8 round-trip ok';
};

subtest 'write_file writes CRLF' => sub {
    my $f = "$TMP/write_crlf.txt";
    write_file({ path => $f, eol => 'crlf' }, "line1\nline2");
    open my $fh, '<:raw', $f or die;
    local $/;
    my $bytes = <$fh>;
    close $fh;
    like $bytes, qr/\r\n/, 'CRLF bytes present';
};

subtest 'write_file preserves eol' => sub {
    my $f = "$TMP/write_preserve.txt";
    write_file({ path => $f, eol => 'preserve' }, "line1\r\nline2\nline3");
    open my $fh, '<:raw', $f or die;
    local $/;
    my $bytes = <$fh>;
    close $fh;
    like $bytes, qr/line1\r\nline2\nline3/, 'mixed eol preserved';
};

subtest 'write_file writes array lines' => sub {
    my $f = "$TMP/write_lines.txt";
    write_file($f, ['alpha', 'beta', 'gamma']);
    my $text = read_file($f);
    like $text, qr/alpha\nbeta\ngamma/, 'lines joined with LF';
};

subtest 'write_file writes CP932' => sub {
    my $f = "$TMP/write_cp932.txt";
    write_file({ path => $f, encoding => 'CP932' }, "テスト");
    open my $fh, '<:raw', $f or die;
    local $/;
    my $bytes = <$fh>;
    close $fh;
    # CP932 のカタカナは 2 バイト/文字、UTF-8 は 3 バイト/文字なので CP932 の方が短い
    # これにより CP932 エンコーディングが実際に適用されたことを確認できる
    ok length($bytes) < length(Encode::encode('UTF-8', 'テスト')), 'CP932 bytes differ from UTF-8';
};

subtest 'append_file appends to existing file' => sub {
    my $f = "$TMP/append.txt";
    write_file($f, "first\n");
    append_file($f, "second\n");
    my $text = read_file($f);
    like $text, qr/first\nsecond/, 'both lines present';
};

subtest 'read_file returns scalar text' => sub {
    my $f = "$TMP/read_scalar.txt";
    write_file($f, "hello world");
    my $text = read_file($f);
    is $text, "hello world", 'scalar text matches';
};

subtest 'read_file returns line array' => sub {
    my $f = "$TMP/read_lines.txt";
    write_file($f, "line1\nline2\nline3");
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

subtest 'read_file preserves CRLF with eol=>preserve' => sub {
    my $f = "$TMP/read_preserve.txt";
    open my $fh, '>:raw', $f or die;
    print {$fh} "line1\r\nline2\r\n";
    close $fh;
    my $text = read_file({ path => $f, eol => 'preserve' });
    like $text, qr/\r\n/, 'CRLF preserved';
};

subtest 'read_file throws on missing file' => sub {
    eval { read_file("$TMP/no_such_file.txt") };
    like $@, qr/Cannot read/, 'exception on missing file';
};

subtest 'read_file reads CP932 file' => sub {
    my $f = "$TMP/read_cp932.txt";
    write_file({ path => $f, encoding => 'CP932' }, "テスト");
    my $text = read_file({ path => $f, encoding => 'CP932' });
    is $text, 'テスト', 'CP932 round-trip ok';
};

subtest 'read_file with hash path spec' => sub {
    my $f = "$TMP/read_hash.txt";
    write_file({ path => $f, encoding => 'UTF-8', eol => 'lf' }, "ハッシュpath");
    my $text = read_file({ path => $f, encoding => 'UTF-8', eol => 'preserve' });
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

subtest 'write_do rejects encoding option' => sub {
    my $f = "$TMP/do_enc.do";
    eval { write_do({ path => $f, encoding => 'CP932' }, { x => 1 }) };
    like $@, qr/Unsupported path option: encoding/, 'write_do rejects encoding';
};

subtest 'write_do rejects eol option' => sub {
    my $f = "$TMP/do_eol.do";
    eval { write_do({ path => $f, eol => 'crlf' }, { x => 1 }) };
    like $@, qr/Unsupported path option: eol/, 'write_do rejects eol';
};

subtest 'read_do throws on missing file' => sub {
    eval { read_do("$TMP/no_such.do") };
    like $@, qr/file not found or empty|Failed to read/, 'exception on missing file';
};

subtest 'read_do throws on syntax error file' => sub {
    my $f = "$TMP/syntax_err.do";
    write_file($f, 'this is not valid perl $$$');
    eval { read_do($f) };
    like $@, qr/Failed to read/, 'syntax error triggers exception';
};

subtest 'read_do rejects encoding option' => sub {
    my $f = "$TMP/read_do_enc.do";
    write_do($f, { ok => 1 });
    eval { read_do({ path => $f, encoding => 'CP932' }) };
    like $@, qr/Unsupported path option: encoding/, 'read_do rejects encoding';
};

subtest 'read_do rejects eol option' => sub {
    my $f = "$TMP/read_do_eol.do";
    write_do($f, { ok => 1 });
    eval { read_do({ path => $f, eol => 'lf' }) };
    like $@, qr/Unsupported path option: eol/, 'read_do rejects eol';
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

subtest 'setup_console returns UTF-8' => sub {
    my $enc = setup_console('UTF-8');
    is $enc, 'UTF-8', 'returns UTF-8';
};

subtest 'setup_console returns CP932' => sub {
    my $enc = setup_console('CP932');
    is $enc, 'CP932', 'returns CP932';
    setup_console('UTF-8');    # テスト後に UTF-8 へ戻す
};

subtest 'setup_console with no arg does not throw' => sub {
    my $enc;
    eval { $enc = setup_console() };
    ok !$@, 'no exception without arg';
    ok defined $enc, 'returns encoding name';
};

subtest 'setup_console rejects unsupported encoding' => sub {
    eval { setup_console('EUC-JP') };
    like $@, qr/Unsupported console encoding/i, 'EUC-JP rejected';
};


subtest 'run_in_fork executes code in child' => sub {
    my $f = "$TMP/fork_result.txt";
    unlink $f if -f $f;
    run_in_fork(sub {
        write_file($f, '子プロセス実行');
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
    write_file($f, 'initial');
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
    out_file({ path => $f, encoding => 'UTF-8', eol => 'lf' }, "ハッシュ\n");
    out_file({ path => $f, encoding => 'UTF-8', eol => 'lf' }, "追記\n");
    my $text = read_file($f);
    like $text, qr/ハッシュ\n追記/, 'hash path spec works with out_file';
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

subtest 'dp does not die with various inputs' => sub {
    open my $saved_err, '>&', \*STDERR or die "Cannot dup STDERR: $!";
    open STDERR, '>', '/dev/null' or die "Cannot open /dev/null: $!";

    ok eval { dp(); 1 },                  'dp() - no args';
    ok eval { dp('hello'); 1 },           'dp(scalar string)';
    ok eval { dp(42); 1 },                'dp(scalar number)';
    ok eval { dp([1, 2, 3]); 1 },         'dp(arrayref)';
    ok eval { dp({ a => 1 }); 1 },        'dp(hashref)';
    ok eval { dp(1, 2, 3); 1 },           'dp(multiple args - list)';
    ok eval { dp('日本語'); 1 },          'dp(kanji scalar)';
    ok eval { dp(['日本語', '漢字']); 1 }, 'dp(arrayref with kanji)';

    open STDERR, '>&', $saved_err or die "Cannot restore STDERR: $!";
};

cleanup();

done_testing();
