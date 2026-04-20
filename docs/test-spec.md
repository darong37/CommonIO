# CommonIO テスト仕様書

## テスト方針

- 正常系・異常系・境界条件を網羅する
- エンコーディング変換は実バイト列で検証する
- 一時ファイルは `/tmp/spool/commonio-test/` に作成し、テスト前後に削除する

## テスト環境・前提条件

| 項目 | 内容 |
|---|---|
| テストフレームワーク | `Test::More` |
| 実行コマンド | `prove -lr test/` |
| 一時ディレクトリ | `/tmp/spool/commonio-test/` |
| PERL5LIB | `src:lib`（settings.json で設定済み） |

## テストケース一覧

### BEGIN ブロック系

| テスト名 | 目的 | 前提条件 | 確認内容 |
|---|---|---|---|
| BEGIN auto-runs: STDOUT has encoding layer | use CommonIO 時に STDOUT にエンコード層が設定される | なし | PerlIO::get_layers(STDOUT) に `encoding` が含まれる |
| BEGIN auto-runs: STDERR has encoding layer | use CommonIO 時に STDERR にエンコード層が設定される | なし | PerlIO::get_layers(STDERR) に `encoding` が含まれる |
| CommonIO dies with empty LOGDIR | LOGDIR が空のとき use CommonIO で die する | `$ENV{LOGDIR} = ''` を設定したサブプロセス | 終了コードが非ゼロ／エラーメッセージに「LOGDIR」が含まれる |
| CommonIO dies with unset LOGDIR | LOGDIR が未定義のとき use CommonIO で die する | `delete $ENV{LOGDIR}` したサブプロセス | 終了コードが非ゼロ／エラーメッセージに「LOGDIR」が含まれる |
| CommonIO dies when LOGDIR directory does not exist | LOGDIR ディレクトリが存在しないとき die する | 存在しないパスを LOGDIR に指定 | 終了コードが非ゼロ／「LOGDIR directory does not exist」が含まれる |

### ログ系（log / dying）

| テスト名 | 目的 | 前提条件 | 確認内容 |
|---|---|---|---|
| log returns formatted line | log の戻り値が `[LEVEL] message` 形式 | なし | 戻り値が `[INFO] …` 形式にマッチする |
| log writes to auto-determined file in LOGDIR | log が LOGDIR 配下の自動ファイルへ書き込む | LOGDIR が設定済み | LOGDIR 配下に `commonio*.log` が存在し、ログ内容が書き込まれる |
| log file name matches commonio+8digit+.log | ログファイル名が `<basename><MMDDHHMM>.log` 形式 | LOGDIR が設定済み | ファイル名が `/commonio\d{8}\.log$` にマッチする |
| log file is UTF-8 encoded | ログファイルが UTF-8 で書き込まれる | LOGDIR が設定済み | バイト列を UTF-8 でデコードして日本語メッセージが読める |
| dying logs error to auto file and throws | dying がエラーをログして例外を投げる | LOGDIR が設定済み | 例外メッセージが伝播する／ログファイルに `[ERROR]` 行が書き込まれる |

### at() 系

| テスト名 | 目的 | 前提条件 | 確認内容 |
|---|---|---|---|
| at returns callers arrayref | at() が配列リファレンスを返す | なし | 戻り値が ARRAY リファレンスで要素数が 1 以上 |
| at level 0 has required keys | caller_info が必要な4キーを持つ | なし | `file`・`path`・`line`・`subroutine` がすべて defined |
| at file is basename of path | file が path のベースネームと一致する | なし | `file eq basename(path)` |
| at excludes CommonIO internal frames | CommonIO.pm 内部フレームを含まない | なし | すべてのフレームで `file !~ /CommonIO\.pm$/` |
| at level 0 is test script | レベル 0 がテストスクリプトのフレーム | なし | `file =~ /commonio\.t$/` |

### pathcli 系

| テスト名 | 目的 | 前提条件 | 確認内容 |
|---|---|---|---|
| pathcli with string path returns path_spec | 文字列 path から path_spec を返す | なし | path・encoding・eol・layer が正しい値 |
| pathcli with hash path returns path_spec | ハッシュ path から path_spec を返す | なし | ハッシュのキー値が path_spec に反映される |
| pathcli resolves ? to > on first call | mode=? の初回は > に確定する | なし | layer が `>:encoding(utf8)` になる |
| pathcli resolves ? to >> on second call | mode=? の2回目は >> に確定する | out_file で1回書き込み済み | layer が `>>:encoding(utf8)` になる |
| pathcli rejects mode character in path | path に >・>>・? を渡すと例外 | なし | 「mode character」例外が発生する |

### out_file 系

| テスト名 | 目的 | 前提条件 | 確認内容 |
|---|---|---|---|
| out_file first call overwrites existing file | 初回呼び出しで既存ファイルを上書き | ファイルが存在する | read_file の結果が新しい内容のみ |
| out_file second call appends | 2回目は追記になる | なし | read_file の結果に1回目と2回目の内容が両方含まれる |
| out_file third call also appends | 3回目以降も追記 | なし | 3行分が順番に含まれる |
| out_file different paths are independent | 異なるパスのカウントは独立 | なし | 各パスで期待した内容のみ存在する |
| out_file accepts hash path with encoding and eol | ハッシュ形式のパス指定に対応 | なし | ハッシュ指定で書き込みと追記が正しく動作する |
| out_file scalar text is not changed by eol | スカラ content は eol 変換されない | なし | バイナリ読み取りで書いた文字列がそのまま保存される |
| out_file child process does not clear parent counts | fork 後の子プロセス終了で親のカウントが消えない | なし | 子プロセス実行後も親の2回目呼び出しが追記になる |
| out_file with mode > always overwrites | mode=`>` は毎回上書き | なし | 2回書いても2回目の内容だけ残る |
| out_file with mode >> always appends | mode=`>>` は毎回追記 | なし | 2回書いて両方の内容が残る |
| out_file with mode ? is overwrite then append | mode=`?` は初回上書き・2回目以降追記 | なし | 2回書いて両方の内容が残る |
| out_file rejects path that is a mode character | path に >・>>・? を渡すと例外 | なし | 「mode character」例外が発生する |
| out_file with encoding=>raw writes bytes as-is | encoding=raw でバイト列をそのまま書き込む | なし | バイナリ読み取りで同じバイト列が取得できる |

### read_file 系

| テスト名 | 目的 | 前提条件 | 確認内容 |
|---|---|---|---|
| read_file rejects unsupported encoding | サポート外エンコーディング（EUC-JP）を拒否 | ファイルが存在する | 「Unsupported file encoding」例外が発生する |
| read_file returns scalar text | スカラコンテキストで全文を返す | ファイルが存在する | 戻り値が書き込んだ文字列と一致する |
| read_file returns line array | リストコンテキストで行配列を返す | 3行のファイルが存在する | 配列の要素数が3で各行の内容が正しい |
| read_file normalizes CRLF to LF with eol=>lf | eol=lf 指定時に CRLF を LF へ正規化 | CRLF ファイルを raw モードで作成 | CR が含まれない／LF が含まれる |
| read_file normalizes to CRLF with eol=>crlf | eol=crlf 指定時にすべての改行を CRLF へ正規化 | 混在改行ファイルを raw モードで作成 | すべての行末が CRLF になる |
| read_file throws on missing file | 存在しないファイルを読むと例外 | ファイルが存在しない | 「Cannot read」例外が発生する |
| read_file reads CP932 file | CP932 で書いたファイルを同エンコーディングで読む | CP932 で書き込んだファイルが存在する | 読み取り結果が元の日本語文字列と一致する |
| read_file with hash path spec | ハッシュ形式のパス指定で読み込む | utf8+lf で書き込んだファイルが存在する | ハッシュ指定で日本語テキストが読める |
| read_file with encoding=>raw returns bytes as-is | encoding=raw でバイト列をそのまま返す | raw で書いたファイルが存在する | decode・正規化なしで同じバイト列が得られる |
| read_file with encoding=>raw in list context dies | encoding=raw でリストコンテキストは例外 | raw で書いたファイルが存在する | 「list context」例外が発生する |

### .do ファイル系（write_do / read_do）

| テスト名 | 目的 | 前提条件 | 確認内容 |
|---|---|---|---|
| write_do / read_do round-trip hash | ハッシュリファレンスの書き込みと読み返し | なし | HASH リファレンスが返り各キーの値が一致する |
| write_do / read_do round-trip array | 配列リファレンスの書き込みと読み返し | なし | ARRAY リファレンスが返り各要素が一致する |
| write_do / read_do preserves Unicode | Unicode 文字を含むデータの往復 | なし | 読み返しで日本語文字列が正しく取得できる |
| write_do ignores encoding option | hash path に encoding を渡しても無視 | なし | 例外なし／正常に書き込まれる |
| write_do ignores eol option | hash path に eol を渡しても無視 | なし | 例外なし／正常に書き込まれる |
| read_do throws on missing file | 存在しないファイルを読むと例外 | ファイルが存在しない | 「file not found or empty」または「Failed to read」例外 |
| read_do throws on syntax error file | 構文エラーのあるファイルを読むと例外 | 不正な Perl 構文のファイルが存在する | 「Failed to read」例外が発生する |
| read_do ignores encoding option | hash path に encoding を渡しても無視 | .do ファイルが存在する | 例外なし／正常に読み込まれる |
| read_do ignores eol option | hash path に eol を渡しても無視 | .do ファイルが存在する | 例外なし／正常に読み込まれる |

### dumpU8 系

| テスト名 | 目的 | 前提条件 | 確認内容 |
|---|---|---|---|
| dumpU8 preserves Unicode characters | Unicode 文字を `\x{}` 形式にエスケープせず出力 | なし | ダンプ文字列に漢字が含まれる／`\x{` が含まれない |
| dumpU8 with indent=>0 produces one line | indent=0 でワンライン出力 | なし | ダンプ文字列に改行が含まれない |

### dec 系

| テスト名 | 目的 | 前提条件 | 確認内容 |
|---|---|---|---|
| dec converts UTF-8 bytes to Perl string | utf8 バイト列を decode して内部文字列に変換 | なし | utf8 フラグが ON で正しい文字列が得られる |
| dec passes through already-decoded Perl string | 内部文字列はそのまま返す | なし | 入力と出力が同じ |
| dec passes through ASCII string | ASCII 文字列はそのまま返す | なし | 入力と出力が同じ |
| dec returns original on invalid UTF-8 | decode できないバイト列はそのまま返す | なし | 入力と同じバイト列が返る |
| dec returns undef for undef input | undef 入力は undef を返す | なし | 戻り値が undef |
| dec warns guess_encoding for non-UTF8 bytes | utf8 でないバイト列に guess_encoding 警告を出す | なし | `warn` に「guess_encoding」が含まれる |
| dec warns guess_encoding: unknown for unrecognizable bytes | 不明バイト列に unknown 警告を出す | なし | `warn` に「guess_encoding」が含まれる |

### dp 系

| テスト名 | 目的 | 前提条件 | 確認内容 |
|---|---|---|---|
| dp with no args outputs nothing | 引数なしは何もしない | なし | STDERR 出力が空、例外なし |
| dp with single ref passes ref directly | リファレンス1個はそのまま np に渡る | なし | hashref → STDERR 出力にハッシュ記法 `{` が含まれる |
| dp with scalar wraps in arrayref | 非リファレンスは `[@_]` に包まれる | なし | スカラ → STDERR 出力に配列記法 `[` が含まれる |
| dp with multiple args wraps in arrayref | 複数引数は `[@_]` に包まれる | なし | 複数引数 → STDERR 出力に配列記法 `[` が含まれる |
| dp with kanji does not die | 漢字を含む arrayref で例外が発生しない | なし | 例外なし |

### フォーク系（run_in_fork）

| テスト名 | 目的 | 前提条件 | 確認内容 |
|---|---|---|---|
| run_in_fork executes code in child | 子プロセスでクロージャが実行される | なし | 子プロセスがファイルを作成し、内容が正しい |
| run_in_fork throws when child throws | 子プロセスが例外を投げると親プロセスも例外を投げる | なし | 親プロセスで「confirm failed」例外が発生する |
