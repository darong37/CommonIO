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

cleanup();

done_testing();
