import { describe, expect, test } from "bun:test";
import { LIVE_CREDENTIAL_NAME } from "./01-preload";

// The operator shell exports provider keys (RESEND_API_KEY among them), and `bun test`
// inherits the shell. The preload must strip every credential-shaped name before any
// test file loads, so no test can reach a real provider by accident.
describe("test preload credential strip", () => {
	test("no credential-shaped variable survives into the test process", () => {
		const leaked = Object.keys(process.env).filter((name) =>
			LIVE_CREDENTIAL_NAME.test(name),
		);
		expect(leaked).toEqual([]);
	});

	test("the pattern covers the credential suffixes and spares build metadata", () => {
		for (const name of [
			"RESEND_API_KEY",
			"GITHUB_TOKEN",
			"CRON_SECRET",
			"STRIPE_SECRET_KEY",
			"DB_PASSWORD",
			"SUPABASE_SERVICE_ROLE_KEY",
		]) {
			expect(LIVE_CREDENTIAL_NAME.test(name), name).toBe(true);
		}
		for (const name of ["PATH", "HOME", "NODE_ENV", "VERCEL_GIT_COMMIT_SHA"]) {
			expect(LIVE_CREDENTIAL_NAME.test(name), name).toBe(false);
		}
	});
});
