#!/usr/bin/env python3
"""Patch Fullscreen.swift to use YEN effective/native fullscreen transition state."""

import sys


IS_FULLSCREEN_OLD = "    var isFullscreen: Bool { window.styleMask.contains(.fullScreen) }\n"
IS_FULLSCREEN_NEW = "    var isFullscreen: Bool { window.yenIsEffectivelyFullscreen }\n"

ENTER_NEW = """    func enter() {
        guard !window.yenIsNativeFullscreenTransitioning else {
            YEN.logger.debug("fullscreen: ignoring NativeFullscreen.enter while phase=\\(self.window.yenNativeFullscreenTransitionPhase.rawValue)")
            return
        }
        guard !isFullscreen else { return }

        // The titlebar separator shows up erroneously in fullscreen if the tab bar
        // is made to appear and then disappear by opening and then closing a tab.
        // We get rid of the separator while in fullscreen to prevent this.
        window.titlebarSeparatorStyle = .none

        window.yenNativeFullscreenTransitionPhase = .entering

        // Enter fullscreen
        window.toggleFullScreen(self)

        // Note: we don't call our delegate here because the base class
        // will always trigger the delegate on native fullscreen notifications
        // and we don't want to double notify.
    }
"""

EXIT_NEW = """    func exit() {
        guard !window.yenIsNativeFullscreenTransitioning else {
            YEN.logger.debug("fullscreen: ignoring NativeFullscreen.exit while phase=\\(self.window.yenNativeFullscreenTransitionPhase.rawValue)")
            return
        }
        guard isFullscreen else { return }

        // Restore titlebar separator style. See enter for explanation.
        window.titlebarSeparatorStyle = .automatic

        window.yenNativeFullscreenTransitionPhase = .exiting

        window.toggleFullScreen(nil)

        // Note: we don't call our delegate here because the base class
        // will always trigger the delegate on native fullscreen notifications
        // and we don't want to double notify.
    }
"""

ENTER_CANDIDATES = [
    """    func enter() {
        guard !isFullscreen else { return }

        // The titlebar separator shows up erroneously in fullscreen if the tab bar
        // is made to appear and then disappear by opening and then closing a tab.
        // We get rid of the separator while in fullscreen to prevent this.
        window.titlebarSeparatorStyle = .none

        // Enter fullscreen
        window.toggleFullScreen(self)

        // Note: we don't call our delegate here because the base class
        // will always trigger the delegate on native fullscreen notifications
        // and we don't want to double notify.
    }
""",
    """    func enter() {
        guard !window.yenIsNativeFullscreenTransitioning else {
            YEN.logger.debug("fullscreen: ignoring NativeFullscreen.enter while phase=\\(window.yenNativeFullscreenTransitionPhase.rawValue)")
            return
        }
        guard !isFullscreen else { return }

        // The titlebar separator shows up erroneously in fullscreen if the tab bar
        // is made to appear and then disappear by opening and then closing a tab.
        // We get rid of the separator while in fullscreen to prevent this.
        window.titlebarSeparatorStyle = .none

        // Enter fullscreen
        window.toggleFullScreen(self)

        // Note: we don't call our delegate here because the base class
        // will always trigger the delegate on native fullscreen notifications
        // and we don't want to double notify.
    }
""",
    """    func enter() {
        guard !window.yenIsNativeFullscreenTransitioning else {
            YEN.logger.debug("fullscreen: ignoring NativeFullscreen.enter while phase=\\(self.window.yenNativeFullscreenTransitionPhase.rawValue)")
            return
        }
        guard !isFullscreen else { return }

        // The titlebar separator shows up erroneously in fullscreen if the tab bar
        // is made to appear and then disappear by opening and then closing a tab.
        // We get rid of the separator while in fullscreen to prevent this.
        window.titlebarSeparatorStyle = .none

        // Enter fullscreen
        window.toggleFullScreen(self)

        // Note: we don't call our delegate here because the base class
        // will always trigger the delegate on native fullscreen notifications
        // and we don't want to double notify.
    }
""",
]

EXIT_CANDIDATES = [
    """    func exit() {
        guard isFullscreen else { return }

        // Restore titlebar separator style. See enter for explanation.
        window.titlebarSeparatorStyle = .automatic

        window.toggleFullScreen(nil)

        // Note: we don't call our delegate here because the base class
        // will always trigger the delegate on native fullscreen notifications
        // and we don't want to double notify.
    }
""",
    """    func exit() {
        guard !window.yenIsNativeFullscreenTransitioning else {
            YEN.logger.debug("fullscreen: ignoring NativeFullscreen.exit while phase=\\(window.yenNativeFullscreenTransitionPhase.rawValue)")
            return
        }
        guard isFullscreen else { return }

        // Restore titlebar separator style. See enter for explanation.
        window.titlebarSeparatorStyle = .automatic

        window.toggleFullScreen(nil)

        // Note: we don't call our delegate here because the base class
        // will always trigger the delegate on native fullscreen notifications
        // and we don't want to double notify.
    }
""",
    """    func exit() {
        guard !window.yenIsNativeFullscreenTransitioning else {
            YEN.logger.debug("fullscreen: ignoring NativeFullscreen.exit while phase=\\(self.window.yenNativeFullscreenTransitionPhase.rawValue)")
            return
        }
        guard isFullscreen else { return }

        // Restore titlebar separator style. See enter for explanation.
        window.titlebarSeparatorStyle = .automatic

        window.toggleFullScreen(nil)

        // Note: we don't call our delegate here because the base class
        // will always trigger the delegate on native fullscreen notifications
        // and we don't want to double notify.
    }
""",
]


def apply_replacement(content, candidates, new, path):
    if new in content:
        return content, False
    old = next((candidate for candidate in candidates if candidate in content), None)
    if old is None:
        print(f"  ERROR: native fullscreen helper anchor missing in {path}")
        return None, False
    return content.replace(old, new, 1), True


def main():
    if len(sys.argv) != 2:
        print("usage: native-fullscreen-helper.py <Fullscreen.swift>", file=sys.stderr)
        return 2

    path = sys.argv[1]
    with open(path, "r", encoding="utf-8", errors="surrogateescape") as handle:
        content = handle.read()

    changed = False
    if IS_FULLSCREEN_NEW not in content:
        if IS_FULLSCREEN_OLD not in content:
            print(f"  ERROR: native fullscreen helper anchor missing in {path}")
            return 1
        content = content.replace(IS_FULLSCREEN_OLD, IS_FULLSCREEN_NEW, 1)
        changed = True

    content, did_change = apply_replacement(content, ENTER_CANDIDATES, ENTER_NEW, path)
    if content is None:
        return 1
    changed = changed or did_change

    content, did_change = apply_replacement(content, EXIT_CANDIDATES, EXIT_NEW, path)
    if content is None:
        return 1
    changed = changed or did_change

    with open(path, "w", encoding="utf-8", errors="surrogateescape") as handle:
        handle.write(content)

    if changed:
        print("    Applied native fullscreen transition guard patch to Fullscreen.swift")
    else:
        print("    Native fullscreen transition guard patch already applied to Fullscreen.swift")
    return 0


if __name__ == "__main__":
    sys.exit(main())
