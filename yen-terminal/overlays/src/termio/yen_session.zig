//! YEN persistent sessions: run a pane inside the bundled zmx so its shell
//! outlives the app (_docs/01-architecture.md -> Persistent sessions).
//!
//! The macOS app marks a pane by setting YEN_PERSISTENT_SESSION=<pane UUID> in
//! the surface environment. Exec.zig calls `wrapFromEnv` after shell
//! integration has rewritten the command for the real shell, so integration
//! still applies to the shell zmx starts. The marker never reaches the child.
//!
//! This file depends only on `std`, so `zig test` runs it standalone; the
//! command union is taken as `anytype` with the engine's `shell`/`direct` shape.

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Environment marker the macOS app sets on a persistent pane.
pub const env_key = "YEN_PERSISTENT_SESSION";

/// A session name is a pane UUID; anything else is refused so it can be
/// spliced into a shell string without quoting.
pub fn validName(name: []const u8) bool {
    if (name.len == 0 or name.len > 64) return false;
    for (name) |c| switch (c) {
        'a'...'z', 'A'...'Z', '0'...'9', '-' => {},
        else => return false,
    };
    return true;
}

/// Path of the bundled zmx for a resources dir (`Contents/Resources/yen`).
pub fn zmxPath(alloc: Allocator, resources_dir: []const u8) !?[]const u8 {
    const resources = std.fs.path.dirname(resources_dir) orelse return null;
    return try std.fs.path.join(alloc, &.{ resources, "bin", "zmx" });
}

/// Returns `command` wrapped in `zmx attach <name>` when the environment marks
/// the pane as persistent and the bundled zmx exists; otherwise `command`
/// unchanged. Always removes the marker from `env`.
pub fn wrapFromEnv(
    alloc: Allocator,
    io: std.Io,
    command: anytype,
    env: *std.process.Environ.Map,
    resources_dir: ?[]const u8,
) !@TypeOf(command) {
    const raw = env.get(env_key) orelse return command;
    const name = try alloc.dupe(u8, raw);
    _ = env.orderedRemove(env_key);
    if (!validName(name)) return command;

    const dir = resources_dir orelse return command;
    const zmx = try zmxPath(alloc, dir) orelse return command;
    std.Io.Dir.accessAbsolute(io, zmx, .{}) catch return command;
    return try wrap(alloc, command, zmx, name);
}

/// Wrap a command in `zmx attach <name>`.
///
/// A `shell` command keeps the login semantics Exec.zig gives it on macOS: the
/// inner shell is started through `/bin/bash --noprofile --norc -c 'exec -l …'`,
/// exactly as Exec.zig starts an unwrapped shell inside login(1).
pub fn wrap(
    alloc: Allocator,
    command: anytype,
    zmx: []const u8,
    name: []const u8,
) !@TypeOf(command) {
    const Command = @TypeOf(command);
    return switch (command) {
        .shell => |v| shell: {
            const inner = try std.fmt.allocPrint(alloc, "exec -l {s}", .{v});
            const quoted_inner = try shellQuote(alloc, inner);
            const quoted_zmx = try shellQuote(alloc, zmx);
            const value = try alloc.dupeSentinel(u8, try std.fmt.allocPrint(
                alloc,
                "{s} attach {s} /bin/bash --noprofile --norc -c {s}",
                .{ quoted_zmx, name, quoted_inner },
            ), 0);
            break :shell @unionInit(Command, "shell", value);
        },
        .direct => |v| direct: {
            var args: std.ArrayList([:0]const u8) = try .initCapacity(alloc, v.len + 3);
            defer args.deinit(alloc);
            try args.append(alloc, try alloc.dupeSentinel(u8, zmx, 0));
            try args.append(alloc, try alloc.dupeSentinel(u8, "attach", 0));
            try args.append(alloc, try alloc.dupeSentinel(u8, name, 0));
            for (v) |arg| try args.append(alloc, try alloc.dupeSentinel(u8, arg, 0));
            break :direct @unionInit(Command, "direct", try args.toOwnedSlice(alloc));
        },
    };
}

/// Single-quote a string for /bin/sh and bash.
fn shellQuote(alloc: Allocator, s: []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = try .initCapacity(alloc, s.len + 2);
    defer out.deinit(alloc);
    try out.append(alloc, '\'');
    for (s) |c| {
        if (c == '\'') {
            try out.appendSlice(alloc, "'\\''");
        } else {
            try out.append(alloc, c);
        }
    }
    try out.append(alloc, '\'');
    return try out.toOwnedSlice(alloc);
}

const TestCommand = union(enum) {
    shell: [:0]const u8,
    direct: []const [:0]const u8,
};

test "validName accepts a UUID and refuses shell metacharacters" {
    try std.testing.expect(validName("6F1D2C3B-0A4E-4F5A-9B8C-1D2E3F4A5B6C"));
    try std.testing.expect(!validName(""));
    try std.testing.expect(!validName("a b"));
    try std.testing.expect(!validName("x;rm"));
    try std.testing.expect(!validName("$(id)"));
    try std.testing.expect(!validName("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"));
}

test "wrap keeps login semantics for a shell command" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const result = try wrap(alloc, TestCommand{ .shell = "/bin/zsh" }, "/Apps/YEN.app/Contents/Resources/bin/zmx", "ABC-123");
    try std.testing.expectEqualStrings(
        "'/Apps/YEN.app/Contents/Resources/bin/zmx' attach ABC-123 /bin/bash --noprofile --norc -c 'exec -l /bin/zsh'",
        result.shell,
    );
}

test "wrap quotes single quotes and spaces" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const result = try wrap(alloc, TestCommand{ .shell = "bash --rcfile 'my rc'" }, "/Apps/My YEN.app/zmx", "S1");
    try std.testing.expectEqualStrings(
        "'/Apps/My YEN.app/zmx' attach S1 /bin/bash --noprofile --norc -c 'exec -l bash --rcfile '\\''my rc'\\'''",
        result.shell,
    );
}

test "wrap prefixes a direct command" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const argv = [_][:0]const u8{ "nvim", "a b" };
    const result = try wrap(alloc, TestCommand{ .direct = &argv }, "/z/zmx", "S1");
    try std.testing.expectEqual(@as(usize, 5), result.direct.len);
    try std.testing.expectEqualStrings("/z/zmx", result.direct[0]);
    try std.testing.expectEqualStrings("attach", result.direct[1]);
    try std.testing.expectEqualStrings("S1", result.direct[2]);
    try std.testing.expectEqualStrings("nvim", result.direct[3]);
    try std.testing.expectEqualStrings("a b", result.direct[4]);
}

test "wrapFromEnv removes the marker and leaves the command alone without zmx" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var env = std.process.Environ.Map.init(alloc);
    try env.put(env_key, "ABC-123");
    const original = TestCommand{ .shell = "/bin/zsh" };

    const no_resources = try wrapFromEnv(alloc, std.testing.io, original, &env, null);
    try std.testing.expectEqualStrings("/bin/zsh", no_resources.shell);
    try std.testing.expect(env.get(env_key) == null);

    try env.put(env_key, "ABC-123");
    const missing_zmx = try wrapFromEnv(alloc, std.testing.io, original, &env, "/nonexistent/Resources/yen");
    try std.testing.expectEqualStrings("/bin/zsh", missing_zmx.shell);
    try std.testing.expect(env.get(env_key) == null);
}

test "wrapFromEnv refuses an unsafe name but still strips the marker" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var env = std.process.Environ.Map.init(alloc);
    try env.put(env_key, "x;rm -rf ~");
    const result = try wrapFromEnv(alloc, std.testing.io, TestCommand{ .shell = "/bin/zsh" }, &env, "/tmp/Resources/yen");
    try std.testing.expectEqualStrings("/bin/zsh", result.shell);
    try std.testing.expect(env.get(env_key) == null);
}

test "wrapFromEnv wraps when the bundled zmx exists" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const io = std.testing.io;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(io, "Resources/yen");
    try tmp.dir.createDirPath(io, "Resources/bin");
    try tmp.dir.writeFile(io, .{ .sub_path = "Resources/bin/zmx", .data = "" });
    const root = try tmp.dir.realPathFileAlloc(io, ".", alloc);
    const resources_dir = try std.fs.path.join(alloc, &.{ root, "Resources", "yen" });

    var env = std.process.Environ.Map.init(alloc);
    try env.put(env_key, "ABC-123");
    const result = try wrapFromEnv(alloc, io, TestCommand{ .shell = "/bin/zsh" }, &env, resources_dir);
    try std.testing.expect(std.mem.indexOf(u8, result.shell, "/Resources/bin/zmx' attach ABC-123 ") != null);
    try std.testing.expect(env.get(env_key) == null);
}
