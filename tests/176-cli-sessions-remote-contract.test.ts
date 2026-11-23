import { afterAll, beforeEach, describe, expect, test } from "bun:test";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
	EXIT,
	header,
	RemoteHarness,
	sessionID,
} from "./fixtures/sessions-remote-harness";

// The remote attach contract in _docs/01-architecture.md -> Persistent sessions
// -> Remote attach and _docs/04-security.md -> Remote Attach Threat Model, for
// the parts tests/172 leaves open: the exact ssh options on both connections,
// the ssh failure text the CLI classifies, the bytes it replays, what it hands
// ssh on stdin, and the remote command on the peer.

const harness = new RemoteHarness(mkdtempSync(join(tmpdir(), "yen-remote-c-")));
afterAll(() => rmSync(harness.root, { recursive: true, force: true }));
beforeEach(() => harness.next());

const list = ["list", "--porcelain", "--host", "mini"];
const attach = ["attach", "--host", "mini", sessionID];

describe("yen sessions --host: the remote command on the peer", () => {
	test.each(["relative/YEN.app", "/Users/dev/YEN copy.app", "/x;id/YEN.app"])(
		"YEN_REMOTE_APP %j is refused before ssh runs",
		(app) => {
			harness.plan(["1 0"], { 1: `${header}\n` });
			for (const args of [list, attach]) {
				const result = harness.sessions(args, { YEN_REMOTE_APP: app });
				expect(result.status).toBe(EXIT.usage);
				expect(result.stderr).toContain(
					"YEN_REMOTE_APP must be an absolute path",
				);
			}
			expect(harness.calls()).toEqual([]);
		},
	);
});
