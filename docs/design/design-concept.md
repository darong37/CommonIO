# CommonIO Design Concept

## Terms

- `path`: 入出力先を表す値である。文字列のときはファイルパスを意味し、ハッシュのときはファイルパスと入出力条件をまとめた指定である。
- `mode`: 書き込み方法を表す指定である。`>` は上書き、`>>` は追記、`?` は `out` を意味する。
- `encoding`: テキストをバイト列へ変換するとき、またはバイト列からテキストへ戻すときに使う文字エンコーディングである。既定値は `utf8` であり、`raw` は変換を行わない特別値である。
- `eol`: 改行の扱いを表す指定である。`lf` または `crlf` の文字列で指定する。
- `content`: `out_file` に渡す書き込み内容である。`text` または文字列配列のリファレンスを取る。
- `text`: 通常のファイル入出力で扱う文字列である。
- `lines`: 通常のファイル書き込みや読み込みで扱う行配列である。
- `path_spec`: `pathcli` が返す入出力仕様である。`path`、`encoding`、`eol`、`layer` を持つ。
- `layer`: `open` にそのまま渡すモード込みのレイヤー文字列である。
- `var`: `.do` に保存したり `.do` から復元したりする Perl 変数である。
- `dump`: `var` の構造を表し、`do` で読める形へ整えた文字列である。
- `level`: ログの重要度である。利用者は `debug` / `info` / `warn` / `warning` / `error` を渡す。
- `msg`: ログまたは例外として扱うメッセージである。
- `args`: API に渡された引数列である。
- `data`: API に渡される元データである。utf8 のバイト列、またはすでに Perl の文字列になっている値を含む。
- `guess_encoding`: `data` が utf8 の内部文字列でないときに推測した文字コード名である。推測結果であり、確定値ではない。
- `code`: 子プロセスで実行する処理である。
- `opts`: 補助指定のまとまりである。
- `line`: 整形済みの 1 行ログ文字列である。
- `console_encoding`: `BEGIN` ブロックで `I18N::Langinfo` の `langinfo(CODESET)` に合わせて決定し、`STDOUT` と `STDERR` へ設定するコンソール用エンコーディング名である。
- `callers`: 呼び出し位置の履歴を表す `caller_info` の配列リファレンスである。
- `caller_info`: `callers` の 1 要素を表すハッシュである。`file`、`path`、`line`、`subroutine` を持つ。

## Concept

- 第一コンセプトは、Perl で文字コードや改行コードを都度気にせずに入出力できるようにすることである。
- CommonIO を通すことで、利用者は文字列を Perl の値としてそのまま扱い、エンコーディング変換と改行処理は CommonIO に任せる。
- 基本の文字コードは `utf8` とし、必要なときだけ `cp932` も扱えるようにする。
- `raw` は文字コード変換を行わずにそのまま扱いたい場合の逃がし口として用意する。
- ファイル、`.do`、ログ、コンソール出力を同じ方針で揃え、どの入出力でも同じ考え方で扱えるようにする。
- 第二コンセプトは、入出力に付随して毎回書きがちな補助処理も CommonIO 側へ寄せることである。
- `read_file`、`out_file`、`read_do`、`write_do`、`log` を使うことで、利用者は個別の入出力手順をあまり意識せずに済むようにする。
- `dying` は単なる `die` の置き換えではなく、メッセージをログへ残し、トレースバック付きで失敗を表現する共通経路として扱う。
- ログはまず `stderr` へ出し、必要なときだけ追加でファイルへ保存する。
- ログファイルは利用者が後から設定するのではなく、読込時点で自動決定できる形を基本にする。
- コンソールのエンコーディング層は、`use CommonIO` した最初の 1 回で動く `BEGIN` ブロックで設定することを基本にする。
- コード中で `STDOUT` や `STDERR` へ個別に `binmode` を当てるのは、その `BEGIN` ブロック以外では行わない。
- `run_in_fork` のような周辺機能も、エラー処理とログ方針を揃えて使えるように CommonIO に含める。
- `dec` のような補助 API も含め、入力された値が utf8 のバイト列なのか、すでに Perl の文字列なのかを利用者が毎回気にしなくて済むようにする。
- 既存の処理の中で `dec` で吸収できる文字列化処理は、個別対応を増やさず `dec` へ置き換えて共通化する。
- utf8 の内部文字列でない値に対しては、必要に応じて文字コード推測も併用し、利用者が原因調査しやすい情報を残せるようにする。
- この共通化の対象は今後も増やせるようにし、入出力まわりで繰り返し書く処理を集約していく。

## API

### API Interface List

| API | Interface | Return |
| --- | --- | --- |
| `out_file` | `out_file($path, $content)`<br>`out_file($mode, $path, $content)` | なし |
| `pathcli` | `pathcli($mode, $path)` | `path_spec` |
| `read_file` | `read_file($path)` | 既定ではスカラで `text`、リストコンテキストで `lines`。`encoding => raw` のときはスカラのみ |
| `write_do` | `write_do($path, $var)` | なし |
| `read_do` | `read_do($path)` | `var` |
| `log` | `log($level, $msg)` | `line` |
| `at` | `at()` | `callers` |
| `dying` | `dying($msg)` | 戻らない |
| `dumpU8` | `dumpU8($var, %opts)` | `dump` |
| `dec` | `dec($data)` | `text` |
| `dp` | `dp(@args)` | なし |
| `run_in_fork` | `run_in_fork($code)` | なし |

### `path`

- 文字列の `path` はファイルパスとして扱う。
- `path` には `>`、`>>`、`?` を使わない。これらは常に `mode` として解釈する。
- ハッシュの `path` は次のキーを扱う。
- `path`: 必須のファイルパス。
- `encoding`: `out_file` / `read_file` でのみ任意。省略時は `utf8`、指定可能なのは `utf8`、`cp932`、`raw` である。
- `eol`: `out_file` / `read_file` でのみ任意。省略時は `lf`、指定可能なのは `lf` と `crlf` である。

### `mode`

- `>` はファイルを新規内容で上書きする。
- `>>` は既存内容の末尾へ追記する。
- `?` は同じ `path` への 1 回目の書き込みでは上書きし、2 回目以降は追記する。
- `mode` を省略したときの既定値は `?` である。

### `out_file`

- `out_file($path, $content)` は、`mode` を省略した形であり、`out_file('?', $path, $content)` と同じ意味で扱う。
- `out_file('>', $path, $content)` は、毎回上書きする。
- `out_file('>>', $path, $content)` は、毎回追記する。
- `out_file('?', $path, $content)` は、同じ `path` への 1 回目は上書きし、2 回目以降は追記する。
- 利用者が直接 `open` や `binmode` を書かなくても、`path` の条件に従って文字列を保存できる。
- `content` が `text` のときは、そのまま `path` の条件で書き込む。
- `content` が文字列配列のリファレンスのときは、`eol` に従って各要素を連結して書き込む。
- `encoding => raw` のときは encode を行わず、受け取った値をそのままファイルへ書き込む。
- 既出判定はファイルパス文字列ごとに行う。
- 書き込みが成功した回数を、同じファイルパス文字列ごとに数える。
- 戻り値は持たない。

### `pathcli`

- `pathcli($mode, $path)` は、`path` と `mode` から実際の入出力仕様を `path_spec` として返す。
- `path_spec` は `path`、`encoding`、`eol`、`layer` を持つ。
- `mode` が `?` のときは、この時点で `>` または `>>` に確定させる。
- `mode` として受け付けるのは `<`、`>`、`>>`、`?` である。
- `path` が文字列のときは、既定値として `encoding => utf8`、`eol => lf` を補う。
- `path` がハッシュのときは、`path`、`encoding`、`eol` を読んで `path_spec` を組み立てる。
- `layer` は `mode` を含んだ 1 本の文字列とし、`open` にそのまま渡せる形で返す。
- `path` に `>`、`>>`、`?` が来たときは例外にする。

### `read_file`

- `read_file($path)` はスカラでは `text`、リストコンテキストでは `lines` を返す。
- 利用者が直接 `decode` を意識しなくても、`path` の条件に従って Perl の文字列として読める。
- `lines` は行単位に分割した配列である。
- `eol => 'lf'` のときは `CRLF` と `CR` を `LF` へ正規化する。
- `eol => 'crlf'` のときは、読み込んだ改行を `CRLF` へ正規化する。
- `encoding => raw` のときは decode と改行正規化を行わず、スカラでは読み込んだ値をそのまま返す。リストコンテキストは扱わない。
- 対象が存在しない、または空で `do`/read の結果が未定義なら例外にする。

### `write_do`

- `write_do($path, $var)` は `var` を `dump` へ変換し、`use utf8;` 付きの `.do` 形式で保存する。
- `.do` は `utf8` 固定で保存する。
- `path` は文字列でもハッシュでも受け付けるが、実際に使うのは保存先の `path` だけである。
- 戻り値は持たない。

### `read_do`

- `read_do($path)` は `.do` を評価して `var` として返す。
- `.do` は `utf8` 固定で扱う。
- `path` は文字列でもハッシュでも受け付けるが、実際に使うのは読込先の `path` だけである。

### `log`

- `log($level, $msg)` は `[LEVEL] message` 形式の 1 行を返す。
- ログは `stderr` へ出力する。
- ログファイルは読込時に文字列の `path` として自動決定し、同じ内容をファイルへも保存する。
- ログファイル名の決定では必ず `at()` を使い、最上位の `.pl` ファイル名を `at` のレベル 0 から取得する。
- `.pl` が見つからないときは、`at()` で取得できた最上位フレームを使う。
- ログファイルへの保存は `out_file($path, $content)` の既定値、すなわち `utf8` と `lf` に従う。

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

### `BEGIN`

- `BEGIN` ブロックは `STDOUT` と `STDERR` のエンコーディングを、`I18N::Langinfo` の `langinfo(CODESET)` に合わせて決定して設定する。
- この設定は `use CommonIO` したときに最初の 1 回だけ自動実行される前提とし、同じ読込過程で重ねて設定しない。
- 利用者から `encoding` は受け取らず、常に `I18N::Langinfo` の `langinfo(CODESET)` に合わせる。
- コンソール表示でも利用者が都度 `binmode` を書かずに済むようにする。
- `STDOUT` と `STDERR` への `binmode` 設定はこの `BEGIN` ブロックだけが担当し、それ以外の API はコンソール層を書き換えない。

### `dumpU8`

- `dumpU8($var, %opts)` は `var` を Unicode を保った `dump` へ変換して返す。

### `dec`

- `dec($data)` は `data` を `utf8` の `text` として扱える形へそろえて返す。
- `data` が `utf8` のバイト列なら、それを decode した `text` を返す。
- `data` がすでに Perl の文字列として扱える値なら、そのまま返す。
- `utf8` として decode できないときも例外にはせず、受け取った `data` をそのまま返す。
- `utf8` として decode できないときは、必要に応じて `guess_encoding` を推測し、その結果を警告へ出せるようにする。

### `dp`

- `dp(@args)` は渡された引数リストを Data::Printer で整形し STDERR へ出力する。
- 引数が 0 個のときは何もしない。
- 引数が 1 個でその値がリファレンスのときは、そのリファレンスをそのまま Data::Printer へ渡す。
- それ以外のときは、渡された引数リスト全体を `[@_]` の配列リファレンスへ包んで Data::Printer へ渡す。
- 利用者は `@` や `%` などの先頭記号を意識せずに `dp($scalar)`、`dp(@array)`、`dp(%hash)` と書ける。
- 漢字を含む Unicode を正しく表示することを最優先とし、Data::Printer 側の表示上の問題点はこのラッパー側で吸収する。
- 戻り値は持たない。

### `run_in_fork`

- `run_in_fork($code)` は子プロセスで `code` を実行し、成功時のみ親へ戻る。
- 子プロセス内で例外が起きたときは `error` ログを残し、親側では失敗として例外にする。
- 戻り値は持たない。
