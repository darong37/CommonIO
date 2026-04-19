# CommonIO 全 To Do 対応 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** design-concept.md の残 To Do を全て実装し、CommonIO を最終仕様に揃える。

**Architecture:** `src/CommonIO.pm` と `test/commonio.t` の2ファイルのみを変更する。変更は依存順（`_setup_console` → `out_file` mode → `encoding=>raw` → `write_file`/`append_file` 廃止 → `dec` 改善 → `dp` 修正）に進め、タスクごとにコミットする。

**Tech Stack:** Perl 5.38.5, Test::More, Encode, Encode::Guess, I18N::Langinfo, Data::Printer

---

## ファイル構成

| ファイル | 役割 |
|---|---|
| `src/CommonIO.pm` | 実装本体（全変更対象） |
| `test/commonio.t` | テストスイート（テスト追加・削除・修正） |

---

## Task 1: `_setup_console` 自動実行・内部ルーティン化

**Files:**
- Modify: `src/CommonIO.pm`
- Modify: `test/commonio.t`

- [ ] **Step 1: テストを修正する（import 更新・旧テスト削除・新テスト追加）**

`test/commonio.t` の `use CommonIO` から `setup_console` を削除し、4つの `setup_console` subtest を削除する。代わりに自動実行確認テストを追加する。

`use CommonIO` 行を変更：
```perl
use CommonIO qw(
    append_file at dec dp dying dumpU8 log out_file read_do read_file
    run_in_fork write_do write_file
);
```

削除する subtest（4つ）：
- `'setup_console returns UTF-8'`
- `'setup_console returns CP932'`
- `'setup_console with no arg does not throw'`
- `'setup_console rejects unsupported encoding'`

追加する subtest（`run_in_fork` subtest の前に挿入）：
```perl
subtest '_setup_console auto-runs: STDOUT has encoding layer' => sub {
    my @layers = PerlIO::get_layers(STDOUT);
    ok grep( { $_ eq 'encoding' } @layers ), 'STDOUT has encoding layer';
};

subtest '_setup_console auto-runs: STDERR has encoding layer' => sub {
    my @layers = PerlIO::get_layers(STDERR);
    ok grep( { $_ eq 'encoding' } @layers ), 'STDERR has encoding layer';
};
```

- [ ] **Step 2: テストを実行してレッドを確認する**

```bash
prove -lr test/commonio.t 2>/dev/null
```

期待結果：`_setup_console auto-runs` の2テストが FAIL

- [ ] **Step 3: `setup_console` → `_setup_console` にリネームし、引数を削除する**

`src/CommonIO.pm` の `@EXPORT_OK` から `setup_console` を削除：
```perl
our @EXPORT_OK = qw(
    append_file
    at
    dec
    dp
    dying
    dumpU8
    log
    out_file
    read_do
    read_file
    run_in_fork
    write_do
    write_file
);
```

`setup_console` サブルーティンを以下に置き換え：
```perl
sub _setup_console {
    my $console_encoding = _console_encoding_name();
    binmode STDOUT, ":encoding($console_encoding)"
        or die "Cannot set STDOUT encoding to $console_encoding: $!\n";
    binmode STDERR, ":encoding($console_encoding)"
        or die "Cannot set STDERR encoding to $console_encoding: $!\n";
    return $console_encoding;
}
```

`_console_encoding_name` の呼び出し形式も引数なしに変更（現在は `$encoding` を受け取るが、`_setup_console` からは引数なしで呼ぶ。`_console_encoding_name` 自体はそのまま）。

- [ ] **Step 4: `BEGIN` ブロックを `1;` の直前に追加する**

ファイル末尾の `1;` の直前に追加：
```perl
BEGIN { _setup_console() }

1;
```

- [ ] **Step 5: テストを実行してグリーンを確認する**

```bash
prove -lr test/commonio.t 2>/dev/null
```

期待結果：全テスト PASS

- [ ] **Step 6: コミットする**

```bash
git add src/CommonIO.pm test/commonio.t
git commit -m "feat: auto-run _setup_console via BEGIN block on module load"
```

---

## Task 2: `out_file` mode 引数対応

**Files:**
- Modify: `src/CommonIO.pm`
- Modify: `test/commonio.t`

- [ ] **Step 1: テストを追加する**

`test/commonio.t` の `out_file` subtest 群の後（`dp` subtest の前）に追加：

```perl
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
    eval { out_file({ path => '>', encoding => 'UTF-8' }, 'text') };
    like $@, qr/mode character/i, 'path => > is rejected';

    eval { out_file({ path => '>>' }, 'text') };
    like $@, qr/mode character/i, 'path => >> is rejected';

    eval { out_file({ path => '?' }, 'text') };
    like $@, qr/mode character/i, 'path => ? is rejected';
};
```

- [ ] **Step 2: テストを実行してレッドを確認する**

```bash
prove -lr test/commonio.t 2>/dev/null
```

期待結果：追加した4つの subtest が FAIL（mode 引数未対応）

- [ ] **Step 3: `_encode_and_write` ヘルパーを追加し、`out_file` を書き換える**

`write_file` と `append_file` の定義の間に `_encode_and_write` を追加：
```perl
sub _encode_and_write {
    my ($spec, $text, $mode) = @_;
    my $rendered = _render_write_text($text, $spec->{eol});
    my $enc      = _file_encoding_name($spec->{encoding});
    my $bytes    = encode($enc, $rendered, FB_CROAK);
    _write_bytes($spec->{path}, $bytes, $mode);
    return;
}
```

`out_file` を以下に置き換え：
```perl
sub out_file {
    my ($first, @rest) = @_;

    my ($mode, $path_arg, $text);
    if (defined $first && ($first eq '>' || $first eq '>>' || $first eq '?')) {
        $mode     = $first;
        $path_arg = $rest[0];
        $text     = $rest[1];
    } else {
        $mode     = '?';
        $path_arg = $first;
        $text     = $rest[0];
    }

    my $spec = _parse_path($path_arg, qw(path encoding eol));
    my $key  = $spec->{path};

    CommonIO::dying("path must not be a mode character: $key")
        if $key eq '>' || $key eq '>>' || $key eq '?';

    my $actual_mode;
    if ($mode eq '>') {
        $actual_mode = '>';
    } elsif ($mode eq '>>') {
        $actual_mode = '>>';
    } else {
        $actual_mode = (exists $_out_counts{$key} && $_out_counts{$key} > 0)
            ? '>>' : '>';
    }

    _encode_and_write($spec, $text, $actual_mode);
    $_out_counts{$key}++;
    return;
}
```

- [ ] **Step 4: テストを実行してグリーンを確認する**

```bash
prove -lr test/commonio.t 2>/dev/null
```

期待結果：全テスト PASS

- [ ] **Step 5: コミットする**

```bash
git add src/CommonIO.pm test/commonio.t
git commit -m "feat: add mode argument to out_file and validate path"
```

---

## Task 3: `encoding => raw` 対応

**Files:**
- Modify: `src/CommonIO.pm`
- Modify: `test/commonio.t`

- [ ] **Step 1: テストを追加する**

Task 2 で追加した `out_file` テスト群の後に追加：

```perl
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
```

- [ ] **Step 2: テストを実行してレッドを確認する**

```bash
prove -lr test/commonio.t 2>/dev/null
```

期待結果：追加した3つの subtest が FAIL

- [ ] **Step 3: `_is_raw_encoding` を追加し、`_encode_and_write` と `read_file` を更新する**

`_encode_and_write` の直前に追加：
```perl
sub _is_raw_encoding {
    my ($enc) = @_;
    return defined $enc && lc($enc) eq 'raw';
}
```

`_encode_and_write` を更新：
```perl
sub _encode_and_write {
    my ($spec, $text, $mode) = @_;
    if (_is_raw_encoding($spec->{encoding})) {
        _write_bytes($spec->{path}, $text, $mode);
        return;
    }
    my $rendered = _render_write_text($text, $spec->{eol});
    my $enc      = _file_encoding_name($spec->{encoding});
    my $bytes    = encode($enc, $rendered, FB_CROAK);
    _write_bytes($spec->{path}, $bytes, $mode);
    return;
}
```

`read_file` を更新（`$bytes` を取得した直後に raw 分岐を追加）：
```perl
sub read_file {
    my ($path) = @_;
    my $spec = _parse_path($path, qw(path encoding eol));
    open my $fh, '<:raw', $spec->{path} or CommonIO::dying("Cannot read $spec->{path}: $!");
    local $/;
    my $bytes = <$fh>;
    close $fh or CommonIO::dying("Cannot close $spec->{path}: $!");
    CommonIO::dying("Cannot read $spec->{path}: file not found or empty") unless defined $bytes;

    if (_is_raw_encoding($spec->{encoding})) {
        CommonIO::dying("read_file with encoding=>raw does not support list context")
            if wantarray;
        return $bytes;
    }

    my $text = decode(_file_encoding_name($spec->{encoding}), $bytes, FB_CROAK);
    $text = _normalize_read_eol($text, $spec->{eol});
    return wantarray ? _split_lines($text) : $text;
}
```

- [ ] **Step 4: テストを実行してグリーンを確認する**

```bash
prove -lr test/commonio.t 2>/dev/null
```

期待結果：全テスト PASS

- [ ] **Step 5: コミットする**

```bash
git add src/CommonIO.pm test/commonio.t
git commit -m "feat: add encoding=>raw support to out_file and read_file"
```

---

## Task 4: `write_file` / `append_file` 廃止

**Files:**
- Modify: `src/CommonIO.pm`
- Modify: `test/commonio.t`

- [ ] **Step 1: テストファイルを更新する**

`use CommonIO` の import から `append_file` と `write_file` を削除：
```perl
use CommonIO qw(
    at dec dp dying dumpU8 log out_file read_do read_file
    run_in_fork write_do
);
```

削除する subtest（9つ）：
- `'write_file rejects unsupported encoding'`
- `'read_file rejects unsupported encoding'`（`write_file` 依存、削除後に別途追加）
- `'append_file rejects unsupported encoding'`
- `'write_file writes UTF-8 text'`
- `'write_file writes CRLF'`
- `'write_file preserves eol'`
- `'write_file writes array lines'`
- `'write_file writes CP932'`
- `'append_file appends to existing file'`

`'read_file rejects unsupported encoding'` は削除後、`out_file` 依存で同等テストを追加する：
```perl
subtest 'read_file rejects unsupported encoding' => sub {
    my $f = "$TMP/enc_r.txt";
    out_file('>', $f, 'test');
    eval { read_file({ path => $f, encoding => 'EUC-JP' }) };
    like $@, qr/Unsupported file encoding/i, 'EUC-JP is rejected on read';
};
```

`write_file` を fixture として使っている各 subtest 内を以下ルールで置き換える：
- `write_file($f, $text)` → `out_file('>', $f, $text)`
- `write_file({ path => $f, encoding => 'CP932' }, $text)` → `out_file('>', { path => $f, encoding => 'CP932' }, $text)`
- `write_file({ path => $f, encoding => 'UTF-8', eol => 'lf' }, $text)` → `out_file('>', { path => $f, encoding => 'UTF-8', eol => 'lf' }, $text)`
- `write_file($f, 'this is not valid perl $$$')` → `out_file('>', $f, 'this is not valid perl $$$')`

**注意:** `'out_file first call overwrites existing file'` は `out_file('>', ...)` で fixture を作ると `$_out_counts` のカウンタが進み、テスト本体の `out_file($f, ...)` が追記になって失敗する。直接 `open` で書く形に変更：

```perl
subtest 'out_file first call overwrites existing file' => sub {
    my $f = "$TMP/out_first.txt";
    open my $fh, '>:utf8', $f or die "Cannot create $f: $!";
    print {$fh} 'initial';
    close $fh;
    out_file($f, 'replaced');
    is read_file($f), 'replaced', 'first call overwrites';
};
```

`'run_in_fork executes code in child'` 内の `write_file` も `out_file('>', ...)` に置き換える。

- [ ] **Step 2: テストを実行してレッドを確認する**

```bash
prove -lr test/commonio.t 2>/dev/null
```

期待結果：`write_file` 削除済みなので import エラーが起きる（まだ実装が残っているので PASS になる可能性もある）。この段階では PASS でも構わない。

- [ ] **Step 3: `write_file` と `append_file` の sub 定義を `src/CommonIO.pm` から削除する**

`@EXPORT_OK` から `append_file` と `write_file` を削除：
```perl
our @EXPORT_OK = qw(
    at
    dec
    dp
    dying
    dumpU8
    log
    out_file
    read_do
    read_file
    run_in_fork
    write_do
);
```

`sub write_file { ... }` と `sub append_file { ... }` の定義を丸ごと削除する。

`write_do` が `write_file` を呼んでいるので `_encode_and_write` を使う形に更新：
```perl
sub write_do {
    my ($path, $var) = @_;
    my $spec = _parse_path($path, qw(path));
    my $dump = dumpU8($var, indent => 1);
    my $text = "use utf8;\n\n" . $dump;
    _encode_and_write({ path => $spec->{path}, encoding => 'UTF-8', eol => 'lf' }, $text, '>');
    return;
}
```

- [ ] **Step 4: テストを実行してグリーンを確認する**

```bash
prove -lr test/commonio.t 2>/dev/null
```

期待結果：全テスト PASS

- [ ] **Step 5: コミットする**

```bash
git add src/CommonIO.pm test/commonio.t
git commit -m "feat: remove write_file and append_file, unify writes through out_file"
```

---

## Task 5: `dec` 改善（`Encode::Guess` による `guess_encoding`）

**Files:**
- Modify: `src/CommonIO.pm`
- Modify: `test/commonio.t`

- [ ] **Step 1: テストを追加する**

`test/commonio.t` の `dec` subtest 群の後に追加：

```perl
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
```

- [ ] **Step 2: テストを実行してレッドを確認する**

```bash
prove -lr test/commonio.t 2>/dev/null
```

期待結果：追加した2つの subtest が FAIL（`dec` が warn を出さない）

- [ ] **Step 3: `use Encode::Guess` を追加し、`dec` を更新する**

`src/CommonIO.pm` の `use` 行に追加（`use Encode` の次の行）：
```perl
use Encode::Guess;
```

`dec` を以下に置き換え：
```perl
sub dec {
    my ($data) = @_;
    return $data unless defined $data;
    return $data if is_utf8($data);
    my $text = eval { decode('UTF-8', $data, FB_CROAK) };
    return $text if defined $text;
    my $guess = Encode::Guess->guess($data);
    if (ref $guess) {
        warn "guess_encoding: " . $guess->name . "\n";
    } else {
        warn "guess_encoding: unknown\n";
    }
    return $data;
}
```

- [ ] **Step 4: テストを実行してグリーンを確認する**

```bash
prove -lr test/commonio.t 2>/dev/null
```

期待結果：全テスト PASS

- [ ] **Step 5: コミットする**

```bash
git add src/CommonIO.pm test/commonio.t
git commit -m "feat: add Encode::Guess fallback to dec for guess_encoding warn"
```

---

## Task 6: `dp` 出力経路修正

**Files:**
- Modify: `src/CommonIO.pm`

- [ ] **Step 1: テストを実行して現状のグリーンを確認する**

```bash
prove -lr test/commonio.t 2>/dev/null
```

期待結果：全テスト PASS（`dp` テストは既存）

- [ ] **Step 2: `dp` の raw ハンドル出力を `print STDERR` に置き換える**

`src/CommonIO.pm` の `dp` を以下に置き換え：
```perl
sub dp {
    my @args = @_;
    return unless @args;
    my $out = (@args == 1 && ref $args[0])
        ? &np($args[0])
        : &np(\@args);
    print STDERR $out;
    return;
}
```

- [ ] **Step 3: テストを実行してグリーンを確認する**

```bash
prove -lr test/commonio.t 2>/dev/null
```

期待結果：全テスト PASS

- [ ] **Step 4: コミットする**

```bash
git add src/CommonIO.pm
git commit -m "fix: use print STDERR in dp, rely on _setup_console encoding layer"
```
