# CommonIO

CommonIO は Perl で文字コードや改行コードを意識せずにファイル入出力ができるモジュールです。

## 特徴

- UTF-8・CP932（Shift_JIS）・raw でのファイル読み書き — `binmode` や `encode`/`decode` を手書き不要
- 改行コードの柔軟な変換: `lf`・`crlf`
- `use CommonIO` 時に `STDOUT`/`STDERR` のエンコーディングをロケールに合わせて自動設定（`BEGIN` ブロック）
- `.do` ファイルへの Perl 変数シリアライズ（UTF-8 固定）
- `LOGDIR` 配下への自動ログ出力（UTF-8 固定）
- Unicode を保った `Data::Dumper` 出力
- Unicode 対応のデバッグ出力（`Data::Printer`）
- エラー伝播付きのサブプロセス実行

## 必要な環境変数

> `LOGDIR` 環境変数が必須です。CommonIO は `$LOGDIR/<スクリプト名><MMDDHHMM>.log` へログを書き込みます。

## 使い方

```perl
use lib 'src';
use CommonIO qw(out_file pathcli read_file write_do read_do
                log at dying dumpU8 dec dp run_in_fork);
```

`use CommonIO` 時に `BEGIN` ブロックが自動実行され、ロケールに合わせて `STDOUT`/`STDERR` のエンコーディングが設定されます。

## API 一覧

| API | 説明 |
|---|---|
| `out_file($path, $content)` | ファイルへ書き込む（初回上書き・2回目以降追記） |
| `out_file($mode, $path, $content)` | mode を明示して書き込む: `>` 上書き、`>>` 追記、`?` 自動 |
| `pathcli($mode, $path)` | path と mode から `path_spec` を解決する |
| `read_file($path)` | ファイルを読む（スカラ: テキスト、リスト: 行配列） |
| `write_do($path, $var)` | Perl 変数を `.do` ファイルに保存 |
| `read_do($path)` | `.do` ファイルから Perl 変数を読み込む |
| `log($level, $msg)` | STDERR および LOGDIR 配下の自動決定ファイルへログ出力 |
| `at()` | 呼び出し履歴を `callers` として返す |
| `dying($msg)` | エラーログを残してトレースバック付きで例外を投げる |
| `dumpU8($var, %opts)` | Unicode を保った Data::Dumper 出力 |
| `dec($data)` | UTF-8 バイト列を Perl 文字列へ変換（既に文字列ならそのまま） |
| `dp(@args)` | Data::Printer で整形して STDERR へ出力 |
| `run_in_fork($code)` | 子プロセスでコードを実行 |

## mode

| 値 | 動作 |
|---|---|
| `>` | 毎回上書き |
| `>>` | 毎回追記 |
| `?` | 同じ path への初回は上書き、2回目以降は追記 |
| 省略 | `?` と同じ |

## path 指定

`$path` には文字列またはハッシュ ref を渡せます:

```perl
# 文字列 — utf8・lf が既定値
out_file('/tmp/out.txt', $text);

# ハッシュ ref — encoding と eol を明示指定
out_file({ path => '/tmp/out.txt', encoding => 'cp932', eol => 'crlf' }, $text);
```

| キー | 必須 | 既定値 | 説明 |
|---|---|---|---|
| `path` | 必須 | — | ファイルパス |
| `encoding` | 任意 | `utf8` | `utf8`・`cp932`・`raw` のいずれか |
| `eol` | 任意 | `lf` | `lf` または `crlf` |

## 固定エンコーディング方針

| API | encoding |
|---|---|
| `log` / ログファイル | UTF-8 固定（変更不可） |
| `write_do` / `read_do` | UTF-8 固定（変更不可） |

## テスト実行

```
prove -lr test/
```

## ドキュメント

- [API リファレンス](docs/spec.md)
- [テスト仕様書](docs/test-spec.md)
