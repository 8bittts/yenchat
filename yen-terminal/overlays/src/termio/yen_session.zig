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

/// Socket directory variable the app sets beside the marker; zmx reads it too.
pub const socket_dir_key = "ZMX_DIR";

/// The zmx build that started this pane's session. Attaching with the same
/// build keeps working when an update ships a zmx with another protocol.
pub const zmx_key = "YEN_PERSISTENT_SESSION_ZMX";
/// zmx sets this inside a session and refuses to attach while it is set.
pub const inherited_session_key = "ZMX_SESSION";

pub fn Prepared(comptime Command: type) type {
    return struct {
        command: Command,
        /// `<ZMX_DIR>/<name>.tty`, where the patched zmx daemon records the
        /// session's pty path; null when the pane is not wrapped.
        tty_file: ?[]const u8 = null,
    };
}

/// Returns `command` wrapped in `zmx attach <name>` when the environment marks
/// the pane as persistent and the bundled zmx exists; otherwise `command`
/// unchanged. Always removes the marker from `env`.
pub fn prepare(
    alloc: Allocator,
    io: std.Io,
    command: anytype,
    env: *std.process.Environ.Map,
    resources_dir: ?[]const u8,
) !Prepared(@TypeOf(command)) {
    const unchanged: Prepared(@TypeOf(command)) = .{ .command = command };
    const recorded: ?[]const u8 = if (env.get(zmx_key)) |v| try alloc.dupe(u8, v) else null;
    _ = env.orderedRemove(zmx_key);
    const raw = env.get(env_key) orelse return unchanged;
    const name = try alloc.dupe(u8, raw);
    _ = env.orderedRemove(env_key);
    if (!validName(name)) return unchanged;

    const zmx = zmx: {
        if (recorded) |path| {
            if (std.fs.path.isAbsolute(path)) {
                if (std.Io.Dir.accessAbsolute(io, path, .{})) |_| break :zmx path else |_| {}
            }
        }
        const dir = resources_dir orelse return unchanged;
        const bundled = try zmxPath(alloc, dir) orelse return unchanged;
        std.Io.Dir.accessAbsolute(io, bundled, .{}) catch return unchanged;
        break :zmx bundled;
    };

    const tty_file: ?[]const u8 = if (env.get(socket_dir_key)) |socket_dir|
        try std.fmt.allocPrint(alloc, "{s}/{s}.tty", .{ socket_dir, name })
    else
        null;
    return .{ .command = try wrap(alloc, command, zmx, name), .tty_file = tty_file };
}

/// `prepare` without the tty record.
pub fn wrapFromEnv(
    alloc: Allocator,
    io: std.Io,
    command: anytype,
    env: *std.process.Environ.Map,
    resources_dir: ?[]const u8,
) !@TypeOf(command) {
    return (try prepare(alloc, io, command, env, resources_dir)).command;
}

/// Read the pty path the zmx daemon recorded. Only a `/dev/tty*` path is
/// accepted, so a stray file can never point the app at anything else.
pub fn innerTtyPath(buf: *[256]u8, tty_file: []const u8) ?[:0]const u8 {
    var path_buf: [1024]u8 = undefined;
    const path = std.fmt.bufPrintSentinel(&path_buf, "{s}", .{tty_file}, 0) catch return null;
    const fd = std.c.open(path.ptr, .{ .ACCMODE = .RDONLY }, @as(c_uint, 0));
    if (fd < 0) return null;
    defer _ = std.c.close(fd);
    const n = std.c.read(fd, buf, buf.len - 1);
    if (n <= 0) return null;
    const content = std.mem.trimEnd(u8, buf[0..@intCast(n)], "\n");
    if (!std.mem.startsWith(u8, content, "/dev/tty")) return null;
    for (content["/dev/".len..]) |c| switch (c) {
        'a'...'z', 'A'...'Z', '0'...'9' => {},
        else => return null,
    };
    buf[content.len] = 0;
    return buf[0..content.len :0];
}

/// Open the session's inner pty for a termios read. The caller closes it at
/// once: holding the slave open would keep the pty alive after the shell exits.
pub fn openInnerTty(tty_file: []const u8) ?c_int {
    var buf: [256]u8 = undefined;
    const path = innerTtyPath(&buf, tty_file) orelse return null;
    const fd = std.c.open(path.ptr, .{ .ACCMODE = .RDONLY, .NOCTTY = true, .NONBLOCK = true }, @as(c_uint, 0));
    return if (fd < 0) null else fd;
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

test "a pane never inherits the session the app was launched from" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const io = std.testing.io;

    // An app started from a persistent pane inherits that pane's ZMX_SESSION.
    // zmx treats an attach under it as nested and fails, so the pane dies.
    var env = std.process.Environ.Map.init(alloc);
    try env.put(inherited_session_key, "PARENT-1");
    try env.put(env_key, "ABC-123");
    _ = try wrapFromEnv(alloc, io, TestCommand{ .shell = "/bin/zsh" }, &env, null);
    try std.testing.expect(env.get(inherited_session_key) == null);

    // A pane that is not persistent is not inside that session either.
    try env.put(inherited_session_key, "PARENT-1");
    _ = try wrapFromEnv(alloc, io, TestCommand{ .shell = "/bin/zsh" }, &env, null);
    try std.testing.expect(env.get(inherited_session_key) == null);
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

test "prepare reports the tty record only when it wraps" {
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
    try env.put(socket_dir_key, "/Users/dev/.local/state/yen/zmx");
    const wrapped = try prepare(alloc, io, TestCommand{ .shell = "/bin/zsh" }, &env, resources_dir);
    try std.testing.expectEqualStrings("/Users/dev/.local/state/yen/zmx/ABC-123.tty", wrapped.tty_file.?);

    const plain = try prepare(alloc, io, TestCommand{ .shell = "/bin/zsh" }, &env, resources_dir);
    try std.testing.expect(plain.tty_file == null);
}

test "innerTtyPath accepts only a /dev/tty path" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const root = try tmp.dir.realPathFileAlloc(io, ".", arena.allocator());

    const cases = [_]struct { data: []const u8, want: ?[]const u8 }{
        .{ .data = "/dev/ttys007\n", .want = "/dev/ttys007" },
        .{ .data = "/dev/ttys012", .want = "/dev/ttys012" },
        .{ .data = "/etc/passwd", .want = null },
        .{ .data = "/dev/tty/../disk0", .want = null },
        .{ .data = "", .want = null },
    };
    for (cases, 0..) |case, i| {
        const name = try std.fmt.allocPrint(arena.allocator(), "s{d}.tty", .{i});
        try tmp.dir.writeFile(io, .{ .sub_path = name, .data = case.data });
        const file = try std.fs.path.join(arena.allocator(), &.{ root, name });
        var buf: [256]u8 = undefined;
        const got = innerTtyPath(&buf, file);
        if (case.want) |want| {
            try std.testing.expectEqualStrings(want, got.?);
        } else {
            try std.testing.expect(got == null);
        }
    }
    var buf: [256]u8 = undefined;
    try std.testing.expect(innerTtyPath(&buf, "/nonexistent/x.tty") == null);
}

test "prepare attaches with the recorded zmx build and strips its variable" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const io = std.testing.io;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(io, "Resources/yen");
    try tmp.dir.createDirPath(io, "Resources/bin");
    try tmp.dir.createDirPath(io, "state/bin");
    try tmp.dir.writeFile(io, .{ .sub_path = "Resources/bin/zmx", .data = "" });
    try tmp.dir.writeFile(io, .{ .sub_path = "state/bin/zmx-old", .data = "" });
    const root = try tmp.dir.realPathFileAlloc(io, ".", alloc);
    const resources_dir = try std.fs.path.join(alloc, &.{ root, "Resources", "yen" });
    const old = try std.fs.path.join(alloc, &.{ root, "state", "bin", "zmx-old" });

    var env = std.process.Environ.Map.init(alloc);
    try env.put(env_key, "ABC-123");
    try env.put(zmx_key, old);
    const recorded = try prepare(alloc, io, TestCommand{ .shell = "/bin/zsh" }, &env, resources_dir);
    try std.testing.expect(std.mem.startsWith(u8, recorded.command.shell, "'"));
    try std.testing.expect(std.mem.indexOf(u8, recorded.command.shell, "/state/bin/zmx-old' attach ABC-123 ") != null);
    try std.testing.expect(env.get(zmx_key) == null);

    // A recorded build that is gone, or a relative path, falls back to the bundled zmx.
    for ([_][]const u8{ "/nonexistent/zmx-gone", "state/bin/zmx-old" }) |bad| {
        try env.put(env_key, "ABC-123");
        try env.put(zmx_key, bad);
        const fallback = try prepare(alloc, io, TestCommand{ .shell = "/bin/zsh" }, &env, resources_dir);
        try std.testing.expect(std.mem.indexOf(u8, fallback.command.shell, "/Resources/bin/zmx' attach ABC-123 ") != null);
        try std.testing.expect(env.get(zmx_key) == null);
    }
}
