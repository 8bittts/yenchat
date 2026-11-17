//! Build logic for YEN Terminal. A single "build.zig" file became far too complex
//! and spaghetti, so this package extracts the build logic into smaller,
//! more manageable pieces.
//!
//! YEN NOTE: This overlay adds YENCustomResources import and references
//! the renamed YEN*.zig files (branding renames Ghostty*.zig → YEN*.zig).

pub const gtk = @import("gtk.zig");
pub const Config = @import("Config.zig");
pub const GitVersion = @import("GitVersion.zig");

// Artifacts (renamed from Ghostty* to YEN* by branding step)
pub const GhosttyBench = @import("YENBench.zig");
pub const GhosttyDist = @import("YENDist.zig");
pub const GhosttyDocs = @import("YENDocs.zig");
pub const GhosttyExe = @import("YENExe.zig");
pub const GhosttyFrameData = @import("YENFrameData.zig");
pub const GhosttyLib = @import("YENLib.zig");
pub const GhosttyLibVt = @import("YENLibVt.zig");
pub const GhosttyResources = @import("YENResources.zig");
pub const GhosttyI18n = @import("YENI18n.zig");
pub const GhosttyXcodebuild = @import("YENXcodebuild.zig");
pub const GhosttyXCFramework = @import("YENXCFramework.zig");
pub const GhosttyWebdata = @import("YENWebdata.zig");
pub const GhosttyZig = @import("YENZig.zig");
pub const HelpStrings = @import("HelpStrings.zig");
pub const LibVtPackages = @import("LibVtPackages.zig");
pub const SharedDeps = @import("SharedDeps.zig");
pub const UnicodeTables = @import("UnicodeTables.zig");

// YEN Custom Resources - bundles CLI, commands, themes, etc. into YEN.app
pub const YENCustomResources = @import("YENCustomResources.zig");

// Steps
pub const LibtoolStep = @import("LibtoolStep.zig");
pub const LipoStep = @import("LipoStep.zig");
pub const MetallibStep = @import("MetallibStep.zig");
pub const XCFrameworkStep = @import("XCFrameworkStep.zig");

// Helpers
pub const requireZig = @import("zig.zig").requireZig;
