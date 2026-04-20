# CommonIO

[日本語版 README はこちら](README_ja.md)

CommonIO is a Perl module for file I/O without worrying about character encoding or line endings.

## Features

- Read and write files in UTF-8, CP932 (Shift_JIS), or raw — no manual `binmode` or `encode`/`decode`
- Flexible line-ending handling: `lf` or `crlf`
- Automatic `STDOUT`/`STDERR` encoding setup on `use CommonIO` (via `BEGIN` block)
- Perl data serialization via `.do` files (UTF-8 fixed)
- Logging to console and auto-determined file in `LOGDIR` (UTF-8 fixed)
- Unicode-safe `Data::Dumper` output
- Debug printing via `Data::Printer` with Unicode support
- Fork-safe subprocess execution with error propagation

## Requirements

> `LOGDIR` environment variable must be set. CommonIO writes logs to `$LOGDIR/<script><MMDDHHMM>.log`.

## Usage

```perl
use lib 'src';
use CommonIO qw(out_file pathcli read_file write_do read_do
                log at dying dumpU8 dec dp run_in_fork);
```

`use CommonIO` automatically sets `STDOUT`/`STDERR` encoding to match the locale (via `BEGIN` block).

## API Overview

| API | Description |
|---|---|
| `out_file($path, $content)` | Write to a file (overwrite on first call, append on subsequent calls) |
| `out_file($mode, $path, $content)` | Write with explicit mode: `>` overwrite, `>>` append, `?` auto |
| `pathcli($mode, $path)` | Resolve path and mode into a `path_spec` |
| `read_file($path)` | Read a file (scalar: text, list: lines) |
| `write_do($path, $var)` | Save a Perl variable to a `.do` file |
| `read_do($path)` | Load a Perl variable from a `.do` file |
| `log($level, $msg)` | Log to STDERR and auto-determined file in LOGDIR |
| `at()` | Return call stack as `callers` arrayref |
| `dying($msg)` | Log error and throw with traceback |
| `dumpU8($var, %opts)` | Unicode-safe Data::Dumper output |
| `dec($data)` | Decode UTF-8 bytes to Perl string, pass through if already decoded |
| `dp(@args)` | Print args to STDERR via Data::Printer |
| `run_in_fork($code)` | Run code in a child process |

## mode

| Value | Behavior |
|---|---|
| `>` | Always overwrite |
| `>>` | Always append |
| `?` | Overwrite on first call for this path, append thereafter |
| (omitted) | Same as `?` |

## path Specification

`$path` can be a string or a hashref:

```perl
# String — uses utf8 and lf by default
out_file('/tmp/out.txt', $text);

# Hashref — explicit encoding and eol
out_file({ path => '/tmp/out.txt', encoding => 'cp932', eol => 'crlf' }, $text);
```

| Key | Required | Default | Description |
|---|---|---|---|
| `path` | yes | — | File path |
| `encoding` | no | `utf8` | `utf8`, `cp932`, or `raw` |
| `eol` | no | `lf` | `lf` or `crlf` |

## Fixed Encoding Policy

| API | Encoding |
|---|---|
| `log` / log file | UTF-8 (not configurable) |
| `write_do` / `read_do` | UTF-8 (not configurable) |

## Running Tests

```
prove -lr test/
```

## Documentation

- [API Reference (Japanese)](docs/spec.md)
- [Test Specification (Japanese)](docs/test-spec.md)
