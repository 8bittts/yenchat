# YEN Tests

Behavior and release verification tests for YEN.

## Running Tests

```bash
bun test
bun run test:policy
bun run test:prod
bun run test:ide-integration
```

## Test Surfaces

- `bun test`: deterministic local behavior/runtime regressions in `tests/*.test.ts` and `tests/*.test.tsx`.
- `bun run test:policy`: editorial and shipped-data policy gates that should not run on every default test pass.
  Documentation-copy contracts live in `tests/154-documentation-contracts.policy.ts`.
- `bun run test:prod`: live production probes against `https://yen.chat` and the GitHub Release it points to.
- `bun run test:ide-integration`: opt-in managed-debugger, remote, and devcontainer IDE integration coverage in `tests/*.integration.ts`; it is not part of default `bun test` or `/update-yen`.

## Key Live Suites

- `tests/10-production.prod.ts`: download/update pipeline smoke checks.

## Philosophy

Only test silent breakage. If you'd notice it by visiting the site or from a failed workflow, it doesn't need a test.

Any test whose assertions live inside a loop over a discovered set — themes, personas, files, routes — must assert the set is non-empty before the loop.
Without that floor an input that goes missing or stops parsing collapses every assertion to zero and the test still reports PASS, which is worse than having no test.
`tests/76-theme-contrast-gates.test.ts` and `tests/125-lint-swift-view-modifiers.test.ts` carry the pattern.
The same rule applies to scripts that scan a tree: see the scanned-file floor in `scripts/41-lint-swift-view-modifiers.sh`.

Do not use `bun test` for source-text/doc-copy parity checks, editorial policy checks, or live production probes. Keep those in purpose-built verification scripts or separate entrypoints so the default suite stays focused on local behavior regressions.

The one carve-out is a **process guardrail**: a test that reads a shipped doc in order to prove a _gate_ still exists and still fails closed, not to police its wording.
`tests/119`/`tests/120` spawn the real vendor and release scripts and assert non-zero exits; the doc reads there exist because the `/update-yen` skill files ARE the executable procedure.
The line is intent — asserting a gate's behavior is in scope, asserting prose is not.
Two rules keep that carve-out honest: mirror-parity proves copies match each other and never that they match reality, so `tests/120` also resolves every `tests/` path those surfaces advertise against the real directory; and every such scan needs a per-surface non-empty floor, because one global counter lets a surface go silently empty.

Use `.integration.ts` only for process-spawning IDE coverage that is too slow or environment-sensitive for the default lane. Keep cheap unit/contract coverage in `.test.ts`.

`yen ide` tests create temps through `tests/fixtures/ide-temp.ts` (`createIdeTemp()`), never `mkdtempSync(join(tmpdir(), ...))`.
The harness deletes those directories after each test and tears down any process whose argv contains the path.
`tests/146-ide-temp-harness.test.ts` fails the suite if an ide test file goes back to raw `mkdtemp`.
The same call sets the time limits for the file: a 30-second default for each test and each cleanup hook, because Bun's 5-second default fails healthy CLI tests on a loaded machine.
A test that chains many CLI calls or waits on a daemon passes `IDE_CLI_SLOW_TEST_TIMEOUT_MS` as its `timeout`, never a number; `tests/170-cli-test-limits.test.ts` proves the limits and refuses a numeric one.

A test process never holds a live provider credential.
`bun test` skips `.env.local` but inherits the shell, and the operator shell exports `RESEND_API_KEY`; `tests/01-preload.ts` strips every credential-shaped variable before any file loads, and `tests/160-credential-strip.test.ts` asserts that strip.
A test that needs a provider injects a fake client, and a test whose behavior depends on `new Date()` pins the clock with `setSystemTime` — guarding only the assertion still runs the side effect, which is how a Monday run once sent a real production email.
