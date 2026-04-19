# 変更仕様書：全 To Do 一括対応

日付：2026-04-19

## 変更スコープ

1. `_setup_console` 自動実行・内部ルーティン化
2. `out_file` mode 対応・`encoding => raw`・`write_file`/`append_file` 廃止
3. `dec` 改善（`Encode::Guess` による `guess_encoding`）
4. `dp` 出力経路の整理

---

## 1. `_setup_console` 自動実行・内部ルーティン化

### 変更内容

- `setup_console` を `_setup_console` にリネームする。
- `@EXPORT_OK` から削除し、外部公開しない内部ルーティンとする。
- 引数を受け取らない形にする。常に `I18N::Langinfo` の `langinfo(CODESET)` を使ってコンソールエンコーディングを決定する。
- `CommonIO.pm` 内の `BEGIN` ブロックで `_setup_console()` を1回呼ぶ。
- `BEGIN` ブロックは `$LOG_TARGET` 初期化ブロックよりも前に置く。
- `STDOUT`/`STDERR` への `binmode` 設定は `_setup_console` だけが行う。他の API はコンソール層を書き換えない。
- 戻り値は `console_encoding`（設定したエンコーディング名）。

### 前提

- モジュールは `%INC` により1回しかコンパイルされないため、`BEGIN` ブロックも1回だけ実行される。
- `_setup_console` を明示呼び出しする既存コードがある場合、実行時エラーで検出できる。その都度対応する。

---

## 2. `out_file` mode 対応・`encoding => raw`・`write_file`/`append_file` 廃止

### `out_file` の引数解釈

- 第1引数が `>`、`>>`、`?` のいずれかであれば `mode` として扱う。
- それ以外の第1引数は `path` として扱い、`mode` の既定値 `?` を適用する。
- `path`（文字列またはハッシュの `path` キー）に `>`、`>>`、`?` が含まれていた場合は `dying` でエラーにする。

### `mode` の動作

| mode | 動作 |
|---|---|
| `>` | 毎回上書き |
| `>>` | 毎回追記 |
| `?` | 同じ `path` への1回目は上書き、2回目以降は追記 |
| 省略 | `?` と同じ |

### `encoding => raw`

- `out_file` において `encoding => raw` を指定した場合、encode を行わず受け取った値をそのままバイト列としてファイルへ書き込む。
- `read_file` において `encoding => raw` を指定した場合、decode と改行正規化を行わず、読み込んだバイト列をそのまま返す。
- `read_file` で `encoding => raw` かつリストコンテキストの場合は `dying` でエラーにする。

### `write_file`/`append_file` の廃止

- `write_file` と `append_file` を `@EXPORT_OK` から削除する。
- サブルーティン定義自体も `src/CommonIO.pm` から削除する。
- `out_file` の内部実装は `_write_bytes` を直接使う形に整理する。
- 外部から呼ばれている場合は実行時エラーで検出できる。その都度対応する。

---

## 3. `dec` 改善（`Encode::Guess` による `guess_encoding`）

### 変更内容

- `dec($data)` の基本動作・戻り値は変えない（戻り値は `text`）。
- `is_utf8($data)` が false かつ utf-8 decode に失敗したとき、`Encode::Guess` で文字コードを推測する。
- 推測できた場合：`warn "guess_encoding: <name>\n"` を出す。
- 推測できなかった場合：`warn "guess_encoding: unknown\n"` を出す。
- いずれの場合も `data` をそのまま返す（例外にはしない）。
- `Encode::Guess` は `use Encode::Guess` で追加する。

### スコープ外

- 既存 API（`log` など）の引数を `dec` 経由に置き換える変更は今回含まない。

### 動作フロー

```
dec($data)
├─ $data が undef → そのまま返す
├─ is_utf8($data) が true → そのまま返す
├─ utf-8 decode 成功 → decode した text を返す
└─ utf-8 decode 失敗
   ├─ Encode::Guess で推測成功 → warn "guess_encoding: <name>" → $data をそのまま返す
   └─ 推測失敗 → warn "guess_encoding: unknown" → $data をそのまま返す
```

---

## 4. `dp` 出力経路の整理

### 変更内容

- `np()` の戻り値は Perl の内部文字列（`utf8::is_utf8 == 1`）である。
  - 根拠：`perl -Mutf8 -MData::Printer -e 'my $x = "日本語"; my $s = np($x); print utf8::is_utf8($s) ? "yes" : "no"'` → `yes`、`length($s) == 5`、`length(encode("utf-8", $s)) == 11`
- 現在の raw ハンドル経由の出力（`open my $raw_err, '>>&', \*STDERR; binmode $raw_err, ':raw'`）を削除する。
- `print STDERR $out` に置き換え、`_setup_console` が設定した STDERR のエンコード層に処理を委ねる（`log` と同じ方式）。

---

## テスト方針

### `_setup_console`

- `use CommonIO` 後に `STDOUT`/`STDERR` のエンコーディングが設定されていることを確認する。
- 2回目以降の `use CommonIO`（別ファイル）で重複実行されないことは `%INC` の仕組みで保証されるため、テスト不要。

### `out_file` mode 対応

| テストケース | 確認内容 |
|---|---|
| `out_file($path, $text)` x2 | 1回目は上書き、2回目は追記 |
| `out_file('>', $path, $text)` x2 | 毎回上書き |
| `out_file('>>', $path, $text)` x2 | 毎回追記 |
| `out_file('?', $path, $text)` x2 | 1回目は上書き、2回目は追記 |
| `path` に `>` を含む文字列 | `dying` が呼ばれる |

### `encoding => raw`

| テストケース | 確認内容 |
|---|---|
| `out_file({path=>..., encoding=>'raw'}, $bytes)` | バイト列がそのまま書き込まれる |
| `read_file({path=>..., encoding=>'raw'})` スカラ | バイト列がそのまま返る |
| `read_file({path=>..., encoding=>'raw'})` リストコンテキスト | `dying` が呼ばれる |

### `dec` 改善

| テストケース | 確認内容 |
|---|---|
| utf-8 decode 失敗のバイト列を渡す | `warn` が出て `data` がそのまま返る |
| CP932 バイト列を渡す | `guess_encoding` の warn が出る |

### `dp` 出力経路

- `dp` 呼び出しで例外が発生しないことを確認する（既存テストの継続）。

---

## 変更ファイル一覧

| ファイル | 変更種別 |
|---|---|
| `src/CommonIO.pm` | 修正（全4変更） |
| `test/commonio.t` | 修正（新規テストケース追加） |
