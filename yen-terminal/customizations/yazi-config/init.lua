-- YEN File Browser Plugin Configuration
-- This file loads bundled plugins for the YEN file browser.

-- Git status indicators in file list
-- Shows modified, staged, untracked, ignored status next to files
-- Wrapped in pcall: if plugin fails to load (corruption, version mismatch),
-- yazi continues without git status rather than crashing init
pcall(function() require("git"):setup() end)

-- YEN branding in terminal/window title (replaces Yazi's default "Yazi: {cwd}").
-- Yazi v26.5.6 removed the static `title_format` TOML key in favor of the
-- `ind-app-title` DDS event, which lets us compute the title dynamically.
-- Wrapped in pcall so older Yazi runtimes (where ps.sub or cx may not exist)
-- continue to launch even if the subscription fails.
pcall(function()
  ps.sub("ind-app-title", function(args)
    local cwd = cx and cx.active and cx.active.current and cx.active.current.cwd
    if cwd then
      args.value = "YEN: " .. tostring(cwd)
    else
      args.value = "YEN"
    end
    return args
  end)
end)
