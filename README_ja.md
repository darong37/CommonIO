# CommonIO

CommonIO は Perl で文字コードや改行コードを意識せずにファイル入出力ができるモジュールです。

## 特徴

- UTF-8 / CP932（Shift_JIS）でのファイル読み書き — `binmode` や `encode`/`decode` を手書き不要
- 改行コードの柔軟な変換: `lf`・`crlf`・`preserve`
- `.do` ファイルへの Perl 変数シリアライズ（UTF-8 固定）
- コンソールおよびファイルへのログ出力（UTF-8 固定）
- `STDOUT`/`STDERR` のエンコーディング設定
- Unicode を保った `Data::Dumper` 出力
- エラー伝播付きのサブプロセス実行

## 使い方

```perl
use lib 'src';
use CommonIO qw(write_file append_file read_file write_do read_do
                log setLogFile dying setup_console dumpU8 run_in_fork);
```

## API 一覧

| API | 説明 |
|---|---|
| `write_file($path, $text\|$lines)` | ファイルを新規作成または上書き |
| `append_file($path, $text\|$lines)` | ファイルの末尾に追記 |
| `read_file($path)` | ファイルを読む（スカラ: テキスト、リスト: 行配列） |
| `write_do($path, $var)` | Perl 変数を `.do` ファイルに保存 |
| `read_do($path)` | `.do` ファイルから Perl 変数を読み込む |
| `log($level, $msg)` | STDERR へログ出力（ファイルへの保存も可） |
| `setLogFile($path)` | ログファイルの保存先を設定 |
| `dying($msg)` | エラーログを残してトレースバック付きで例外を投げる |
| `setup_console($encoding)` | STDOUT/STDERR のエンコーディングを設定 |
| `dumpU8($var, %opts)` | Unicode を保った Data::Dumper 出力 |
| `run_in_fork($code)` | 子プロセスでコードを実行 |

## path 指定

`$path` には文字列またはハッシュ ref を渡せます:

```perl
# 文字列 — UTF-8・lf（書き込み）/ preserve（読み込み）が既定値
write_file('/tmp/out.txt', $text);

# ハッシュ ref — encoding と eol を明示指定
write_file({ path => '/tmp/out.txt', encoding => 'CP932', eol => 'crlf' }, $text);
```

| キー | 必須 | 既定値 | 説明 |
|---|---|---|---|
| `path` | 必須 | — | ファイルパス |
| `encoding` | 任意 | `UTF-8` | `UTF-8` または `CP932` のみ |
| `eol` | 任意 | 書き込み: `lf` / 読み込み: `preserve` | 改行コードの扱い |

## 固定エンコーディング方針

| API | encoding |
|---|---|
| `setLogFile` / `log` | UTF-8 固定（変更不可） |
| `write_do` / `read_do` | UTF-8 固定（変更不可） |

## テスト実行

```
PERL5LIB=src:lib prove test/commonio.t
```

## ドキュメント

- [API リファレンス](docs/spec.md)
- [テスト仕様書](docs/test-spec.md)
