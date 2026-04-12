use strict;
use warnings;
use utf8;

use Test::More;
use File::Path qw(remove_tree);

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

cleanup();

done_testing();
