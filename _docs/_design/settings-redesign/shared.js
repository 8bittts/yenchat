/*
 * YEN Settings redesign: one settings inventory rendered into three shells.
 * Every view mounts the same PANES schema, so the consolidated feature set is
 * identical across the demos and only the layout differs.
 */
(function () {
  "use strict";

  const THEMES = [
    ["YEN", "dark", "262b36", "ffffff", "ff5100", ["e06c75", "98c379", "e5c07b", "61afef", "c678dd", "56b6c2"]],
    ["Atom One Dark", "dark", "21252b", "abb2bf", "abb2bf", ["e06c75", "98c379", "e5c07b", "61afef", "c678dd", "56b6c2"]],
    ["Catppuccin Mocha", "dark", "1e1e2e", "cdd6f4", "f5e0dc", ["f38ba8", "a6e3a1", "f9e2af", "89b4fa", "f5c2e7", "94e2d5"]],
    ["Dracula", "dark", "282a36", "f8f8f2", "f8f8f2", ["ff5555", "50fa7b", "f1fa8c", "bd93f9", "ff79c6", "8be9fd"]],
    ["Everforest Dark Med", "dark", "232a2e", "d3c6aa", "e69875", ["e67e80", "a7c080", "dbbc7f", "7fbbb3", "d699b6", "83c092"]],
    ["GitHub Dark", "dark", "101216", "8b949e", "c9d1d9", ["f78166", "56d364", "e3b341", "6ca4f8", "db61a2", "2b7489"]],
    ["Gruvbox Dark", "dark", "282828", "ebdbb2", "ebdbb2", ["cc241d", "98971a", "d79921", "458588", "b16286", "689d6a"]],
    ["iTerm2 Solarized Dark", "dark", "002b36", "839496", "839496", ["dc322f", "859900", "b58900", "268bd2", "d33682", "2aa198"]],
    ["Kanagawa Wave", "dark", "1f1f28", "dcd7ba", "dcd7ba", ["c34043", "76946a", "c0a36e", "7e9cd8", "957fb8", "6a9589"]],
    ["Monokai Pro", "dark", "2d2a2e", "fcfcfa", "c1c0c0", ["ff6188", "a9dc76", "ffd866", "fc9867", "ab9df2", "78dce8"]],
    ["Nord", "dark", "2e3440", "d8dee9", "eceff4", ["bf616a", "a3be8c", "ebcb8b", "81a1c1", "b48ead", "88c0d0"]],
    ["Retro Terminal", "dark", "050907", "7cff91", "33ff66", ["2fa34f", "33ff66", "9ce287", "4ca66b", "66cc88", "57d69a"]],
    ["Rose Pine", "dark", "191724", "e0def4", "e0def4", ["eb6f92", "31748f", "f6c177", "9ccfd8", "c4a7e7", "ebbcba"]],
    ["TokyoNight", "dark", "1a1b26", "c0caf5", "c0caf5", ["f7768e", "9ece6a", "e0af68", "7aa2f7", "bb9af7", "7dcfff"]],
    ["Catppuccin Latte", "light", "eff1f5", "4c4f69", "dc8a78", ["d20f39", "40a02b", "df8e1d", "1e66f5", "ea76cb", "179299"]],
    ["CutePretzel", "light", "ffcfd2", "553e4e", "c03868", ["c03868", "5a8a5a", "a87830", "5868a0", "c04888", "488878"]],
    ["GitHub Light Default", "light", "ffffff", "1f2328", "0969da", ["cf222e", "116329", "4d2d00", "0969da", "8250df", "1b7c83"]],
    ["Gruvbox Light", "light", "fbf1c7", "3c3836", "3c3836", ["cc241d", "98971a", "d79921", "458588", "b16286", "689d6a"]],
    ["iTerm2 Solarized Light", "light", "fdf6e3", "657b83", "657b83", ["dc322f", "859900", "b58900", "268bd2", "d33682", "2aa198"]],
    ["Rose Pine Dawn", "light", "faf4ed", "575279", "575279", ["b4637a", "286983", "ea9d34", "56949f", "907aa9", "d7827e"]],
  ].map(([name, tone, bg, fg, cur, p]) => ({ name, tone, bg, fg, cur, p }));

  const ICONS = {
    appearance: '<path d="M12 3a9 9 0 1 0 0 18c1.2 0 1.8-.8 1.8-1.7 0-1.4-1.1-1.6-1.1-2.8 0-.9.7-1.5 1.6-1.5H16a5 5 0 0 0 5-5c0-3.9-4-7-9-7Z"/><circle cx="7.6" cy="11.2" r="1"/><circle cx="10.4" cy="7.4" r="1"/><circle cx="15" cy="7.6" r="1"/>',
    general: '<circle cx="12" cy="12" r="3.2"/><path d="M12 2.8v2.4M12 18.8v2.4M2.8 12h2.4M18.8 12h2.4M5.5 5.5l1.7 1.7M16.8 16.8l1.7 1.7M5.5 18.5l1.7-1.7M16.8 7.2l1.7-1.7"/>',
    notifications: '<path d="M6 16.5V11a6 6 0 1 1 12 0v5.5l1.6 2H4.4l1.6-2Z"/><path d="M10 20.5a2.2 2.2 0 0 0 4 0"/>',
    dictation: '<rect x="9" y="3" width="6" height="11" rx="3"/><path d="M5.5 11.5a6.5 6.5 0 0 0 13 0M12 18v3"/>',
    shortcuts: '<rect x="2.8" y="6" width="18.4" height="12" rx="3"/><path d="M6.5 10h.01M10 10h.01M13.5 10h.01M17 10h.01M7.5 14h9"/>',
    check: '<path d="M5 12.5l4.2 4.2L19 7"/>',
    lock: '<rect x="5.5" y="10.5" width="13" height="9" rx="2.5"/><path d="M8.5 10.5V8a3.5 3.5 0 0 1 7 0v2.5"/>',
  };

  const PANES = [
    {
      id: "appearance",
      title: "Appearance",
      tint: "#ff5100",
      groups: [
        { special: "preview" },
        { special: "themes", title: "Theme" },
        {
          title: "Text",
          rows: [
            { label: "Font", control: { type: "popup", key: "font", options: ["JetBrains Mono", "SF Mono", "Menlo", "Monaco", "Fira Code", "Cascadia Code", "IBM Plex Mono"] } },
            { label: "Size", control: { type: "slider", key: "fontSize", min: 10, max: 24, step: 1, unit: " pt" } },
          ],
        },
        {
          title: "Cursor",
          rows: [
            { label: "Style", control: { type: "segment", key: "cursor", options: [["block", "Block"], ["bar", "Bar"], ["underline", "Underline"]] } },
            { label: "Blink", control: { type: "switch", key: "blink" } },
          ],
        },
        {
          title: "Window",
          footer: "Opacity applies the next time you open YEN.",
          rows: [
            { label: "Opacity", control: { type: "slider", key: "opacity", min: 30, max: 100, step: 5, unit: "%" } },
            { label: "Padding", control: { type: "stepper", key: "padding", min: 0, max: 40, step: 2, unit: " pt" } },
            { label: "Background Image", control: { type: "button", label: "Choose…" } },
            { label: "Border", hint: "Outlines the focused pane.", control: { type: "switch", key: "border" } },
            { label: "Color", child: true, showIf: "border", control: { type: "segment", key: "borderColor", options: [["theme", "Theme"], ["accent", "Accent"]] } },
            { label: "Weight", child: true, showIf: "border", control: { type: "segment", key: "borderWeight", options: [["1", "Thin"], ["2", "Regular"], ["4", "Thick"]] } },
          ],
        },
      ],
    },
    {
      id: "general",
      title: "General",
      tint: "#8e8e93",
      groups: [
        {
          rows: [
            { label: "Open YEN at Login", control: { type: "switch", key: "login" } },
            { label: "Copy on Select", hint: "Selecting text copies it to the clipboard.", control: { type: "switch", key: "copyOnSelect" } },
            { label: "Scroll Bar", control: { type: "popup", key: "scrollbar", options: ["Automatic", "Never"] } },
          ],
        },
        {
          title: "Workspace",
          rows: [
            { label: "Tab Sidebar", hint: "Lists tabs with their folder and Git branch.", control: { type: "popup", key: "sidebar", options: ["Off", "Floating", "Docked"] } },
            { label: "Pane Labels", control: { type: "switch", key: "splitLabels" } },
            { label: "Name Panes After Their Worktree", child: true, showIf: "splitLabels", control: { type: "switch", key: "worktree" } },
            { label: "Scratchpad", keycap: "⇧⌘J", control: { type: "switch", key: "scratchpad" } },
          ],
        },
        {
          title: "Links",
          rows: [
            { label: "Open Links in YEN", hint: "Web links from the terminal open in the built-in browser.", control: { type: "switch", key: "links" } },
            { label: "Open the Browser in a Split", child: true, showIf: "links", control: { type: "switch", key: "browserSplit" } },
          ],
        },
        {
          rows: [{ label: "Reset All Settings", control: { type: "button", label: "Reset…", style: "is-destructive" } }],
        },
      ],
    },
    {
      id: "notifications",
      title: "Notifications",
      tint: "#ff3b30",
      groups: [
        {
          rows: [
            { label: "Notifications", control: { type: "status", state: "is-warn", label: "Not Allowed", button: "Open System Settings…" } },
          ],
        },
        {
          title: "When a Command Finishes",
          rows: [
            { label: "Notify", control: { type: "popup", key: "notifyWhen", options: ["Never", "When YEN Is in the Background", "Always"] } },
            { label: "Only After", child: true, showIf: "notifyOn", control: { type: "stepper", key: "notifyAfter", min: 0, max: 600, step: 5, unit: " s" } },
            { label: "Ring the Terminal Bell", child: true, showIf: "notifyOn", control: { type: "switch", key: "bell" } },
            { label: "Show a Notification", child: true, showIf: "notifyOn", control: { type: "switch", key: "banner" } },
          ],
        },
        {
          title: "Alert Sounds",
          rows: [
            { label: "General", control: { type: "popup", key: "soundGeneral", options: ["None", "Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero", "Morse", "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink"] } },
            { label: "Build Finished", control: { type: "popup", key: "soundBuild", options: ["None", "Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero", "Morse", "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink"] } },
          ],
        },
        {
          title: "While YEN Is Active",
          rows: [
            { label: "Play Sounds", control: { type: "switch", key: "activeSounds" } },
            { label: "Show Banners", control: { type: "switch", key: "activeBanners" } },
          ],
        },
      ],
    },
    {
      id: "dictation",
      title: "Dictation",
      tint: "#34c759",
      groups: [
        {
          title: "Permissions",
          footer: "Hold ⌥Space to dictate. Speech is recognized on this Mac.",
          rows: [
            { label: "Accessibility", control: { type: "status", state: "is-ok", label: "Allowed" } },
            { label: "Microphone", control: { type: "status", state: "is-ok", label: "Allowed" } },
            { label: "Speech Recognition", control: { type: "status", state: "is-warn", label: "Not Allowed", button: "Allow…" } },
          ],
        },
        {
          rows: [
            { label: "Microphone", control: { type: "popup", key: "mic", options: ["System Default", "MacBook Pro Microphone", "Studio Display Microphone"] } },
            { label: "Show Live Transcript", control: { type: "switch", key: "liveTranscript" } },
          ],
        },
        {
          title: "Translation",
          rows: [
            { label: "Translate Dictation", hint: "Translates what you say before it is typed.", control: { type: "switch", key: "translate" } },
            { label: "Translate To", child: true, showIf: "translate", control: { type: "popup", key: "translateTo", options: ["Japanese", "Spanish", "French", "German", "Korean", "Portuguese"] } },
          ],
        },
      ],
    },
    {
      id: "shortcuts",
      title: "Shortcuts",
      tint: "#5e5ce6",
      groups: [{ special: "shortcuts" }],
    },
  ];

  const SHORTCUTS = {
    Terminal: [["Copy", "⌘C"], ["Paste", "⌘V"], ["Select All", "⌘A"], ["Clear Screen", "⌘K"], ["Find", "⌘F"], ["Insert Newline", "⇧↩", true]],
    Windows: [["New Window", "⌘N"], ["Close Window", "⇧⌘W"], ["Toggle Full Screen", "⌘↩", true], ["Command Palette", "⇧⌘P"], ["Settings", "⌘,", true]],
    Tabs: [["New Tab", "⌘T"], ["Close Tab", "⌥⌘W"], ["Next Tab", "⇧⌘]"], ["Previous Tab", "⇧⌘["], ["Reopen Closed Tab", "⇧⌘T", true]],
    Splits: [["Split Right", "⌘D"], ["Split Down", "⇧⌘D"], ["Close Pane", "⌘W"], ["Zoom Pane", "⇧⌘↩"], ["Focus Next Pane", "⌘]"]],
    YEN: [["Dictation", "⌥Space", true], ["Scratchpad", "⇧⌘J", true], ["Tab Sidebar", "⇧⌘B", true], ["Git Drawer", "⇧⌘G", true], ["Screenshot", "⇧⌘S", true]],
  };

  const state = {
    theme: "YEN", font: "JetBrains Mono", fontSize: 14, cursor: "block", blink: true,
    opacity: 100, padding: 8, border: false, borderColor: "theme", borderWeight: "2",
    login: false, copyOnSelect: true, scrollbar: "Automatic", sidebar: "Floating",
    splitLabels: false, worktree: false, scratchpad: true, links: false, browserSplit: false,
    notifyWhen: "Never", notifyAfter: 5, bell: true, banner: false,
    soundGeneral: "None", soundBuild: "Glass", activeSounds: true, activeBanners: false,
    mic: "System Default", liveTranscript: false, translate: false, translateTo: "Japanese",
    themeFilter: "all", shortcutCat: "Terminal",
  };

  const derived = { notifyOn: () => state.notifyWhen !== "Never" };
  const isOn = (key) => (key in derived ? derived[key]() : Boolean(state[key]));
  const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));
  const icon = (name) => `<svg class="icon" viewBox="0 0 24 24" aria-hidden="true">${ICONS[name] || ""}</svg>`;

  function controlHTML(c, label) {
    const name = esc(label);
    switch (c.type) {
      case "switch":
        return `<label class="switch"><input type="checkbox" data-key="${c.key}" aria-label="${name}" ${state[c.key] ? "checked" : ""}><span class="track"></span><span class="knob"></span></label>`;
      case "segment":
        return `<div class="segmented" role="group" aria-label="${name}" data-key="${c.key}">${c.options
          .map(([v, l]) => `<button type="button" data-value="${esc(v)}" aria-pressed="${String(state[c.key]) === v}">${esc(l)}</button>`)
          .join("")}</div>`;
      case "popup":
        return `<select class="popup" data-key="${c.key}" aria-label="${name}">${c.options
          .map((o) => `<option ${state[c.key] === o ? "selected" : ""}>${esc(o)}</option>`)
          .join("")}</select>`;
      case "slider":
        return `<input class="slider" type="range" data-key="${c.key}" data-unit="${esc(c.unit)}" min="${c.min}" max="${c.max}" step="${c.step}" value="${state[c.key]}" aria-label="${name}"><span class="row-value" data-value-for="${c.key}"></span>`;
      case "stepper":
        return `<span class="stepper"><span class="row-value" data-value-for="${c.key}" data-unit="${esc(c.unit)}"></span><span class="stepper-buttons" data-key="${c.key}" data-min="${c.min}" data-max="${c.max}" data-step="${c.step}"><button type="button" data-dir="-1" aria-label="Decrease ${name}">−</button><button type="button" data-dir="1" aria-label="Increase ${name}">+</button></span></span>`;
      case "button":
        return `<button type="button" class="button ${c.style || ""}">${esc(c.label)}</button>`;
      case "status":
        return `<span class="status ${c.state}">${esc(c.label)}</span>${c.button ? `<button type="button" class="button">${esc(c.button)}</button>` : ""}`;
      default:
        return "";
    }
  }

  function rowHTML(r) {
    return `<div class="row${r.child ? " is-child" : ""}"${r.showIf ? ` data-show-if="${r.showIf}"` : ""}>
      <span class="row-text"><span class="row-label">${esc(r.label)}</span>${r.hint ? `<span class="row-hint">${esc(r.hint)}</span>` : ""}</span>
      <span class="row-control">${r.keycap ? `<span class="keycap">${esc(r.keycap)}</span>` : ""}${controlHTML(r.control, r.label)}</span>
    </div>`;
  }

  function termHTML(lines) {
    const all = [
      '<span class="c4">~/code/yen</span> <span class="c5">main</span> <span class="c2">❯</span> git status --short',
      ' <span class="c3">M</span> Sources/Settings/Appearance.swift',
      ' <span class="c2">A</span> Sources/Settings/ThemeGallery.swift',
      '<span class="c4">~/code/yen</span> <span class="c5">main</span> <span class="c2">❯</span> swift build <span class="dim">-c release</span>',
      '<span class="c6">Compiling</span> YEN <span class="dim">(42 sources)</span>',
      '<span class="c2">Build complete!</span> <span class="dim">(3.41s)</span>',
      '<span class="c4">~/code/yen</span> <span class="c5">main</span> <span class="c2">❯</span> <span class="c1">yen</span> theme <span class="c3">--list</span>',
      '<span class="dim">20 themes · 14 dark · 6 light</span>',
    ];
    const body = all.slice(0, lines || all.length).join("\n");
    return `<div class="term-body">${body}\n<span class="c4">~/code/yen</span> <span class="c5">main</span> <span class="c2">❯</span> <span class="cursor"></span></div>`;
  }

  function themeTileHTML(t) {
    return `<button type="button" class="theme-tile" data-theme="${esc(t.name)}" aria-pressed="${state.theme === t.name}" title="${esc(t.name)}">
      <span class="theme-swatch" style="background:#${t.bg};color:#${t.fg}"><b><span style="color:#${t.p[3]}">~</span> <span style="color:#${t.p[1]}">❯</span> yen</b><b style="opacity:.6">ready</b><span class="dots">${t.p.slice(0, 5).map((c) => `<i style="background:#${c}"></i>`).join("")}</span></span>
      <span class="theme-name">${esc(t.name)}</span>
    </button>`;
  }

  function themesHTML() {
    const list = THEMES.filter((t) => state.themeFilter === "all" || t.tone === state.themeFilter);
    return list.map(themeTileHTML).join("");
  }

  function themeFilterHTML() {
    const counts = { all: THEMES.length, dark: THEMES.filter((t) => t.tone === "dark").length, light: THEMES.filter((t) => t.tone === "light").length };
    return `<div class="segmented" role="group" aria-label="Theme filter" data-key="themeFilter">${[["all", "All"], ["dark", "Dark"], ["light", "Light"]]
      .map(([v, l]) => `<button type="button" data-value="${v}" aria-pressed="${state.themeFilter === v}">${l} <span style="color:var(--label-3)">${counts[v]}</span></button>`)
      .join("")}</div>`;
  }

  function shortcutsHTML() {
    const cats = Object.keys(SHORTCUTS);
    const rows = SHORTCUTS[state.shortcutCat]
      .map(([name, keys, locked]) => `<div class="row"><span class="row-text"><span class="row-label">${esc(name)}</span></span><span class="row-control">${locked ? `<span style="color:var(--label-3);display:inline-flex">${icon("lock")}</span>` : ""}<span class="keys"><button type="button" ${locked ? "disabled" : ""} data-keys="${esc(keys)}" aria-label="${esc(name)} shortcut, ${esc(keys)}">${esc(keys)}</button></span></span></div>`)
      .join("");
    return `<div class="shortcut-cats"><div class="segmented" role="group" aria-label="Shortcut category" data-key="shortcutCat">${cats
      .map((c) => `<button type="button" data-value="${c}" aria-pressed="${state.shortcutCat === c}">${c}</button>`)
      .join("")}</div></div>
      <div class="group"><div class="group-card">${rows}</div><p class="group-footer">Click a shortcut, then press the new keys. Locked shortcuts belong to YEN or macOS.</p></div>
      <div class="group"><div class="group-card"><div class="row"><span class="row-text"><span class="row-label">Restore Default Shortcuts</span></span><span class="row-control"><button type="button" class="button">Restore…</button></span></div></div></div>`;
  }

  function groupHTML(g, opts) {
    if (g.special === "preview") {
      return opts.inlinePreview ? `<div class="group"><div class="term hero-term" data-term>${termHTML(opts.previewLines || 4)}</div></div>` : "";
    }
    if (g.special === "themes") {
      if (!opts.inlineThemes) return "";
      if (opts.themeLayout === "sections") {
        const block = (tone, label) => {
          const list = THEMES.filter((t) => t.tone === tone);
          return `<div class="group"><div class="themes-head"><h3 class="group-title">${label}</h3><span class="themes-count">${list.length}</span></div><div class="themes grid">${list.map(themeTileHTML).join("")}</div></div>`;
        };
        return block("dark", "Dark Themes") + block("light", "Light Themes");
      }
      return `<div class="group"><div class="themes-head"><h3 class="group-title">Theme</h3>${themeFilterHTML()}</div><div class="themes ${opts.themeLayout || "grid"}" data-themes>${themesHTML()}</div></div>`;
    }
    if (g.special === "shortcuts") {
      return `<div data-shortcuts>${shortcutsHTML()}</div>`;
    }
    return `<section class="group">${g.title ? `<h3 class="group-title">${esc(g.title)}</h3>` : ""}<div class="group-card">${g.rows.map(rowHTML).join("")}</div>${g.footer ? `<p class="group-footer">${esc(g.footer)}</p>` : ""}</section>`;
  }

  function apply(root) {
    const theme = THEMES.find((t) => t.name === state.theme) || THEMES[0];
    document.querySelectorAll("[data-term]").forEach((el) => {
      const s = el.style;
      s.setProperty("--t-bg", `#${theme.bg}`);
      s.setProperty("--t-fg", `#${theme.fg}`);
      s.setProperty("--t-cur", `#${theme.cur}`);
      theme.p.forEach((c, i) => s.setProperty(`--t-${i + 1}`, `#${c}`));
      const scale = Number(el.dataset.scale || 1);
      s.setProperty("--t-size", `${Math.round(state.fontSize * scale * 10) / 10}px`);
      s.setProperty("--t-pad", `${state.padding}px`);
      s.setProperty("--t-opacity", String(state.opacity / 100));
      s.setProperty("--t-border-w", `${state.borderWeight}px`);
      s.fontFamily = `"${state.font}", var(--font-mono)`;
      el.dataset.cursor = state.cursor;
      el.dataset.blink = String(state.blink);
      el.dataset.border = state.border ? state.borderColor : "none";
    });
    document.querySelectorAll("[data-theme-name]").forEach((el) => { el.textContent = theme.name; });
    document.querySelectorAll("[data-theme-tone]").forEach((el) => { el.textContent = theme.tone === "dark" ? "Dark" : "Light"; });
    root.querySelectorAll("[data-show-if]").forEach((el) => { el.hidden = !isOn(el.dataset.showIf); });
    root.querySelectorAll(".slider").forEach((el) => {
      const pct = ((el.value - el.min) / (el.max - el.min)) * 100;
      el.style.setProperty("--pct", `${pct}%`);
    });
    root.querySelectorAll("[data-value-for]").forEach((el) => {
      const key = el.dataset.valueFor;
      const unit = el.dataset.unit || (root.querySelector(`.slider[data-key="${key}"]`) || {}).dataset?.unit || "";
      el.textContent = `${state[key]}${unit}`;
    });
    root.querySelectorAll(".theme-tile").forEach((el) => el.setAttribute("aria-pressed", String(el.dataset.theme === state.theme)));
  }

  function mount(options) {
    const opts = Object.assign({ inlinePreview: true, inlineThemes: true, themeLayout: "grid", start: "appearance" }, options);
    const root = document.querySelector(opts.root || "[data-settings]");
    const panesEl = root.querySelector("[data-panes]");
    panesEl.innerHTML = PANES.map((p) => `<div class="pane" data-pane="${p.id}">${p.groups.map((g) => groupHTML(g, opts)).join("")}</div>`).join("");

    root.querySelectorAll("[data-nav]").forEach((nav) => {
      nav.innerHTML = PANES.map((p) => (opts.navItem ? opts.navItem(p, icon) : `<button type="button" data-go="${p.id}">${icon(p.id)}<span>${p.title}</span></button>`)).join("");
    });
    root.querySelectorAll("[data-external-themes]").forEach((el) => { el.innerHTML = themesHTML(); });
    root.querySelectorAll("[data-external-filter]").forEach((el) => { el.innerHTML = themeFilterHTML(); });
    root.querySelectorAll("[data-term]:empty").forEach((el) => { el.innerHTML = termHTML(Number(el.dataset.lines || 8)); });

    function go(id) {
      const pane = PANES.find((p) => p.id === id) || PANES[0];
      root.dataset.activePane = pane.id;
      root.querySelectorAll(".pane").forEach((el) => el.classList.toggle("is-active", el.dataset.pane === pane.id));
      root.querySelectorAll("[data-go]").forEach((el) => {
        const active = el.dataset.go === pane.id;
        el.setAttribute("aria-current", active ? "page" : "false");
      });
      root.querySelectorAll("[data-title]").forEach((el) => { el.textContent = pane.title; });
      const scroller = root.querySelector("[data-scroll]");
      if (scroller) scroller.scrollTop = 0;
      if (opts.onPane) opts.onPane(pane);
    }

    function rerenderThemes() {
      root.querySelectorAll("[data-themes]").forEach((el) => { el.innerHTML = themesHTML(); });
      root.querySelectorAll("[data-external-themes]").forEach((el) => { el.innerHTML = themesHTML(); });
    }

    root.addEventListener("click", (event) => {
      const goBtn = event.target.closest("[data-go]");
      if (goBtn) return go(goBtn.dataset.go);

      const tile = event.target.closest(".theme-tile");
      if (tile) { state.theme = tile.dataset.theme; return apply(root); }

      const seg = event.target.closest(".segmented button");
      if (seg) {
        const group = seg.parentElement;
        const key = group.dataset.key;
        state[key] = seg.dataset.value;
        group.querySelectorAll("button").forEach((b) => b.setAttribute("aria-pressed", String(b === seg)));
        if (key === "themeFilter") rerenderThemes();
        if (key === "shortcutCat") root.querySelectorAll("[data-shortcuts]").forEach((el) => { el.innerHTML = shortcutsHTML(); });
        return apply(root);
      }

      const step = event.target.closest(".stepper-buttons button");
      if (step) {
        const box = step.parentElement;
        const key = box.dataset.key;
        const next = state[key] + Number(step.dataset.dir) * Number(box.dataset.step);
        state[key] = Math.min(Number(box.dataset.max), Math.max(Number(box.dataset.min), next));
        return apply(root);
      }

      const keys = event.target.closest(".keys button");
      root.querySelectorAll(".keys button.is-recording").forEach((b) => {
        if (b !== keys) { b.classList.remove("is-recording"); b.textContent = b.dataset.keys; }
      });
      if (keys && !keys.disabled) {
        const recording = keys.classList.toggle("is-recording");
        keys.textContent = recording ? "Type shortcut…" : keys.dataset.keys;
      }
    });

    root.addEventListener("input", (event) => {
      const el = event.target;
      const key = el.dataset && el.dataset.key;
      if (!key) return;
      if (el.type === "checkbox") state[key] = el.checked;
      else if (el.type === "range") state[key] = Number(el.value);
      else state[key] = el.value;
      apply(root);
    });

    root.addEventListener("keydown", (event) => {
      const rec = root.querySelector(".keys button.is-recording");
      if (!rec) return;
      event.preventDefault();
      if (event.key === "Escape") { rec.classList.remove("is-recording"); rec.textContent = rec.dataset.keys; return; }
      if (["Meta", "Shift", "Alt", "Control"].includes(event.key)) return;
      const combo = `${event.ctrlKey ? "⌃" : ""}${event.altKey ? "⌥" : ""}${event.shiftKey ? "⇧" : ""}${event.metaKey ? "⌘" : ""}${event.key.length === 1 ? event.key.toUpperCase() : event.key}`;
      rec.dataset.keys = combo;
      rec.textContent = combo;
      rec.classList.remove("is-recording");
    });

    document.querySelectorAll("[data-appearance-set]").forEach((btn) => {
      btn.addEventListener("click", () => {
        const value = btn.dataset.appearanceSet;
        if (value === "auto") document.documentElement.removeAttribute("data-appearance");
        else document.documentElement.setAttribute("data-appearance", value);
        document.querySelectorAll("[data-appearance-set]").forEach((b) => b.setAttribute("aria-pressed", String(b === btn)));
      });
    });

    const paneFromHash = () => {
      const id = location.hash.replace("#", "");
      return PANES.some((p) => p.id === id) ? id : null;
    };
    window.addEventListener("hashchange", () => { const id = paneFromHash(); if (id) go(id); });
    go(paneFromHash() || opts.start);
    apply(root);
    return { go, state };
  }

  window.YENSettings = { mount, PANES, THEMES, icon };
})();
