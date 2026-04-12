# CommonIO 仕様設計書

Date: 2026-04-12

## 背景・目的

CommonIO は Perl で文字コードや改行コードを都度気にせずに入出力できるようにするモジュールである。
ToDo に従い、以下の3つの成果物を「アプローチC（仕様書とテストを並行設計）」で作成する。

1. `docs/spec.md` — 利用者向けリファレンス（詳細版）
2. `test/commonio.t` — 網羅的テスト追加
3. `docs/test-spec.md` — テスト仕様書

---

## ToDo 1：確定事項

`src/CommonIO.pm` の実装と `docs/design/design-concept.md` の内容は一致しており、変更不要として確定。

---

## ToDo 2：`docs/spec.md` の構成

### 対象読者

CommonIO を利用するプログラマ。内部実装は知らなくてよい。

### 構成

```
# CommonIO

## インストール・使い方（use 宣言の例）

## 用語

## path 指定
  - 文字列の場合
  - ハッシュの場合（path / encoding / eol キー）
  - encoding の選択肢（UTF-8 / CP932）
  - eol の選択肢（lf / crlf / preserve）

## API リファレンス

### write_file
### append_file
### read_file
### write_do
### read_do
### log
### setLogFile
### dying
### setup_console
### dumpU8
### run_in_fork
```

### 各 API セクションの記述形式

| 項目 | 内容 |
|------|------|
| シグネチャ | `write_file($path, $text)` 形式 |
| 説明 | 何をするAPIか一文で |
| 引数 | 各引数の型・意味・省略可否 |
| 戻り値 | 返す値または「なし」 |
| 使用例 | 実際のコードスニペット（1〜2例） |
| エラー | どんなときに例外が発生するか |

---

## ToDo 3：`test/commonio.t` 追加テスト計画

アプローチC により、spec.md の各APIセクションを書いたら対応するテストも追加する。

### write_file / append_file / read_file

| テストケース | 確認内容 |
|---|---|
| write_file 基本 | 文字列をUTF-8で書き込み・read_fileで読み戻し一致 |
| write_file CRLF | `eol => 'crlf'` で書いたバイト列に `\r\n` が含まれること |
| write_file preserve | `eol => 'preserve'` で改行変換されないこと |
| write_file 配列 | `$lines`（ARRAY ref）を渡すと連結されて書き込まれること |
| write_file CP932 | `encoding => 'CP932'` でShift_JISバイト列になること |
| append_file | 既存ファイルの末尾に追記されること |
| read_file スカラ | テキスト全体が返ること |
| read_file リスト | 行配列が返ること |
| read_file LF正規化 | `eol => 'lf'` でCRLF/CRがLFに統一されること |
| read_file preserve | `eol => 'preserve'` でCRLFがそのまま残ること |
| read_file 不在 | 存在しないファイルで例外が発生すること |
| path ハッシュ指定 | `{ path => ..., encoding => ..., eol => ... }` 形式が動くこと |

### write_do / read_do

| テストケース | 確認内容 |
|---|---|
| ハッシュref の保存・復元 | 内容が一致すること |
| 配列ref の保存・復元 | 内容が一致すること |
| Unicode保持 | 日本語文字列が化けずに復元されること |
| read_do 不在 | 存在しないファイルで例外が発生すること |

### dumpU8

| テストケース | 確認内容 |
|---|---|
| Unicode保持 | `\x{...}` エスケープが展開された文字列になること |
| indent オプション | `indent => 0` で一行になること |

### setup_console

| テストケース | 確認内容 |
|---|---|
| UTF-8 設定 | `'UTF-8'` を渡すと `'UTF-8'` が返ること |
| CP932 設定 | `'CP932'` を渡すと `'CP932'` が返ること |
| 省略時 | 引数なしでも例外が出ないこと |
| 不正エンコーディング | サポート外の値で例外が発生すること |

### run_in_fork

| テストケース | 確認内容 |
|---|---|
| 正常実行 | コードブロックが子プロセスで実行されること（副作用で確認） |
| 子プロセス例外 | 子で例外が起きたとき親でも例外が発生すること |

---

## ToDo 4：`docs/test-spec.md` の構成

テストコードを書いた後に、内容を人が読める形でまとめるドキュメント。

### 構成

```
# CommonIO テスト仕様書

## テスト方針

## テスト環境・前提条件

## テストケース一覧

### ログ系（log / setLogFile / dying）
### ファイルIO系（write_file / append_file / read_file）
### .doファイル系（write_do / read_do）
### ダンプ系（dumpU8）
### コンソール系（setup_console）
### フォーク系（run_in_fork）
```

### 各テストケースの記述形式

| 項目 | 内容 |
|------|------|
| テスト名 | `subtest` の名前 |
| 目的 | 何を確認するか一文で |
| 前提条件 | ファイルの有無・状態など |
| 確認内容 | `ok` / `like` / `is` で何を検証するか |

---

## 実装順序（アプローチC）

1. `docs/spec.md` の `write_file` セクションを書く → `write_file` / `append_file` のテストを追加
2. `docs/spec.md` の `read_file` セクションを書く → `read_file` のテストを追加
3. `docs/spec.md` の `write_do` / `read_do` セクションを書く → テストを追加
4. `docs/spec.md` の `dumpU8` セクションを書く → テストを追加
5. `docs/spec.md` の `setup_console` セクションを書く → テストを追加
6. `docs/spec.md` の `run_in_fork` セクションを書く → テストを追加
7. `docs/spec.md` の残り（log / setLogFile / dying / 共通セクション）を完成させる
8. `docs/test-spec.md` を書く
