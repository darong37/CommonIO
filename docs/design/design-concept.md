# CommonIO Design Concept

## Terms

- `path`: 入出力先を表す値である。文字列のときはファイルパスを意味し、ハッシュのときはファイルパスと入出力条件をまとめた指定である。
- `encoding`: テキストをバイト列へ変換するとき、またはバイト列からテキストへ戻すときに使う文字エンコーディングである。既定値は `UTF-8` である。
- `eol`: 改行の扱いを表す指定である。書き込みでは `lf` / `crlf` / `preserve`、読み込みでは `lf` / `preserve` を扱う。
- `text`: 通常のファイル入出力で扱う文字列である。
- `lines`: 通常のファイル書き込みや読み込みで扱う行配列である。
- `var`: `.do` に保存したり `.do` から復元したりする Perl 変数である。
- `dump`: `var` の構造を表し、`do` で読める形へ整えた文字列である。
- `level`: ログの重要度である。利用者は `debug` / `info` / `warn` / `warning` / `error` を渡す。
- `msg`: ログまたは例外として扱うメッセージである。
- `code`: 子プロセスで実行する処理である。
- `opts`: 補助指定のまとまりである。
- `line`: 整形済みの 1 行ログ文字列である。
- `console_encoding`: `setup_console` が設定して返すコンソール用エンコーディング名である。
- `callers`: 呼び出し位置の履歴を表す `caller_info` の配列リファレンスである。
- `caller_info`: `callers` の 1 要素を表すハッシュである。`file`、`path`、`line`、`subroutine` を持つ。

## Concept

- 第一コンセプトは、Perl で文字コードや改行コードを都度気にせずに入出力できるようにすることである。
- CommonIO を通すことで、利用者は文字列を Perl の値としてそのまま扱い、エンコーディング変換と改行処理は CommonIO に任せる。
- 基本の文字コードは `UTF-8` とし、必要なときだけ `CP932` も扱えるようにする。
- ファイル、`.do`、ログ、コンソール出力を同じ方針で揃え、どの入出力でも同じ考え方で扱えるようにする。
- 第二コンセプトは、入出力に付随して毎回書きがちな補助処理も CommonIO 側へ寄せることである。
- `read_file`、`write_file`、`read_do`、`write_do`、`log`、`setup_console` を使うことで、利用者は個別の入出力手順をあまり意識せずに済むようにする。
- `dying` は単なる `die` の置き換えではなく、メッセージをログへ残し、トレースバック付きで失敗を表現する共通経路として扱う。
- ログはまずコンソールへ出し、必要なときだけ追加でファイルへ保存する。
- ログファイルは利用者が後から設定するのではなく、読込時点で自動決定できる形を基本にする。
- `run_in_fork` のような周辺機能も、エラー処理とログ方針を揃えて使えるように CommonIO に含める。
- この共通化の対象は今後も増やせるようにし、入出力まわりで繰り返し書く処理を集約していく。

## API

### API Interface List

| API | Interface | Return |
| --- | --- | --- |
| `write_file` | `write_file($path, $text)`<br>`write_file($path, $lines)` | なし |
| `append_file` | `append_file($path, $text)`<br>`append_file($path, $lines)` | なし |
| `out_file` | `out_file($path, $text)`<br>`out_file($path, $lines)` | なし |
| `read_file` | `read_file($path)` | スカラでは `text`、リストコンテキストでは `lines` |
| `write_do` | `write_do($path, $var)` | なし |
| `read_do` | `read_do($path)` | `var` |
| `log` | `log($level, $msg)` | `line` |
| `at` | `at()` | `callers` |
| `dying` | `dying($msg)` | 戻らない |
| `setup_console` | `setup_console($encoding)` | `console_encoding` |
| `dumpU8` | `dumpU8($var, %opts)` | `dump` |
| `run_in_fork` | `run_in_fork($code)` | なし |

### `path`

- 文字列の `path` はファイルパスとして扱う。
- ハッシュの `path` は次のキーを扱う。
- `path`: 必須のファイルパス。
- `encoding`: `write_file` / `append_file` / `read_file` でのみ任意。省略時は `UTF-8`、指定可能なのは `CP932` を含む許可値のみ。
- `eol`: `write_file` / `append_file` / `read_file` でのみ任意。書き込み時の既定値は `lf`、読み込み時の既定値は `preserve`。

### `write_file`

- `write_file($path, $text)` または `write_file($path, $lines)` はファイルを新規内容で上書きする。
- 利用者が直接 `open` や `binmode` を書かなくても、`path` の条件に従って文字列を保存できる。
- `text` はそのまま `path` の条件で書き込む。
- `lines` は `eol` に従って各要素を連結して書き込む。
- 戻り値は持たない。

### `append_file`

- `append_file($path, $text)` または `append_file($path, $lines)` は `write_file` と同じ変換規則で末尾へ追記する。
- 戻り値は持たない。

### `out_file`

- `out_file($path, $text)` または `out_file($path, $lines)` は、同じ `path` への 1 回目の書き込みでは `write_file` と同じ動作をし、2 回目以降は `append_file` と同じ動作をする。
- 既出判定はファイルパス文字列ごとに行う。
- 書き込みが成功した回数を、同じファイルパス文字列ごとに数える。
- 戻り値は持たない。

### `read_file`

- `read_file($path)` はスカラでは `text`、リストコンテキストでは `lines` を返す。
- 利用者が直接 `decode` を意識しなくても、`path` の条件に従って Perl の文字列として読める。
- `lines` は行単位に分割した配列である。
- `eol => 'lf'` のときは `CRLF` と `CR` を `LF` へ正規化する。
- 対象が存在しない、または空で `do`/read の結果が未定義なら例外にする。

### `write_do`

- `write_do($path, $var)` は `var` を `dump` へ変換し、`use utf8;` 付きの `.do` 形式で保存する。
- `.do` は `UTF-8` 固定で保存し、`path` 文字列のみを受け付ける。
- 戻り値は持たない。

### `read_do`

- `read_do($path)` は `.do` を評価して `var` として返す。
- `.do` は `UTF-8` 固定で扱い、`path` 文字列のみを受け付ける。

### `log`

- `log($level, $msg)` は `[LEVEL] message` 形式の 1 行を返す。
- ログはコンソールへ出力する。
- ログファイルは読込時に自動決定し、同じ内容をファイルへも追記する。
- ログファイル名の決定では必ず `at()` を使い、最上位の `.pl` ファイル名を `at` のレベル 0 から取得する。
- `.pl` が見つからないときは、`at()` で取得できた最上位フレームを使う。
- ログファイルの既定値は `encoding => UTF-8`、`eol => lf` である。

### `at`

- `at()` は `caller` ベースで集めた呼び出し履歴を、`callers` として返す。
- 返す配列は最上位の `.pl` をレベル 0 とし、そこから 1、2、3 と現在の呼び出し位置まで順に並べる。
- 最上位の `.pl` が見つからないときは、取得できた最上位フレームをレベル 0 とする。
- CommonIO 自身の内部フレームは返却対象に含めない。
- 各要素は `caller_info` のハッシュであり、`file`、`path`、`line`、`subroutine` を返す。
- `file` はベースネームのファイル名、`path` はフルパスのファイルパスとする。
- `subroutine` はパッケージ名を含む完全修飾名、すなわち `Package::subroutine` の形とする。
- `at` はログファイル名の自動決定にも使える共通 API として扱う。

### `dying`

- `dying($msg)` は `error` レベルでログしてから例外を投げる。
- 例外は `confess` によりトレースバック付きで扱う。

### `setup_console`

- `setup_console($encoding)` は `STDOUT` と `STDERR` のエンコーディングを設定する。
- 現時点では `UTF-8` と `CP932` 系を受け付ける。
- コンソール表示でも利用者が都度 `binmode` を書かずに済むようにする。
- 設定した `console_encoding` を返す。

### `dumpU8`

- `dumpU8($var, %opts)` は `var` を Unicode を保った `dump` へ変換して返す。

### `run_in_fork`

- `run_in_fork($code)` は子プロセスで `code` を実行し、成功時のみ親へ戻る。
- 子プロセス内で例外が起きたときは `error` ログを残し、親側では失敗として例外にする。
- 戻り値は持たない。
