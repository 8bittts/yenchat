import { expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";

const repoRoot = process.cwd();

test("lazygit vendor wrapper stays a pure vendor (no branding patch hooks)", () => {
	const script = readFileSync(
		join(repoRoot, "scripts/32-vendor-lazygit.sh"),
		"utf8",
	);

	expect(script.indexOf("vendor_binary \\")).toBeGreaterThan(-1);
	// The retired YEN branding patch must not be reintroduced.
	expect(script).not.toContain("PATCH_SCRIPT");
	expect(script).not.toContain("patch-lazygit-binary.sh");
	expect(script).not.toContain("VENDOR_BINARY_ALLOW_EXEC_FAILURE");
});
