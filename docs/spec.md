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
- ファイルが存在しない場合は例外: `Cannot read`
- ファイルが空の場合は例外: `file not found or empty`
- `encoding` が `UTF-8` / `CP932` 以外の場合は例外: `Unsupported file encoding`

---
