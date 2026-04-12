# CommonIO spec・テスト・test-spec 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `src/CommonIO.pm` の encoding 制限を修正し、`docs/spec.md`（利用者向け詳細リファレンス）・`test/commonio.t`（網羅的テスト）・`docs/test-spec.md`（テスト仕様書）を完成させる。

**Architecture:** アプローチC（並行設計）— `docs/spec.md` の各 API セクションを書いたら対応するテストも追加する。最後にテスト仕様書をまとめる。実装修正（Task 1）を先に行い、以降のタスクは spec + test の追加のみとする。

**Tech Stack:** Perl 5, Test::More, prove, Encode, Data::Dumper, POSIX

---

## ファイル構成

| ファイル | 操作 | 内容 |
|---|---|---|
| `src/CommonIO.pm` | 修正 | `_file_encoding_name` 追加、encoding 制限 |
| `docs/spec.md` | 更新 | 利用者向け詳細リファレンス |
| `test/commonio.t` | 更新 | 網羅的テスト追加 |
| `docs/test-spec.md` | 更新 | テスト仕様書 |

テスト実行コマンド（全タスク共通）:
```
PERL5LIB=src:lib prove test/commonio.t
```

---

## Task 1: CommonIO.pm の encoding 制限修正

**Files:**
- Modify: `src/CommonIO.pm`
- Test: `test/commonio.t`

### 背景

現在の `_encoding_name` は任意のエンコーディングを受け付ける。
`write_file` / `append_file` / `read_file` は `UTF-8` / `CP932` のみ許可するよう制限する。
`setLogFile` / `log` はログファイルを UTF-8 固定にする。
`write_do` は `$path` にハッシュが渡されても encoding を無視して UTF-8 固定にする。

- [ ] **Step 1: テストを書く（失敗確認用）**

`test/commonio.t` の `use CommonIO` 行を以下に更新（全 API をインポート）:

```perl
use CommonIO qw(
    append_file dying dumpU8 log read_do read_file
    run_in_fork setLogFile setup_console write_do write_file
);
```

ファイル末尾の `done_testing();` の直前に以下を追加:

```perl
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
```

- [ ] **Step 2: テストを実行して失敗を確認**

```
PERL5LIB=src:lib prove test/commonio.t
```

期待: `write_file rejects unsupported encoding` と `read_file rejects unsupported encoding` が FAIL（現在は EUC-JP でも通る）

- [ ] **Step 3: `_file_encoding_name` を `src/CommonIO.pm` に追加**

`_encoding_name` 関数のすぐ下（127行目付近）に以下を挿入:

```perl
sub _file_encoding_name {
    my ($encoding) = @_;
    $encoding = 'UTF-8' unless defined $encoding && length $encoding;
    my $key = uc $encoding;
    $key =~ s/[^A-Z0-9]//g;
    return 'UTF-8' if $key eq 'UTF8';
    return 'CP932' if $key eq 'CP932';
    CommonIO::dying("Unsupported file encoding: $encoding (use UTF-8 or CP932)");
}
```

- [ ] **Step 4: `write_file` / `append_file` / `read_file` で `_file_encoding_name` を使う**

`write_file` 内（238行目付近）:
```perl
# 変更前
my $encoding = _encoding_name($spec->{encoding});
# 変更後
my $encoding = _file_encoding_name($spec->{encoding});
```

`append_file` 内（247行目付近）:
```perl
# 変更前
my $encoding = _encoding_name($spec->{encoding});
# 変更後
my $encoding = _file_encoding_name($spec->{encoding});
```

`read_file` 内（256行目付近）:
```perl
# 変更前
my $encoding = _encoding_name($spec->{encoding});
# 変更後
my $encoding = _file_encoding_name($spec->{encoding});
```

- [ ] **Step 5: `setLogFile` でログを UTF-8 固定にする**

`setLogFile` 内（73行目付近）の `$LOG_TARGET = $spec;` の直前に追加:

```perl
$spec->{encoding} = 'UTF-8';
```

完成後の `setLogFile`:
```perl
sub setLogFile {
    my ($path) = @_;
    if (!defined $path) {
        $LOG_TARGET = undef;
        return;
    }

    my $spec = _parse_path($path);
    $spec->{eol}      = 'lf'    unless defined $spec->{eol}      && length $spec->{eol};
    $spec->{encoding} = 'UTF-8';
    $LOG_TARGET = $spec;
    return $LOG_TARGET->{path};
}
```

- [ ] **Step 6: `write_do` で encoding を無視して UTF-8 固定にする**

`write_do`（288行目付近）を以下に変更:

```perl
sub write_do {
    my ($path, $var) = @_;
    my $spec = _parse_path($path);
    my $dump = dumpU8($var, indent => 1);
    my $text = "use utf8;\n\n" . $dump;
    write_file($spec->{path}, $text);
    return;
}
```

- [ ] **Step 7: テストを実行してすべて通ることを確認**

```
PERL5LIB=src:lib prove test/commonio.t
```

期待: `All tests successful`

- [ ] **Step 8: コミット**

```bash
git add src/CommonIO.pm test/commonio.t
git commit -m "fix: limit file encoding to UTF-8/CP932, fix log and write_do to UTF-8 fixed"
```

---

## Task 2: spec.md の write_file / append_file セクション + テスト

**Files:**
- Modify: `docs/spec.md`
- Modify: `test/commonio.t`

- [ ] **Step 1: `docs/spec.md` に write_file / append_file セクションを書く**

`docs/spec.md` を以下の内容で上書き（この時点では write_file / append_file セクションのみ）:

```markdown
# CommonIO

[日本語] CommonIO を使うと Perl で文字コードや改行コードを意識せずにファイル入出力ができます。

## インストール・使い方

```perl
use lib 'src';
use CommonIO qw(write_file append_file read_file write_do read_do
                log setLogFile dying setup_console dumpU8 run_in_fork);
```

## 用語

| 用語 | 意味 |
|---|---|
| `path` | 入出力先の指定。文字列またはハッシュ |
| `encoding` | 文字エンコーディング。既定値 `UTF-8`、`CP932` のみ指定可 |
| `eol` | 改行コードの扱い |
| `text` | Perl の文字列（内部文字列） |
| `lines` | 行配列（`text` を改行で分割したもの） |

## path 指定

`path` は文字列またはハッシュで渡します。

**文字列の場合:**
```perl
write_file('/path/to/file.txt', $text);
```
encoding は UTF-8、eol は `lf`（書き込み）/ `preserve`（読み込み）が既定値です。

**ハッシュの場合:**
```perl
write_file({ path => '/path/to/file.txt', encoding => 'CP932', eol => 'crlf' }, $text);
```

| キー | 必須 | 既定値 | 説明 |
|---|---|---|---|
| `path` | 必須 | — | ファイルパス |
| `encoding` | 任意 | `UTF-8` | `UTF-8` または `CP932` のみ。それ以外は例外 |
| `eol` | 任意 | 書き込み: `lf` / 読み込み: `preserve` | 改行コードの扱い |

## 固定方針

| API | encoding |
|---|---|
| `setLogFile` / `log` | UTF-8 固定（変更不可） |
| `write_do` / `read_do` | UTF-8 固定（変更不可） |

## eol の選択肢

| 値 | 書き込み時 | 読み込み時 |
|---|---|---|
| `lf` | `\r\n` / `\r` を `\n` へ変換して書く | `\r\n` / `\r` を `\n` へ正規化 |
| `crlf` | `\n` を `\r\n` へ変換して書く | — |
| `preserve` | 改行をそのまま書く | 改行をそのまま返す |

---

## API リファレンス

### write_file

**シグネチャ:**
```
write_file($path, $text)
write_file($path, $lines)
```

**説明:** ファイルを新規作成または上書きします。

**引数:**

| 引数 | 型 | 説明 |
|---|---|---|
| `$path` | 文字列またはハッシュ | 書き込み先。[path 指定](#path-指定)を参照 |
| `$text` | 文字列 | 書き込む内容。eol に従って改行変換される |
| `$lines` | 配列 ref | 各要素を eol で連結して書き込む |

**戻り値:** なし

**使用例:**
```perl
# 文字列を UTF-8 LF で書き込む
write_file('/tmp/out.txt', "Hello\nWorld");

# CRLF・CP932 で書き込む
write_file({ path => '/tmp/out.txt', encoding => 'CP932', eol => 'crlf' }, "こんにちは");

# 行配列で書き込む
write_file('/tmp/out.txt', ['line1', 'line2', 'line3']);
```

**エラー:**
- `$path` が存在しないディレクトリを指す場合は例外
- `encoding` が `UTF-8` / `CP932` 以外の場合は例外: `Unsupported file encoding`

---

### append_file

**シグネチャ:**
```
append_file($path, $text)
append_file($path, $lines)
```

**説明:** ファイルの末尾に追記します。変換規則は `write_file` と同じです。

**引数:** `write_file` と同じ

**戻り値:** なし

**使用例:**
```perl
append_file('/tmp/log.txt', "追加行\n");
```

**エラー:** `write_file` と同じ

---
```

- [ ] **Step 2: write_file / append_file のテストを `test/commonio.t` に追加**

`done_testing();` の直前（encoding テストの後）に以下を追加:

```perl
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
    # CP932 の「テスト」は UTF-8 より短いバイト列になる
    ok length($bytes) < length(Encode::encode('UTF-8', 'テスト')), 'CP932 bytes differ from UTF-8';
};

subtest 'append_file appends to existing file' => sub {
    my $f = "$TMP/append.txt";
    write_file($f, "first\n");
    append_file($f, "second\n");
    my $text = read_file($f);
    like $text, qr/first\nsecond/, 'both lines present';
};
```

`use CommonIO` の行の下に以下を追加:

```perl
use Encode ();
```

- [ ] **Step 3: テストを実行してすべて通ることを確認**

```
PERL5LIB=src:lib prove test/commonio.t
```

期待: `All tests successful`

- [ ] **Step 4: コミット**

```bash
git add docs/spec.md test/commonio.t
git commit -m "docs+test: add write_file/append_file spec section and tests"
```

---

## Task 3: spec.md の read_file セクション + テスト

**Files:**
- Modify: `docs/spec.md`
- Modify: `test/commonio.t`

- [ ] **Step 1: `docs/spec.md` に read_file セクションを追記**

`append_file` セクションの `---` の直後に以下を追加:

```markdown
### read_file

**シグネチャ:**
```
$text  = read_file($path)           # スカラコンテキスト
@lines = read_file($path)           # リストコンテキスト
```

**説明:** ファイルを読み込んで Perl の内部文字列として返します。

**引数:**

| 引数 | 型 | 説明 |
|---|---|---|
| `$path` | 文字列またはハッシュ | 読み込み元。[path 指定](#path-指定)を参照 |

**戻り値:**
- スカラコンテキスト: ファイル全体の文字列
- リストコンテキスト: 改行で分割した行配列

**eol の挙動（読み込み時）:**

| eol | 挙動 |
|---|---|
| `preserve`（既定） | 改行をそのまま返す |
| `lf` | `\r\n` / `\r` を `\n` に正規化してから返す |

**使用例:**
```perl
# テキスト全体を読む
my $text = read_file('/tmp/data.txt');

# 行配列として読む
my @lines = read_file('/tmp/data.txt');

# CRLF を LF に正規化して読む
my $text = read_file({ path => '/tmp/win.txt', eol => 'lf' });

# CP932 ファイルを読む
my $text = read_file({ path => '/tmp/sjis.txt', encoding => 'CP932' });
```

**エラー:**
- ファイルが存在しない場合は例外: `Cannot read`
- ファイルが空の場合は例外: `file not found or empty`
- `encoding` が `UTF-8` / `CP932` 以外の場合は例外: `Unsupported file encoding`

---
```

- [ ] **Step 2: read_file のテストを `test/commonio.t` に追加**

```perl
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
```

- [ ] **Step 3: テストを実行してすべて通ることを確認**

```
PERL5LIB=src:lib prove test/commonio.t
```

期待: `All tests successful`

- [ ] **Step 4: コミット**

```bash
git add docs/spec.md test/commonio.t
git commit -m "docs+test: add read_file spec section and tests"
```

---

## Task 4: spec.md の write_do / read_do セクション + テスト

**Files:**
- Modify: `docs/spec.md`
- Modify: `test/commonio.t`

- [ ] **Step 1: `docs/spec.md` に write_do / read_do セクションを追記**

`read_file` セクションの `---` の直後に以下を追加:

```markdown
### write_do

**シグネチャ:**
```
write_do($path, $var)
```

**説明:** Perl 変数を `do` で読める形式（`.do` ファイル）に保存します。エンコーディングは UTF-8 固定です。

**引数:**

| 引数 | 型 | 説明 |
|---|---|---|
| `$path` | 文字列またはハッシュ | 保存先ファイルパス（encoding / eol は無視） |
| `$var` | 任意 | 保存する Perl 変数（ハッシュ ref、配列 ref など） |

**戻り値:** なし

**使用例:**
```perl
write_do('/tmp/config.do', { key => 'value', name => '日本語' });
```

**エラー:**
- 書き込み先が存在しない場合は例外

---

### read_do

**シグネチャ:**
```
$var = read_do($path)
```

**説明:** `write_do` で保存した `.do` ファイルを評価して Perl 変数として返します。

**引数:**

| 引数 | 型 | 説明 |
|---|---|---|
| `$path` | 文字列またはハッシュ | 読み込み元ファイルパス |

**戻り値:** 保存された Perl 変数

**使用例:**
```perl
my $config = read_do('/tmp/config.do');
```

**エラー:**
- ファイルが存在しない、または評価が未定義の場合は例外: `file not found or empty`
- 構文エラーがある場合は例外: `Failed to read`

---
```

- [ ] **Step 2: write_do / read_do のテストを追加**

```perl
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
    # encoding キーを渡しても UTF-8 固定になること
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
```

- [ ] **Step 3: テストを実行してすべて通ることを確認**

```
PERL5LIB=src:lib prove test/commonio.t
```

期待: `All tests successful`

- [ ] **Step 4: コミット**

```bash
git add docs/spec.md test/commonio.t
git commit -m "docs+test: add write_do/read_do spec section and tests"
```

---

## Task 5: spec.md の dumpU8 セクション + テスト

**Files:**
- Modify: `docs/spec.md`
- Modify: `test/commonio.t`

- [ ] **Step 1: `docs/spec.md` に dumpU8 セクションを追記**

`read_do` セクションの `---` の直後に以下を追加:

```markdown
### dumpU8

**シグネチャ:**
```
$dump = dumpU8($var)
$dump = dumpU8($var, indent => $n)
```

**説明:** Perl 変数を `Data::Dumper` 形式の文字列に変換します。Unicode 文字が `\x{...}` エスケープされず、そのまま出力されます。

**引数:**

| 引数 | 型 | 既定値 | 説明 |
|---|---|---|---|
| `$var` | 任意 | — | ダンプする変数 |
| `indent` | 整数 | `1` | `Data::Dumper` の Indent 値（0: 一行、1: 整形） |

**戻り値:** Unicode 文字をそのまま含んだダンプ文字列

**使用例:**
```perl
my $dump = dumpU8({ name => '日本語' });
# => "{\n  'name' => '日本語'\n}\n"

my $one = dumpU8(['a', 'b'], indent => 0);
# => "['a', 'b']"
```

**エラー:** なし

---
```

- [ ] **Step 2: dumpU8 のテストを追加**

```perl
subtest 'dumpU8 preserves Unicode characters' => sub {
    my $dump = dumpU8({ word => '漢字' });
    like $dump, qr/漢字/, 'Unicode not escaped';
    unlike $dump, qr/\\x\{/, 'no \\x{} escapes';
};

subtest 'dumpU8 with indent=>0 produces one line' => sub {
    my $dump = dumpU8(['x', 'y'], indent => 0);
    unlike $dump, qr/\n/, 'no newline with indent 0';
};
```

- [ ] **Step 3: テストを実行してすべて通ることを確認**

```
PERL5LIB=src:lib prove test/commonio.t
```

期待: `All tests successful`

- [ ] **Step 4: コミット**

```bash
git add docs/spec.md test/commonio.t
git commit -m "docs+test: add dumpU8 spec section and tests"
```

---

## Task 6: spec.md の setup_console セクション + テスト

**Files:**
- Modify: `docs/spec.md`
- Modify: `test/commonio.t`

- [ ] **Step 1: `docs/spec.md` に setup_console セクションを追記**

`dumpU8` セクションの `---` の直後に以下を追加:

```markdown
### setup_console

**シグネチャ:**
```
$console_encoding = setup_console()
$console_encoding = setup_console($encoding)
```

**説明:** `STDOUT` と `STDERR` のエンコーディングを設定します。以降の `print` / `warn` でバイト列への変換が自動で行われます。

**引数:**

| 引数 | 型 | 既定値 | 説明 |
|---|---|---|---|
| `$encoding` | 文字列 | ロケールから自動検出 | `UTF-8` または `CP932` 系 |

受け付ける値の例: `UTF-8`、`utf-8`、`CP932`、`cp932`、`Shift_JIS`、`SJIS`

**戻り値:** 設定したエンコーディング名（`'UTF-8'` または `'CP932'`）

**使用例:**
```perl
my $enc = setup_console('UTF-8');
print "日本語が正しく出力されます\n";
```

**エラー:**
- `UTF-8` / `CP932` 系以外を渡した場合は例外: `Unsupported console encoding`

---
```

- [ ] **Step 2: setup_console のテストを追加**

```perl
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
```

- [ ] **Step 3: テストを実行してすべて通ることを確認**

```
PERL5LIB=src:lib prove test/commonio.t
```

期待: `All tests successful`

- [ ] **Step 4: コミット**

```bash
git add docs/spec.md test/commonio.t
git commit -m "docs+test: add setup_console spec section and tests"
```

---

## Task 7: spec.md の log / setLogFile / dying セクション + テスト補強

**Files:**
- Modify: `docs/spec.md`
- Modify: `test/commonio.t`

- [ ] **Step 1: `docs/spec.md` に log / setLogFile / dying セクションを追記**

`setup_console` セクションの `---` の直後に以下を追加:

```markdown
### log

**シグネチャ:**
```
$line = log($level, $msg)
```

**説明:** ログを STDERR へ出力します。`setLogFile` でファイルが設定されていれば同じ内容をファイルにも追記します。ログファイルのエンコーディングは UTF-8 固定です。

**引数:**

| 引数 | 型 | 説明 |
|---|---|---|
| `$level` | 文字列 | `debug` / `info` / `warn` / `warning` / `error` |
| `$msg` | 文字列 | ログメッセージ |

**戻り値:** `[LEVEL] message\n` 形式の文字列

**使用例:**
```perl
my $line = log('info', '処理開始');
# => "[INFO] 処理開始\n"

log('error', '致命的エラー');
```

**エラー:**
- 不正な `$level` を渡した場合は例外: `Unsupported log level`

---

### setLogFile

**シグネチャ:**
```
$path = setLogFile($path)
         setLogFile(undef)
```

**説明:** ログの保存先ファイルを設定します。`undef` を渡すとファイル保存を無効にします。エンコーディングは UTF-8、改行は LF 固定です。

**引数:**

| 引数 | 型 | 説明 |
|---|---|---|
| `$path` | 文字列またはハッシュ | ログファイルパス（`encoding` キーは無視され UTF-8 固定） |
| `undef` | — | ファイル保存を無効にする |

**戻り値:** 設定したパス文字列。`undef` 指定時は戻り値なし

**エラー:** なし

---

### dying

**シグネチャ:**
```
dying($msg)    # 戻らない
```

**説明:** `error` レベルでログを残してからトレースバック付きで例外を投げます。`die` の代わりに使うことで、ログと例外を同時に処理できます。

**引数:**

| 引数 | 型 | 説明 |
|---|---|---|
| `$msg` | 文字列 | エラーメッセージ |

**戻り値:** 戻りません

**使用例:**
```perl
open my $fh, '<', $file or dying("Cannot open $file: $!");
```

**エラー:** 常に例外を投げます

---
```

- [ ] **Step 2: log / setLogFile の UTF-8 固定テストを追加**

```perl
subtest 'log file is always UTF-8 regardless of setLogFile encoding spec' => sub {
    my $f = "$TMP/log_utf8_fixed.log";
    setLogFile({ path => $f, encoding => 'CP932' });  # encoding 無視される
    log('info', '固定UTF8');
    setLogFile(undef);
    open my $fh, '<:raw', $f or die;
    local $/;
    my $bytes = <$fh>;
    close $fh;
    my $text = Encode::decode('UTF-8', $bytes);
    like $text, qr/固定UTF8/, 'log file is UTF-8';
};
```

- [ ] **Step 3: テストを実行してすべて通ることを確認**

```
PERL5LIB=src:lib prove test/commonio.t
```

期待: `All tests successful`

- [ ] **Step 4: コミット**

```bash
git add docs/spec.md test/commonio.t
git commit -m "docs+test: add log/setLogFile/dying spec sections and UTF-8 fixed test"
```

---

## Task 8: spec.md の run_in_fork セクション + テスト

**Files:**
- Modify: `docs/spec.md`
- Modify: `test/commonio.t`

- [ ] **Step 1: `docs/spec.md` に run_in_fork セクションを追記**

`dying` セクションの `---` の直後に以下を追加:

```markdown
### run_in_fork

**シグネチャ:**
```
run_in_fork($code)
```

**説明:** `$code` を子プロセスで実行します。子プロセスが正常終了したら親へ戻ります。子プロセスで例外が発生した場合、`error` ログを残してから親でも例外を投げます。

**引数:**

| 引数 | 型 | 説明 |
|---|---|---|
| `$code` | コードリファレンス | 子プロセスで実行する処理 |

**戻り値:** なし

**使用例:**
```perl
run_in_fork(sub {
    write_file('/tmp/result.txt', '子プロセス完了');
});
```

**エラー:**
- `fork` に失敗した場合は例外: `fork failed`
- 子プロセスで例外が発生した場合、親で例外: `confirm failed`

---
```

- [ ] **Step 2: run_in_fork のテストを追加**

```perl
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
```

- [ ] **Step 3: テストを実行してすべて通ることを確認**

```
PERL5LIB=src:lib prove test/commonio.t
```

期待: `All tests successful`

- [ ] **Step 4: コミット**

```bash
git add docs/spec.md test/commonio.t
git commit -m "docs+test: add run_in_fork spec section and tests"
```

---

## Task 9: spec.md を完成させる

**Files:**
- Modify: `docs/spec.md`

- [ ] **Step 1: spec.md の冒頭共通セクションを整える**

`docs/spec.md` の最初の `---` の前に、以下のセクションが揃っていることを確認し、不足があれば追記する（Task 2 で書いた内容が基盤）:

- `# CommonIO` — 一行説明
- `## インストール・使い方` — use 宣言の例
- `## 用語` — 用語表
- `## path 指定` — 文字列・ハッシュ・各キーの説明
- `## 固定方針` — log/do 系の UTF-8 固定
- `## eol の選択肢` — lf / crlf / preserve の表

- [ ] **Step 2: 全 API セクションが揃っていることを確認**

以下が全て存在することを目視確認:
- `write_file`, `append_file`, `read_file`
- `write_do`, `read_do`
- `log`, `setLogFile`, `dying`
- `setup_console`, `dumpU8`, `run_in_fork`

- [ ] **Step 3: コミット**

```bash
git add docs/spec.md
git commit -m "docs: finalize spec.md common sections"
```

---

## Task 10: test-spec.md を書く

**Files:**
- Modify: `docs/test-spec.md`

- [ ] **Step 1: `docs/test-spec.md` を以下の内容で上書きする**

```markdown
# CommonIO テスト仕様書

## テスト方針

- TDD（テスト先行）で実装と仕様を対応させる
- 正常系・異常系・境界条件を網羅する
- エンコーディング変換は実バイト列で検証する
- 一時ファイルは `/tmp/spool/commonio-test/` に作成し、テスト前後に削除する

## テスト環境・前提条件

| 項目 | 内容 |
|---|---|
| テストフレームワーク | `Test::More` |
| 実行コマンド | `PERL5LIB=src:lib prove test/commonio.t` |
| 一時ディレクトリ | `/tmp/spool/commonio-test/` |
| PERL5LIB | `src:lib` |

## テストケース一覧

### ログ系（log / setLogFile / dying）

| テスト名 | 目的 | 確認内容 |
|---|---|---|
| log writes UTF-8 text to log file | ログが UTF-8 でファイルに書かれること | `like $text, qr/[DEBUG] 漢字ログ/` |
| dying logs error and throws | dying が ERROR ログを残して例外を投げること | `like $@, qr/重大エラー/`, ログファイルに ERROR が残ること |
| setLogFile undef disables file logging | undef でファイル保存が無効になること | ファイルが作られないこと |
| log file is always UTF-8 regardless of setLogFile encoding spec | ログファイルは encoding 指定を無視して UTF-8 固定 | バイト列を UTF-8 デコードして内容が一致すること |

### ファイルIO系（write_file / append_file / read_file）

| テスト名 | 目的 | 確認内容 |
|---|---|---|
| write_file rejects unsupported encoding | EUC-JP 等を拒否すること | `like $@, qr/Unsupported file encoding/` |
| read_file rejects unsupported encoding | EUC-JP 等を拒否すること | `like $@, qr/Unsupported file encoding/` |
| write_file writes UTF-8 text | UTF-8 で書き込み・読み戻しが一致すること | `like $text, qr/日本語テキスト/` |
| write_file writes CRLF | eol=>crlf でバイト列に `\r\n` が含まれること | 生バイト列で確認 |
| write_file preserves eol | eol=>preserve で改行が変換されないこと | `\r\n` と `\n` が混在したまま保存されること |
| write_file writes array lines | 配列 ref が LF で連結されること | `like $text, qr/alpha\nbeta\ngamma/` |
| write_file writes CP932 | CP932 バイト列になること | バイト長が UTF-8 より短いこと |
| append_file appends to existing file | 末尾に追記されること | `like $text, qr/first\nsecond/` |
| read_file returns scalar text | スカラコンテキストでテキスト全体が返ること | `is $text, "hello world"` |
| read_file returns line array | リストコンテキストで行配列が返ること | `is scalar @lines, 3` |
| read_file normalizes CRLF to LF with eol=>lf | `\r\n` / `\r` が `\n` に正規化されること | `unlike $text, qr/\r/` |
| read_file preserves CRLF with eol=>preserve | CRLF がそのまま返ること | `like $text, qr/\r\n/` |
| read_file throws on missing file | 存在しないファイルで例外が発生すること | `like $@, qr/Cannot read/` |
| read_file reads CP932 file | CP932 ファイルを正しく読めること | `is $text, 'テスト'` |
| read_file with hash path spec | ハッシュ path 指定が動くこと | `like $text, qr/ハッシュpath/` |

### .doファイル系（write_do / read_do）

| テスト名 | 目的 | 確認内容 |
|---|---|---|
| write_do / read_do round-trip hash | ハッシュ ref を保存・復元できること | `is $got->{key}, 'val'` |
| write_do / read_do round-trip array | 配列 ref を保存・復元できること | `is $got->[0], 'a'` |
| write_do / read_do preserves Unicode | 日本語が化けないこと | `is $got->{msg}, '日本語テスト'` |
| write_do UTF-8 fixed regardless of path encoding spec | encoding 指定を無視して UTF-8 で保存すること | ファイル先頭に `use utf8` が含まれること |
| read_do throws on missing file | 存在しないファイルで例外が発生すること | `like $@, qr/file not found or empty\|Failed to read/` |

### ダンプ系（dumpU8）

| テスト名 | 目的 | 確認内容 |
|---|---|---|
| dumpU8 preserves Unicode characters | `\x{...}` にエスケープされず Unicode のまま出力されること | `like $dump, qr/漢字/`, `unlike $dump, qr/\\x{/` |
| dumpU8 with indent=>0 produces one line | indent=>0 で一行になること | `unlike $dump, qr/\n/` |

### コンソール系（setup_console）

| テスト名 | 目的 | 確認内容 |
|---|---|---|
| setup_console returns UTF-8 | UTF-8 を渡すと UTF-8 が返ること | `is $enc, 'UTF-8'` |
| setup_console returns CP932 | CP932 を渡すと CP932 が返ること | `is $enc, 'CP932'` |
| setup_console with no arg does not throw | 引数なしで例外が出ないこと | `ok !$@` |
| setup_console rejects unsupported encoding | EUC-JP 等で例外が発生すること | `like $@, qr/Unsupported console encoding/` |

### フォーク系（run_in_fork）

| テスト名 | 目的 | 確認内容 |
|---|---|---|
| run_in_fork executes code in child | 子プロセスでファイルが作られること | `ok -f $f`, `like $text, qr/子プロセス実行/` |
| run_in_fork throws when child throws | 子で例外が起きたとき親で例外が発生すること | `like $@, qr/confirm failed/` |
```

- [ ] **Step 2: テストを実行して全て通ることを最終確認**

```
PERL5LIB=src:lib prove test/commonio.t
```

期待: `All tests successful`

- [ ] **Step 3: コミット**

```bash
git add docs/test-spec.md
git commit -m "docs: write test-spec.md"
```

---

## Task 11: 最終確認とプッシュ準備

**Files:** なし（確認のみ）

- [ ] **Step 1: appset を実行して環境確認**

```
bash $HOME/.claude/skills/appset/appset.sh
```

期待: `[NG]` なし

- [ ] **Step 2: 全テストを実行**

```
PERL5LIB=src:lib prove test/commonio.t
```

期待: `All tests successful`

- [ ] **Step 3: git log で全コミットを確認**

```
git log --oneline
```

- [ ] **Step 4: ユーザーに push 確認を求める**

push は必ずユーザーの許可を得てから実行する。
