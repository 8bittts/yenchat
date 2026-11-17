import { describe, expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";

const repoRoot = process.cwd();
const clearAppCachePath = join(
	repoRoot,
	"yen-terminal/customizations/clear-app-cache.sh",
);
describe("clear-app-cache contract", () => {
	test("targets installed app copies plus the current repo build", () => {
		const script = readFileSync(clearAppCachePath, "utf8");

		expect(script).toContain('if [ -d "/Applications/YEN.app" ]; then');
		expect(script).toContain('if [ -d "$HOME/Applications/YEN.app" ]; then');
		expect(script).toContain('pkill -f "$HOME/Applications/YEN.app"');
		expect(script).toContain(
			'LOCAL_BUILD_APP="$REPO_DIR/ghostty/zig-out/YEN.app"',
		);
		expect(script).toContain(
			'CURRENT_REPO_XCODE_BUILD_DIR="$REPO_DIR/ghostty/macos/build"',
		);
	});

	test("does not sweep generic Documents builds or prescribe bare yen init guidance", () => {
		const script = readFileSync(clearAppCachePath, "utf8");

		expect(script).not.toContain('find ~/Documents -name "YEN.app"');
		expect(script).not.toContain("yen init zsh");
		expect(script).not.toContain("yen init bash");
		expect(script).toContain("then rerun diagnose-yen-cli.sh.");
		expect(script).toContain("init $SHELL_TYPE");
	});

	test("touches the bundled shell integration files that are actually shipped", () => {
		const script = readFileSync(clearAppCachePath, "utf8");

		expect(script).toContain('touch "$shell_base/zsh/.zshenv"');
		expect(script).toContain('touch "$shell_base/zsh/yen-integration"');
		expect(script).toContain('touch "$shell_base/bash/yen.bash"');
		expect(script).toContain('touch "$shell_base/yen-welcome.sh"');
	});

	test("clears Sparkle appcast files with null-delimited find pipelines", () => {
		const script = readFileSync(clearAppCachePath, "utf8");

		expect(script).toContain(
			'find "$HOME/Library/Caches" -type f -iname "*appcast*" -ipath "*${bundle}*" -print0',
		);
		expect(script).toContain(
			'find "$HOME/Library/Application Support" -type f -iname "*appcast*" -ipath "*${bundle}*" -print0',
		);
		expect(script).toContain("xargs -0 rm -f");
		expect(script).not.toContain('grep -i "${bundle}" | xargs rm -f');
	});

	test("backs up config.yen before the wipe and restores it by default", () => {
		const script = readFileSync(clearAppCachePath, "utf8");

		// The backup must run AFTER step 1 terminates the app: YEN flushes its
		// debounced config writes on quit, so an earlier copy loses the last edit.
		const backupIndex = script.indexOf("[1b/20] Backing up user config...");
		const killIndex = script.indexOf("[1/20] Detecting and terminating");
		const wipeIndex = script.indexOf(
			"rm -rf ~/Library/Application\\ Support/${bundle}",
		);
		expect(backupIndex).toBeGreaterThan(killIndex);
		expect(wipeIndex).toBeGreaterThan(backupIndex);

		expect(script).toContain(
			'CONFIG_BACKUP_DIR="$HOME/Library/Application Support/yen-config-backups"',
		);
		expect(script).toContain(
			'CONFIG_BACKUP_PATH="$CONFIG_BACKUP_DIR/$(date +%Y%m%d-%H%M%S)"',
		);

		// A failed backup must abort rather than proceed into a destructive wipe.
		expect(script).toContain(
			"Backup FAILED — aborting so settings are not lost",
		);

		// The restore runs after the wipe and is opt-out via --fresh.
		const restoreIndex = script.indexOf("[restore] User config...");
		expect(restoreIndex).toBeGreaterThan(wipeIndex);
		expect(script).toContain("RESTORE_CONFIG=1");
		expect(script).toContain("--fresh)");
		expect(script).toContain(
			'cp "$CONFIG_BACKUP_PATH/config.yen" "$USER_CONFIG_PATH"',
		);

		// The old advice pointed at a path nothing ever created.
		expect(script).not.toContain("cp ~/backup/config.yen");
	});

	test("backgrounds travel with the config so no restored path dangles", () => {
		const script = readFileSync(clearAppCachePath, "utf8");

		// TerminalBackgroundImageStore copies the chosen image into backgrounds/ and
		// writes that path into config.yen. Restoring one without the other yields a
		// config pointing at a file the wipe deleted.
		expect(script).toContain(
			'USER_BACKGROUNDS_DIR="$HOME/Library/Application Support/com.yenchat.yen/backgrounds"',
		);
		expect(script).toContain(
			'cp -R "$USER_BACKGROUNDS_DIR/." "$CONFIG_BACKUP_PATH/backgrounds/"',
		);
		expect(script).toContain(
			'cp -R "$CONFIG_BACKUP_PATH/backgrounds/." "$USER_BACKGROUNDS_DIR/"',
		);

		// `cp -R src dst` nests when dst exists, so both copies must move CONTENTS
		// into a pre-made directory rather than the directory itself.
		expect(script).not.toContain(
			'cp -R "$USER_BACKGROUNDS_DIR" "$CONFIG_BACKUP_PATH/backgrounds"',
		);
		expect(script).not.toContain(
			'cp -R "$CONFIG_BACKUP_PATH/backgrounds" "$USER_BACKGROUNDS_DIR"',
		);

		// A failed image backup aborts: a restored config would dangle otherwise.
		expect(script).toContain("Background image backup FAILED — aborting");

		// Images must be on disk before the config that names them.
		const bgRestore = script.indexOf('  ✓ Restored background images"');
		const configRestore = script.indexOf(
			'  ✓ Restored config.yen (settings preserved)"',
		);
		expect(bgRestore).toBeGreaterThan(-1);
		expect(configRestore).toBeGreaterThan(bgRestore);
	});

	test("prunes old backups without touching the one just written", () => {
		const script = readFileSync(clearAppCachePath, "utf8");

		expect(script).toContain("CONFIG_BACKUP_KEEP=10");
		// Reverse sort puts newest first, so tail skips exactly the newest N.
		expect(script).toContain("sort -r | tail -n +$((CONFIG_BACKUP_KEEP + 1))");

		// Pruning must run after the restore, never before it.
		const restoreIndex = script.indexOf("[restore] User config...");
		const pruneIndex = script.indexOf("# Prune old backups");
		expect(pruneIndex).toBeGreaterThan(restoreIndex);
	});
});
