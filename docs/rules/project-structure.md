# Project Structure Rules

## Scope

- This file defines repository structure and file-reference rules.

## Repository Structure

- `src/`: implementation source files.
- `lib/`: external libraries brought from other projects, plus `*.spec.md` files that define how to use them.
- `docs/spec.md`: current specification and output contract.
- `docs/design/`: `design-concept.md`, which is the base design document. Spec and implementation must start from it, concretize it, and not diverge from it.
- `docs/superpowers/specs/`: session-level change specifications.
- `test/`: test suite.

## Reference Rules

- Before updating `docs/design/design-concept.md`, read `/Users/darong/PRJDEV/_shared/design-concept-instruction.md`.
- When referring to `lib/<Module>.pm`, read `lib/<Module>.spec.md` in the same directory first.
