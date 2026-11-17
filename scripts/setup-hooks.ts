// Point Git at the tracked hooks so every clone and worktree runs .githooks/commit-msg and pre-push.
//
// The path is the MAIN checkout's .githooks, as an absolute path. core.hooksPath lives in the
// config every worktree shares, and a relative ".githooks" resolves inside each worktree, so a
// worktree checked out from an older commit would run that commit's hooks, which lack the
// pre-push guard against the private pre-open-source history.
import { spawnSync } from "node:child_process";
import { basename, dirname, join } from "node:path";

function git(args: string[]) {
	return spawnSync("git", args, {
		encoding: "utf8",
		stdio: ["ignore", "pipe", "pipe"],
	});
}

if (git(["rev-parse", "--is-inside-work-tree"]).status !== 0) {
	process.exit(0);
}

const commonDir = git([
	"rev-parse",
	"--path-format=absolute",
	"--git-common-dir",
]).stdout.trim();
const hooksPath =
	basename(commonDir) === ".git"
		? join(dirname(commonDir), ".githooks")
		: ".githooks";

const configure = git(["config", "core.hooksPath", hooksPath]);
if (configure.status !== 0) {
	throw new Error(configure.stderr.trim() || "Git refused the hooks path.");
}

console.info(`[hooks] PASS — core.hooksPath is ${hooksPath}.`);
