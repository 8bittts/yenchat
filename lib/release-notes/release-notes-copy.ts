// HUMAN-CURATED release-notes voice layer — this file IS meant to be hand-edited.
//
// scripts/gen-release-notes.ts owns *which* builds exist and *when* they shipped
// (from public/stable/version.json bump commits). This file owns the public
// *voice*: RELEASE_COPY preserves a factual, customer-facing line per version;
// RELEASE_WEEK_COPY turns those facts into the short narrative product stories
// published at blog.yen.chat/releases. The generator retains every version/date as weekly
// provenance while showing one curated story per Monday-Sunday release week.
//
// Editorial rules (voice, lineage neutrality, retired-runtime handling) live in
// _docs/10-gtm.md → "Release Notes". Two rules bind THIS file directly:
//   - [SHAPE] Break every story into paragraphs with a literal blank line
//     ("\n\n"). The release notes page splits on it and renders one <p> per
//     paragraph, so a missing break is a wall of text on the live page.
//   - Builds that shipped nothing user-facing (pure test/CI, or purely a
//     retired runtime) go in RELEASE_EXCLUDE with a reason, never reframed.

// version -> curated public summary.
export const RELEASE_COPY: Record<string, string> = {
	"1.278":
		"On macOS 14 and later, native tabs share the titlebar by default. The tab strip grows as you open tabs, and the sidebar highlights the active shell. Two controls at the upper left in native fullscreen let you show the sidebar or return to a window.",
	"1.277":
		"YEN can find and reopen a detached shell session even after an update changes the tool that started it. The yen sessions command lists old and new sessions together and reports an error if it cannot read the session directory. In Settings, the Live Preview label now lines up with the window controls.",
	"1.275":
		"Panes now keep running when you quit YEN, when it updates, or if it crashes, and reattach with their screen and scrollback when YEN opens again. Quitting no longer stops what runs in your panes, so a dev server keeps its port; close a pane to end its session, use End All Sessions in Settings > General, or run yen sessions kill <id>. Turn it off with Settings > General > Keep Sessions Running, which applies to new panes. Password prompts inside a kept pane still turn on Secure Input, and YEN can reopen up to eight detached sessions missed by window restore.",
	"1.274":
		"The bundled diff viewer moves to its latest release, which shows when a submodule has uncommitted changes.",
	"1.273":
		"If your Mac uses a Retina display and a non-Retina display together, Japanese text, symbols, and other characters drawn from fallback fonts no longer turn into the wrong glyphs after the Mac wakes from sleep. The bundled diff viewer moves to its latest release, which highlights the syntax of deleted files and keeps your line-number styles in side-by-side view.",
	"1.268":
		"If the fallback font chosen for a character cannot be loaded, that cell shows a replacement mark instead of the whole row going blank, and YEN no longer retries the failed font on every frame.",
	"1.267":
		"Selecting text still copies it to both the clipboard and the selection pasteboard by default. If your config sets copy-on-select = true by hand, a selection now goes only to the selection pasteboard that Paste Selection reads; set it to both to keep the clipboard copy. Scrolling and erasing output do slightly less work, and padding a copied region that is shorter than the window no longer clears past the end of a row.",
	"1.265":
		"Click a split you were not working in and it only takes focus: neither the press nor the release reaches the program inside it. When a window resizes, a shell prompt that redraws no longer leaves a stale copy behind.",
	"1.264":
		"Settings is rebuilt around a live preview of your terminal, with a glass inspector of five panes beside it: Appearance, General, Notifications, Dictation, and Shortcuts. Choose one of the 20 bundled themes from the Appearance dock and the preview changes at once; click a shortcut to record a new one. Search, import and export, and per-pane reset are removed. A config with no theme, or with a theme YEN no longer bundles, opens with YEN, and the tab sidebar takes its color from the theme the terminal applied. Values you wrote by hand in your config survive unrelated Settings changes.",
	"1.263":
		"After you restore a session, the next thing you type uses the room the last page already kept, instead of pausing to allocate it.",
	"1.262":
		"The Git drawer follows the focused split’s directory even when the tab sidebar is hidden and refreshes when repository files change. Selecting a file reuses the existing repository snapshot. Project paths, command-palette text, and background configuration reuse cached work across queries or windows. Terminal images stay visible while replacement data arrives.",
	"1.261":
		"This maintenance build finishes the internal cleanup behind terminal layouts, settings, dictation, Git review, and browser controls. Release checks now follow the reorganized packaging code and verify that themes land in the correct folder.",
	"1.260":
		"Dictation is steadier: the live preview drops a pending update once newer speech replaces it, a permission reply that arrives late can no longer start or stop the wrong session, and YEN checks the target pane again right before it pastes. If that paste fails, YEN tells you once and leaves the transcript on your clipboard. Once pending dictation work finishes, the next transcript can insert immediately again when translation is off. Layout presets check the focused pane before they open new terminals. If you cap scrollback with scrollback-limit-lines, YEN reuses the memory of the oldest page it drops instead of freeing and allocating it again, and the Dutch command palette translation is updated.",
	"1.259":
		"Color and style changes on a row are applied in one pass, and text that contains an invalid byte is decoded once for the valid part instead of twice.",
	"1.258":
		"Making a window taller while making it narrower now pulls your scrollback down to fill the new rows instead of leaving them blank. Text that contains an invalid byte keeps the valid part before it instead of losing it, and the Indonesian translation is updated.",
	"1.257":
		"If the terminal briefly runs short of memory while drawing, rows that failed to update are retried on the next frame instead of staying stale. Widening a terminal with a lot of scrollback keeps selections and marks attached to the right lines. The bundled Git tool no longer breaks a submodule in your main checkout when you remove it from a linked worktree, and it ignores submodules whose path points outside the repository.",
	"1.256":
		"When the ssh helper sets up terminal support on a remote host, the install step now runs under a standard POSIX shell, so it works even when your login shell on that host is not sh-compatible. The bundled file search tool passes filenames that are not valid UTF-8 through to pipes unchanged, and the bundled fuzzy finder fixes filter-mode sorting, symlinked search roots, and data races in its preview.",
	"1.255":
		"Triple-clicking a line of output keeps the selection when it crosses blank lines. When the ssh helper sets up terminal support on a remote host, it installs into your home ~/.terminfo and checks that the entry resolves before using it. Terminals holding many images free the oldest transmitted image first, and styled output draws with less work.",
	"1.254":
		"You can now switch the window theme to light, dark, or your system appearance for the current session from the command palette or a keybinding, and choose the configured theme again to go back. Images placed with placeholder characters target the right placement, and the bundled system info tool no longer waits forever when a terminal answers only part of its color query.",
	"1.253":
		"You can open Bitcoin from About, beside Docs, or from the new Bitcoin link in Help. JP the Cat now has a paws icon in Help. Resizing a terminal with scrollback disabled keeps the cursor valid when its old row is removed, and the Dutch translation is updated.",
	"1.250":
		"On macOS 27, the tab bar no longer stays clipped the first time you show it on a window without tabs, or when you merge all windows. The layout still runs when the new-tab button is not on screen yet. Looking up a program on PATH also stops when the candidate path fills the buffer, instead of writing past the end, and the bundled file finder moves up a bugfix release.",
	"1.249":
		"Quitting YEN with Command-Q or the menu now works while a clipboard paste confirmation is open, instead of being ignored until you dismiss it. Plain text output also prints faster, scrolling inside a region does less work, and the Japanese translation is updated.",
	"1.248":
		"Text draws faster: output that mixes regular and wide characters, such as CJK text or emoji, and text inside links stays on the fast drawing path, and rows that are already blank are not erased again. When a program sets left and right margins, a wide character after a line wraps now stays inside them.",
	"1.247":
		"New tabs, splits, and windows open in your current folder again on Macs whose names contain spaces, apostrophes, or other characters that are not valid in internet hostnames. Very long scrollback is also guarded against size overflows, and pages that hold many links or long strings now grow with the room they need.",
	"1.246":
		"Output full of colors and styles, like an editor, a system monitor, or a colorful build log, now renders faster: YEN applies every style in a color or style change at once instead of one at a time, and new scrollback keeps the room that recent output needed instead of growing it again and again. The Indonesian translation is also updated.",
	"1.245":
		"Clearing the screen in a shell that does not mark its prompts no longer triggers a scan for prompts, so a clear in a plain shell costs less. The ssh helper shows authentication messages while it sets up terminfo on the remote host instead of hiding them, tmux control mode parses pane output without a regular expression, and clearing an empty circular buffer can no longer fail.",
	"1.244":
		"If you use tmux control mode, closing a tmux window or switching the active one now updates YEN, pane output with escaped characters shows up as it was written, and oversized control ids are refused. Text you copy or save with its formatting keeps a line that wraps at the right edge intact, and a command in your configuration that is empty after its prefix is reported as an error, while extra spaces between its words are ignored.",
	"1.242":
		"Full-screen programs that insert or delete whole columns, or that step the cursor past the left or right margin, now get the terminal response they expect instead of being ignored. An environment value in your configuration that runs past 256 characters no longer makes printing your settings fail.",
	"1.241":
		"A configuration value that ends in a cut-off multi-byte character no longer risks a crash while YEN reads it, and a Unicode escape written inside a configuration value is checked more strictly instead of being half-accepted.",
	"1.240":
		"The zoom indicator on a split clears once the split is gone instead of staying behind. A folder name that contains escape characters can no longer pass them through shell integration into your terminal, and malformed tmux pane layouts are rejected instead of accepted. AppleScript tabs and terminals gain a readable and writable name override property, and the software updater moves up a release.",
	"1.239":
		"Moving a tab between windows no longer flashes the title bar on macOS 26. Programs that ask the terminal to report mode 2031 no longer risk a hang while waiting for the response.",
	"1.238":
		"The bundled system monitor moves up a release. It no longer crashes while a Time Machine backup runs over the network or when it reads a swap disk, and it handles resizing and its own background threads more safely.",
	"1.237":
		"Clearing your scrollback now clears the inline images that lived in it, instead of leaving them behind with nothing to belong to. SVG previews in the file browser draw more of what the file intends, including blend modes, rotated filters, right-to-left text, and clipped markers.",
	"1.235":
		"A session you restore now brings its inline images back with the rest of the screen, instead of leaving those pictures behind. Graphics transfers that were cancelled, or that restart in the middle of a sequence, are discarded cleanly rather than drawn half-finished.",
	"1.234":
		"Opening the Scratchpad for the first time after YEN starts no longer quits the app. The editor now takes focus once the panel has finished sliding in, which is what it was meant to do all along.",
	"1.233":
		"Every inline image on screen, whether it sits in the grid or is pinned in place with placeholder characters, is now drawn from the same snapshot the terminal takes of your screen each frame, so pictures stay in step with the text around them. Programs that report their status through OSC 7501 with a malformed id are refused instead of half-read, and a terminal that fails to open no longer leaks the memory it set aside.",
	"1.232":
		"Images that a program pins in place with Unicode placeholder characters, the method that keeps image previews working inside tmux, now redraw far faster: with a screen full of them, a frame that changes one line takes about a sixtieth of the time it did, because the terminal no longer rescans the whole window on every frame while one is visible.",
	"1.231":
		"Full-screen programs that set left and right margins keep the cursor inside them on a backspace or cursor-left, and programs in origin mode place the cursor where they asked. Image tools in a sandboxed Mac app can send pictures through shared memory again, the last button on a many-button mouse is tracked like the others, and terminal contents copied or saved with their escape codes replay with their blank gaps, erased backgrounds, and trailing blank lines intact.",
	"1.229":
		"The Tab Sidebar, the Scratchpad, and the Git drawer now open the way Quick Terminal does: each slides in from behind the edge of the terminal window with the same timing and fade, and slides back out the same way. The transient Tab Sidebar and the Scratchpad now open over the window's left and right edges instead of floating beside the window.",
	"1.227":
		"If your Mac is set to Japanese, Indonesian, or Catalan, more of the interface is translated. The command palette now has a Catalan translation.",
	"1.226":
		"The right-click menu now includes Close Split, so the split you clicked can be closed from that menu. Text dropped into the terminal goes through paste protection and bracketed paste, and a paste that contains carriage returns is checked the same way as one with newlines. A click on the prompt no longer also moves the cursor. A link from an unknown source is treated as untrusted, and YEN refuses to run a file whose path contains a control character. Wide-character selections now render the same text you copy. The bundled Git tool keeps drawing while you scroll a long diff, gets through a very long diff faster, and exits when a repository or worktree is deleted underneath it.",
	"1.225":
		"A coding agent working in a git worktree can now report its directory with the new yen pane cwd command, and the split label, the tab sidebar and the Git drawer follow that worktree while the agent is in front, without changing the shell's own directory. Split labels now pick up a branch switch in an idle pane instead of showing the old branch until the pane redraws. The terminal engine no longer occasionally drops an emoji that wrapped from the right edge when copying a selection, keeps every piece of an emoji sequence that widens at the end of a line, and answers programs that ask for the screen size in characters. The bundled fuzzy finder and Git tool each move up a maintenance release.",
	"1.224":
		"The terminal engine now supports the soft terminal reset command, so a program that sends it restores its modes and cursor state without clearing the screen. The engine also picks up paging fixes for its theme browser and a Danish translation update.",
	"1.223":
		"When a program turns on origin mode and then asks for its screen contents to be saved or copied out, the cursor position in that output is now written relative to the margins instead of the full screen. The terminal engine also picks up a Danish translation update.",
	"1.222":
		"Selecting a line of output with a triple-click now stops at the prompt instead of running on across blank space into the next one. Characters outside the old 8-bit range, printed while a program has switched character sets, now appear as themselves the way other terminals draw them rather than being mangled. A single-shift character set command now affects exactly one printed character, so the text after it is left alone.",
	"1.221":
		"When a program asks YEN to resize its window while the window is still animating into fullscreen, YEN now declines instead of resizing it mid-transition. On macOS 27, running a YEN action from Shortcuts, Spotlight, or the shortcuts command while no YEN window is open now gives you one window instead of two. The terminal engine also picks up its latest maintenance work: a more transparent tab bar over transparent title bars on macOS 27, correct mouse modes inside tmux panes, a new decoder for compressed terminal images, and stricter reading of the numbers inside terminal control sequences.",
	"1.219":
		"This build added a bundled file of license notices for the included open-source software. Nothing changed about how YEN runs.",
	"1.218":
		"Double-clicking a word next to CJK text or emoji now selects the word itself instead of running into the character beside it. When a program moves the cursor back across a line YEN wrapped for you, it lands on the row you would point at rather than jumping elsewhere. The terminal engine also picks up its latest maintenance work.",
	"1.217":
		"Split labels can name a pane after the git worktree its working directory sits in, falling back to the branch when the folder name is generic. Turn it on in Settings > Workspace > Split Labels; a label you type by hand still wins, and clearing it returns the pane to automatic naming.",
	"1.216":
		"The terminal engine moves forward with its latest maintenance work, bringing improved Unicode support, faster mode lookups, and ongoing stability improvements. Shipping builds continue to recognize stable Xcode toolchains reliably.",
	"1.215":
		"The terminal engine picks up Unicode 18, so characters and emoji added in the latest standard are measured and grouped correctly in the grid. Programs that ask which terminal modes are on get their answer from a faster lookup, and the engine picks up its latest maintenance work.",
	"1.214":
		"YEN's Bash shell integration now recognises prompt hooks kept in a PROMPT_COMMAND array without installing its own hook a second time. Split, focus, and close requests follow the same path as their keyboard shortcuts, and the terminal engine picks up its latest maintenance work.",
	"1.213":
		"YEN's Bash shell integration now hands the terminal each command's real exit status instead of reporting every command as successful, including prompt hooks that run several commands or receive their status through a PROMPT_COMMAND array. The terminal engine also picks up its latest maintenance work.",
	"1.212":
		"The terminal engine picks up its latest maintenance work. Shipping builds recognise Apple's current stable Xcode correctly.",
	"1.211":
		"The terminal engine picks up Lithuanian translation updates. Selected Settings rows keep a high-contrast label on the brand orange fill on every Mac YEN supports.",
	"1.210":
		"Custom fonts in the title bar no longer clip on macOS 26. Selected Settings rows keep a high-contrast label on the brand orange fill, search matches are marked by weight instead of orange text, and JP the Cat now lives in Help. The idle dictation menu extra is a template waveform that follows the menu bar. The terminal engine also picks up its latest maintenance work, including more complete answers to terminal mode queries and Italian translation updates.",
	"1.209":
		"The bundled Git tool moves up a release. Pressing Escape now registers immediately rather than lagging behind on some terminals, and the tool no longer loads or rewrites your configuration when it runs in the background for a single task. The terminal engine also picks up its latest maintenance work and translation updates.",
	"1.208":
		"The bundled fuzzy finder moves up a release. Stray characters no longer leak into the search box when a terminal answers a startup query late or when you hold Ctrl and press an arrow key, path ranking finds the last separator even when the line contains accented characters, and the list no longer opens a line short when a header or footer border is shown. The terminal engine also picks up its latest maintenance work.",
	"1.207":
		"Clipboard image paths now skip stale file URLs so pasted paths point to live files.",
	"1.206":
		"The terminal engine moves up to its 1.4 release, bringing its latest maintenance work and translation updates.",
	"1.205":
		"Hold an arrow, then press Cmd + D to split the focused terminal left, right, up, or down. The existing Cmd + D and Cmd + Shift + D shortcuts still split right and down.",
	"1.204":
		"A terminal that is still drawing now keeps its display timer running instead of stopping it while a frame is assembled, so animation and output stay in step. The terminal engine also picks up its latest maintenance work.",
	"1.203":
		"The bundled Git tool moves up a release. Stopping in the middle of a rebase now selects the conflicted commit for you, resolving a conflict keeps your place instead of jumping elsewhere, and files whose conflicts you have already settled stay in view rather than vanishing from the list. Diffs no longer flicker or glitch while they load, the tool starts faster, and the keybinding and recent-repository menus narrow as you type. Terminal color themes are refreshed, and the terminal engine picks up its latest maintenance work.",
	"1.202":
		"Held-down modifier keys are encoded more precisely for programs that ask for it: control key combinations, the numeric keypad, F13 through F25, Alt+Escape, and non-ASCII characters typed with Alt all now report through the same modern encoding path. The website now runs its server work beside YEN's Oregon-hosted release and download data, which removes the former cross-country database path.",
	"1.201":
		"Find Previous now moves backward when the search field has focus. Window placement also waits until macOS finishes showing a new window before applying its cascade, and each terminal starts with less fixed memory.",
	"1.200":
		"New tabs arrive without the brief flash they used to show, and windows with a hidden title bar now cascade like every other kind. A search keeps its results when a program writes more output above them, and opening a link or file no longer leaves a background helper spinning on a CPU core.",
	"1.199":
		"New terminal windows cascade into place again. Opening several in a row steps each one across the screen from the last, instead of stacking them all at the same spot.",
	"1.198": "The terminal engine picks up its latest maintenance work.",
	"1.197": "The terminal engine picks up its latest maintenance work.",
	"1.196":
		"A window you are not typing in now keeps up when it has something new to show. Output arriving in a background window is drawn at the display's own pace instead of waiting for you to look at it, so a build log or a long-running job stays current in the corner of your eye. Terminal programs that hand images to YEN through shared memory also have those requests checked against the naming rules before anything is opened, and a malformed request is refused rather than acted on.",
	"1.195":
		"Closing a window while several programs are still running now offers to review them first. YEN tells you how many windows have work in them and walks you through those windows one at a time, so you decide each one instead of ending everything on a single confirmation. The terminal engine also picks up its latest maintenance work.",
	"1.194":
		"AppleScript key commands now translate each key once through your current keyboard layout, so scripted input arrives as intended. Emoji font lookup also follows the latest macOS font names.",
	"1.193":
		"A terminal you are not typing in draws less. When a window has nothing new to show, the renderer parks its display timer rather than waking on every screen refresh, and starts it again the moment output arrives. Leave YEN open behind your other work and the idle time stops costing you frames nobody asked for.",
	"1.192":
		"The microphone picker announced two releases ago now actually appears. Settings > Sounds > Dictation shows a Microphone row listing System Default, named with the device it currently resolves to, alongside every other input you have connected. If you tried to find it after reading about it and could not, this is why: the control was built and tested but never drew itself on screen. The terminal engine also picks up its latest maintenance work, and the bundled file finder moves up a release.",
	"1.191":
		"The terminal follows the control-code rules more closely. A small group of control characters now takes effect as it is read rather than being passed through as text, and control codes that arrive as multi-byte sequences are ignored in that same position instead of being acted on. Programs that emit those bytes now draw the way their authors intended.",
	"1.190":
		"Dictation now records from the microphone you pick. Settings > Sounds lists every audio input device, and System Default names the device it currently resolves to, so you can see which microphone is about to be used. A microphone you selected that is no longer plugged in stays in the list marked as not connected instead of quietly reverting, and if YEN cannot use your choice it says why underneath the picker. A change applies to your next dictation, and unplugging a microphone mid-sentence ends that session cleanly rather than switching sources partway through.",
	"1.189":
		"Windows you are not looking at now release the graphics memory they were holding and rebuild it the moment you return. Text dropped onto the terminal arrives as a paste, so programs expecting bracketed paste handle it correctly. Clipboard exchanges follow the protocol more strictly: oversized writes are refused, encoded text is validated before it is accepted, and listing what is on the clipboard no longer raises a prompt. Terminal output is parsed more precisely, and recycled scrollback rows no longer carry stale formatting.",
	"1.188":
		"Programs running in the terminal can now read and write your clipboard through the clipboard protocol, always behind a confirmation prompt that previews images and names the files being shared. Dragging files onto the terminal reports them to the program you are using. Menu shortcuts follow your active keyboard layout, repeated new-tab presses stay responsive, and the cursor style no longer lingers after a program clears the screen.",
	"1.187":
		"Terminal images now respect relative placement and scroll or clip correctly within terminal margins. Voice documentation now explains when Apple keeps recognition on-device and when older macOS versions can use Apple's service. Thanks to Jon Tippens for the Voice feedback.",
	"1.186":
		"Voice now keeps your words safer during long dictation: audio-conversion failures preserve partial text and reset cleanly, while a larger layered rainbow waveform makes the listening state obvious. The retired forecast command has been removed from the CLI and public documentation. Thanks to Jon Tippens for helping improve Voice through direct feedback.",
	"1.185":
		"Reload Configuration now sits in its own Settings menu group, while selection links, clipboard copies, text bindings, and shell setup avoid several temporary allocations behind the scenes. The website now states YEN's system requirements, Apple Speech behavior, proprietary license, privacy boundaries, and service use more precisely, while the docs restore terminal history and a neutral approach comparison.",
	"1.184":
		"Images sent to the terminal now follow the graphics protocol more strictly: a tall image leaves the cursor in the cell after it, an unfinished transfer is discarded instead of shown incomplete, and a delete or query matches the image it named.",
	"1.183":
		"Backspace, Delete, and other control keys now stay on the physical key instead of being written as text, so programs using the extended keyboard protocol see what you pressed. Copying a wrapping line keeps the wrap, and notifications no longer split a UTF-8 character.",
	"1.182":
		"The terminal engine picks up its latest maintenance work, including config parsing fixes for theme paths and hex-escape handling.",
	"1.181": "The terminal engine picks up its latest maintenance work.",
	"1.180":
		"The terminal engine picks up its latest maintenance work, and the bundled file browser moves up several releases.",
	"1.179":
		"The terminal engine now handles grapheme-heavy output and wide-character reflow on resize much faster, so emoji-dense logs and CJK text stay responsive when the window changes size.",
	"1.178":
		"The terminal engine picks up its latest maintenance work, including notification delivery and rendering stability.",
	"1.177":
		"The terminal engine picks up its latest maintenance work, and the bundled system-info tool moves to its latest patch release.",
	"1.176":
		"The terminal engine adds Danish, Latvian, Polish, and Turkish translations, sizes dynamic tab stops more reliably, and picks up its latest stability work.",
	"1.175":
		"The terminal engine picks up its latest maintenance work, and the bundled Git TUI moves up a patch release.",
	"1.174":
		"The terminal engine picks up its latest maintenance work, and clipboard prompts learned some manners. When a program in an unfocused window asks to read your clipboard, the confirmation now waits until you actually switch to that window instead of interrupting whatever you were doing. Launching YEN from the command line with -e no longer mistakes the command's file paths for documents to open, Unicode hex input now accepts characters beyond the basic plane — emoji included — and keys like Escape and Tab map more predictably for programs using the extended keyboard protocol.",
	"1.173":
		"The terminal engine picks up its latest maintenance work. In-terminal search keeps the text you typed and its selection moving together, so the find bar no longer risks a stale selection when the needle changes, and on macOS 15 the find field sidesteps a system text-editing crash by using a plainer input path there.",
	"1.172":
		"YEN opens faster. The terminal engine's latest maintenance pass warms up the graphics pipeline while the app is still launching, looks up the emoji font directly, and stops loading windows nobody asked for — upstream measured roughly 15% off launch time and 27% off the wait for the first frame. Images sent to the terminal in multiple passes also stopped stacking on top of themselves when a program retransmits one.",
	"1.171":
		"Every menu-bar item YEN owns now carries an icon. Opening the file browser, taking a screenshot, closing a tab or a window, each split layout preset, the whole Find submenu, and the window controls for selecting and resizing splits were the last ones showing text alone, so finding a command is a glance at its shape rather than a read down the list. Items macOS supplies itself are left exactly as the system draws them. The terminal engine also picks up its latest maintenance work.",
	"1.170":
		"The Keyboard settings tab could open on an empty list — shortcuts that were there all along, just never loaded until you switched away and back. It now loads reliably the first time. The terminal engine also picks up its latest maintenance work.",
	"1.169":
		"The terminal engine moves forward with its latest maintenance work. Release checks now reject prerelease Xcode toolchains, verify vendor downloads against immutable provenance, and test tracked themes without depending on leftover build output — quieter changes that make the build you install easier to trust.",
	"1.168":
		"Settings stopped losing your work. Several settings can legitimately be set more than once — your keyboard shortcuts, a theme's individual colors, the fonts YEN falls back through — and saving from the Settings window kept only the last of each, silently discarding the rest. It now preserves every one. Editing a global shortcut works in both directions too: removing one actually removes it, rather than leaving behind a fragment that quietly disabled the key. Searching Settings finds more of what you would expect it to, and applying a layout preset now tells you what happened in the terminal itself instead of only in a Settings footer you may have closed.",
	"1.167":
		"An engine update that fixes a piece of mistaken plumbing. Four terminal actions YEN does not support on macOS were wired to fall through into the handler that reports a finished process, so asking for one of them ran unrelated code with the wrong information rather than doing nothing. They now correctly do nothing and say so. The menu-bar icon also adapts to how the next version of macOS wants to present it.",
	"1.166":
		"Clicking a notification from a terminal that was mid-move could focus nothing at all. While macOS attaches or moves a native tab, that terminal briefly has no window to speak of, and YEN was asking the window which pane it owned — so it got no answer and quietly gave up. It now asks the split layout, which knows the answer the whole time. The same fix keeps the command palette pointed at the right terminal instead of resetting its available commands mid-move.",
	"1.165":
		"If your Mac was locked, asleep, or between displays when a window started drawing, the timer that paces rendering could fail to attach and then never try again — leaving that window to redraw only when something changed. YEN now sets it up lazily and picks it back up when a display returns. The find bar also keeps its text selection valid while you retype, closing a terminal that asked not to be confirmed no longer stops to confirm anyway, and a pane being moved into a native tab is matched to the window that actually owns it rather than the one it briefly reports mid-move.",
	"1.164":
		"Updating is now something you can drive from the command palette — install and restart, or cancel and skip, without reaching for a menu. If an update already installed itself quietly in the background, quitting asks you first instead of closing on you, and checking for updates when one is already waiting tells you which version is staged and when it was released, rather than appearing to do nothing. Windows that tile now stay inside the visible screen area, and a run of repeated characters prints in batches instead of one at a time.",
	"1.163":
		"Images that arrive in pieces now display in full. A program sending the terminal a picture too large to fit in one message can split it across several, and YEN holds the parts until the last one lands instead of discarding them. Text shaping also stopped allocating memory on its hottest path, and the terminal releases the memory behind messages it never delivers.",
	"1.162":
		"When a program hands the terminal something to put on your clipboard, YEN now decodes it with a faster path and stops copying the payload around on the way out — which shows up when what you copied was large. Installing an update routes through a single code path instead of two that had drifted apart, and the renderer behind SVG previews in the file browser takes a patch update.",
	"1.161":
		"The renderer behind SVG previews in the file browser moves up a release, so vector files resolve more accurately when you look at them without opening anything.",
	"1.160":
		"The update notice now actually appears when an update check fails, instead of leaving you to wonder whether it ran. Underneath, the terminal tracks where a partially-received sequence left off, so output that arrives in pieces replays in the right order rather than losing its place.",
	"1.159":
		"A correctness fix in scrollback: shrinking the history left its internal bookkeeping out of step with the buffer it described. The rest of this release is the machinery around the download itself — the checks that stand between a change and the build you install now fail loudly when they cannot actually verify something, instead of quietly reporting success.",
	"1.158":
		"When YEN sets up a remote host over SSH, a failure to cache the terminal description no longer passes silently — you get told what went wrong and why, instead of landing in a session where colors and keys quietly misbehave. The bundled fuzzy finder also moves up a patch release.",
	"1.157":
		"A fix for links in scrollback: resizing a window rewraps every line that was already on screen, and lines carrying a clickable link were measured slightly short while being rewrapped. Widen or narrow a window now and the links in your history survive the reflow intact.",
	"1.156":
		"Link detection no longer swallows a trailing space, so a path you click at the end of a line resolves to the file you meant instead of one character too many. Programs can also ask whether the terminal is currently visible and get a truthful answer, which lets long-running tools hold their output until you're actually looking, and theme previews clean up after themselves when you exit the theme list.",
	"1.155":
		"The renderer now reserves only the graphics memory it actually needs when the grid grows, instead of twice that much, and box- and line-drawing characters are traced with a more precise inset path, so borders and table rules line up cleanly at any font size.",
	"1.154":
		"Scrollback can now be capped by number of lines instead of raw memory size, so history length means what you'd expect no matter how wide your window or how heavy each line is. The memory-based limit becomes optional, and either limit can be set to unlimited.",
	"1.153":
		"Terminal-engine fixes for the moments around closing and reopening work: tab teardown now completes in the right order instead of deferring cleanup, and programs that ask the terminal to describe its own cursor and underline state get accurate answers, so editors and shells restore what you were looking at.",
	"1.152":
		"A memory-efficiency pass across the native workspace: closed retain cycles in theme preview and dictation, bounded the background-wallpaper cache so it can't accumulate large decodes, and freed merge-conflict data on close, so long sessions stay lean.",
	"1.151":
		"A terminal-engine build refinement that keeps YEN linking cleanly against the latest macOS toolchains, so the engine underneath stays reliable and current.",
	"1.150":
		"A terminal-engine refresh on modernized build foundations, re-tuned for the latest macOS toolchains so YEN stays fast, stable, and current.",
	"1.149":
		"Every sliding panel — Quick Terminal, Git Drawer, Tab Sidebar, and Scratchpad — now follows the same park, slide, and complete sequence, including Reduce Motion, so open and close feel identical no matter which tray you use.",
	"1.148":
		"Quick Terminal is full-width again with the stray black bar removed and rounded edges restored. Quick Terminal, Git Drawer, Tab Sidebar, and Scratchpad now share one native slide-and-fade rhythm, while refreshed terminal foundations strengthen row handling under pressure.",
	"1.147":
		"Command Palette now takes focus immediately, closes cleanly after commands, Escape, outside clicks, or app switches, and returns typing to the terminal; Tab Sidebar also keeps its full-height frame even with only a few tabs.",
	"1.146":
		"Download 1.146 for the audit follow-through: Scratchpad protects unreadable notes, unusual Git filenames fail safely, review logs and background images stay reliable under concurrency, screenshots preserve exact pixels without overwrite races, and rejected shortcuts explain themselves clearly to sighted and VoiceOver users.",
	"1.145":
		"A deep macOS quality pass that reduces main-thread work, improves Settings and review responsiveness, strengthens data and permission handling, and expands VoiceOver, keyboard focus, Dynamic Type, toast, and dictation support throughout YEN.",
	"1.144":
		"A reliability, accessibility, and supply-chain pass: the command palette drops outdated searches so it stays quick in large repos, the merge-conflict view now handles accented and non-English filenames, background Git checks no longer collide with your own commits, and Bun installs now scan dependencies before they land — plus sharper dictation, safer clipboard handling, and better VoiceOver and Dynamic Type support throughout.",
	"1.143":
		"Synced the terminal engine and taught your cursor to survive a live config reload — restyle YEN mid-session and the cursor you asked for actually sticks.",
	"1.142":
		"A fresh engine sync plus a design pass: Dynamic Type support so the UI respects your system text size, and a tidy stacked-toast system for notifications.",
	"1.141":
		"Pulled in the latest terminal-engine work so YEN stays fast, stable, and current.",
	"1.140":
		"A terminal-engine refresh, a sharper bundled Git TUI, and a round of overlay fixes — so diffs, staging, and everyday panels feel instant.",
	"1.139":
		"Unified the marketing design system and refactored window border colors for one consistent, considered look across the whole product.",
	"1.138":
		"Fixed Quick Terminal width and unified the slide animations and rounded corners across every panel, so surfaces move as one coherent system.",
	"1.137":
		"Modularized Settings and fixed search and toast behavior — a faster, tidier control room for tuning YEN.",
	"1.136":
		"Sharpened in-terminal search and added nushell completions, so finding text and driving your shell both feel more precise.",
	"1.135":
		"Added a friendly toast that explains why a disabled Tab Sidebar or Scratchpad hotkey did nothing — no more silent mystery keys.",
	"1.134":
		"Closed a pinned tab-sidebar memory leak so long sessions stay lean, no matter how many tabs you keep around.",
	"1.133":
		"Moved Launch at Login into General settings, right where you'd expect to find it.",
	"1.132":
		"Wired up Reduce Motion and tuned terminal performance, so YEN respects your accessibility preferences without giving up speed.",
	"1.131":
		"A large terminal-engine sync plus a Sparkle 2.9.4 security update — the auto-updater that keeps YEN current is now hardened too.",
	"1.130": "A terminal-engine upstream sync to keep YEN fast and current.",
	"1.129":
		"Padding settings gained stepper arrows, so dialing in your window spacing is now a click instead of a guess.",
	"1.128":
		"Switched to delta patches, so updates download a fraction of the size and land faster.",
	"1.127":
		"Removed a logger crash risk in the app lifecycle, so startup and shutdown stay rock-solid.",
	"1.126":
		"Added the JP the Cat menu icon and cleaned up a duplicate test filename.",
	"1.125": "A terminal-engine upstream sync for continued speed and stability.",
	"1.124":
		"A 38-commit terminal-engine sync — a big batch of upstream speed and correctness work, folded in and verified.",
	"1.123":
		"Refreshed bundled tools and hardened the release pipeline behind them.",
	"1.122": "Kept the maintenance and release workflows in lockstep.",
	"1.121":
		"Improved multi-file clipboard paste, so dropping several files into the terminal at once just works.",
	"1.120":
		"Refreshed the built-in color themes for cleaner, more legible palettes out of the box.",
	"1.119": "Added a JP the Cat menu link for one-click access.",
	"1.118": "Routine maintenance and a dependency refresh to keep YEN current.",
	"1.117": "A terminal-engine refresh with a round of fixes.",
	"1.116":
		"Added selection-gesture support in the terminal library, so selecting content feels natural.",
	"1.115":
		"Fixed a text-rendering stability issue, so glyphs stay crisp and correct under load.",
	"1.114":
		"Sped up diff previews and background-image rendering, so heavy views stay smooth.",
	"1.113":
		"Fixed Quick Terminal and side-panel anchoring, so transient surfaces open exactly where you expect.",
	"1.112": "A terminal-engine update for continued speed and stability.",
	"1.111":
		"The Git drawer's j/k navigation now respects diff focus, so keyboard movement goes where your eyes are.",
	"1.110":
		"Copy-on-select now works correctly in the Git drawer and Scratchpad — highlight and it's yours.",
	"1.109":
		"The diff pane now sticks to the top and copies as plain text on select, so grabbing code stays clean.",
	"1.108":
		"The Git drawer now copies highlighted text the instant you select it.",
	"1.107":
		"The Git drawer header now shows your folder and branch at a glance.",
	"1.106": "Aligned the Git drawer icons for a tidier header.",
	"1.105":
		"Brought native diff coloring to the Git drawer, so additions and deletions read instantly.",
	"1.104":
		"Bounded the IDE detection scan and polished the Git drawer layout for faster, calmer startup.",
	"1.103": "Polished the Git drawer layout for a calmer, tidier view.",
	"1.102":
		"Gave the Git drawer a native Quick Terminal-style slide animation and folded in a small engine update with a retain-cycle fix.",
	"1.101":
		"Moved editor handoff off the main thread and fixed a controller leak and an unbounded merge-conflict preview — smoother, leaner Git work.",
	"1.100":
		"Refined Quick Terminal anchoring and added stash listings to the Git drawer.",
	"1.099": "Further Quick Terminal anchoring and Git drawer refinements.",
	"1.098":
		"Fixed a Git drawer overlay glitch so it renders cleanly every time.",
	"1.097": "Fixed a Git drawer shortcut so it fires reliably.",
	"1.096":
		"Fixed Git drawer diffs and folded in an 11-commit terminal-engine update.",
	"1.095": "Fixed Quick Terminal frame bounds so it always lands on-screen.",
	"1.094": "Maintenance update to the bundled JSON tool.",
	"1.093": "An upstream terminal-engine maintenance update.",
	"1.092":
		"Improved Shortcuts terminal capture and color handling for cleaner automation output.",
	"1.091": "Refined Settings navigation and the theme catalog.",
	"1.090":
		"Settings tabs now render eagerly, so switching between them is instant.",
	"1.089":
		"Brightened Settings input outlines for clearer, more legible fields.",
	"1.088": "Normalized and polished the Settings panel end to end.",
	"1.087":
		"Streamlined Settings copy and sharpened shortcut feedback, so the panel reads and responds better.",
	"1.086": "Fixed the increase-font-size keyboard shortcut.",
	"1.085":
		"Faster file previews plus reliability fixes, so browsing files stays quick and trustworthy.",
	"1.084": "Updated the bundled file finder for faster, more accurate matches.",
	"1.083":
		"Layout presets now target the focused tab, so arranging splits does exactly what you meant.",
	"1.082":
		"Improved terminal click reporting and shell integration for more accurate mouse and prompt behavior.",
	"1.081": "A round of stability, performance, and bundled-tool fixes.",
	"1.080": "Fixed a browser link crash, so opening links stays rock-solid.",
	"1.079": "Fixed system-info rendering and shored up stability.",
	"1.078":
		"A 13-commit engine update and system-info tool refresh, with the fail-closed release gates hardened behind them.",
	"1.077": "Fixed a tab-sidebar toggle crash, so the panel opens every time.",
	"1.076": "Fixed Quick Terminal splits and refreshed bundled tools.",
	"1.075":
		"Fixed a memory-safety issue in terminal selection, so selecting large output stays safe.",
	"1.074": "A terminal-engine refresh with color-scheme updates.",
	"1.073": "Terminal-engine improvements for continued speed and correctness.",
	"1.072": "Terminal-engine and bundled Git tool updates.",
	"1.071":
		"An upstream terminal-engine refresh for continued speed and stability.",
	"1.070": "An upstream terminal-engine refresh, folded in and verified.",
	"1.069": "Refreshed the bundled Git TUI with the latest upstream work.",
	"1.068":
		"A vendor refresh — a 22-commit engine update and a newer fuzzy finder, folded in and verified.",
	"1.067": "Smoother search and a round of reliability tweaks.",
	"1.066": "Refreshed the fuzzy finder and bundled tooling.",
	"1.065": "Smoother focus and quit handling, so windows behave predictably.",
	"1.064":
		"Made the Services-menu “Open Terminal Here” reliable, so right-click-to-terminal always works.",
	"1.063": "Fixed nested splits and split resizing for predictable layouts.",
	"1.062":
		"Opacity now persists across tabs and windows, so your chosen transparency stays put.",
	"1.061": "Refreshed the bundled system-info tool.",
	"1.060": "Normalized paths on macOS and added a new locale.",
	"1.059": "Refreshed the file browser and sped up previews.",
	"1.058":
		"Tab-sidebar clicks now register immediately and rename paths stay aligned.",
	"1.057":
		"Locked the Settings sidebar and removed its collapse button for a steadier layout.",
	"1.056": "Fixed a batch of Settings paper cuts and cleaned up sounds.",
	"1.055": "Fixed Settings deep-link scrolling so links land on the right row.",
	"1.054":
		"Added Apple Silicon GPU monitoring via an updated system monitor, so you can watch your GPU right in the terminal.",
	"1.053":
		"The “yen agents” note now shows help when run bare, so discovery is built in.",
	"1.052": "IME polish, a cleaner copy menu, and a command-palette focus fix.",
	"1.051": "Search fixes, middle-click actions, and an engine refresh.",
	"1.050": "Browser polish, longer search reach, and an engine refresh.",
	"1.049":
		"Reliability fixes and accessibility polish, plus an engine refresh.",
	"1.048": "Hardened the shell IDE-detect payload.",
	"1.047": "Documentation and tooling refinements.",
	"1.046": "An upstream maintenance update to keep YEN current.",
	"1.045":
		"A 37-commit terminal-engine sync that adds OpenType font validation, so richer fonts render correctly.",
	"1.044": "A terminal-engine sync with module cleanup.",
	"1.043": "Scriptability additions and stability fixes.",
	"1.042": "Hardened the browser split-window lifecycle.",
	"1.041": "Browser audit hardening and a UI layering fix.",
	"1.040": "Faster UTF-8 handling and viewport fixes.",
	"1.039": "Stability and menu-shortcut improvements.",
	"1.038": "Settings lifecycle polish and build hygiene.",
	"1.037": "A terminal-engine refresh with retired-feature config cleanup.",
	"1.036":
		"Fixed a tab memory leak and shrank the binary, so YEN is lighter to run and to download.",
	"1.035": "A terminal-engine update with window fixes.",
	"1.034": "Dead-code cleanup and a terminal-engine update.",
	"1.033": "Memory fixes and a terminal-engine vendor update.",
	"1.032": "Review-workspace polish and a vendor-pipeline fix.",
	"1.031": "A terminal refresh with Tahoe dock-icon polish.",
	"1.030":
		"A terminal-engine refresh plus a hidden-surface memory optimization for leaner background tabs.",
	"1.029": "A terminal-engine refresh and a Scratchpad copy-on-select fix.",
	"1.028": "Vendor updates and a source-built diff renderer.",
	"1.027": "Hardened the build workflow and docs.",
	"1.026": "Vendor updates and maintenance to keep the bundled tools fresh.",
	"1.025": "Hardened app intents and trust gating.",
	"1.024": "Cached IDE detection for noticeably faster shell prompts.",
	"1.023": "Hardened app intents and IDE port detection.",
	"1.022": "Cleaned up the Settings sidebar layout.",
	"1.021": "A Settings typography consistency pass.",
	"1.020": "Fixed menu shortcuts and a notification icon.",
	"1.019": "Fixed delete-key mapping and folded in an engine update.",
	"1.018": "A terminal-engine update that fixes overlay drift.",
	"1.017": "Eliminated wallpaper flicker on config changes.",
	"1.016": "Hardened wallpaper loading and updated the terminal engine.",
	"1.015": "Added iCloud wallpaper download retry.",
	"1.014": "Fixed wallpaper titlebar transparency.",
	"1.013": "Fixed whole-window wallpaper not showing.",
	"1.012": "Enabled the Sparkle auto-update permission dialog.",
	"1.011": "A maintenance rebuild with stability improvements.",
	"1.010": "Updated the terminal engine and system-info tool.",
	"1.009": "Updated the terminal engine and bundled packages.",
	"1.008": "Added a wallpaper scope toggle and runtime hardening.",
	"1.007": "Updated packages and the vendored terminal engine.",
	"1.006": "A docs update plus IDE workspace detection.",
	"1.005": "Restored the Settings panel design for a cleaner, familiar layout.",
	"1.004": "Faster IDE detection and an update-logic fix.",
	"1.003": "A terminal-engine sync and a branding-check false-positive fix.",
	"1.002": "A terminal-engine sync and vendor refresh.",
	"1.001": "A terminal-engine sync and a zsh prompt fix.",
	"1.000":
		"The 1.0 milestone — a terminal-engine sync and vendor refresh mark YEN crossing into 1.x.",
	"0.999": "A Settings refresh, terminal-engine update, and hardening.",
	"0.998": "Fullscreen fixes, notch handling, and a terminal-engine update.",
	"0.997": "IDE hardening, sharing, and Settings polish.",
	"0.996":
		"Layout-aware keybind conflict detection, notification coalescing, and an export flush fix.",
	"0.995":
		"Split-pane labels, command-palette hardening, and a terminal-engine vendor update.",
	"0.994": "A tab-sidebar deinit fix and hardening improvements.",
	"0.993": "Bug fixes and improvements across everyday use.",
	"0.992":
		"Added the Tab Sidebar, PR review workspace, and merge-conflict workspace — richer Git work without leaving the terminal.",
	"0.991":
		"Security hardening, Scratchpad click-away, and a Homebrew cask install path.",
	"0.990": "A vendor update with dictation improvements.",
	"0.989": "Workflow hardening and release maintenance.",
	"0.988": "An engine refresh with stability improvements.",
	"0.987": "An engine refresh with stability improvements.",
	"0.986": "An engine update with focus and prompt fixes.",
	"0.985": "An engine update and build-pipeline hardening.",
	"0.984":
		"An engine update, legacy branding cleanup, and a surface baseline fix.",
	"0.983": "An engine update, new DMG artwork, and notification hardening.",
	"0.982": "An engine update, document attachments, and stability work.",
	"0.980": "An engine update and a redesigned DMG installer.",
	"0.979": "An engine update with stability fixes.",
	"0.978": "DMG layout polish and an engine update.",
	"0.977": "Full-bleed icons for clean Tahoe rendering.",
	"0.976": "Fixed the Finder icon chrome on Tahoe and updated the engine.",
	"0.975": "Fixed the About-window icon border on Tahoe.",
	"0.974": "Refreshed the DMG art and updated the terminal engine.",
	"0.973": "DMG installer reliability and dictation fixes.",
	"0.972":
		"A dictation stop-session refactor and a DMG Finder persistence fix.",
	"0.971": "A new app icon and dictation hotkey improvements.",
	"0.970": "Sound-pack UX, a vendor sync, and docs polish.",
	"0.969": "A vendor sync and terminal-engine update.",
	"0.968": "A vendor sync and notification UX polish.",
	"0.967": "A terminal-engine window-restore fix and keybind remap.",
	"0.966": "Disabled-panel menu gating and status polish.",
	"0.965": "Scratchpad, Settings, and dictation hardening.",
	"0.964": "A documentation audit and path fixes.",
	"0.963":
		"Added the global Scratchpad panel — a quick, always-there note surface.",
	"0.962": "Routine vendor maintenance to keep bundled tools current.",
	"0.960": "System-info layout improvements and test sync.",
	"0.959": "System-info ASCII-art colorization and layout improvements.",
	"0.958": "A documentation audit and public-docs cleanup.",
	"0.957": "Fixed network-retry detection and a shell-script regex.",
	"0.955": "A terminal-engine sync and refreshed bundled system tools.",
	"0.954": "Provenance hardening and a terminal-engine sync.",
	"0.953":
		"Reliability hardening, accessibility work, and a terminal-engine update.",
	"0.952": "Badge notifications and build-pipeline hardening.",
	"0.951": "A sound-library refresh and terminal-engine update.",
	"0.948": "Hardened the DMG layout and release checklist.",
	"0.947": "Concurrency hardening and provenance-guard consistency.",
	"0.946": "Hardened build-pipeline safety and script reliability.",
	"0.945": "Hardened vendor and branding provenance guards.",
	"0.944": "A vendor update with split-focus stability.",
	"0.943": "Git TUI spacing fix and hotkey hints.",
	"0.942": "Branded the bundled Git TUI with yengit aliases.",
	"0.941": "Build-pipeline hardening and stability.",
	"0.940": "Integrated the Git TUI and updated the terminal engine.",
	"0.939": "A responsive welcome banner and overlay-pipeline fixes.",
	"0.938": "A terminal-engine update and dictation hardening.",
	"0.937": "File-browser hardening and expanded test coverage.",
	"0.936": "Automatic release-artifact cleanup to keep downloads tidy.",
	"0.935":
		"Hardened the build pipeline so every release ships clean and verified.",
	"0.934":
		"A terminal-engine update that restores file-browser Git status colors.",
	"0.932": "File-browser fixes for smoother, more reliable browsing.",
	"0.931": "A terminal-engine update and build-pipeline cleanup.",
	"0.930": "A vendor refresh to keep the bundled tools current.",
	"0.929": "A docs refresh and build hardening, so releases stay dependable.",
	"0.928": "File-browser theme parity and build-workflow improvements.",
	"0.927": "Bug fixes and stability improvements.",
	"0.926": "File-browser theme fallback and path canonicalization.",
	"0.925": "A split-opacity rollback and file-browser preview hardening.",
	"0.924": "A Swift covariance fix, vendor sync, and todo cleanup.",
	"0.923": "A docs refresh, vendor sync, and an Intel build fix.",
	"0.922": "Split transparency and memory hardening.",
	"0.920": "Settings accessibility and opacity-display fixes.",
	"0.919": "Docs cleanup and a terminal-engine update.",
	"0.918": "A terminal-engine update for continued speed and correctness.",
	"0.917":
		"Internal cleanup and entitlement hardening for a tighter, safer app.",
	"0.916": "A terminal-engine update with internal cleanup.",
	"0.915": "Theme-override persistence and a terminal-engine update.",
	"0.914": "A terminal-engine update and window-border hardening.",
	"0.913": "Memory-lifecycle hardening across the overlay stack.",
	"0.912": "Window-border hardening and a tab-inheritance fix.",
	"0.911": "A Settings titlebar fix, menu icons, and an engine update.",
	"0.910": "Sound-pack pipeline hardening and clearer build-status wording.",
	"0.909":
		"Window standards, Settings lifecycle hardening, and an engine update.",
	"0.908": "An engine update and build-pipeline hardening.",
	"0.906": "An engine update, sound packs, and build improvements.",
	"0.899": "Resource hardening and a UI spacing fix.",
	"0.897":
		"Detected legacy dictation-disabled state and hardened sound import.",
	"0.896": "Settings UX fixes for shortcuts and speech setup.",
	"0.894": "Dictation permission prompts and an onboarding visibility fix.",
	"0.893": "Hardened the build pipeline and auto-detected the build token.",
	"0.892":
		"A terminal-engine update, a vendor-audit gate, and a Settings toolbar.",
	"0.891": "A terminal-engine update with native archive previews.",
	"0.890": "File-browser previews and pipeline hardening.",
	"0.889": "Preview tools, a terminal-engine update, and skins cleanup.",
	"0.888": "Build-pipeline hardening and a terminal-engine update.",
	"0.887": "A terminal-engine update and pipeline fixes.",
	"0.886": "Sound-pack delivery and a terminal-engine update.",
	"0.885": "Pipeline verification and a skins-builder call to action.",
	"0.884": "New sounds, skin frames, and build hardening.",
	"0.883":
		"A terminal-engine vendor update, palette skins, and dictation fixes.",
	"0.882": "Speech recognition hardening and a docs-accuracy pass.",
	"0.881": "The SpeechAnalyzer migration and design-audit fixes.",
	"0.880": "A terminal-engine update and a Swift concurrency fix.",
	"0.879": "A terminal-engine update and web hardening.",
	"0.878": "Experimental skins, sidebar polish, and build fixes.",
	"0.877":
		"An Experimental tab, a hands-free pointer, and a terminal-engine update.",
	"0.876": "A whitepaper refresh and documentation updates.",
	"0.875": "CLI sign-out, aliases, and a terminal-engine update.",
	"0.874": "Hands-free pointer reliability across macOS versions.",
	"0.872": "A hands-free camera fix and keybind-safety improvements.",
	"0.871": "A hands-free pointer toggle and branded build notifications.",
	"0.869": "A notification sound picker and app alerts.",
	"0.867": "Cleaner CLI app routing.",
	"0.866":
		"Tabbed Settings and a keyboard-shortcut editor with conflict detection.",
	"0.864": "Cloud DMG hosting and a terminal-engine update.",
	"0.863": "Notification sounds and cloud DMG hosting.",
	"0.862": "A stability and polish build, smoothing the everyday rough edges.",
	"0.861": "More stability and polish for calmer daily sessions.",
	"0.860": "A round of stability and polish across the app.",
	"0.859": "Typing indicators and a terminal-engine update.",
	"0.858": "Ten split-layout presets, mapped to Cmd + Option + 1-0.",
	"0.856": "Added split-layout preset customization.",
	"0.854": "A terminal-engine update that fixes an escape-sequence leak.",
	"0.847":
		"Escape-aware wrapping, notification improvements, and a terminal-engine vendor update.",
	"0.845": "Build-verification hardening across 29 branding checks.",
	"0.842": "A menu-bar click menu and docs updates.",
	"0.841": "The Tab Sidebar, animation fixes, and a docs update.",
	"0.840": "Code quality, accessibility, and docs-accuracy work.",
	"0.835": "Path hardening, strict smoke tests, and docs cleanup.",
	"0.834": "Hardened vendor checks and fixed the release workflow.",
	"0.833": "Updated the terminal engine and cleaned up docs.",
	"0.832": "Fixed a file-browser bracketed-paste bug.",
	"0.831": "Three-digit versioning and a spec rewrite.",
	"0.83": "Hardened layout save with validation and auto-clear.",
	"0.77": "Added a recording indicator for voice-to-text dictation.",
	"0.56": "A terminal-engine zsh title-handling fix.",
	"0.55": "A stabilizing build for daily usage.",
	"0.29": "A brand accent color for system UI.",
	"0.15": "Terminal-engine updates and performance improvements.",
	"0.82": "ARM64-only builds — smaller, faster downloads.",
	"0.81": "Apple Silicon only — smaller ARM64 builds.",
	"0.80": "A smaller app bundle after a size-optimization pass.",
	"0.79": "Build fixes and script-path updates.",
	"0.78": "Build fixes for the terminal-engine structure mirroring.",
	"0.76": "A config-driven theme system and leaner shell checks.",
	"0.75": "Path fixes for window styles.",
	"0.74": "Bug fixes and improvements.",
	"0.72": "Build-workflow hardening with explicit file permissions.",
	"0.71": "The DMG distribution format.",
	"0.70": "Restructured the documentation with sequential numbering.",
	"0.69": "Removed emojis from build scripts.",
	"0.68": "A simplified build workflow and shell-compatibility fixes.",
	"0.67": "Fixed build-process issues and documented critical fixes.",
	"0.66": "Critical build fixes and comprehensive documentation.",
	"0.65": "Simplified the Sparkle update architecture and workflows.",
	"0.64": "Fixed cache-clearing scripts and added a /nuke-cli command.",
	"0.63": "TUI formatting improvements and a directory cleanup.",
	"0.62": "Added CLI diagnostic tools and richer cache clearing.",
	"0.61": "Cleaned up duplicate documentation tables.",
	"0.60": "Updated documentation for build-workflow improvements.",
	"0.59": "CLI hardening and a comprehensive failure-mode audit.",
	"0.58": "CLI TUI component-library updates and dependency improvements.",
	"0.57": "CLI TUI Phase 3 completion and build-workflow improvements.",
	"0.54": "Fixed the Sparkle updater restart by checking session state.",
	"0.53": "Fixed the Sparkle relaunch path to prevent install failures.",
	"0.52": "Fixed Sparkle update signing and added key verification.",
	"0.51": "TUI build integration and CLI improvements.",
	"0.50": "Fixed a download-route corruption bug and enforced CLI auth.",
	"0.49": "Fixed build cleanup so signed release files are never deleted.",
	"0.48": "Made the welcome banner easier to read and cleaned up old files.",
	"0.47": "Fixed deployment verification of relative download links.",
	"0.46":
		"Download links now point straight at versioned files, so it's crystal clear which build you're getting.",
	"0.45": "Fixed a build-process warning.",
	"0.44": "Fixed a download-route 404 and removed unsafe-eval from the CSP.",
	"0.43": "Fixed out-of-memory handling in config cloning.",
	"0.42": "Simplified the build by removing 12 unneeded customizations.",
	"0.41": "Build race-condition prevention and dependency documentation.",
	"0.40": "Fixed critical shell-integration path bugs.",
	"0.39": "Added the /download route with versioned filenames.",
	"0.38": "Added a custom 404 page with the global header and footer.",
	"0.37": "Fixed an empty-config-file crash.",
	"0.36": "Simplified the welcome banner and build workflow.",
	"0.35":
		"Optimized queries for faster performance and refreshed the terminal engine.",
	"0.34": "A single-source-of-truth version-sync workflow.",
	"0.33": "Fixed welcome-banner version display and shell wrappers.",
	"0.32": "Process improvements and comprehensive documentation updates.",
	"0.31":
		"Migrated the site to Tailwind v4 and made the mobile menu consistent everywhere.",
	"0.30": "Polished the docs and consolidated Sentry setup.",
	"0.28":
		"Made build-verification scripts far clearer, so you always know what went wrong.",
	"0.27": "Fixed a welcome-banner build bug and improved update detection.",
	"0.26": "Fixed a Sparkle update-check race and documented the init order.",
	"0.24": "Fixed the welcome-banner build and documented shell integration.",
	"0.21": "Freshened up some stale documentation.",
	"0.20": "Freshened up some stale documentation.",
	"0.19": "Fixed version.json bundling and a build-script path bug.",
	"0.18": "Fixed the welcome banner using a .zshenv pattern.",
	"0.17": "Fixed welcome-banner build order and version conflicts.",
	"0.16": "Fixed build-order issues with file-rename verification.",
	"0.14": "Fixed a Sparkle update-detection bug and cleaned up CLI wrappers.",
	"0.13": "Added animated squiggle underlines and trimmed CLI wrappers.",
	"0.12": "Updated the terminal engine and aligned the build process.",
	"0.11": "Fixed a Sparkle update-installation bug.",
	"0.10": "Refined the build workflow with systematic component verification.",
	"0.099": "A welcome-banner version documentation update.",
	"0.098": "Fixed an About-panel typo and improved the welcome banner.",
	"0.097": "Fixed an About-panel typo and added Intel-Mac universal binaries.",
	"0.096": "Speech build integration and docs cleanup.",
	"0.095": "Welcome-banner and menu-icon fixes.",
	"0.094": "Build-workflow polish and welcome-banner restoration.",
	"0.73": "Separated the app and model versions for clearer versioning.",
	"0.7.22": "A status-bar redesign.",
	"0.7.18": "A shell-integration path fix and cleanup.",
	"0.7.17": "Fixed shell integration so YEN features persist after login.",
	"0.7.16": "Bug fixes and polish.",
	"0.7.15": "Simplified the update flow to reuse the quit dialog.",
	"0.7.14": "A documentation polish release.",
	"0.7.13": "User-controlled update installation flow.",
	"0.7.12": "A build verifying Sparkle updater relaunch.",
	"0.7.11": "Fixed the Sparkle updater not relaunching during updates.",
	"0.7.10": "Fixed the wrapper not executing on terminal launch.",
	"0.7.9": "Fixed the default theme so YEN's defaults ship correctly.",
	"0.7.8": "Internal workflow hardening.",
	"0.7.7": "macOS 13 API compatibility and branding fixes.",
	"0.7.6": "Fixed Sparkle auto-updates.",
	"0.7.5": "A security patch with CLI fixes.",
	"0.7.4": "Settings page polish.",
	"0.7.2": "Build-workflow improvements.",
	"0.7.1": "Build-workflow improvements and a copy-button visibility fix.",
	"0.7.0": "Settings simplification and a menu-icon fix.",
	"0.7.21": "Quieted verbose keychain output.",
	"0.07": "A version-system overhaul on a single-source-of-truth pattern.",
	"0.06": "Path-standardization fixes and build-workflow improvements.",
	"0.05": "Fixed version display in the About panel and status-bar menu.",
	"0.04": "Fixed formatting issues in the Zig build system.",
	"0.03": "Fixed a formatting issue in the Zig build system.",
	"0.01": "Simplified the versioning system.",
	"0.6.94": "Brand-orange update notifications.",
	"0.6.92": "Fixed Sparkle auto-update notifications.",
	"0.6.9": "Enabled automatic update checks.",
	"0.6.8": "The build workflow now uses real commit data for release notes.",
	"0.6.7": "A performance-improvements release.",
	"0.6.6":
		"Fixed an input-buffer leak and signed the Git helper for notarization.",
	"0.6.5": "Apple notarization and code signing.",
	"0.6.4": "The first release with styled Sparkle update notes.",
	"0.6.3": "Documentation cleanup and build fixes.",
	"0.6.1": "Documentation consolidation and a slash-command audit.",
	"0.5.5": "Wrapper verification tests and a release workflow command.",
	"0.5.4": "The terminal startup wrapper, baked into the app.",
	"0.5.3": "Consolidated release files and auto-version display.",
	// Mixed retired+surviving builds, curated to the surviving feature only:
	"0.7.19": "Added the terminal status bar.",
	"0.09": "Security and shell-wrapper hardening.",
	"0.08": "Version badges on the Settings page.",
};

// Monday week-start -> curated public story for every release week.
// Keep these proportional to the version evidence above. The weekly story is the
// reader-facing release note; individual versions remain generated provenance.
export const RELEASE_WEEK_COPY: Record<string, string> = {
	"2026-11-16":
		"Open a second tab on macOS 14 or later and both tabs sit beside the window controls. In fullscreen, the two buttons at the upper left open the sidebar and return you to a window.\n\nLeave a dev server running in a shell pane and quit YEN. When you reopen it, the server still has its port and the pane brings back its screen and scrollback. After a crash, YEN can reopen up to eight detached shells, including shells from an older version. Closing a pane still ends its session. Run yen sessions to see what's running, or use End All Sessions in Settings to stop them together.\n\nIf you use Retina and non-Retina displays together, Japanese text and other fallback characters keep the right glyphs after your Mac wakes. In the diff viewer, deleted files keep their syntax highlighting, and you can see when a submodule has uncommitted changes.\n\nThe online manual now covers split headers in builds from source. Click a header to focus its pane or drag it to a highlighted edge. The icons in a tab show which tools its panes are running.",
	"2026-11-09":
		"Open Settings and your terminal fills the window as a live preview, with a glass inspector beside it holding five short panes: Appearance, General, Notifications, Dictation, and Shortcuts. Pick one of the 20 bundled themes from the dock and the preview changes at once; click a shortcut to record a new one. Search, import and export, and per-pane reset are gone, so changing how YEN looks and behaves takes a glance instead of a hunt. A config with no theme, or one naming a theme YEN no longer bundles, opens with YEN, and the tab sidebar takes its color from the theme the terminal applied.\n\nSwitch folders in a split, and the Git drawer follows that split even with the tab sidebar hidden, refreshing when repository files change. Resize a window taller and narrower, and your scrollback fills the new rows instead of leaving a blank gap. Click a split you were not working in and it only takes focus, so neither the press nor the release reaches the program inside it, and a prompt that redraws on resize no longer leaves a stale copy behind. Restore a session and the next thing you type uses room the last page already kept, so it does not pause to allocate it. The sidebar, split labels, command palette, and window backgrounds reuse repeated work, a terminal image stays visible while its replacement arrives, output keeps the valid text before a stray invalid byte, layout presets check the focused pane before opening terminals, and the Indonesian and Dutch translations are refreshed. Late in the week, scrolling and erasing output do slightly less work, and if you set copy-on-select = true in your config, a selection now goes only to the selection pasteboard that Paste Selection reads; set it to both to keep the clipboard copy, which stays the default. If the fallback font for a character cannot load, that cell now shows a replacement mark instead of blanking the whole row.\n\nDictation drops superseded preview updates and ignores late permission replies from an old session. YEN checks the target pane again before pasting; if paste fails, it tells you once and leaves the transcript on the clipboard. With translation off, the next transcript can insert immediately after pending work finishes. The web guide now groups workspace controls, combines installation with requirements, and removes historical and comparison material, keeping setup and feature limits close at hand.",
	"2026-11-02":
		"Open a new tab, split, or window and you stay in the folder you were working in, even when your Mac's name contains spaces, apostrophes, or underscores. Text that mixes regular and wide characters, including CJK text and emoji, draws faster, and wide characters stay inside a program's margins after a line wraps.\n\nYou can quit while a paste confirmation is open instead of dismissing it first. On macOS 27, showing the tab bar or merging windows no longer leaves the bar clipped. Resizing a terminal with scrollback disabled also keeps the cursor valid when its old row disappears.\n\nYou can now open Bitcoin directly from Help or from About, beside Docs, and spot JP the Cat by its paws icon in Help. On the website, Music and the other project links live together in the footer, and Terms brings privacy and cookies onto one page. Later in the week, you can switch a window between light, dark, and your system appearance for the session from the command palette, without editing your config. A triple-click over output with blank lines keeps the whole selection, and connecting with the ssh helper now checks that the remote host can actually use YEN's terminal type before relying on it. The week ends with the ssh helper installing terminal support on a remote host through a standard shell, so it no longer depends on your login shell there, while the bundled file search and fuzzy finder tools pick up their latest fixes. On Sunday, drawing got sturdier: if the terminal runs short of memory mid-frame, the rows it missed are drawn again on the next one, and widening a window with deep scrollback keeps your selection on the lines you chose. If you work with submodules across git worktrees, the bundled Git tool no longer breaks one in your main checkout when you remove it elsewhere. The small controls around your terminal take fewer detours, while the text you work with stays where it belongs.",
	"2026-10-26":
		"Move a tab between windows on macOS 26 and the title bar no longer flashes during the move. Programs that request a terminal mode report also get their response without a possible hang, and the zoom indicator no longer stays behind on a split that is gone.\n\nOpen a folder whose name contains escape characters and shell integration no longer passes them through to your terminal. Malformed tmux pane layouts are now rejected instead of being accepted, so a bad layout cannot leave a pane in a broken state.\n\nIf you script YEN with AppleScript, tabs and terminals now have a name override property you can read and set. The software updater also moves up a release, so the next update check runs on the newer one.\n\nA configuration file is also harder to break. A value that stops partway through a multi-byte character can no longer crash YEN while it loads your settings, and a Unicode escape inside a value is validated properly instead of being half-read, so a typo in your config shows up as a clear error rather than a quit. Later in the week, an environment value that runs past 256 characters also stops making the settings printout fail.\n\nFull-screen programs get more of the terminal they expect, too. Editors and tools that insert or delete whole columns, or that step the cursor past the left or right margin, now see those requests carried out instead of ignored, so a redraw lands where the program meant it to.\n\nThe week closes with tmux control mode getting more dependable. Close a tmux window or switch to another one and YEN follows along, pane output that contains escaped characters appears the way it was written, and that output is now parsed without a regular expression. A command in your configuration with extra spaces between its words runs as you meant it, and copied text that wraps at the right edge keeps its line intact. If you connect through the ssh helper, the authentication messages it used to hide while setting up terminfo now show, and clearing the screen in a shell that does not mark its prompts skips a prompt scan it never needed.\n\nThe last build of the week is about speed. Run something with a lot of color, like an editor, a system monitor, or a colorful build log, and YEN now draws it with less work: each color and style change is applied in one step, and new scrollback starts with the room recent output needed instead of growing again and again.",
	"2026-10-19":
		"If you run full-screen programs that draw inside margins, the cursor now stays where they put it. A backspace or a cursor-left stops at the left margin instead of slipping past it, and a program in origin mode moves the cursor relative to its scrolling region, so editors and dashboards that draw in a box line up the way their authors intended.\n\nThe rest of this update is just as specific. An image tool running inside a sandboxed Mac app can hand pictures to the terminal through shared memory again instead of being refused, the eleventh button on a many-button mouse is tracked like any other, and when you copy or save terminal contents with their escape codes, replaying them brings back the blank gaps, erased backgrounds, and trailing blank lines that were there.\n\nImages got cheaper to keep on screen, and they come back with you. If you use an image tool that pins pictures in place with placeholder characters, the method that keeps previews working inside tmux, a screen full of them now redraws a changed line in about a sixtieth of the time, because the terminal no longer rescans the whole window on every frame. Every kind of image is drawn from the same snapshot of your screen the text is drawn from, so a picture stays in step with the lines around it. Restore a session and those pictures come back with the rest of the screen instead of vanishing, and a transfer that was cancelled or that restarts mid-sequence is discarded instead of drawn half-finished. Clear your scrollback and the images that lived in it go with it. SVG files in the file browser preview more faithfully too, with blend modes, rotated filters, and right-to-left text drawn the way the file intends. Nothing about how you work changes; the programs you run draw where they mean to, and the images you keep on screen no longer slow down every frame.\n\nOne fix matters more than its size. If YEN quit the first time you opened the Scratchpad, that is fixed: the panel slides in from the right edge of your window, the editor takes focus once it arrives, and your notes are where you left them. If you open the bundled system monitor, it no longer quits during a network Time Machine backup or while reading a swap disk.",
	"2026-10-12":
		"Right-click a split and Close Split is in the menu. It closes the split under your pointer, on the same path as the other split commands, so the pane you clicked is the one that goes. The panels around your terminal now move as one set, too. Open the Tab Sidebar, the Scratchpad, or the Git drawer and it slides in from behind the edge of your window, left, right, or bottom, with the same timing and fade as Quick Terminal, and the sidebar and the Scratchpad open over the window's edge instead of floating beside it.\n\nDrop a block of text into the terminal and it now takes the same path as a paste. Paste protection and bracketed paste apply to the drop, a paste that carries carriage returns is checked the way a paste with newlines already was, and a click on your prompt no longer also moves the cursor. A link from a source the terminal does not know is treated as untrusted, and YEN refuses to run a file whose path contains a control character.\n\nThe bundled Git tool stays readable on a long diff. Scrolling keeps the drawing in place, a very long diff gets through faster, and if a repository or worktree is deleted while the tool is open it exits instead of remaining on a folder that is gone. A wide character you select is the same text you copy. If you work in splits and long diffs, this update closes the pane you pointed at and keeps the diff you are reading on screen. If your Mac is set to Japanese, Indonesian, or Catalan, more of the interface is translated, including the command palette in Catalan. The web guide now gives you the current Settings paths, dictation and clipboard limits, and setup requirements. Its instructions now use consistent text sizes and headings, with clearer tables and links. The guide keeps the familiar centered page width and gives more of it to the instructions. AI-summary buttons have been removed across the site. It also documents agent worktree reporting, while the privacy page explains download-request network lookups and temporary browser-preview data.",
	"2026-10-05":
		"Run a coding agent in a split and send it into a git worktree, and the pane can now tell you where the agent is actually working. Your shell stays in the checkout you launched from, so until now the split label, the tab sidebar and the Git drawer named that checkout for every agent pane. An agent can now report its directory with the new yen pane cwd command, and those three follow it while the agent is in front, then return to your shell's directory when you are back at the prompt; your shell's own location never changes. Split labels also notice a branch switch in a pane you are not touching, instead of holding the old branch name until something redraws it.\n\nWhat you copy now matches what you pointed at. Triple-click a line of output and the selection ends at the prompt instead of sliding across blank cells into the next command. An emoji that wrapped from the right edge no longer occasionally drops out of a copy, and an emoji sequence that widens to two columns at the end of a line wraps whole instead of losing pieces. Programs that switch character sets draw a character past the old 8-bit range as itself, and a single-shift command changes exactly one character.\n\nFull-screen programs get more of what they ask for. A soft reset restores the modes and cursor state a program changed without clearing your screen, a program that draws inside margins and asks for its screen contents gets the cursor where it put it, and a program that asks for the screen size in characters gets an answer. The bundled fuzzy finder and Git tool each move up a maintenance release, and Danish speakers get a refreshed translation. Nothing about how you type changes; your panes say where the work is, and the text you select is the text you get.",
	"2026-09-28":
		"If you drive YEN from Shortcuts or Spotlight on macOS 27, an action that opens a terminal now opens one. When no YEN window is open, macOS 27 wakes the app in the background before it hands over your shortcut, and YEN used to answer that wake-up with a window of its own, so you got two. It now ignores the background wake-up unless the shortcut asked YEN to come forward.\n\nFullscreen got steadier in the same build. A program that asks to resize the window while it is still sliding into fullscreen is now told no, so the animation finishes where it should instead of being pulled to a new size halfway through. On macOS 27 the tab bar lets more of a transparent title bar show through, tmux panes report the mouse modes you set, and the terminal engine reads the numbers in control sequences more strictly. Nothing about how you work changes; the window you asked for is the one you get, at the size you expect.",
	"2026-09-21":
		"Keep several git worktrees open and your splits can finally tell each other apart. Turn on Split Labels in Settings > Workspace and each pane names itself after the worktree it is working in, so a three-pane layout reads as three different pieces of work instead of three copies of the same folder name. When a worktree folder is called something forgettable like wt, the pane shows the branch instead. Type your own name over any pane and yours stays until you clear it.\n\nPaste a line carrying the newest emoji or an unfamiliar script and it now takes up the room it should. The terminal engine moves up to Unicode 18, so characters added in the latest standard are measured and grouped the way your font draws them, instead of splitting apart or crowding the text beside them. Selecting inside that kind of line got more exact too: double-click a word sitting next to CJK characters or emoji and you get the word, not the character beside it. And when a program moves the cursor back across a line YEN wrapped for you, it now lands on the row you would point at. Programs that ask which terminal modes are on get their answer from a faster lookup, and the engine takes its usual maintenance pass.\n\nShipping builds keep recognising Apple's current stable toolchains, and the release gates underneath fail loudly when they cannot verify something rather than waving a build through. Nothing changes about how you type or arrange your windows — you just get a clearer read on which pane is which, and a grid that handles current text correctly.",
	"2026-09-14":
		"If you set a custom font for the title bar, the letters used to get clipped at the top on macOS 26. They now sit fully in the bar, so the window title you chose is the one you can actually read.\n\nThe same stretch makes the rest of the chrome read like a Mac app. Selected Settings rows keep a dark label on the brand orange instead of washed-out white, a search match is marked by weight rather than a second orange, and section headings stay in title case. JP the Cat moved to Help. The idle dictation extra is a template waveform that tints with the menu bar, About and the command palette follow your system text size, and onboarding permission rows still make sense when color is not the cue.\n\nUnderneath, the terminal engine takes another maintenance pass: Lithuanian strings are current, programs that ask which modes are on get a complete answer, and the Italian translation is filled in. A follow-up engine sync keeps that foundation current, and the shipping build recognises Apple's latest stable Xcode so the update you download is the one that passed its gates. The same follow-up fixes what Bash tells the terminal about your last command: it used to report every command as successful, so a failed one looked exactly like a good one, and it now passes the real exit status through, including from prompt hooks that run several commands. A last engine sync closes the week: if you keep your prompt hooks in a PROMPT_COMMAND array, YEN now finds them there instead of adding its own twice. How you type and split windows is unchanged — the surface you look at every day just stopped cutting your title off and stopped calling every command a success.",
	"2026-09-07":
		"The terminal engine moves up to its 1.4 release, bringing its latest maintenance work and translation updates. You will not feel a behavior change — the engine underneath is simply current.\n\nThis week also adds a clipboard fix: when you paste a file path, YEN now skips stale URLs so the path points to a live file instead of a deleted one.\n\nThe bundled fuzzy finder moves up a release in the same stretch. Stray characters no longer leak into the search box when a terminal answers a startup query late or when you hold Ctrl and press an arrow key, path ranking finds the last separator even when the line contains accented characters, and the list no longer opens a line short when a header or footer border is shown.\n\nThis week also closes the 1.205 cycle: you can now place a new split exactly where you want it by holding an arrow and pressing Cmd + D to split left, right, up, or down. A terminal that is still drawing keeps its display timer running so animation and long-running output stay in step. The bundled Git tool moves up a release with faster diffs, conflict handling that keeps your place, and searchable keybinding and recent-repository menus.\n\nThe week closes back in source control. Pressing Escape in the bundled Git tool now registers immediately instead of lagging behind, and the tool no longer loads or rewrites your configuration when it runs in the background for a single task. The terminal engine takes one more maintenance and translation pass, so the tools underneath stay current without asking anything of you.",
	"2026-08-31":
		"Open a few terminal windows in a row and they step across the screen again instead of landing on top of one another. A new window is placed before its offset is applied, and windows with a hidden title bar now cascade like every other kind, so the arrangement you expect happens whichever style you use.\n\nNew tabs also arrive cleanly. The brief flash you could catch when opening one is gone, because the background is in place before the tab is drawn. A search holds onto its results when a program writes more output above them, and Find Previous now moves backward when the search field has focus, so both directions take you where you asked to go. Opening a link or a file no longer leaves a background helper spinning on a CPU core.\n\nThe week closes on how your keystrokes travel to the program you're running. Control key combinations, the numeric keypad, F13 through F25, Alt+Escape, and non-ASCII characters typed with Alt now report through the same modern encoding path, so editors and multiplexers that ask for it see exactly the key you pressed. The terminal also starts with less fixed memory, keeping the foundation current without changing how you work.\n\nThe week closes in source control. The bundled Git tool moves up a release, and most of what changed is about not losing your place: stop in the middle of a rebase and the conflicted commit is already selected, resolve a conflict and the file you were on stays selected, and files you have already settled remain in the list instead of disappearing the moment they are fixed. Diffs no longer flicker or glitch while they load, the tool starts faster, and the keybinding and recent-repository menus narrow as you type. Refreshed terminal color themes round out the week.",
	"2026-08-24":
		"You can now choose exactly which microphone Voice uses. Settings > Sounds > Dictation lists every input, names the device behind System Default, and keeps a disconnected choice visible instead of silently switching. The picker now appears reliably, so the control you read about is finally where you expect it.\n\nYEN also gets lighter when you leave it open. An idle terminal parks its display timer, hidden windows release their graphics memory, and both return immediately when you need them. Clipboard exchanges stay behind clear approval prompts, dropped text behaves like a paste, and stricter validation keeps oversized or malformed clipboard writes out.\n\nThe week closes with input and output behaving more precisely. Control codes, terminal images, physical keys, wrapping, shortcuts, and cursor changes now follow their intended rules more closely. AppleScript key commands translate each key once through your current keyboard layout, while updated emoji font lookup keeps scripted input and expressive output dependable. And when you close a window with several programs still running, YEN now offers to walk you through those windows one at a time, so a long-running job is something you decide about rather than something you lose. That care now extends to the windows you are not watching: when output arrives in a background window, it is drawn at the display's own pace instead of waiting for your attention, so the build you left running stays readable at a glance. Images handed to the terminal through shared memory are checked against the naming rules first, and a malformed request is refused rather than opened. A final engine maintenance pass keeps the foundation current without changing anything you touch.",
	"2026-08-17":
		"Voice is easier to trust and easier to see. On macOS 26, an audio-conversion failure now preserves your partial words, stops cleanly, and prepares the recognizer for your next attempt. A larger layered rainbow waveform responds while YEN listens, then yields to the stable processing state. Thanks to Jon Tippens for helping improve Voice through direct feedback.\n\nImages stay where terminal programs put them. Relative placements now work correctly, images scroll or clip at terminal margins, and incomplete transfers are discarded instead of appearing half-drawn. Backspace, Delete, and other control keys also remain physical keys for programs using the extended keyboard protocol, while wrapped copies keep their wrap.\n\nThe website now explains when Apple Speech stays on-device and when older macOS versions can use Apple's service. It also states YEN's system requirements, proprietary license, privacy boundaries, and network services consistently, so the product and its documentation tell the same clear story.",
	"2026-08-10":
		"This week starts with something you feel before you type a single character: YEN opens noticeably faster. The engine's latest maintenance pass warms up the graphics pipeline while the app is still launching, resolves the emoji font directly instead of searching for it, and skips loading windows that have nothing to show — upstream measured roughly 15% off launch time and 27% off the wait for the first frame. Nothing about the terminal changed once it is open; the time between clicking the icon and seeing your prompt simply shrank.\n\nAccuracy came along for the ride. Programs that send images to the terminal in several passes — plotting tools, image previewers over SSH — could leave a retransmitted image stacked on top of its earlier self, and now the newest copy cleanly replaces the old one.\n\nIn-terminal search got steadier too. The find bar now keeps what you typed and what is selected moving as one, so editing your search never leaves a stale selection behind, and on macOS 15 the field avoids a system text-editing crash by taking a plainer input path.\n\nMidweek brought interruptions and input into focus. When a program in a window you are not looking at asks to read your clipboard, the confirmation now waits until you switch to that window instead of stealing your attention mid-thought. Launching YEN from the command line with -e no longer mistakes the command's file paths for documents to open, and Unicode hex input accepts the full range of characters — emoji included.\n\nSpeed you notice when the screen is full of emoji or CJK text followed: grapheme-heavy output and wide-character reflow on resize are much faster, so dense logs stay responsive when you change the window size. Translation updates for Danish, Latvian, Polish, and Turkish, more reliable dynamic tab stops, a patched Git TUI, and a refreshed system-info tool rode along.\n\nThe week closes with the engine's usual maintenance pass and the bundled file browser jumping up several releases, keeping the tools underneath current without asking anything of you. A follow-up maintenance pass on the engine landed the same week, keeping things current between releases.",
	"2026-08-03":
		"Settings now preserve every repeated value you chose, including keyboard shortcuts, individual theme colors, and fallback fonts. Removing a global shortcut removes it completely, search finds more of what you expect, and layout presets report their result in the terminal instead of a footer you may already have closed. The Keyboard tab itself also got more dependable this week: it could open with an empty shortcut list until you switched away and back, and now loads reliably the first time.\n\nMenus read faster too. Every item YEN owns now carries an icon — opening the file browser, taking a screenshot, the split layout presets, the whole Find submenu, and the window controls for selecting and resizing splits — so you find a command by its shape instead of reading down the list. Updates are easier to control from the command palette, large images arrive intact across multiple messages, and windows recover their drawing pace after sleep, lock, or a display change. Notification focus and command-palette actions also stay attached to the correct pane while macOS moves a native tab.\n\nThe checks behind each download received the same attention. Empty scans now fail instead of looking clean, vendor downloads carry immutable provenance, prerelease Xcode toolchains cannot enter a shipping build, and theme checks no longer depend on leftover artifacts. These changes stay out of your way, but they make every update easier to trust.",
	"2026-07-27":
		'Scrollback now behaves the way you always assumed it did. YEN used to cap terminal history by how much memory it consumed, which meant the amount of work you could scroll back through quietly changed with your window width and the weight of each line. Set the limit in lines instead and "keep my last fifty thousand lines" means exactly that — or set either limit to unlimited and keep everything. The renderer follows the same thinking, reserving only the graphics memory it actually needs when the grid grows rather than twice that much, and tracing box- and line-drawing characters along a more precise inset path so the borders and table rules your tools draw all day line up cleanly at any font size.\n\nThe rest of the week was precision of a different kind. Clicking a file path at the end of a line no longer picks up the trailing space and sends you somewhere that does not exist, and links in your scrollback now survive a window resize intact. Programs can ask whether the terminal is actually visible, so the tools you leave running can wait until you are looking before they say anything. A failed update check tells you so instead of failing quietly, output that arrives in fragments replays in the right order, and a failed terminal-description cache over SSH no longer drops you into a session where colors and keys misbehave without explanation. Find, Reload Configuration, Change Tab Title and Terminal Read-only had gone missing from the menu bar, and they are back. SVG files preview more accurately in the file browser.\n\nThe week also closed underneath the product rather than in it. The verification that stands between a change and the build you install was audited end to end and tightened: several checks that could report success without having actually inspected anything now fail loudly instead. You will not see any of it. That is the point — it is the difference between a release that passed its checks and one that merely did not fail them.',
	"2026-07-20":
		"Every sliding surface in YEN now moves as one system. Quick Terminal, Git Drawer, Tab Sidebar, and Scratchpad park, slide, and finish on the same sequence in both directions, including under Reduce Motion — and Quick Terminal is full-width again, without the stray black bar. Open any of them and the workspace feels native rather than assembled.\n\nUnderneath, a memory-efficiency pass made long sessions genuinely lighter: retain cycles closed in theme preview and dictation, a bounded background-wallpaper cache that can no longer accumulate large decodes, and merge-conflict data freed the moment you close the workspace.\n\nThe week closed on quieter correctness. Tab teardown finishes in the right order instead of deferring cleanup, and programs that ask the terminal to describe its own cursor and underline state finally get accurate answers, so editors and shells restore exactly what you were looking at.",
	"2026-07-13":
		"A week spent making the native workspace hold up under real pressure. A deep audit ran through the app and its fixes shipped as they landed: Scratchpad protects unreadable notes, unusual Git filenames fail safely, review logs and background images survive concurrency, screenshots preserve exact pixels without overwrite races, and rejected shortcuts explain themselves — to sighted users and VoiceOver alike.\n\nThe daily surfaces sharpened in the same stretch. Command Palette takes focus immediately and closes cleanly, the Tab Sidebar keeps its full-height frame, Settings became modular and faster, in-terminal search got more precise, nushell completions arrived, and Dynamic Type support means the UI respects your system text size.\n\nEven the supply chain tightened — dependencies are now scanned before they install. Individually minor, together the difference between a workspace you tolerate and one you trust.",
	"2026-07-06":
		"Updating YEN became almost free. Delta patches arrived, so an update downloads a fraction of its former size, and the auto-updater took a security refresh — staying current now costs you seconds and asks for very little trust.\n\nAccessibility and control moved with it: Reduce Motion support arrived without giving up performance, padding settings gained stepper arrows, Launch at Login moved into General settings where you would actually look for it, and a friendly toast now explains why a disabled panel hotkey did nothing instead of leaving a silent mystery key.\n\nA pinned tab-sidebar memory leak was closed, a logger crash risk removed from the app lifecycle, and a 38-commit engine sync landed underneath — fourteen builds that made both the product and the act of receiving it lighter.",
	"2026-06-29":
		"The Git drawer became a genuinely fast keyboard-first workspace. j/k navigation now respects diff focus so movement goes where your eyes are, the diff pane sticks to the top and copies as plain text, copy-on-select works the instant you highlight — in the drawer and in Scratchpad — and the header names your folder and branch. You can review real changes without touching the mouse or leaving the terminal.\n\nThe same precision carried through the rest of the app: multi-file clipboard paste just works, selection gestures feel natural, Quick Terminal and side panels anchor exactly where you expect, text rendering stays crisp under load, and heavy diff previews and background images stay smooth.\n\nRefreshed built-in themes closed the loop — a week that made the daily review-and-ship cycle feel like it belongs to the terminal.",
	"2026-06-22":
		"Git work started feeling native to YEN rather than bolted on. The Git drawer gained a Quick Terminal-style slide, native diff coloring, stash listings, and a header that shows your folder and branch at a glance; its diffs, shortcuts, and overlay rendering were each fixed in turn as the week iterated on it build by build.\n\nEditor handoff moved off the main thread — open a large conflict review and YEN stays responsive while it loads — and a controller leak and an unbounded merge-conflict preview were closed in the same pass.\n\nEleven builds, nearly all of them on one surface: by the end of the week the drawer had stopped being a panel and started being a place.",
	"2026-06-15":
		"A short week about keeping fast workflows inside the lines. Quick Terminal now stays on-screen where you put it, and Shortcuts captures cleaner terminal output with correct color handling, so the automations you build on YEN read the way they should.\n\nA terminal-engine maintenance update and a refreshed bundled JSON tool keep the small machinery behind that everyday automation dependable.",
	"2026-06-08":
		"Customizing YEN stopped feeling administrative. Settings tabs render eagerly so switching is instant, input outlines got brighter and more legible, copy was streamlined, shortcut feedback sharpened, and navigation and the theme catalog were refined — ten builds, most of them aimed at the panel you tune the product from.\n\nThe terminal followed. Layout presets now target the tab you are focused on, so arranging splits does exactly what you meant; click reporting and shell integration became more accurate; the increase-font-size shortcut works again.\n\nFaster file previews and an updated file finder rounded out a week aimed squarely at immediacy — change a thing, feel it land, move on.",
	"2026-06-01":
		"A concentrated week of making edges unbreakable. A memory-safety issue in terminal selection was fixed, a browser-link crash was eliminated, the Tab Sidebar toggle stopped crashing, and Quick Terminal splits were repaired — four different moments of it-should-never-do-that, all closed.\n\nSystem information renders correctly again, color schemes were refreshed alongside a 13-commit engine update, and the release gates underneath were hardened to fail closed — a check that cannot run now reads as a failure, never as a pass.\n\nSteadier from click to command, and wired to stay that way.",
	"2026-05-25":
		"A foundation week, moved in one clean batch: a 22-commit terminal-engine refresh, a newer fuzzy finder, and updated Git tooling, folded in and verified.\n\nNothing asks you to relearn anything. Search, rendering, and source control are simply current — and the days-long run of engine refreshes behind them is the quiet contract that YEN never drifts far from its foundation's best work.",
	"2026-05-18":
		"Small interactions, made dependable. Open Terminal Here now works reliably from Finder's Services menu, nested splits resize predictably instead of fighting you, and focus and quit handling finally feel settled — no more windows that refuse to let go.\n\nSmoother search plus a refreshed fuzzy finder and bundled tooling keep the find-anything loop quick from the moment a window opens. A week of small certainties, which is what daily tools are made of.",
	"2026-05-11":
		"Your workspace now remembers more of what makes it yours: window transparency persists across tabs and windows instead of quietly resetting. Set it once and it stays set — every new tab, every new window.\n\nThe bundled system-info tool was refreshed in the same stretch, so what YEN reports about your Mac keeps matching reality.",
	"2026-05-04":
		"File work got faster where you feel it most: previews. Arrow through a directory and the gap between finding a file and understanding it shrank noticeably, because the refreshed file browser answers before you have finished asking.\n\nNormalized macOS paths and a new locale carry that same experience cleanly into more environments.",
	"2026-04-27":
		"Your Mac's hardware moved into view: Apple Silicon GPU monitoring arrived in the bundled system monitor, putting live GPU telemetry a keystroke away in the same place you already watch CPU and memory.\n\nAround it, the surfaces you touch constantly each got more certain. Tab Sidebar clicks register immediately, Settings deep links scroll to the right row, the sidebar stopped collapsing under you, IME input and the copy menu behave, middle-click actions work, Command Palette focus is predictable, and running yen agents bare now explains itself instead of doing nothing.\n\nNothing here changes what YEN is. All of it changes how often YEN does exactly what you meant on the first try.",
	"2026-04-20":
		"Typography led the week: a 37-commit terminal-engine sync brought OpenType font validation, so more of the fonts you actually want to run — with their ligatures and alternates — render correctly instead of silently degrading.\n\nThe advanced workflows around the terminal got sturdier in the same stretch. Browser split-window lifecycles were hardened after an audit, scriptability grew, search reached further, the shell's IDE-detection payload was hardened, and accessibility took another pass.\n\nIf you push YEN past being just a terminal window — fonts, automation, embedded browsing — this was the week those edges stopped feeling experimental.",
	"2026-04-13":
		"The surfaces you only notice when they fail, tightened. UTF-8 handling got faster, viewport bugs were fixed, browser windows layer correctly, Settings stopped misbehaving across open-close cycles, and menu shortcuts fire reliably every time.\n\nNo headline. Just five builds of the discipline that keeps a terminal composed under everyday pressure — which is most of what anyone means when they call software solid.",
	"2026-04-06":
		"Long sessions got measurably lighter. A tab memory leak was closed, hidden surfaces — the tabs and splits you are not currently looking at — stopped holding memory they did not need, and the app download itself shrank. Keep YEN open for days with a dozen tabs and the difference is real.\n\nScratchpad picked up copy-on-select, the review workspace took a polish pass, the dock icon learned Tahoe's conventions, and a run of engine refreshes kept the foundation current. Lean was the theme, and it held from the download to the hundredth hour of uptime.",
	"2026-03-30":
		"Speed you can feel at the prompt. IDE detection results are now cached, so the shell prompt that used to pay for detection on every launch renders noticeably faster — the kind of change you notice in the first minute and then never think about again.\n\nTrust moved with it: app intents were hardened twice over with explicit trust gating, and the diff renderer behind code review is now built from source, trimming an outside dependency from the supply chain. Fixes across delete-key mapping, menu shortcuts, Settings typography and sidebar layout, notifications, and bundled tools cleared friction from a dozen small places.\n\nA week without a headline feature — just a terminal that starts faster, asks better questions before granting access, and gets out of your way.",
	"2026-03-23":
		"YEN crossed 1.0. The milestone build itself was deliberately unglamorous — a terminal-engine sync and vendor refresh — because the point of 1.0 was that nothing needed to be special about it: the product underneath had already become dependable.\n\nThe week around it belonged to wallpaper. A scope toggle chooses whether a background fills the whole window or each split, iCloud-stored images gained download retry, titlebar transparency and whole-window display were fixed, and a flicker on config changes was eliminated — five releases of persistence until backgrounds simply worked.\n\nThe updater also learned manners: it now asks permission before checking automatically. A restored Settings design brought back the cleaner, familiar layout, and IDE detection got faster. Eighteen builds, one number rollover, and a workspace that finally felt ready to call home.",
	"2026-03-09":
		"The final approach to 1.0 read like a checklist of power-user respect. Keybind conflict detection became layout-aware, so it catches the collisions your physical keyboard would actually produce rather than theoretical ones. Split panes gained labels that keep complex arrangements readable at a glance, and notifications learned to coalesce instead of stacking.\n\nFullscreen behavior and notch handling were fixed, IDE detection hardened, sharing improved, and Settings took another polish pass — the elaborate setups YEN now supports became easier to operate with confidence. Everything about the week said the same thing: the milestone was close, and it would be earned rather than declared.",
	"2026-03-02":
		"The biggest step yet toward YEN as a terminal-first IDE. One release brought the Tab Sidebar, a pull-request review workspace, and a merge-conflict workspace — review a PR, resolve its conflicts, and ship it without leaving the app or losing your place. The rest of the week was spent making that leap land: presentation-lifecycle fixes, restore-state fixes, command-palette hardening.\n\nGetting YEN got easier too — a Homebrew cask joined the redesigned DMG installer — and living with it got calmer: Scratchpad learned click-away dismissal, notifications were hardened, document attachments arrived, and security hardening ran through the same builds.\n\nFifteen releases in seven days, most of them iterations on one ambition: serious Git work, inside the terminal, that feels native rather than embedded.",
	"2026-02-23":
		"Scratchpad arrived — a global, always-there note surface you can summon from anywhere in the app, the fastest way yet to get a thought out of your head without leaving the terminal. The same week folded a full Git TUI into YEN, branded and wired with yengit aliases, so staging, diffing, and committing gained a serious keyboard-driven home.\n\nSystem information gained colorized ASCII art and a better layout, the file browser recovered its Git status colors and became harder to break, and dictation kept hardening. A new app icon landed alongside a run of Tahoe fixes — Finder chrome, About-window borders, full-bleed rendering — so YEN looks right on the next macOS before most people are running it.\n\nForty-five builds also left the release machine stronger than they found it: automatic artifact cleanup, DMG installer reliability, provenance and concurrency guards. Breadth was the theme; the reliability work is what made the breadth safe to lean on daily.",
	"2026-02-16":
		"Personality week. Palette skins and sound packs arrived, so YEN could start looking and sounding like yours; a Settings toolbar tied the growing options together, and theme overrides began persisting the way you would expect. The file browser learned to preview more of what you point it at, including native archive previews that let you look inside a compressed file without extracting anything.\n\nDictation was rebuilt on Apple's newer speech engine and then hardened: clearer permission prompts, recovery from a legacy disabled state, safer sound import. Window standards, border hardening, split transparency, and a run of Settings fixes kept the native workspace tightening while the personality layer grew.\n\nBeneath both, the pipeline learned to prove its own provenance — a vendor-audit gate, entitlement hardening, memory-lifecycle work across the overlay stack — because a product this configurable is only fun if the foundation refuses to wobble.",
	"2026-02-09":
		"The week YEN turned configuration into a playground. Tabbed Settings arrived with a keyboard-shortcut editor that catches conflicts before you save them, notification sounds gained a picker, and ten split-layout presets landed on Cmd + Option + 1-0 — with customization, so the arrangement you actually work in is one keystroke away.\n\nThe Tab Sidebar made its first appearance, the menu-bar icon gained a click menu, and hands-free pointer control arrived alongside an Experimental tab to hold it — early, ambitious input work shipped honestly as an experiment. Escape-aware wrapping and an escape-sequence leak fix kept the terminal itself precise underneath the new surfaces.\n\nThe releases also started carrying their own proof: build verification grew to 29 branding checks, versioning moved to three digits, and DMG hosting moved to the cloud. Thirty-one builds in a week, most of them shaping how YEN feels to own rather than just to open.",
	"2026-01-19":
		"One build, one promise kept: press the dictation shortcut and YEN now shows a clear recording indicator, so you know it is listening before you start talking.\n\nSpeaking to your terminal only works if you trust the microphone state — this closed that gap, and removed the one real hesitation in using your voice at the prompt.",
	"2026-01-12":
		"A deliberately boring week, which was the point. A stabilizing build settled daily usage, and a zsh title-handling fix stopped window titles from drifting out of sync with what the shell was actually doing.\n\nSmall fixes, but the kind you feel every session: the terminal starts predictable and stays that way.",
	"2025-12-29":
		"A quiet holiday week with two changes worth knowing about. The terminal engine moved forward with performance improvements, so the core of what YEN does — drawing your text fast — got faster still.\n\nAnd YEN's orange arrived in the system UI: the brand accent now colors the moments macOS speaks for the app, a small signature that keeps YEN recognizably itself even inside a system dialog.",
	"2025-12-22":
		"With launch behind it, this week was about being able to trust the machine that makes the releases. The build workflow was simplified, hardened with explicit file permissions, cured of shell-compatibility landmines, and documented end to end — and when something does look wrong, new CLI diagnostic tools and cache-clearing commands give you a way to see it and fix it rather than reinstall and hope.\n\nThe product moved too. YEN switched to DMG distribution — the drag-to-Applications install Mac users expect — and to Apple Silicon-only builds, making downloads smaller and faster. A config-driven theme system replaced hard-coded colors, the update architecture lost a layer of complexity, and the CLI's terminal UI finished its third build-out phase.\n\nNone of this is a feature you can point at. It is the reason the next several hundred releases could ship at the rate they did.",
	"2025-12-15":
		"The week everything had to become real. YEN had been a fast terminal build; this week it became software you could hand to a stranger. Builds were signed and notarized with Apple, produced for both Apple Silicon and Intel Macs, and wired into an auto-updater that could deliver the next version by itself — then that updater was tested, broken, and fixed in public across a dozen point releases until installing an update and relaunching just worked.\n\nThe terminal grew up alongside the packaging. The startup wrapper moved inside the app bundle so shell integration survives login, YEN's default theme actually shipped as the default, a status bar arrived, and the welcome banner learned to report the version you are really running. Versioning itself was overhauled until one source of truth drove the app, the site, and the update feed.\n\nAround it, the distribution surface took shape: direct versioned download links so it is crystal clear which build you are getting, a custom 404 page, a consistent mobile site, and build verification that explains what went wrong instead of leaving you to guess. Eighty-nine builds in seven days — the pace of a product finding out, in a hurry, what shipping means.",
};

// version -> reason. Excluded from the public page (retired runtimes / accounts /
// login / pure test builds). Kept explicit so the exclusion is never silent and a
// future editor can see why a build is intentionally absent.
export const RELEASE_EXCLUDE: Record<string, string> = {
	"1.272":
		"maintenance build: terminal engine refresh whose changes are a Linux-only input fix, a new benchmark and contributor-list metadata, no user-facing change on macOS",
	"1.271":
		"maintenance build: terminal engine refresh whose only change is contributor-list metadata, no user-facing change",
	"1.270":
		"maintenance build: terminal engine refresh whose changes are CI workflow and contributor-list metadata, no user-facing change",
	"1.269":
		"maintenance build: terminal engine refresh whose changes are a build toolchain bump, debug-only integrity checks, translation tooling and themes YEN does not bundle, no user-facing change on macOS",
	"1.266":
		"maintenance build: rebuild of 1.265 with no product change since that release, no user-facing change",
	"1.252":
		"maintenance build: rebuild of 1.251 with no product change since that release, no user-facing change",
	"1.251":
		"maintenance build: terminal engine refresh whose changes are embedding-library packaging and internal build work, no user-facing change on macOS",
	"1.243":
		"maintenance build: terminal engine refresh whose changes are Linux-only translations or internal, no user-facing change on macOS",
	"1.236":
		"maintenance build: terminal engine refresh whose only upstream change is a contributor list that is not part of the app, no user-facing change",
	"1.230":
		"maintenance build: terminal engine refresh whose changes are Linux-only or internal, no user-facing change on macOS",
	"1.228":
		"maintenance build: 1.227 rebuilt and re-verified on the macOS 27 SDK, no user-facing change",
	"1.220":
		"maintenance build: bundled license notices removed and a release-gate receipt fixed, no user-facing change",
	"0.7.20": "retired: Gmail integration (mail runtime removed from main)",
	"0.093": "retired: Apple Sign In + cloud sync (accounts removed from main)",
	"0.092": "retired: account login prompt (accounts removed from main)",
	"0.25": "retired: email TUI + account auth (mail/accounts removed from main)",
	"0.23": "retired: email templates (mail runtime removed from main)",
	"0.6.95":
		"retired: Learning System / Portable Profile (account/assistant era removed)",
	"0.091": "test build: auto-updater verification, no user-facing change",
	"0.6.93": "test build: Sparkle auto-update detection, no user-facing change",
	"0.6.91": "test build: Sparkle auto-update delivery, no user-facing change",
	"0.101": "test build: version-sync system, no user-facing change",
	"0.100": "test build: version-sync system, no user-facing change",
	"0.22": "test build: update-error/CLI testing, no user-facing change",
	"0.933":
		"retired: weather runtime (removed from main; see weather-removal guard)",
};
