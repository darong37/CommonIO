# Perl Coding Rules

## Scope and Priority

- This file applies only during Perl implementation and editing work.
- If this file conflicts with `docs/design/design-concept.md`, `docs/design/design-concept.md` wins.
- Terms, API names, variable names, and argument names defined in `docs/design/design-concept.md` must be preserved exactly.
- Do not change user-specified identifiers, spelling, or case unless the user explicitly asks for that change.

## 1. Naming

- Naming must follow `docs/design/design-concept.md` Terms and API first.
- For local variable names not defined by Terms or API, follow the rules below.
- Variable names should be short and meaningful, ideally 3 to 4 characters.
- Use `idx` as the base name for position-like variables, and add a suffix that makes each role unique.
- Avoid `_` (`snake_case`) by default, but use it when a base concept from Terms or API needs a descriptive modifier in front of it, such as `log_path` for a specific kind of `path`.
- Use lowercase for small-scope variables.
- Use uppercase for external input and globals.
- New subroutine and function names must be lowercase unless `docs/design/design-concept.md` explicitly says otherwise.

## 2. Style

- Write Perl keywords in lowercase (`if`, `my`, `sub`).
- Write constants in uppercase.
- Keep indentation consistent with spaces.
- Prefer one operation per line.
- Avoid unnecessary parentheses.

## 3. Variable Use

- Do not use uninitialized variables.
- Do not design around `undef`; always provide a value.
- Do not reuse the same variable name for different meanings in one scope.
- Keep temporary variables to the minimum necessary.

## 4. Structure

- Keep one function responsible for one thing.
- Separate responsibilities at the subroutine level.
- Keep nesting to at most three levels.
- Minimize state changes inside loops.

## 5. Error Handling

- Detect every error.
- Use `die` and `warn` appropriately.
- Keep return-value meaning consistent.

## 6. Data Structures

- Make the purpose of arrays and hashes clear.
- Handle AoH and HoA with explicit structure.
- Keep key structure consistent across all elements.

## 7. DB / SQL

- Use lowercase for table and column names.
- Use uppercase for SQL keywords.
- Always use placeholders.
- Prefer batch or `COPY` for large data.

## 8. Performance

- Avoid unnecessary loops.
- Avoid repeated identical calculations; cache them.
- Assume large data should be processed in chunks.

## 9. Comments

- Code comments must be written in English.
- Comments should explain why.
- Write comments only for complex logic.
- Keep comments aligned with the implementation.
- Do not apply the English-only rule to user-facing documents unless another rule explicitly says so.

## 10. Prohibitions

- Do not hardcode magic numbers.
- Do not rely on implicit type conversion.
- Do not overuse globals.
- Do not use unclear shortcut implementations.
