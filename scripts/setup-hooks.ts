// Point Git at the tracked hooks so every clone and worktree runs .githooks/commit-msg and pre-push.
import { spawnSync } from "node:child_process";

const probe = spawnSync("git", ["rev-parse", "--is-inside-work-tree"], {
	stdio: "ignore",
});
if (probe.status !== 0) {
	process.exit(0);
}

const configure = spawnSync("git", ["config", "core.hooksPath", ".githooks"], {
	encoding: "utf8",
	stdio: ["ignore", "ignore", "pipe"],
});
if (configure.status !== 0) {
	throw new Error(configure.stderr.trim() || "Git refused the hooks path.");
}

console.info("[hooks] PASS — core.hooksPath is .githooks.");
