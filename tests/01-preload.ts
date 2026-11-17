// Bun test preload entrypoint.
// Keep this file present because bunfig.toml references it.

// [CRITICAL] A test process must never hold a live provider credential.
// `bun test` skips `.env.local` (NODE_ENV=test) but inherits the shell environment, and the
// operator shell exports RESEND_API_KEY globally. Measured: on a Monday UTC a since-removed
// owner-report route test found that key, sent a real production email, and consumed the
// day's idempotency key, so the scheduled send then failed with a 409.
// A test that needs a provider injects a fake client.
export const LIVE_CREDENTIAL_NAME =
	/(?:API_KEY|_TOKEN|_SECRET|SECRET_KEY|_PASSWORD|SERVICE_ROLE_KEY)$/;

for (const name of Object.keys(process.env)) {
	if (LIVE_CREDENTIAL_NAME.test(name)) delete process.env[name];
}

// Run the `yen ide verify` step harness in a non-login shell during tests. Production
// defaults to a login shell (so user toolchains via login profiles resolve), but in
// tests a login shell re-sources /etc/profile (path_helper) — slow and PATH-reordering,
// which both times out fixture steps and bypasses injected fake binaries. Tests that
// spawn the CLI inherit this via process.env. See yen-cli/lib/ide/verify-test.sh.
process.env.YEN_IDE_VERIFY_LOGIN_SHELL ??= "0";
