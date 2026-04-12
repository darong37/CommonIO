# CommonIO

[日本語版 README はこちら](README_ja.md)

CommonIO is a Perl module for file I/O without worrying about character encoding or line endings.

## Features

- Read and write files in UTF-8 or CP932 (Shift_JIS) — no manual `binmode` or `encode`/`decode`
- Flexible line-ending handling: `lf`, `crlf`, or `preserve`
- Perl data serialization via `.do` files (UTF-8 fixed)
- Logging to console and/or file (UTF-8 fixed)
- Console encoding setup for `STDOUT`/`STDERR`
- Unicode-safe `Data::Dumper` output
- Fork-safe subprocess execution with error propagation

## Usage

```perl
use lib 'src';
use CommonIO qw(write_file append_file read_file write_do read_do
                log setLogFile dying setup_console dumpU8 run_in_fork);
```

## API Overview

| API | Description |
|---|---|
| `write_file($path, $text\|$lines)` | Write or overwrite a file |
| `append_file($path, $text\|$lines)` | Append to a file |
| `read_file($path)` | Read a file (scalar: text, list: lines) |
| `write_do($path, $var)` | Save a Perl variable to a `.do` file |
| `read_do($path)` | Load a Perl variable from a `.do` file |
| `log($level, $msg)` | Log to STDERR (and optionally a file) |
| `setLogFile($path)` | Set log file destination |
| `dying($msg)` | Log error and throw with traceback |
| `setup_console($encoding)` | Set STDOUT/STDERR encoding |
| `dumpU8($var, %opts)` | Unicode-safe Data::Dumper output |
| `run_in_fork($code)` | Run code in a child process |

## path Specification

`$path` can be a string or a hashref:

```perl
# String — uses UTF-8 and lf (write) / preserve (read) by default
write_file('/tmp/out.txt', $text);

# Hashref — explicit encoding and eol
write_file({ path => '/tmp/out.txt', encoding => 'CP932', eol => 'crlf' }, $text);
```

| Key | Required | Default | Description |
|---|---|---|---|
| `path` | yes | — | File path |
| `encoding` | no | `UTF-8` | `UTF-8` or `CP932` only |
| `eol` | no | write: `lf` / read: `preserve` | Line ending handling |

## Fixed Encoding Policy

| API | Encoding |
|---|---|
| `setLogFile` / `log` | UTF-8 (not configurable) |
| `write_do` / `read_do` | UTF-8 (not configurable) |

## Running Tests

```
PERL5LIB=src:lib prove test/commonio.t
```

## Documentation

- [API Reference (Japanese)](docs/spec.md)
- [Test Specification (Japanese)](docs/test-spec.md)
