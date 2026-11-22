import { describe, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import {
	chmodSync,
	existsSync,
	mkdirSync,
	mkdtempSync,
	readFileSync,
	rmSync,
	writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

declare const Bun: {
	TOML: {
		parse: (source: string) => unknown;
	};
};

const repoRoot = process.cwd();
const keymapPath = join(
	repoRoot,
	"yen-terminal/customizations/yazi-config/keymap.toml",
);
const themePath = join(
	repoRoot,
	"yen-terminal/customizations/yazi-config/theme.toml",
);
const yaziConfigPath = join(
	repoRoot,
	"yen-terminal/customizations/yazi-config/yazi.toml",
);
const yaziArchiveNativePluginPath = join(
	repoRoot,
	"yen-terminal/customizations/yazi-config/plugins/archive-native.yazi/main.lua",
);
const yaziExtractNativePluginPath = join(
	repoRoot,
	"yen-terminal/customizations/yazi-config/plugins/extract-native.yazi/main.lua",
);
const yaziSvgNativePluginPath = join(
	repoRoot,
	"yen-terminal/customizations/yazi-config/plugins/svg-native.yazi/main.lua",
);
const yaziGitPluginPath = join(
	repoRoot,
	"yen-terminal/customizations/yazi-config/plugins/git.yazi/main.lua",
);
const yaziVideoNativePluginPath = join(
	repoRoot,
	"yen-terminal/customizations/yazi-config/plugins/video-native.yazi/main.lua",
);
const yaziPdfNativePluginPath = join(
	repoRoot,
	"yen-terminal/customizations/yazi-config/plugins/pdf-native.yazi/main.lua",
);
const yenVidThumbSourcePath = join(repoRoot, "yen-vidthumb/main.swift");
const yenPdfThumbSourcePath = join(repoRoot, "yen-pdfthumb/main.swift");
const yaziCodeGuardPluginPath = join(
	repoRoot,
	"yen-terminal/customizations/yazi-config/plugins/code-guard.yazi/main.lua",
);
const yaziInitLuaPath = join(
	repoRoot,
	"yen-terminal/customizations/yazi-config/init.lua",
);
const browsePath = join(repoRoot, "yen-terminal/customizations/bin/browse");
const quickLookPath = join(
	repoRoot,
	"yen-terminal/customizations/bin/yen-quicklook",
);
const yaziEditPath = join(
	repoRoot,
	"yen-terminal/customizations/bin/yen-yazi-edit",
);
const zshIntegrationPath = join(
	repoRoot,
	"yen-terminal/customizations/shell-integration/zsh/yen-integration.zsh",
);
const bashIntegrationPath = join(
	repoRoot,
	"yen-terminal/customizations/shell-integration/bash/yen-integration.bash",
);
const verifyComponentsScriptPath = join(
	repoRoot,
	"scripts/03-verify-components.sh",
);
const detectFailuresScriptPath = join(
	repoRoot,
	"scripts/05-detect-failures.sh",
);
const bundleResourcesScriptPath = join(
	repoRoot,
	"scripts/lib/bundle-resource-phases/03-binaries.sh",
);

const yaziTest = test;

const LEGACY_TOP_LEVEL_THEME_KEYS = ["completion"];
const LEGACY_MGR_THEME_KEYS = [
	"hovered",
	"tab_active",
	"tab_inactive",
	"tab_width",
];
const LEGACY_ICON_THEME_KEYS = ["prepend_rules", "append_rules"];

function parseToml(path: string) {
	return Bun.TOML.parse(readFileSync(path, "utf8")) as Record<string, unknown>;
}

function runLuaScript(script: string) {
	return spawnSync("lua", ["-"], {
		encoding: "utf8",
		input: script,
	});
}

function gitPluginLuaHarness(
	body: string,
	options?: { trackedDirLimit?: number },
) {
	const trackedDirLimit = options?.trackedDirLimit ?? 2048;
	return `
local function read_all(path)
  local handle = assert(io.open(path, "r"))
  local data = assert(handle:read("*a"))
  handle:close()
  return data
end

local source = read_all(${JSON.stringify(yaziGitPluginPath)})
source = source:gsub("local MAX_TRACKED_DIRS = 2048", "local MAX_TRACKED_DIRS = ${trackedDirLimit}", 1)
source = source:gsub(
  "return { setup = setup, fetch = fetch }",
  "return { setup = setup, fetch = fetch, __test = { add = add, remove = remove, CODES = CODES } }",
  1
)

local state = {}
ya = {
  target_family = function()
    return "unix"
  end,
  sync = function(fn)
    return function(...)
      return fn(state, ...)
    end
  end,
}
ui = {
  render = function() end,
  Style = function()
    return {
      fg = function(self, _)
        return self
      end,
    }
  end,
}
th = {}
Linemode = {
  children_add = function() end,
}

local plugin = assert(load(source, "@git.yazi"))()
plugin.setup(state, {})
local CODES = plugin.__test.CODES

${body}
`;
}

// Yazi 26.9's `fs.cha` takes a Url and raises on a string or a Path. A
// permissive stub hid three plugins that passed the wrong type, and every
// PDF, video and archive preview showed a Lua error. `statOf` is the Lua
// expression the stub returns.
function strictFsChaStub(statOf: string) {
	return `
local YaziUrl = {}
YaziUrl.__index = YaziUrl
YaziUrl.__tostring = function(self)
  return self.raw
end
Url = function(raw)
  return setmetatable({ raw = tostring(raw) }, YaziUrl)
end
fs = {
  cha = function(target)
    if getmetatable(target) ~= YaziUrl then
      error("bad argument #1: expected userdata of type 'UrlBuf', got " .. type(target))
    end
    return ${statOf}
  end,
}
`;
}

function codeGuardLuaHarness(body: string) {
	return `
local function read_all(path)
  local handle = assert(io.open(path, "r"))
  local data = assert(handle:read("*a"))
  handle:close()
  return data
end

local source = read_all(${JSON.stringify(yaziCodeGuardPluginPath)})
source = source:gsub(
  "return M",
  "return { peek = M.peek, seek = M.seek, __test = { build_plain_lines = build_plain_lines, should_use_plain = should_use_plain } }",
  1
)

ya = {
  emit = function() end,
  preview_widget = function() end,
}
ui = {
  Text = function(items)
    return {
      items = items,
      area = function(self, _)
        return self
      end,
    }
  end,
}
${strictFsChaStub("{ len = 0, mtime = 1, mode = 33188 }")}
cx = {
  active = {
    preview = { skip = 0 },
  },
}

local plugin = assert(load(source, "@code-guard.yazi"))()

${body}
`;
}

function videoPluginLuaHarness(body: string) {
	return `
local function read_all(path)
  local handle = assert(io.open(path, "r"))
  local data = assert(handle:read("*a"))
  handle:close()
  return data
end

local source = read_all(${JSON.stringify(yaziVideoNativePluginPath)})
source = source:gsub(
  "return M",
  "return { __test = { duration_for = duration_for } }",
  1
)

current_stat = { len = 1, mtime = 2, mode = 33188 }
output_calls = 0

${strictFsChaStub("current_stat")}

Command = setmetatable({ PIPED = "piped" }, {
  __call = function(_, _)
    return {
      arg = function(self, _)
        return self
      end,
      stdout = function(self, _)
        return self
      end,
      stderr = function(self, _)
        return self
      end,
      output = function(self)
        output_calls = output_calls + 1
        return { status = { success = true }, stdout = "120.00" }
      end,
    }
  end,
})

local plugin = assert(load(source, "@video-native.yazi"))()

${body}
`;
}

function pdfPluginLuaHarness(body: string) {
	return `
local function read_all(path)
  local handle = assert(io.open(path, "r"))
  local data = assert(handle:read("*a"))
  handle:close()
  return data
end

local source = read_all(${JSON.stringify(yaziPdfNativePluginPath)})
source = source:gsub(
  "return M",
  "return { __test = { page_count = page_count } }",
  1
)

current_stat = { len = 1, mtime = 2, mode = 33188 }
output_calls = 0

${strictFsChaStub("current_stat")}

Command = setmetatable({ PIPED = "piped" }, {
  __call = function(_, _)
    return {
      arg = function(self, _)
        return self
      end,
      stdout = function(self, _)
        return self
      end,
      stderr = function(self, _)
        return self
      end,
      output = function(self)
        output_calls = output_calls + 1
        return { status = { success = true }, stdout = "12\\n" }
      end,
    }
  end,
})

local plugin = assert(load(source, "@pdf-native.yazi"))()

${body}
`;
}

function assertNoLegacyThemeKeys(theme: Record<string, unknown>) {
	for (const key of LEGACY_TOP_LEVEL_THEME_KEYS) {
		expect(theme).not.toHaveProperty(key);
	}

	expect(theme).toHaveProperty("cmp");
	expect(theme).toHaveProperty("tabs");
	expect(theme).toHaveProperty("indicator");

	const mgr = (theme.mgr ?? {}) as Record<string, unknown>;
	for (const key of LEGACY_MGR_THEME_KEYS) {
		expect(mgr).not.toHaveProperty(key);
	}

	const icon = (theme.icon ?? {}) as Record<string, unknown>;
	for (const key of LEGACY_ICON_THEME_KEYS) {
		expect(icon).not.toHaveProperty(key);
	}

	const filetype = (theme.filetype ?? {}) as Record<string, unknown>;
	const rules = (filetype.rules ?? []) as Record<string, unknown>[];
	for (const rule of rules) {
		expect(rule).not.toHaveProperty("name");
	}
}

describe("Yazi edit/reveal wiring", () => {
	yaziTest("uses hovered-file placeholders for shell keybindings", () => {
		const keymap = readFileSync(keymapPath, "utf8");
		expect(keymap).toContain("%h");
		expect(keymap).not.toContain('"$0"');
		expect(keymap).toContain("shell --block -- yen-yazi-edit %h");
		expect(keymap).not.toContain("shell --block -- ${EDITOR:-vi} %h");
		expect(keymap).toContain('on = "e"');
		expect(keymap).toContain("open -R -- %h");
		expect(keymap).toContain("open -- %h");
		expect(keymap).toContain("yen-quicklook %h >/dev/null 2>&1");
		expect(keymap).not.toContain("qlmanage -p %h >/dev/null");
		expect(keymap).not.toContain("&>/dev/null");
		expect(keymap).not.toContain("killall qlmanage");
	});

	yaziTest("keeps core shortcuts without command-palette leakage", () => {
		const keymap = readFileSync(keymapPath, "utf8");
		expect(keymap).toContain('on = ["g", "o"]');
		expect(keymap).toContain('on = ["g", "r"]');
		expect(keymap).toContain('on = "<Space>"');
		expect(keymap).toContain('on = "<Tab>"');
		expect(keymap).toContain('on = "e"');
		expect(keymap).toContain('on = "?"');
		expect(keymap).toContain('on = "~"');
		expect(keymap).not.toContain("Cmd + Shift + O");
		expect(keymap).not.toContain("yen gh");
		expect(keymap).not.toContain("plugin gh");
	});

	yaziTest(
		"keeps explicit edit opener for open-with and bulk edit flows",
		() => {
			const config = readFileSync(yaziConfigPath, "utf8");
			expect(config).toContain("[opener]");
			expect(config).toContain('edit = [{ run = "yen-yazi-edit %s"');
			expect(config).toContain('{ url = "bulk-create.txt", use = "edit" }');
			expect(config).toContain('{ url = "bulk-rename.txt", use = "edit" }');
		},
	);

	yaziTest("registers all custom plugins in prepend_previewers", () => {
		const config = readFileSync(yaziConfigPath, "utf8");
		for (const plugin of [
			"archive-native",
			"code-guard",
			"video-native",
			"pdf-native",
			"svg-native",
		]) {
			expect(config).toContain(`run = "${plugin}"`);
		}
	});

	yaziTest(
		"routes .svgz to the SVG previewer ahead of the archive rule",
		() => {
			// A .svgz file has the mime type application/gzip, and Yazi runs the
			// first matching rule, so the SVG rule must come before the archive
			// rule that matches gzip.
			const config = readFileSync(yaziConfigPath, "utf8");
			const previewers = config.slice(
				config.indexOf("prepend_previewers"),
				config.indexOf("prepend_preloaders"),
			);
			const svgz = previewers.indexOf('{ url = "*.svgz", run = "svg-native" }');
			const gzipArchive = previewers.search(
				/\{ mime = "application\/\{[^}]*\bgzip\b[^}]*\}", run = "archive-native" \}/,
			);
			expect(svgz).toBeGreaterThanOrEqual(0);
			expect(gzipArchive).toBeGreaterThanOrEqual(0);
			expect(svgz).toBeLessThan(gzipArchive);
		},
	);

	yaziTest("wires view opener for Enter = read-only system pager", () => {
		const config = readFileSync(yaziConfigPath, "utf8");
		expect(config).toContain('view = [{ run = "less -R -+F -- %s"');
		expect(config).toContain(
			'{ mime = "text/*", use = [ "view", "edit", "reveal" ] }',
		);
	});

	yaziTest("restricts mouse events to avoid motion capture", () => {
		const config = readFileSync(yaziConfigPath, "utf8");
		expect(config).toContain('mouse_events = ["click", "scroll", "touch"]');
	});

	yaziTest("routes ndjson through code-guard for large file protection", () => {
		const config = readFileSync(yaziConfigPath, "utf8");
		expect(config).toContain("ndjson");
		expect(config).toContain("x-ndjson");
		const previewerSection = config.slice(config.indexOf("prepend_previewers"));
		expect(previewerSection).toContain("ndjson");
		// Yazi v25.12.29 renamed `name` to `url` for previewer/preloader rules
		// to support virtual file system URLs.
		expect(previewerSection).toContain('url = "*.ndjson"');
		expect(previewerSection).not.toContain('name = "*.ndjson"');
	});
});

describe("Yazi theme schema compatibility", () => {
	yaziTest("static theme omits legacy keys and keeps git section", () => {
		const theme = parseToml(themePath);
		assertNoLegacyThemeKeys(theme);
		expect(theme).toHaveProperty("git");
	});
});

describe("Yazi shell launch parity", () => {
	yaziTest(
		"routes y() launches through the browse wrapper in both shells",
		() => {
			const zshIntegration = readFileSync(zshIntegrationPath, "utf8");
			const bashIntegration = readFileSync(bashIntegrationPath, "utf8");

			expect(zshIntegration).toContain(
				'local browse_bin="$resources/bin/browse"',
			);
			expect(zshIntegration).toContain("setopt localtraps");
			expect(zshIntegration).toContain('"$browse_bin" "$@" --cwd-file="$tmp"');
			expect(bashIntegration).toContain(
				'local browse_bin="$resources/bin/browse"',
			);
			expect(bashIntegration).toContain('"$browse_bin" "$@" --cwd-file="$tmp"');
			expect(zshIntegration).not.toContain("trap 'rm -f -- \"$tmp\"' EXIT");
			expect(zshIntegration).toContain("return $y_status");
			expect(bashIntegration).toContain('return "$y_status"');
		},
	);

	yaziTest("browse wrapper sets config home and PATH", () => {
		const browse = readFileSync(browsePath, "utf8");
		expect(browse).toContain("export YAZI_CONFIG_HOME");
		expect(browse).toContain('export PATH="$SCRIPT_DIR:$PATH"');
		expect(browse).toContain('exec "$SCRIPT_DIR/yazi" "$@"');
	});

	yaziTest("quick look wrapper avoids direct qlmanage on AV media", () => {
		const quicklook = readFileSync(quickLookPath, "utf8");
		expect(quicklook).toContain('qlmanage -p -- "$target"');
		expect(quicklook).toContain("public.movie");
		expect(quicklook).toContain("public.video");
		expect(quicklook).toContain("public.audio");
		expect(quicklook).toContain('exec open -- "$target"');
	});

	yaziTest(
		"editor wrapper sets micro session flags for wrapped, gutter-free editing",
		() => {
			const yaziEdit = readFileSync(yaziEditPath, "utf8");
			expect(yaziEdit).toContain('editor_cmd="${EDITOR:-vi}"');
			expect(yaziEdit).toContain('if [ "$editor_name" = "micro" ]; then');
			expect(yaziEdit).toContain("editor_handoff_split_command");
			expect(yaziEdit).toContain("-ruler false");
			expect(yaziEdit).toContain("-softwrap true");
			expect(yaziEdit).toContain("-wordwrap true");
			expect(yaziEdit).toContain('-- "$@"');
		},
	);

	yaziTest(
		"verification gates enforce micro wrap/ruler flags in editor wrapper",
		() => {
			const verifyComponents = readFileSync(verifyComponentsScriptPath, "utf8");
			const detectFailures = readFileSync(detectFailuresScriptPath, "utf8");
			expect(verifyComponents).toContain("YAZI_EDIT_WRAPPER");
			expect(verifyComponents).toContain("-ruler false");
			expect(verifyComponents).toContain("-softwrap true");
			expect(verifyComponents).toContain("-wordwrap true");
			expect(detectFailures).toContain(
				'if [ -f "$RESOURCES/bin/yen-yazi-edit" ]; then',
			);
			expect(detectFailures).toContain("-ruler false");
			expect(detectFailures).toContain("-softwrap true");
			expect(detectFailures).toContain("-wordwrap true");
		},
	);
});

describe("Bundled editor handoff resources", () => {
	yaziTest(
		"keeps the bundled yen CLI beside yen-yazi-edit for native editor bridging",
		() => {
			const bundleScript = readFileSync(bundleResourcesScriptPath, "utf8");
			expect(bundleScript).toContain(
				'cp -pf "$YEN_CLI_DIR/bin/yen" "$APP_PATH/Contents/Resources/bin/"',
			);
			expect(
				readFileSync(
					join(repoRoot, "scripts/lib/bundle-resource-phases/04-yazi.sh"),
					"utf8",
				),
			).toContain(
				'cp -pf "$YAZI_EDIT_SCRIPT" "$APP_PATH/Contents/Resources/bin/"',
			);
		},
	);

	yaziTest(
		"bundled vendor binaries use a shared copy helper while keeping yazi and lazygit assertions explicit",
		() => {
			const bundleScript = readFileSync(bundleResourcesScriptPath, "utf8");

			expect(bundleScript).toContain("bundle_vendor_bin()");
			expect(bundleScript).toContain(
				'cp -pf "$source_path" "$APP_PATH/Contents/Resources/bin/"',
			);
			expect(bundleScript).toContain('chmod 755 "$dest_path"');
			for (const binary of [
				"fd",
				"rg",
				"lazygit",
				"btop",
				"fastfetch",
				"zmx",
			]) {
				expect(bundleScript).toContain(`bundle_vendor_bin "$`);
				expect(bundleScript).toContain(`" "${binary}"`);
			}
			for (const retired of ["fzf", "zoxide", "bat", "jq", "delta", "resvg"]) {
				expect(bundleScript).not.toContain(`" "${retired}"`);
			}
			expect(bundleScript).toContain(
				"ERROR: Yazi companion binary not found at $YAZI_VENDOR_DIR/ya",
			);
			expect(bundleScript).toContain(
				'LC_ALL=C grep -aFq "YEN loves:" "$APP_PATH/Contents/Resources/bin/lazygit"',
			);
			expect(bundleScript).toContain(
				"ERROR: lazygit binary contains the retired YEN branding patch",
			);
		},
	);
});

describe("Yazi edit wrapper runtime", () => {
	yaziTest("preserves quoted EDITOR argv and guards leading-dash paths", () => {
		const tempDir = mkdtempSync(join(tmpdir(), "yen-yazi-edit-"));
		try {
			const logPath = join(tempDir, "argv.log");
			const editorDir = join(tempDir, "Editor Bin");
			mkdirSync(editorDir);

			const mockEditorPath = join(editorDir, "mock-editor");
			writeFileSync(
				mockEditorPath,
				'#!/bin/bash\nprintf "%s\\n" "$0" "$@" > "$YEN_YAZI_EDIT_LOG"\n',
			);
			chmodSync(mockEditorPath, 0o755);

			const targetPath = join(tempDir, "-leading-dash.txt");
			writeFileSync(targetPath, "hello\n");

			const result = spawnSync(yaziEditPath, [targetPath], {
				encoding: "utf8",
				env: {
					...process.env,
					EDITOR: `"${mockEditorPath}" --wait`,
					YEN_YAZI_EDIT_LOG: logPath,
				},
			});

			expect(result.error).toBeUndefined();
			expect(result.status).toBe(0);
			expect(readFileSync(logPath, "utf8").trim().split("\n")).toEqual([
				mockEditorPath,
				"--wait",
				"--",
				targetPath,
			]);
		} finally {
			rmSync(tempDir, { force: true, recursive: true });
		}
	});

	yaziTest("adds micro session flags before forwarded file args", () => {
		const tempDir = mkdtempSync(join(tmpdir(), "yen-yazi-micro-"));
		try {
			const logPath = join(tempDir, "micro-argv.log");
			const mockEditorPath = join(tempDir, "micro");
			writeFileSync(
				mockEditorPath,
				'#!/bin/bash\nprintf "%s\\n" "$0" "$@" > "$YEN_YAZI_EDIT_LOG"\n',
			);
			chmodSync(mockEditorPath, 0o755);

			const targetPath = join(tempDir, "-micro-target.txt");
			writeFileSync(targetPath, "hello\n");

			const result = spawnSync(yaziEditPath, [targetPath], {
				encoding: "utf8",
				env: {
					...process.env,
					EDITOR: `"${mockEditorPath}"`,
					YEN_YAZI_EDIT_LOG: logPath,
				},
			});

			expect(result.error).toBeUndefined();
			expect(result.status).toBe(0);
			expect(readFileSync(logPath, "utf8").trim().split("\n")).toEqual([
				mockEditorPath,
				"-ruler",
				"false",
				"-softwrap",
				"true",
				"-wordwrap",
				"true",
				"--",
				targetPath,
			]);
		} finally {
			rmSync(tempDir, { force: true, recursive: true });
		}
	});

	yaziTest(
		"treats EDITOR metacharacters as literal argv instead of evaluating them",
		() => {
			const tempDir = mkdtempSync(join(tmpdir(), "yen-yazi-literal-"));
			try {
				const logPath = join(tempDir, "literal-argv.log");
				const sideEffectPath = join(tempDir, "should-not-exist");
				const mockEditorPath = join(tempDir, "mock-editor");
				writeFileSync(
					mockEditorPath,
					'#!/bin/bash\nprintf "%s\\n" "$0" "$@" > "$YEN_YAZI_EDIT_LOG"\n',
				);
				chmodSync(mockEditorPath, 0o755);

				const targetPath = join(tempDir, "target.txt");
				writeFileSync(targetPath, "hello\n");

				const result = spawnSync(yaziEditPath, [targetPath], {
					encoding: "utf8",
					env: {
						...process.env,
						EDITOR: `"${mockEditorPath}" ; touch ${sideEffectPath}`,
						YEN_YAZI_EDIT_LOG: logPath,
					},
				});

				expect(result.error).toBeUndefined();
				expect(result.status).toBe(0);
				expect(readFileSync(logPath, "utf8").trim().split("\n")).toEqual([
					mockEditorPath,
					";",
					"touch",
					sideEffectPath,
					"--",
					targetPath,
				]);
				expect(existsSync(sideEffectPath)).toBe(false);
			} finally {
				rmSync(tempDir, { force: true, recursive: true });
			}
		},
	);

	yaziTest("fails closed when EDITOR cannot be parsed", () => {
		const tempDir = mkdtempSync(join(tmpdir(), "yen-yazi-bad-editor-"));
		try {
			const targetPath = join(tempDir, "target.txt");
			writeFileSync(targetPath, "hello\n");

			const result = spawnSync(yaziEditPath, [targetPath], {
				encoding: "utf8",
				env: {
					...process.env,
					EDITOR: '"unterminated',
				},
			});

			expect(result.error).toBeUndefined();
			expect(result.status).toBe(1);
			expect(`${result.stderr ?? ""}`).toContain(
				"Unable to parse editor command",
			);
		} finally {
			rmSync(tempDir, { force: true, recursive: true });
		}
	});
});

describe("Yazi init and plugin loading", () => {
	yaziTest("loads git plugin with pcall resilience wrapper", () => {
		const initLua = readFileSync(yaziInitLuaPath, "utf8");
		expect(initLua).toContain('pcall(function() require("git"):setup() end)');
	});
});

describe("Yazi plugin hardening", () => {
	yaziTest("keeps archive parsing bounded and cacheable", () => {
		const archivePlugin = readFileSync(yaziArchiveNativePluginPath, "utf8");
		expect(archivePlugin).toContain("indexed_limit_reached");
		expect(archivePlugin).toContain("MAX_INDEXED_ENTRIES = 5000");
		expect(archivePlugin).toContain("ARCHIVE_LIST_CACHE_LIMIT = 128");
		expect(archivePlugin).toContain("archive_list_cache");
		expect(archivePlugin).toContain("list_archive_cached");
	});

	yaziTest(
		"strips __MACOSX metadata and cleans temp dirs during native extraction",
		() => {
			const extractPlugin = readFileSync(yaziExtractNativePluginPath, "utf8");
			expect(extractPlugin).toContain("metadata_dir");
			expect(extractPlugin).toContain(
				'fs.remove("dir_all", Url(metadata_dir))',
			);
			expect(extractPlugin).toContain("YEN_ALLOW_INSECURE_ARCHIVE_PASSPHRASE");
			expect(extractPlugin).toContain("cleanup_tmp_dir");
			expect(extractPlugin).toContain("rename_or_cleanup");
			expect(extractPlugin).toContain(
				"Encrypted archives are blocked by default",
			);
		},
	);

	yaziTest(
		"reuses archive listings until the archive file stamp changes",
		() => {
			const result = runLuaScript(`
${strictFsChaStub("current_stat")}
current_stat = { len = 1, mtime = 2, mode = 33188 }
local plugin = dofile(${JSON.stringify(yaziArchiveNativePluginPath)})
local calls = 0
plugin.list_archive = function(_)
  calls = calls + 1
  return { "entry" }, nil
end
plugin.list_archive_cached("/tmp/archive.zip")
plugin.list_archive_cached("/tmp/archive.zip")
if calls ~= 1 then
  error("expected cached archive listing, got " .. tostring(calls))
end
current_stat = { len = 2, mtime = 3, mode = 33188 }
plugin.list_archive_cached("/tmp/archive.zip")
if calls ~= 2 then
  error("expected cache bust after stat change, got " .. tostring(calls))
end
`);

			expect(result.error).toBeUndefined();
			expect(result.status).toBe(0);
		},
	);

	yaziTest(
		"renders only the visible archive slice for the preview widget",
		() => {
			const result = runLuaScript(`
local captured = nil
ya = {
  preview_widget = function(_, widget)
    captured = widget
  end,
  emit = function() end,
}
ui = {
  Text = function(items)
    return {
      items = items,
      area = function(self, _)
        return self
      end,
    }
  end,
  Line = function(parts)
    return parts
  end,
  truncate = function(value, _)
    return value
  end,
  width = function(_)
    return 0
  end,
}
File = function(_)
  return {
    icon = function()
      return nil
    end,
  }
end
Url = function(value)
  return value
end
Cha = function(value)
  return value
end

local plugin = dofile(${JSON.stringify(yaziArchiveNativePluginPath)})
plugin.list_archive_cached = function(_)
  local files = {}
  for i = 1, 20 do
    files[i] = { path = { name = "file" .. i }, depth = 0, is_dir = false }
  end
  return files, nil
end

plugin:peek({
  area = { h = 5, w = 80 },
  skip = 10,
  file = { path = "/tmp/archive.zip", url = "/tmp/archive.zip" },
})

if not captured or not captured.items then
  error("expected archive preview widget to be captured")
end
if #captured.items ~= 5 then
  error("expected 5 visible rows, got " .. tostring(#captured.items))
end
if captured.items[1][3] ~= "file11" or captured.items[5][3] ~= "file15" then
  error("expected preview slice to start at file11 and end at file15")
end
`);

			expect(result.error).toBeUndefined();
			expect(result.status).toBe(0);
		},
	);

	yaziTest("cleans extraction temp dirs when the final move fails", () => {
		const result = runLuaScript(`
local removed = {}
fs = {
  remove = function(_, target)
    table.insert(removed, tostring(target))
  end
}
os.rename = function()
  return false
end
local plugin = dofile(${JSON.stringify(yaziExtractNativePluginPath)})
local ok = pcall(function()
  plugin:rename_or_cleanup("/tmp/source", "/tmp/target", "/tmp/staging")
end)
if ok then
  error("expected rename failure")
end
if #removed ~= 1 or removed[1] ~= "/tmp/staging" then
  error("expected temp-dir cleanup before failure")
end
`);

		expect(result.error).toBeUndefined();
		expect(result.status).toBe(0);
	});

	yaziTest("surfaces SVG preview failures to logs/UI", () => {
		const svgPlugin = readFileSync(yaziSvgNativePluginPath, "utf8");
		expect(svgPlugin).toContain("ya.err(err)");
		expect(svgPlugin).toContain("SVG preview unavailable");
	});

	yaziTest("tracks git repo references without O(n) eviction scans", () => {
		const gitPlugin = readFileSync(yaziGitPluginPath, "utf8");
		expect(gitPlugin).toContain("repo_refcount");
		expect(gitPlugin).toContain("path_owners");
		expect(gitPlugin).not.toContain("for _, tracked_repo in pairs(st.dirs)");
	});

	yaziTest(
		"prunes stale git status paths when a directory scope refreshes",
		() => {
			const result = runLuaScript(
				gitPluginLuaHarness(`
local add = plugin.__test.add
add("/repo/src", "/repo", {
  ["src/alpha.txt"] = CODES.modified,
  ["src/beta.txt"] = CODES.added,
})
add("/repo/src", "/repo", {
  ["src/beta.txt"] = CODES.added,
})

if state.repos["/repo"]["src/alpha.txt"] ~= nil then
  error("expected stale path state to be pruned on refresh")
end
if state.repos["/repo"]["src/beta.txt"] ~= CODES.added then
  error("expected live path state to remain after refresh")
end
if state.path_owners["/repo"] and state.path_owners["/repo"]["src/alpha.txt"] ~= nil then
  error("expected stale path ownership to be released")
end
`),
			);

			expect(result.error).toBeUndefined();
			expect(result.status).toBe(0);
		},
	);

	yaziTest(
		"recomputes shared git status paths when one owner refreshes",
		() => {
			const result = runLuaScript(
				gitPluginLuaHarness(`
local add = plugin.__test.add
add("/repo", "/repo", { ["src"] = CODES.modified })
add("/repo/src", "/repo", { ["src"] = CODES.added, ["src/file.lua"] = CODES.added })
add("/repo", "/repo", {})

if state.repos["/repo"]["src"] ~= CODES.added then
  error("expected shared path to fall back to remaining owner")
end
if state.repos["/repo"]["src/file.lua"] ~= CODES.added then
  error("expected nested path to remain owned by child scope")
end
`),
			);

			expect(result.error).toBeUndefined();
			expect(result.status).toBe(0);
		},
	);

	yaziTest(
		"eviction clears ignored directory markers with their owning scope",
		() => {
			const result = runLuaScript(
				gitPluginLuaHarness(
					`
local add = plugin.__test.add
add("/repo/a", "/repo", { ["ignored-a"] = CODES.excluded, ["dir-a/file.lua"] = CODES.modified })
add("/repo/b", "/repo", {})
add("/repo/c", "/repo", {})
add("/repo/d", "/repo", {})

if state.dirs["/repo/a"] ~= nil then
  error("expected oldest scope to be evicted")
end
if state.dirs["ignored-a"] ~= nil then
  error("expected ignored marker to be removed with evicted scope")
end
if state.repos["/repo"]["dir-a/file.lua"] ~= nil then
  error("expected evicted scope path state to be removed")
end
`,
					{ trackedDirLimit: 3 },
				),
			);

			expect(result.error).toBeUndefined();
			expect(result.status).toBe(0);
		},
	);

	yaziTest(
		"remove() clears ignored directory markers owned by the scope",
		() => {
			const result = runLuaScript(
				gitPluginLuaHarness(`
local add = plugin.__test.add
local remove = plugin.__test.remove
add("/repo", "/repo", { ["ignored-dir"] = CODES.excluded, ["src"] = CODES.modified })
remove("/repo")

if state.dirs["ignored-dir"] ~= nil then
  error("expected ignored marker cleanup on remove")
end
if state.repos["/repo"] ~= nil then
  error("expected repo state cleanup on remove")
end
`),
			);

			expect(result.error).toBeUndefined();
			expect(result.status).toBe(0);
		},
	);

	yaziTest("evicts native media cache entries without self-skip guard", () => {
		const videoPlugin = readFileSync(yaziVideoNativePluginPath, "utf8");
		const pdfPlugin = readFileSync(yaziPdfNativePluginPath, "utf8");
		expect(videoPlugin).not.toContain("evicted ~= nil and evicted ~= path");
		expect(pdfPlugin).not.toContain("evicted ~= nil and evicted ~= path");
	});

	yaziTest("only renders video cache files when non-empty", () => {
		const videoPlugin = readFileSync(yaziVideoNativePluginPath, "utf8");
		expect(videoPlugin).toContain("local cha = fs.cha(cache)");
		expect(videoPlugin).toContain("if cha and cha.len > 0 then");
	});

	yaziTest("video preview follows the upstream thin peek lifecycle", () => {
		const videoPlugin = readFileSync(yaziVideoNativePluginPath, "utf8");
		expect(videoPlugin).toContain("local ok, err = self:preload(job)");
		expect(videoPlugin).toContain("rt.preview.image_delay");
		expect(videoPlugin).toContain("local cha = fs.cha(cache)");
		expect(videoPlugin).toContain("local stamp = path_stamp(path)");
		expect(videoPlugin).toContain("if skip > 0 then");
		expect(videoPlugin).not.toContain("if skip <= 0 then");
		expect(videoPlugin).toContain("tonumber(preview.max_width)");
		expect(videoPlugin).toContain("tonumber(preview.max_height)");
		expect(videoPlugin).toContain(':arg("--max-width")');
		expect(videoPlugin).toContain(':arg("--max-height")');
		expect(videoPlugin).toContain(
			"local _, show_err = ya.image_show(cache, job.area)",
		);
		expect(videoPlugin).toContain("ya.preview_widget(job, show_err)");
	});

	yaziTest("pdf preview follows the upstream thin peek lifecycle", () => {
		const pdfPlugin = readFileSync(yaziPdfNativePluginPath, "utf8");
		expect(pdfPlugin).toContain("local ok, err, bound = self:preload(job)");
		expect(pdfPlugin).toContain("rt.preview.image_delay");
		expect(pdfPlugin).toContain("upper_bound = true");
		expect(pdfPlugin).toContain("local cha = fs.cha(cache)");
		expect(pdfPlugin).toContain("local stamp = path_stamp(path)");
		expect(pdfPlugin).not.toContain("page_cache_path");
		expect(pdfPlugin).toContain("tonumber(preview.max_width)");
		expect(pdfPlugin).toContain("tonumber(preview.max_height)");
		expect(pdfPlugin).toContain(':arg("--max-width")');
		expect(pdfPlugin).toContain(':arg("--max-height")');
		expect(pdfPlugin).toContain(
			"local _, show_err = ya.image_show(cache, job.area)",
		);
		expect(pdfPlugin).toContain("ya.preview_widget(job, show_err)");
	});

	yaziTest("svg preview follows the upstream thin peek lifecycle", () => {
		const svgPlugin = readFileSync(yaziSvgNativePluginPath, "utf8");
		expect(svgPlugin).toContain("local ok, err = self:preload(job)");
		expect(svgPlugin).toContain("rt.preview.image_delay");
		expect(svgPlugin).toContain("preview.max_width");
		expect(svgPlugin).toContain("preview.max_height");
		expect(svgPlugin).toContain(
			"local _, show_err = ya.image_show(cache_path, job.area)",
		);
		expect(svgPlugin).toContain("ya.preview_widget(job, show_err)");
	});

	yaziTest(
		"native video and pdf helpers accept Yazi-sized render bounds",
		() => {
			const vidThumbSource = readFileSync(yenVidThumbSourcePath, "utf8");
			const pdfThumbSource = readFileSync(yenPdfThumbSourcePath, "utf8");

			expect(vidThumbSource).toContain("--max-width <pixels>");
			expect(vidThumbSource).toContain("--max-height <pixels>");
			expect(vidThumbSource).toContain('case "--max-width":');
			expect(vidThumbSource).toContain('case "--max-height":');
			expect(vidThumbSource).toContain(
				"generator.maximumSize = CGSize(width: CGFloat(maxWidth), height: CGFloat(maxHeight))",
			);

			expect(pdfThumbSource).toContain("--max-width <pixels>");
			expect(pdfThumbSource).toContain("--max-height <pixels>");
			expect(pdfThumbSource).toContain('} else if flag == "--max-width" {');
			expect(pdfThumbSource).toContain('} else if flag == "--max-height" {');
			expect(pdfThumbSource).toContain(
				"page.thumbnail(of: CGSize(width: CGFloat(maxWidth), height: CGFloat(maxHeight)), for: .mediaBox)",
			);
		},
	);

	yaziTest(
		"code-guard seek matches upstream viewport-scaled step sizing",
		() => {
			const result = runLuaScript(
				codeGuardLuaHarness(`
local source = string.rep("x", 2048) .. "\\n"
local emitted = nil

${strictFsChaStub("{ len = 2 * 1024 * 1024, mtime = 7, mode = 33188 }")}
io = {
  open = function(_, _)
    local cursor = 0
    return {
      seek = function(_, whence, offset)
        if whence == "end" then
          cursor = #source
          return #source
        elseif whence == "set" then
          cursor = offset or 0
          return cursor
        end
        return cursor
      end,
      read = function(_, n)
        if type(n) ~= "number" then
          return nil
        end
        if cursor >= #source then
          return nil
        end
        local start = cursor + 1
        local stop = math.min(#source, cursor + n)
        cursor = stop
        return source:sub(start, stop)
      end,
      close = function() end,
    }
  end,
}
ya.emit = function(_, payload)
  emitted = payload
end
ya.clamp = function(min, value, max)
  if value < min then
    return min
  elseif value > max then
    return max
  end
  return value
end
cx.active.preview.skip = 10

plugin:seek({
  units = 1,
  area = { h = 20 },
  file = { path = "/tmp/large.txt", url = "/tmp/large.txt" },
})

if emitted == nil or emitted[1] ~= 12 then
  error("expected viewport-scaled seek step to advance from 10 to 12")
end
`),
			);

			expect(result.error).toBeUndefined();
			expect(result.status).toBe(0);
		},
	);

	yaziTest("video duration cache invalidates when file stamp changes", () => {
		const result = runLuaScript(
			videoPluginLuaHarness(`
local first = plugin.__test.duration_for("/tmp/video.mp4")
local second = plugin.__test.duration_for("/tmp/video.mp4")
if first ~= 120 or second ~= 120 then
  error("expected cached duration reads to return parsed value")
end
if output_calls ~= 1 then
  error("expected warm duration cache hit before file change")
end

current_stat = { len = 2, mtime = 3, mode = 33188 }
local third = plugin.__test.duration_for("/tmp/video.mp4")
if third ~= 120 then
  error("expected duration parse after cache bust")
end
if output_calls ~= 2 then
  error("expected file-stamp change to invalidate duration cache")
end
`),
		);

		expect(result.error).toBeUndefined();
		expect(result.status).toBe(0);
	});

	yaziTest("pdf page-count cache invalidates when file stamp changes", () => {
		const result = runLuaScript(
			pdfPluginLuaHarness(`
local first = plugin.__test.page_count("/tmp/doc.pdf")
local second = plugin.__test.page_count("/tmp/doc.pdf")
if first ~= 12 or second ~= 12 then
  error("expected cached page-count reads to return parsed value")
end
if output_calls ~= 1 then
  error("expected warm page-count cache hit before file change")
end

current_stat = { len = 2, mtime = 3, mode = 33188 }
local third = plugin.__test.page_count("/tmp/doc.pdf")
if third ~= 12 then
  error("expected page-count parse after cache bust")
end
if output_calls ~= 2 then
  error("expected file-stamp change to invalidate page-count cache")
end
`),
		);

		expect(result.error).toBeUndefined();
		expect(result.status).toBe(0);
	});

	yaziTest("caches code-guard plain-preview decisions by file stamp", () => {
		const codeGuardPlugin = readFileSync(yaziCodeGuardPluginPath, "utf8");
		expect(codeGuardPlugin).toContain("DECISION_CACHE_LIMIT");
		expect(codeGuardPlugin).toContain("decision_cache");
		expect(codeGuardPlugin).toContain("cache_stamp");
		expect(codeGuardPlugin).toContain("cache_put");
	});

	yaziTest(
		"reuses cached code-guard plain-preview lines for repeated renders",
		() => {
			const result = runLuaScript(
				codeGuardLuaHarness(`
local source = string.rep("x", 2048) .. "\\n"
local open_count = 0

${strictFsChaStub("{ len = 2 * 1024 * 1024, mtime = 7, mode = 33188 }")}
io = {
  open = function(_, _)
    open_count = open_count + 1
    local cursor = 0
    return {
      seek = function(_, whence, offset)
        if whence == "end" then
          cursor = #source
          return #source
        elseif whence == "set" then
          cursor = offset or 0
          return cursor
        end
        return cursor
      end,
      read = function(_, n)
        if type(n) ~= "number" then
          return nil
        end
        if cursor >= #source then
          return nil
        end
        local start = cursor + 1
        local stop = math.min(#source, cursor + n)
        cursor = stop
        return source:sub(start, stop)
      end,
      close = function() end,
    }
  end,
}

local first = plugin.__test.build_plain_lines("/tmp/large.log", "large file", 2 * 1024 * 1024)
local second = plugin.__test.build_plain_lines("/tmp/large.log", "large file", 2 * 1024 * 1024)

if open_count ~= 1 then
  error("expected one file open for cached plain preview, got " .. tostring(open_count))
end
if #first ~= #second then
  error("expected cached line count to match")
end
if first[1] ~= second[1] then
  error("expected cached preview header to match")
end
`),
			);

			expect(result.error).toBeUndefined();
			expect(result.status).toBe(0);
		},
	);

	yaziTest("documents and enforces code-guard threshold constants", () => {
		const codeGuardPlugin = readFileSync(yaziCodeGuardPluginPath, "utf8");
		expect(codeGuardPlugin).toContain("MAX_CODE_BYTES = 1024 * 1024");
		expect(codeGuardPlugin).toContain("SAMPLE_BYTES = 64 * 1024");
		expect(codeGuardPlugin).toContain("MINIFIED_LINE_THRESHOLD = 1200");
		expect(codeGuardPlugin).toContain("MINIFIED_NEWLINE_LIMIT = 12");
		expect(codeGuardPlugin).toContain("PLAIN_PREVIEW_CACHE_LIMIT = 64");
	});

	yaziTest("maintains documented cache limits across plugins", () => {
		const videoPlugin = readFileSync(yaziVideoNativePluginPath, "utf8");
		const pdfPlugin = readFileSync(yaziPdfNativePluginPath, "utf8");
		const gitPlugin = readFileSync(yaziGitPluginPath, "utf8");
		const codeGuardPlugin = readFileSync(yaziCodeGuardPluginPath, "utf8");
		expect(videoPlugin).toContain("DURATION_CACHE_LIMIT = 512");
		expect(pdfPlugin).toContain("PAGE_COUNT_CACHE_LIMIT = 512");
		expect(gitPlugin).toContain("MAX_TRACKED_DIRS = 2048");
		expect(codeGuardPlugin).toContain("DECISION_CACHE_LIMIT = 512");
	});

	yaziTest("git plugin uses dir_order for FIFO eviction", () => {
		const gitPlugin = readFileSync(yaziGitPluginPath, "utf8");
		expect(gitPlugin).toContain("dir_order");
		expect(gitPlugin).toContain("MAX_TRACKED_DIRS");
	});

	yaziTest("git plugin treats non-zero git exits as failures", () => {
		const gitPlugin = readFileSync(yaziGitPluginPath, "utf8");
		expect(gitPlugin).toContain(":stderr(Command.PIPED)");
		expect(gitPlugin).toContain(
			"not output.status or not output.status.success",
		);
		expect(gitPlugin).toContain("`git status` failed");
	});
});
