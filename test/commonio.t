use strict;
use warnings;
use utf8;

use Test::More;
use File::Path qw(remove_tree);
use Encode ();

use CommonIO qw(
    append_file dying dumpU8 log read_do read_file
    run_in_fork setLogFile setup_console write_do write_file
);

my $TMP = '/tmp/spool/commonio-test';

sub cleanup {
    remove_tree($TMP) if -d $TMP;
}

cleanup();
mkdir '/tmp/spool' unless -d '/tmp/spool';
mkdir $TMP or die "Cannot create $TMP: $!";

subtest 'log writes UTF-8 text to log file' => sub {
    my $log = "$TMP/app.log";
    setLogFile($log);
    my $line = log('debug', '漢字ログ');
    like $line, qr/\[DEBUG\] 漢字ログ/, 'log returns formatted line';
    my $text = read_file($log);
    like $text, qr/\[DEBUG\] 漢字ログ/, 'log file gets UTF-8 text';
};

subtest 'dying logs error and throws' => sub {
    my $log = "$TMP/error.log";
    unlink $log if -f $log;
    setLogFile($log);
    eval { dying('重大エラー') };
    like $@, qr/重大エラー/, 'dying throws target message';
    my $text = read_file($log);
    like $text, qr/\[ERROR\] 重大エラー/, 'error log file gets message';
};

subtest 'setLogFile undef disables file logging' => sub {
    my $log = "$TMP/disabled.log";
    unlink $log if -f $log;
    setLogFile(undef);
    my $line = log('info', 'fileなし');
    like $line, qr/\[INFO\] fileなし/, 'log still returns formatted line';
    ok !-f $log, 'no log file created while disabled';
};

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

subtest 'write_do UTF-8 fixed regardless of path encoding spec' => sub {
    my $f = "$TMP/do_enc.do";
    write_do({ path => $f, encoding => 'CP932' }, { x => 1 });
    open my $fh, '<:raw', $f or die;
    local $/;
    my $bytes = <$fh>;
    close $fh;
    ok $bytes =~ /use utf8/, 'UTF-8 header present';
};

subtest 'read_do throws on missing file' => sub {
    eval { read_do("$TMP/no_such.do") };
    like $@, qr/file not found or empty|Failed to read/, 'exception on missing file';
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

cleanup();

done_testing();
