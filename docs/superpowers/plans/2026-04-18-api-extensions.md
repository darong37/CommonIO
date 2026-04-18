# CommonIO API 拡張 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `at()` 追加・ログファイル自動決定・`setLogFile` 廃止・`out_file` 追加の3グループを順番に実装する。

**Architecture:** 変更は `src/CommonIO.pm` と `test/commonio.t` に集中する。`at()` は Group B のログ初期化で使うため Task 1 で先に確立する。モジュールロード時（`use CommonIO`）に LOGDIR チェックとログファイル名決定を行う。

**Tech Stack:** Perl 5, Test::More, File::Basename, File::Spec, POSIX (strftime)

---

## ファイル構成

| ファイル | 変更内容 |
|---|---|
| `src/CommonIO.pm` | `at` 追加、`out_file` 追加、ログ初期化ブロック追加、`setLogFile` を @EXPORT_OK から削除、`File::Basename`・`File::Spec` を use 追加、`POSIX` に `strftime` を追加 |
| `test/commonio.t` | `at`・`out_file` をインポート追加、`setLogFile` をインポートから削除、setLogFile 依存テスト5件を置き換え、新 API テスト追加 |

---

## Task 1: `at()` API 実装

**Files:**
- Modify: `src/CommonIO.pm`
- Modify: `test/commonio.t`

- [ ] **Step 1: 失敗するテストを書く**

`test/commonio.t` の `use CommonIO qw(...)` に `at` を追加し、テスト末尾（`cleanup();` の直前）に以下を追加する。

```perl
use CommonIO qw(
    append_file at dying dumpU8 log read_do read_file
    run_in_fork setLogFile setup_console write_do write_file
);
```

```perl
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
    use File::Basename qw(basename);
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
```

- [ ] **Step 2: テストを実行して失敗を確認する**

```bash
PERL5LIB=src:lib LOGDIR=output/logs prove -lr test/
```

期待結果: `at` が未定義のため FAIL

- [ ] **Step 3: `at()` を実装する**

`src/CommonIO.pm` の `use` 行に追加する（`use Carp` の前後あたり）:

```perl
use File::Basename qw(basename);
use File::Spec;
```

`@EXPORT_OK` に `at` を追加する:

```perl
our @EXPORT_OK = qw(
    append_file
    at
    dying
    dumpU8
    log
    out_file
    read_do
    read_file
    run_in_fork
    setup_console
    write_do
    write_file
);
```

（`setLogFile` はここで削除しない。Task 2 で削除する。）

`_normalize_log_level` の前に `sub at` を追加する:

```perl
sub at {
    my @raw;
    my $depth = 0;
    while (1) {
        my @c = caller($depth);
        last unless @c;
        my ($file, $line, $sub) = @c[1, 2, 3];
        $depth++;
        next if $file =~ /\bCommonIO\.pm$/;
        push @raw, {
            file       => basename($file),
            path       => File::Spec->rel2abs($file),
            line       => $line,
            subroutine => defined $sub ? $sub : 'main::',
        };
    }
    my @frames = reverse @raw;
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
```

- [ ] **Step 4: テストを実行して通過を確認する**

```bash
PERL5LIB=src:lib LOGDIR=output/logs prove -lr test/
```

期待結果: 全テスト PASS

- [ ] **Step 5: コミットする**

```bash
git add src/CommonIO.pm test/commonio.t
git commit -m "feat: add at() API"
```

---

## Task 2: ログファイル自動決定 + `setLogFile` 廃止

**Files:**
- Modify: `src/CommonIO.pm`
- Modify: `test/commonio.t`

- [ ] **Step 1: 既存の setLogFile 依存テスト5件を削除し、置き換えテストを書く**

`test/commonio.t` の以下の subtest を **削除** する:
- `'log writes UTF-8 text to log file'`
- `'dying logs error and throws'`
- `'setLogFile undef disables file logging'`
- `'setLogFile rejects encoding option'`
- `'log file is UTF-8 with valid setLogFile path'`

インポートから `setLogFile` を削除する:

```perl
use CommonIO qw(
    append_file at dying dumpU8 log read_do read_file
    run_in_fork setup_console write_do write_file
);
```

代わりに以下のテストを追加する（`cleanup();` の直前）:

```perl
subtest 'CommonIO dies with empty LOGDIR' => sub {
    local $ENV{LOGDIR} = '';
    my $out = `$^X -Isrc -e 'use CommonIO' 2>&1`;
    isnt $?, 0, 'exits non-zero with empty LOGDIR';
    like $out, qr/LOGDIR/i, 'error mentions LOGDIR';
};

subtest 'log writes to auto-determined file in LOGDIR' => sub {
    my $logdir = $ENV{LOGDIR};
    ok defined $logdir && length $logdir, 'LOGDIR is set';
    log('info', 'auto-log-test-line');
    my @files = glob("$logdir/commonio*.log");
    ok @files > 0, 'log file exists in LOGDIR';
    my $text = read_file($files[0]);
    like $text, qr/auto-log-test-line/, 'log content written to file';
};

subtest 'log file name matches commonio+8digit+.log' => sub {
    my @files = glob("$ENV{LOGDIR}/commonio*.log");
    ok @files > 0, 'log file found';
    like $files[0], qr|/commonio\d{8}\.log$|, 'filename format: basename+MMDDHHMM.log';
};

subtest 'log file is UTF-8 encoded' => sub {
    log('debug', '自動ログUTF8確認');
    my @files = glob("$ENV{LOGDIR}/commonio*.log");
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
    my @files = glob("$ENV{LOGDIR}/commonio*.log");
    my $text = read_file($files[0]);
    like $text, qr/\[ERROR\] 自動ログエラー確認/, 'error written to auto log file';
};
```

- [ ] **Step 2: テストを実行して失敗を確認する**

```bash
PERL5LIB=src:lib LOGDIR=output/logs prove -lr test/
```

期待結果: `setLogFile` インポートエラーまたは新テストが FAIL

- [ ] **Step 3: `src/CommonIO.pm` を修正する**

`use POSIX` に `strftime` を追加する:

```perl
use POSIX qw(_exit strftime);
```

`@EXPORT_OK` から `setLogFile` を削除する（Step 1 の Task 1 で追加した状態から):

```perl
our @EXPORT_OK = qw(
    append_file
    at
    dying
    dumpU8
    log
    out_file
    read_do
    read_file
    run_in_fork
    setup_console
    write_do
    write_file
);
```

`my $LOG_TARGET;` の直後に自動初期化ブロックを追加する:

```perl
my $LOG_TARGET;

# Auto-initialize log file from LOGDIR and calling script name at load time.
{
    die "LOGDIR environment variable is not set or empty\n"
        unless defined $ENV{LOGDIR} && length $ENV{LOGDIR};

    my $callers = CommonIO::at();
    my $top     = $callers->[0];
    my $base    = $top->{file};
    $base =~ s/\.[^.]+$//;

    my $ts      = strftime('%m%d%H%M', localtime);
    my $logfile = "$ENV{LOGDIR}/$base$ts.log";
    $LOG_TARGET = { path => $logfile, encoding => 'UTF-8', eol => 'lf' };
}
```

`sub setLogFile` は内部専用として残す（削除しない）。

- [ ] **Step 4: テストを実行して通過を確認する**

```bash
PERL5LIB=src:lib LOGDIR=output/logs prove -lr test/
```

期待結果: 全テスト PASS

- [ ] **Step 5: コミットする**

```bash
git add src/CommonIO.pm test/commonio.t
git commit -m "feat: auto-determine log file from LOGDIR, remove setLogFile from public API"
```

---

## Task 3: `out_file` API 実装

**Files:**
- Modify: `src/CommonIO.pm`
- Modify: `test/commonio.t`

- [ ] **Step 1: 失敗するテストを書く**

`test/commonio.t` のインポートに `out_file` を追加する（Task 2 終了時点の状態から）:

```perl
use CommonIO qw(
    append_file at dying dumpU8 log out_file read_do read_file
    run_in_fork setup_console write_do write_file
);
```

テスト（`cleanup();` の直前）に追加する:

```perl
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
```

- [ ] **Step 2: テストを実行して失敗を確認する**

```bash
PERL5LIB=src:lib LOGDIR=output/logs prove -lr test/
```

期待結果: `out_file` が未定義のため FAIL

- [ ] **Step 3: `out_file` を実装する**

`src/CommonIO.pm` の `my $LOG_TARGET;` の前に以下を追加する:

```perl
my %_out_counts;
my $_out_pid = $$;

END {
    if ($$ == $_out_pid) {
        %_out_counts = ();
        # Future: report written files and write counts here.
    }
}
```

`sub append_file` の後に `sub out_file` を追加する:

```perl
sub out_file {
    my ($path, $text) = @_;
    my $spec = _parse_path($path, qw(path encoding eol));
    my $key  = $spec->{path};
    if ($_out_counts{$key}) {
        append_file($path, $text);
    } else {
        write_file($path, $text);
    }
    $_out_counts{$key}++;
    return;
}
```

- [ ] **Step 4: テストを実行して通過を確認する**

```bash
PERL5LIB=src:lib LOGDIR=output/logs prove -lr test/
```

期待結果: 全テスト PASS

- [ ] **Step 5: コミットする**

```bash
git add src/CommonIO.pm test/commonio.t
git commit -m "feat: add out_file API with PID-aware write count tracking"
```

---

## セルフレビュー

### スペックカバレッジ

| 要件 | タスク |
|---|---|
| `at()` 正式 API 追加 | Task 1 |
| `at()` が CommonIO 内部フレームを除外 | Task 1 Step 3 |
| `at()` がレベル 0 を最上位 `.pl` とする | Task 1 Step 3 |
| `at()` が `.pl` 未検出時は最上位フレームを使う | Task 1 Step 3 |
| LOGDIR 未設定・空で die | Task 2 Step 3 |
| ログファイル名 = `<basename><MMDDHHMM>.log` | Task 2 Step 3 |
| ログファイル名決定に `at()` を使う | Task 2 Step 3 |
| `setLogFile` 公開 API から廃止 | Task 2 Step 3 |
| `out_file` 1 回目は write_file 相当 | Task 3 Step 3 |
| `out_file` 2 回目以降は append_file 相当 | Task 3 Step 3 |
| 書き込みが成功した回数をカウント | Task 3 Step 3（die しなければ increment されない） |
| PID と組で管理、同 PID の END でクリア | Task 3 Step 3 |
| fork 後の子プロセスではクリアしない | Task 3 Step 3、テストで確認 |
| END ブロックに英語コメントを残す | Task 3 Step 3 |
