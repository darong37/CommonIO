# CommonIO

CommonIO を使うと Perl で文字コードや改行コードを意識せずにファイル入出力ができます。

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
| `var` | `write_do` / `read_do` で扱う Perl 変数 |
| `dump` | `dumpU8` が返す Data::Dumper 形式の文字列 |

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
| `crlf` | `\n` を `\r\n` へ変換して書く | 読み込み時は指定不可 |
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
# 文字列を追記
append_file('/tmp/log.txt', "追加行\n");

# 配列 ref を追記（write_file と同じ変換規則）
append_file('/tmp/log.txt', ['line4', 'line5']);
```

**エラー:** `write_file` と同じ

---

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
- ファイルが存在しない、または読み取りに失敗した場合は例外: `Cannot read`
- `encoding` が `UTF-8` / `CP932` 以外の場合は例外: `Unsupported file encoding`

---

### write_do

**シグネチャ:**
```
write_do($path, $var)
```

**説明:** Perl 変数を `do` で読める形式（`.do` ファイル）に保存します。エンコーディングは UTF-8 固定です。

**引数:**

| 引数 | 型 | 説明 |
|---|---|---|
| `$path` | 文字列またはハッシュ | 保存先ファイルパス（`path` キーのみ有効。`encoding` / `eol` を渡すと例外） |
| `$var` | 任意 | 保存する Perl 変数（ハッシュ ref、配列 ref など） |

**戻り値:** なし

**使用例:**
```perl
write_do('/tmp/config.do', { key => 'value', name => '日本語' });
```

**エラー:**
- 書き込み先が存在しない場合は例外
- `$path` にハッシュで `encoding` / `eol` キーを渡した場合は例外: `Unsupported path option`

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
| `$path` | 文字列またはハッシュ | 読み込み元ファイルパス（`path` キーのみ有効。`encoding` / `eol` を渡すと例外） |

**戻り値:** 保存された Perl 変数

**使用例:**
```perl
my $config = read_do('/tmp/config.do');
```

**エラー:**
- ファイルが存在しない、または評価が未定義の場合は例外: `file not found or empty`
- 構文エラーがある場合は例外: `Failed to read`
- `$path` にハッシュで `encoding` / `eol` キーを渡した場合は例外: `Unsupported path option`

---

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

**注意:**
- STDERR への出力はロケールのエンコーディングを使用します。環境に合わせて事前に `setup_console` を呼ぶことを推奨します。

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
| `$path` | 文字列またはハッシュ | ログファイルパス（`path` / `eol` キーのみ有効。`encoding` を渡すと例外） |
| `undef` | — | ファイル保存を無効にする |

**戻り値:** 設定したパス文字列。`undef` 指定時は戻り値なし

**エラー:**
- `$path` にハッシュで `encoding` キーを渡した場合は例外: `Unsupported path option`

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
