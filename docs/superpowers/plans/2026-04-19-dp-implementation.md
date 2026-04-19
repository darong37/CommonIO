# dp API 追加・log STDERR 修正 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `_print_console_line` の `binmode STDERR, ':raw'` バグを修正し、Data::Printer を薄くラップした `dp` API を追加する。

**Architecture:** `log` の STDERR 出力を `print STDERR $line` に簡略化し、エンコードを `setup_console` 設定済みの Perl エンコード層に委ねる。`dp` は引数の型に応じてリファレンス化し Data::Printer の `p` に渡す。

**Tech Stack:** Perl 5.38.5、Data::Printer（新規依存）、Test::More（既存テストフレームワーク）

---

## ファイル構成

| ファイル | 変更種別 | 内容 |
|---|---|---|
| `cpanfile` | 新規作成 | `requires 'Data::Printer'` |
| `src/CommonIO.pm` | 修正 | `_print_console_line` 削除、`dp` 追加、`use Data::Printer` 追加 |
| `test/commonio.t` | 修正 | `dp` テスト追加、`dp` を import リストに追加 |

---

## Task 1: cpanfile を作成して Data::Printer をインストールする

**Files:**
- Create: `cpanfile`

- [ ] **Step 1: cpanfile を作成する**

```
requires 'Data::Printer';
```

ファイルパス: `cpanfile`（プロジェクトルート）

- [ ] **Step 2: Data::Printer をインストールする**

```bash
cpanm Data::Printer
```

期待出力：`Successfully installed Data-Printer-X.XX`

- [ ] **Step 3: インストールを確認する**

```bash
perl -MData::Printer -e 'print "ok\n"'
```

期待出力：`ok`

- [ ] **Step 4: Data::Printer の escape_chars オプションを確認する**

```bash
perl -MData::Printer -e '
use Data::Printer escape_chars => "none";
my $s = "日本語";
p($s);
'
```

期待出力：`"日本語"` が `\x{...}` にエスケープされず生の文字で表示される。もし表示が壊れる場合は Step 5 の代替案を使う。

- [ ] **Step 5: コミットする**

```bash
git add cpanfile
git commit -m "chore: add cpanfile with Data::Printer dependency"
```

---

## Task 2: `log` を修正して `_print_console_line` を廃止する

**Files:**
- Modify: `src/CommonIO.pm`

- [ ] **Step 1: 既存テストがパスすることを確認する（ベースライン）**

```bash
LOGDIR=/tmp/spool/commonio-test prove -lr test/
```

期待出力：全テスト PASS。

- [ ] **Step 2: `_print_console_line` サブルーチンを削除し、`log` 内の呼び出しを置き換える**

削除するコード（[src/CommonIO.pm:159-169](src/CommonIO.pm#L159)）：

```perl
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
```

`log` 内の該当行（[src/CommonIO.pm:178](src/CommonIO.pm#L178)）：

```perl
_print_console_line($line);
```

置き換え後：

```perl
print STDERR $line;
```

- [ ] **Step 3: `Encode` の `encode` が `log` から除かれたか確認する**

`log` サブルーチン内に `encode(` の呼び出しが残っていないことを確認する（ファイル書き込み部分の `encode` は残す）。

修正後の `log` サブルーチン全体（[src/CommonIO.pm:171](src/CommonIO.pm#L171)）：

```perl
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
```

- [ ] **Step 4: テストを実行して既存テストがパスすることを確認する**

```bash
LOGDIR=/tmp/spool/commonio-test prove -lr test/
```

期待出力：全テスト PASS。Wide character 警告が STDERR に出る場合があるが、テスト失敗ではない。

- [ ] **Step 5: コミットする**

```bash
git add src/CommonIO.pm
git commit -m "fix: remove _print_console_line, inline print STDERR in log"
```

---

## Task 3: `dp` のテストを先に書く（TDD：失敗を確認）

**Files:**
- Modify: `test/commonio.t`

- [ ] **Step 1: `dp` を import リストに追加する**

`test/commonio.t` の先頭 import 部分を修正する（[test/commonio.t:10](test/commonio.t#L10)）：

```perl
use CommonIO qw(
    append_file at dying dp dumpU8 log out_file read_do read_file
    run_in_fork setup_console write_do write_file
);
```

- [ ] **Step 2: `dp` のテストをファイル末尾（`done_testing()` の直前）に追加する**

```perl
subtest 'dp does not die with various inputs' => sub {
    open my $saved_err, '>&', \*STDERR or die "Cannot dup STDERR: $!";
    open STDERR, '>', '/dev/null' or die "Cannot open /dev/null: $!";

    ok eval { dp(); 1 },                 'dp() - no args';
    ok eval { dp('hello'); 1 },          'dp(scalar string)';
    ok eval { dp(42); 1 },               'dp(scalar number)';
    ok eval { dp([1, 2, 3]); 1 },        'dp(arrayref)';
    ok eval { dp({ a => 1 }); 1 },       'dp(hashref)';
    ok eval { dp(1, 2, 3); 1 },          'dp(multiple args - list)';
    ok eval { dp('日本語'); 1 },         'dp(kanji scalar)';
    ok eval { dp(['日本語', '漢字']); 1 }, 'dp(arrayref with kanji)';

    open STDERR, '>&', $saved_err or die "Cannot restore STDERR: $!";
};
```

- [ ] **Step 3: テストを実行して失敗することを確認する**

```bash
LOGDIR=/tmp/spool/commonio-test prove -lr test/
```

期待出力：`dp` が未定義のため `Undefined subroutine &CommonIO::dp` エラーでテスト失敗。

---

## Task 4: `dp` を実装してテストをパスさせる

**Files:**
- Modify: `src/CommonIO.pm`

- [ ] **Step 1: `use Data::Printer` を追加する**

`src/CommonIO.pm` の `use` ブロックに追加する（既存の `use Data::Dumper;` の直後あたり）：

```perl
use Data::Printer escape_chars => 'none';
```

- [ ] **Step 2: `dp` を `@EXPORT_OK` に追加する**

```perl
our @EXPORT_OK = qw(
    append_file
    at
    dp
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

- [ ] **Step 3: `dp` サブルーチンを実装する**

`dumpU8` サブルーチンの直後に追加する（[src/CommonIO.pm:383](src/CommonIO.pm#L383)）：

```perl
sub dp {
    my @args = @_;
    return unless @args;
    if (@args == 1 && ref $args[0]) {
        p($args[0]);
    } else {
        p(\@args);
    }
    return;
}
```

- [ ] **Step 4: テストを実行してパスすることを確認する**

```bash
LOGDIR=/tmp/spool/commonio-test prove -lr test/
```

期待出力：全テスト PASS。

- [ ] **Step 5: `escape_chars => 'none'` の動作を手動確認する（任意）**

```bash
perl -Isrc -e '
use CommonIO qw(setup_console dp);
setup_console("UTF-8");
dp("日本語テスト");
dp([1, "漢字", { key => "値" }]);
'
```

期待出力：漢字が `\x{...}` にエスケープされず、生の文字で STDERR に出力される。

- [ ] **Step 6: コミットする**

```bash
git add src/CommonIO.pm test/commonio.t
git commit -m "feat: add dp API wrapping Data::Printer with Unicode support"
```

---

## 自己レビューチェックリスト（実装者向け）

- [ ] `_print_console_line` が `src/CommonIO.pm` から完全に削除されている
- [ ] `log` が `print STDERR $line;` を使っている
- [ ] `use Data::Printer escape_chars => 'none';` が追加されている
- [ ] `dp` が `@EXPORT_OK` に含まれている
- [ ] `dp` の引数ロジック：0個→return、1個リファレンス→そのまま、それ以外→`\@args`
- [ ] `cpanfile` に `requires 'Data::Printer';` がある
- [ ] 全テスト PASS
