# CommonIO

CommonIO を使うと Perl で文字コードや改行コードを意識せずにファイル入出力ができます。

## インストール・使い方

```perl
use lib 'src';
use CommonIO qw(out_file pathcli read_file write_do read_do
                log at dying dumpU8 dec dp run_in_fork);
```

`use CommonIO` した時点で `BEGIN` ブロックが自動実行され、`STDOUT` と `STDERR` のエンコーディングがロケールに合わせて設定されます。

## 用語

| 用語 | 意味 |
|---|---|
| `path` | 入出力先を表す値。文字列のときはファイルパス、ハッシュのときはファイルパスと入出力条件をまとめた指定 |
| `mode` | 書き込み方法。`>` は上書き、`>>` は追記、`?` は同一 path への1回目上書き・2回目以降追記 |
| `encoding` | 文字エンコーディング。既定値 `utf8`、`cp932`、`raw`（変換なし）を指定可 |
| `eol` | 改行コードの扱い。`lf` または `crlf` で指定 |
| `content` | `out_file` に渡す書き込み内容。`text` または文字列配列リファレンス |
| `text` | Perl の内部文字列 |
| `lines` | 行単位に分割した配列 |
| `path_spec` | `pathcli` が返す入出力仕様。`path`、`encoding`、`eol`、`layer` を持つ |
| `layer` | `open` にそのまま渡せるモード込みのレイヤー文字列 |
| `var` | `write_do` / `read_do` で保存・復元する Perl 変数 |
| `dump` | `var` の構造を `do` で読める形へ整えた文字列 |
| `level` | ログの重要度。`debug` / `info` / `warn` / `warning` / `error` |
| `msg` | ログまたは例外として扱うメッセージ |
| `data` | `dec` に渡される元データ。utf8 のバイト列、またはすでに Perl の文字列 |
| `guess_encoding` | `data` が utf8 でないときに推測した文字コード名 |
| `line` | `[LEVEL] message` 形式の整形済みログ文字列 |
| `console_encoding` | `BEGIN` ブロックで決定し STDOUT/STDERR に設定するエンコーディング名 |
| `callers` | 呼び出し位置の履歴を表す `caller_info` の配列リファレンス |
| `caller_info` | `callers` の1要素。`file`、`path`、`line`、`subroutine` を持つ |
| `code` | 子プロセスで実行する処理（コードリファレンス） |

## path 指定

`path` は文字列またはハッシュで渡します。`path` に `>`、`>>`、`?` は使いません（これらは常に `mode` として解釈されます）。

**文字列の場合:**
```perl
out_file('/path/to/file.txt', $text);
```
`encoding` は `utf8`、`eol` は `lf` が既定値です。

**ハッシュの場合:**
```perl
out_file({ path => '/path/to/file.txt', encoding => 'cp932', eol => 'crlf' }, $text);
```

| キー | 必須 | 既定値 | 説明 |
|---|---|---|---|
| `path` | 必須 | — | ファイルパス |
| `encoding` | 任意 | `utf8` | `utf8`、`cp932`、`raw` のいずれか（`out_file` / `read_file` でのみ有効） |
| `eol` | 任意 | `lf` | `lf` または `crlf`（`out_file` / `read_file` でのみ有効） |

## mode 指定

| 値 | 動作 |
|---|---|
| `>` | 毎回上書き |
| `>>` | 毎回追記 |
| `?` | 同じ `path` への1回目は上書き、2回目以降は追記 |
| 省略 | `?` と同じ |

## 固定方針

| API | encoding |
|---|---|
| `log` / ログファイル | `utf8` 固定 |
| `write_do` / `read_do` | `utf8` 固定 |

---

## API リファレンス

### out_file

**シグネチャ:**
```
out_file($path, $content)
out_file($mode, $path, $content)
```

**説明:** ファイルへ書き込みます。`mode` 省略時は `?` として扱います。

**引数:**

| 引数 | 型 | 説明 |
|---|---|---|
| `$mode` | 文字列 | `>`、`>>`、`?` のいずれか。省略時は `?` |
| `$path` | 文字列またはハッシュ | 書き込み先。[path 指定](#path-指定)を参照 |
| `$content` | 文字列または配列 ref | `text` のときはそのまま書き込む。配列 ref のときは `eol` に従って連結して書き込む |

**戻り値:** なし

**使用例:**
```perl
# mode 省略（?）で書き込む
out_file('/tmp/out.txt', "Hello\nWorld");

# 上書きで書き込む
out_file('>', '/tmp/out.txt', "上書き内容");

# 追記する
out_file('>>', '/tmp/out.txt', "追記内容\n");

# CP932・CRLF で書き込む
out_file({ path => '/tmp/out.txt', encoding => 'cp932', eol => 'crlf' }, "こんにちは");

# 行配列で書き込む
out_file('/tmp/out.txt', ['line1', 'line2', 'line3']);

# encoding => raw でそのまま書き込む
out_file({ path => '/tmp/out.bin', encoding => 'raw' }, $bytes);
```

**エラー:**
- 書き込み先が存在しないディレクトリを指す場合は例外

---

### pathcli

**シグネチャ:**
```
$path_spec = pathcli($mode, $path)
```

**説明:** `path` と `mode` から実際の入出力仕様を `path_spec` として返します。`mode` が `?` のときはこの時点で `>` または `>>` に確定させます。

**引数:**

| 引数 | 型 | 説明 |
|---|---|---|
| `$mode` | 文字列 | `<`、`>`、`>>`、`?` のいずれか。`?` はこの時点で `>` または `>>` に確定する |
| `$path` | 文字列またはハッシュ | 入出力先。[path 指定](#path-指定)を参照 |

**戻り値:** `path_spec`（`path`、`encoding`、`eol`、`layer` を持つハッシュリファレンス）

**エラー:**
- `$mode` に `<`、`>`、`>>`、`?` 以外を渡した場合は例外
- `$path` に `>`、`>>`、`?` を渡した場合は例外

---

### read_file

**シグネチャ:**
```
$text  = read_file($path)      # スカラコンテキスト
@lines = read_file($path)      # リストコンテキスト
```

**説明:** ファイルを読み込んで Perl の内部文字列として返します。`encoding => raw` のときはスカラコンテキストのみ対応します。

**引数:**

| 引数 | 型 | 説明 |
|---|---|---|
| `$path` | 文字列またはハッシュ | 読み込み元。[path 指定](#path-指定)を参照 |

**戻り値:**
- スカラコンテキスト: ファイル全体の `text`（`encoding => raw` のときはバイト列）
- リストコンテキスト: 改行で分割した `lines`

**eol の挙動（読み込み時）:**

| eol | 挙動 |
|---|---|
| `lf`（既定） | `CRLF` / `CR` を `LF` へ正規化してから返す |
| `crlf` | 改行を `CRLF` へ正規化してから返す |

**使用例:**
```perl
# テキスト全体を読む
my $text = read_file('/tmp/data.txt');

# 行配列として読む
my @lines = read_file('/tmp/data.txt');

# CP932 ファイルを読む
my $text = read_file({ path => '/tmp/sjis.txt', encoding => 'cp932' });

# raw で読む（decode・改行正規化なし）
my $bytes = read_file({ path => '/tmp/data.bin', encoding => 'raw' });
```

**エラー:**
- ファイルが存在しない、または空で未定義の場合は例外

---

### write_do

**シグネチャ:**
```
write_do($path, $var)
```

**説明:** Perl 変数を `do` で読める形式（`.do` ファイル）として保存します。エンコーディングは `utf8` 固定です。

**引数:**

| 引数 | 型 | 説明 |
|---|---|---|
| `$path` | 文字列またはハッシュ | 保存先ファイルパス（ハッシュのときは `path` キーのみ使用） |
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

**説明:** `write_do` で保存した `.do` ファイルを評価して Perl 変数として返します。エンコーディングは `utf8` 固定です。

**引数:**

| 引数 | 型 | 説明 |
|---|---|---|
| `$path` | 文字列またはハッシュ | 読み込み元ファイルパス（ハッシュのときは `path` キーのみ使用） |

**戻り値:** 保存された Perl 変数

**使用例:**
```perl
my $config = read_do('/tmp/config.do');
```

**エラー:**
- ファイルが存在しない、または評価が未定義の場合は例外

---

### log

**シグネチャ:**
```
$line = log($level, $msg)
```

**説明:** ログを STDERR へ出力します。ログファイルは `at()` で取得した最上位の `.pl` ファイル名から自動決定し、同じ内容をファイルへも保存します。ログファイルのエンコーディングは `utf8`、改行は `lf` 固定です。

**引数:**

| 引数 | 型 | 説明 |
|---|---|---|
| `$level` | 文字列 | `debug` / `info` / `warn` / `warning` / `error` |
| `$msg` | 文字列 | ログメッセージ |

**戻り値:** `[LEVEL] message\n` 形式の `line`

**使用例:**
```perl
my $line = log('info', '処理開始');
# => "[INFO] 処理開始\n"

log('error', '致命的エラー');
```

**エラー:**
- 不正な `$level` を渡した場合は例外

---

### at

**シグネチャ:**
```
$callers = at()
```

**説明:** `caller` ベースで呼び出し履歴を `callers` として返します。最上位の `.pl` をレベル 0 とし、現在の呼び出し位置まで順に並べます。CommonIO 内部フレームは除外されます。

**戻り値:** `caller_info` の配列リファレンス（`callers`）

各 `caller_info` のキー:

| キー | 説明 |
|---|---|
| `file` | ベースネームのファイル名 |
| `path` | フルパスのファイルパス |
| `line` | 行番号 |
| `subroutine` | `Package::subroutine` 形式の完全修飾名 |

**使用例:**
```perl
my $callers = at();
my $top = $callers->[0];   # 最上位 .pl のフレーム
```

---

### dying

**シグネチャ:**
```
dying($msg)    # 戻らない
```

**説明:** `error` レベルでログを残してからトレースバック付きで例外を投げます。

**引数:**

| 引数 | 型 | 説明 |
|---|---|---|
| `$msg` | 文字列 | エラーメッセージ |

**戻り値:** 戻りません

**使用例:**
```perl
open my $fh, '<', $file or dying("Cannot open $file: $!");
```

---

### dumpU8

**シグネチャ:**
```
$dump = dumpU8($var)
$dump = dumpU8($var, %opts)
```

**説明:** Perl 変数を Unicode を保った `dump` 文字列へ変換して返します。Unicode 文字が `\x{...}` エスケープされずそのまま出力されます。

**引数:**

| 引数 | 型 | 既定値 | 説明 |
|---|---|---|---|
| `$var` | 任意 | — | ダンプする変数 |
| `%opts` | ハッシュ | — | `indent` など `Data::Dumper` への補助指定 |

**戻り値:** Unicode 文字をそのまま含んだ `dump` 文字列

**使用例:**
```perl
my $dump = dumpU8({ name => '日本語' });
```

---

### dec

**シグネチャ:**
```
$text = dec($data)
```

**説明:** `data` を `utf8` の `text` として扱える形へそろえて返します。`utf8` のバイト列なら decode し、すでに Perl の文字列なら そのまま返します。decode できないときは例外にせず受け取った値をそのまま返し、必要に応じて `guess_encoding` を推測して警告を出します。

**引数:**

| 引数 | 型 | 説明 |
|---|---|---|
| `$data` | スカラ | utf8 のバイト列、または Perl の内部文字列 |

**戻り値:** `text`

**使用例:**
```perl
my $text = dec($bytes);   # utf8 バイト列を decode して返す
my $text = dec($str);     # Perl 文字列はそのまま返す
```

---

### dp

**シグネチャ:**
```
dp(@args)
```

**説明:** 渡された引数リストを Data::Printer で整形して STDERR へ出力します。Unicode を正しく表示することを優先します。

**引数の扱い:**

| 引数 | 扱い |
|---|---|
| 0 個 | 何もしない |
| 1 個でリファレンス | そのまま Data::Printer へ渡す |
| それ以外 | `[@args]` に包んで Data::Printer へ渡す |

**戻り値:** なし

**使用例:**
```perl
dp($scalar);
dp(@array);
dp(%hash);
dp($hash_ref);
```

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
    out_file('/tmp/result.txt', '子プロセス完了');
});
```

**エラー:**
- `fork` に失敗した場合は例外
- 子プロセスで例外が発生した場合、親でも例外

---

## BEGIN ブロック

`use CommonIO` した時点で `BEGIN` ブロックが一度だけ自動実行され、`I18N::Langinfo` の `langinfo(CODESET)` に合わせて `STDOUT` と `STDERR` のエンコーディングを設定します。利用者が個別に `binmode` を書く必要はありません。
