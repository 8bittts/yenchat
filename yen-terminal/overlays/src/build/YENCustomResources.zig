/// YENCustomResources.zig
///
/// YEN-specific resource bundling for the macOS app.
/// This module calls bundle-yen-resources.sh which handles all resource bundling:
/// - Pre-compiled icon (615KB instead of generated 71KB)
/// - themes/ (bundled terminal color themes)
/// - commands/ (CLI commands)
/// - lib/ (shared utilities: api.sh, keychain.sh, common.sh)
/// - shell/ (optional shell integration templates for opt-in setup)
/// - bin/ (YEN CLI)
/// - Version sync (reads from version.json, updates Info.plist)
/// - Shell integration (welcome banner, wrappers)
/// - Packaging inputs consumed by finalize-build.sh signing/notarization
///
/// NOTE: config.yen is not bundled. The app writes `theme = YEN` into the
/// user's config at launch when no theme is set (ThemeConfigRepair.swift).
///
/// This replaces 14 separate Zig build steps with a single shell script call,
/// making the build system simpler to maintain and debug.

const YENCustomResources = @This();

const std = @import("std");
const RunStep = std.Build.Step.Run;

/// The step that bundles all YEN resources. Zig 0.17 has no custom step
/// type, so this run step is also the completion step for the bundle.
bundle_step: *std.Build.Step,

pub fn init(b: *std.Build) !YENCustomResources {
    // Single step that calls bundle-yen-resources.sh
    const bundle_resources = blk: {
        const step = RunStep.create(b, "yen: bundle resources");
        // Path is relative to ghostty/ directory (build runs from there)
        step.addArgs(&.{
            "bash", "../customizations/bundle-yen-resources.sh",
        });
        // Zig 0.17 resolves the install prefix only while the build runs, so
        // the app path is a directory argument instead of APP_PATH.
        step.addDirectoryArg2(
            b.graph.path(.install_prefix, "YEN.app"),
            .{ .make_absolute = true },
        );
        break :blk step;
    };

    return .{
        .bundle_step = &bundle_resources.step,
    };
}

/// Add YEN custom resource bundling as a dependency of another step.
pub fn addStepDependencies(
    self: *const YENCustomResources,
    other_step: *std.Build.Step,
) void {
    other_step.dependOn(self.bundle_step);
}

/// Make this run after another step completes.
pub fn dependOn(self: *const YENCustomResources, other_step: *std.Build.Step) void {
    self.bundle_step.dependOn(other_step);
}

/// Hook into the install step
pub fn install(self: *const YENCustomResources) void {
    const b = self.bundle_step.owner;
    b.getInstallStep().dependOn(self.bundle_step);
}
