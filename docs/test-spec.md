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

| テスト名 | 目的 | 前提条件 | 確認内容 |
|---|---|---|---|
| log writes UTF-8 text to log file | log 関数の基本動作（書式・ファイル書き込み） | setLogFile でログファイルを設定 | 戻り値が `[DEBUG] 漢字ログ` 形式になる／ログファイルに UTF-8 テキストが書き込まれる |
| dying logs error and throws | dying 関数がエラーを記録して例外を投げる | setLogFile でエラーログファイルを設定 | `die` で指定メッセージが伝播する／ログファイルに `[ERROR]` 行が書き込まれる |
| setLogFile undef disables file logging | setLogFile(undef) でファイル書き込みを無効化 | ログファイルなし状態で log を呼ぶ | 戻り値は正常に返る／ファイルが作成されない |
| setLogFile rejects encoding option | encoding キーを渡すと即座に例外 | setLogFile({ path => ..., encoding => 'CP932' }) | 「Unsupported path option: encoding」例外が発生する |
| log file is UTF-8 with valid setLogFile path | ログファイルが UTF-8 で書き込まれること | setLogFile でパスのみ設定 | ファイルのバイト列を UTF-8 でデコードしてメッセージが読める |

### ファイルIO系（write_file / append_file / read_file）

| テスト名 | 目的 | 前提条件 | 確認内容 |
|---|---|---|---|
| write_file rejects unsupported encoding | サポート外エンコーディング（EUC-JP）を拒否 | encoding => 'EUC-JP' を指定 | 「Unsupported file encoding」例外が発生する |
| read_file rejects unsupported encoding | 読み込み時にサポート外エンコーディング（EUC-JP）を拒否 | ファイルが存在し encoding => 'EUC-JP' を指定 | 「Unsupported file encoding」例外が発生する |
| append_file rejects unsupported encoding | 追記時にサポート外エンコーディング（EUC-JP）を拒否 | ファイルが存在し encoding => 'EUC-JP' を指定 | 「Unsupported file encoding」例外が発生する |
| write_file writes UTF-8 text | UTF-8 テキストの書き込みと読み返し | なし | read_file で同じ日本語テキストが取得できる |
| write_file writes CRLF | eol => 'crlf' 指定時に CRLF で書き込む | なし | バイナリ読み取りで `\r\n` が含まれる |
| write_file preserves eol | eol => 'preserve' 指定時に混在改行を保持する | なし | バイナリ読み取りで `line1\r\nline2\nline3` がそのまま保存される |
| write_file writes array lines | 配列リファレンスを LF 区切りで書き込む | なし | 各行が LF で結合されてファイルに書き込まれる |
| write_file writes CP932 | encoding => 'CP932' 指定時に CP932 バイト列で書き込む | なし | バイナリサイズが UTF-8 より小さい（カタカナは CP932=2B/文字 < UTF-8=3B/文字） |
| append_file appends to existing file | 既存ファイルへの追記 | write_file で先に1行書き込む | read_file で2行分のテキストが取得できる |
| read_file returns scalar text | スカラーコンテキストで全文を返す | ファイルが存在する | 戻り値が書き込んだ文字列と一致する |
| read_file returns line array | リストコンテキストで行配列を返す | 3行のファイルが存在する | 配列の要素数が3で各行の内容が正しい |
| read_file normalizes CRLF to LF with eol=>lf | eol => 'lf' 指定時に CRLF を LF へ正規化 | CRLF ファイルを raw モードで作成 | CR が含まれない／LF が含まれる |
| read_file preserves CRLF with eol=>preserve | eol => 'preserve' 指定時に CRLF をそのまま保持 | CRLF ファイルを raw モードで作成 | `\r\n` が含まれる |
| read_file throws on missing file | 存在しないファイルを読もうとすると例外 | ファイルが存在しない | 「Cannot read」例外が発生する |
| read_file reads CP932 file | CP932 で書いたファイルを同エンコーディングで読む | CP932 で書き込んだファイルが存在する | 読み取り結果が元の日本語文字列と一致する |
| read_file with hash path spec | ハッシュ形式のパス指定で読み込む | UTF-8 + eol=lf で書き込んだファイルが存在する | ハッシュ指定（encoding=UTF-8, eol=preserve）で日本語テキストが読める |

### .doファイル系（write_do / read_do）

| テスト名 | 目的 | 前提条件 | 確認内容 |
|---|---|---|---|
| write_do / read_do round-trip hash | ハッシュリファレンスの書き込みと読み返し | なし | 読み返しで HASH リファレンスが返り、各キーの値が一致する |
| write_do / read_do round-trip array | 配列リファレンスの書き込みと読み返し | なし | 読み返しで ARRAY リファレンスが返り、各要素が一致する |
| write_do / read_do preserves Unicode | Unicode 文字を含むデータの往復 | なし | 読み返しで日本語文字列が正しく取得できる |
| write_do rejects encoding option | encoding キーを渡すと即座に例外 | write_do({ path => ..., encoding => 'CP932' }, ...) | 「Unsupported path option: encoding」例外が発生する |
| write_do rejects eol option | eol キーを渡すと即座に例外 | write_do({ path => ..., eol => 'crlf' }, ...) | 「Unsupported path option: eol」例外が発生する |
| read_do throws on missing file | 存在しないファイルを読もうとすると例外 | ファイルが存在しない | 「file not found or empty」または「Failed to read」例外が発生する |
| read_do throws on syntax error file | 構文エラーのあるファイルを読もうとすると例外 | 不正な Perl 構文のファイルが存在する | 「Failed to read」例外が発生する |
| read_do rejects encoding option | encoding キーを渡すと即座に例外 | read_do({ path => ..., encoding => 'CP932' }) | 「Unsupported path option: encoding」例外が発生する |
| read_do rejects eol option | eol キーを渡すと即座に例外 | read_do({ path => ..., eol => 'lf' }) | 「Unsupported path option: eol」例外が発生する |

### ダンプ系（dumpU8）

| テスト名 | 目的 | 前提条件 | 確認内容 |
|---|---|---|---|
| dumpU8 preserves Unicode characters | Unicode 文字を `\x{}` 形式にエスケープせず出力 | なし | ダンプ文字列に漢字が含まれる／`\x{` が含まれない |
| dumpU8 with indent=>0 produces one line | indent => 0 でワンライン出力 | なし | ダンプ文字列に改行が含まれない |

### コンソール系（setup_console）

| テスト名 | 目的 | 前提条件 | 確認内容 |
|---|---|---|---|
| setup_console returns UTF-8 | 'UTF-8' を指定すると 'UTF-8' を返す | なし | 戻り値が 'UTF-8' と一致する |
| setup_console returns CP932 | 'CP932' を指定すると 'CP932' を返す | なし | 戻り値が 'CP932' と一致する（テスト後 UTF-8 へ戻す） |
| setup_console with no arg does not throw | 引数なしで呼んでも例外が発生しない | なし | 例外なし／戻り値が定義済み |
| setup_console rejects unsupported encoding | サポート外エンコーディング（EUC-JP）を拒否 | なし | 「Unsupported console encoding」例外が発生する |

### フォーク系（run_in_fork）

| テスト名 | 目的 | 前提条件 | 確認内容 |
|---|---|---|---|
| run_in_fork executes code in child | 子プロセスでクロージャが実行される | なし | 子プロセスがファイルを作成し、内容が正しい |
| run_in_fork throws when child throws | 子プロセスが例外を投げると親プロセスも例外を投げる | なし | 親プロセスで「confirm failed」例外が発生する |
