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

### ログ系（log / dying）

| テスト名 | 目的 | 前提条件 | 確認内容 |
|---|---|---|---|
| CommonIO dies with empty LOGDIR | LOGDIR が空のとき use CommonIO で die する | `$ENV{LOGDIR} = ''` を設定したサブプロセス | 終了コードが非ゼロ／エラーメッセージに「LOGDIR」が含まれる |
| CommonIO dies with unset LOGDIR | LOGDIR が未定義のとき use CommonIO で die する | `delete $ENV{LOGDIR}` したサブプロセス | 終了コードが非ゼロ／エラーメッセージに「LOGDIR」が含まれる |
| log writes to auto-determined file in LOGDIR | log が LOGDIR 配下の自動ファイルへ書き込む | LOGDIR が設定済み | LOGDIR 配下に `commonio*.log` が存在し、ログ内容が書き込まれる |
| log file name matches commonio+8digit+.log | ログファイル名が `<basename><MMDDHHMM>.log` 形式 | LOGDIR が設定済み | ファイル名が `/commonio\d{8}\.log$` にマッチする |
| log file is UTF-8 encoded | ログファイルが UTF-8 で書き込まれる | LOGDIR が設定済み | バイト列を UTF-8 でデコードして日本語メッセージが読める |
| log returns formatted line | log の戻り値が `[LEVEL] message` 形式 | なし | 戻り値が `[INFO] …` 形式にマッチする |
| dying logs error to auto file and throws | dying がエラーをログして例外を投げる | LOGDIR が設定済み | 例外メッセージが伝播する／ログファイルに `[ERROR]` 行が書き込まれる |

### at() 系

| テスト名 | 目的 | 前提条件 | 確認内容 |
|---|---|---|---|
| at returns callers arrayref | at() が配列リファレンスを返す | なし | 戻り値が ARRAY リファレンスで要素数が 1 以上 |
| at level 0 has required keys | caller_info が必要な4キーを持つ | なし | `file`・`path`・`line`・`subroutine` がすべて defined |
| at file is basename of path | file が path のベースネームと一致する | なし | `file eq basename(path)` |
| at excludes CommonIO internal frames | CommonIO.pm 内部フレームを含まない | なし | すべてのフレームで `file !~ /CommonIO\.pm$/` |
| at level 0 is test script | レベル 0 がテストスクリプトのフレーム | なし | `file =~ /commonio\.t$/` |

### out_file 系

| テスト名 | 目的 | 前提条件 | 確認内容 |
|---|---|---|---|
| out_file first call overwrites existing file | 初回呼び出しで既存ファイルを上書き | ファイルが存在する | read_file の結果が新しい内容のみ |
| out_file second call appends | 2回目は追記になる | なし | read_file の結果に1回目と2回目の内容が両方含まれる |
| out_file third call also appends | 3回目以降も追記 | なし | 3行分が順番に含まれる |
| out_file different paths are independent | 異なるパスのカウントは独立 | なし | 各パスで期待した内容のみ存在する |
| out_file accepts hash path with encoding and eol | ハッシュ形式のパス指定に対応 | なし | ハッシュ指定で書き込みと追記が正しく動作する |
| out_file child process does not clear parent counts | fork 後の子プロセス終了で親のカウントが消えない | なし | 子プロセス実行後も親の2回目呼び出しが追記になる |

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
