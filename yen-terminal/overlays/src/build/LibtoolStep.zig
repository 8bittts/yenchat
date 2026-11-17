//! A zig builder step that runs "libtool" against a list of libraries
//! in order to create a single combined static library.
const LibtoolStep = @This();

const std = @import("std");
const Step = std.Build.Step;
const RunStep = std.Build.Step.Run;
const LazyPath = std.Build.LazyPath;

pub const Options = struct {
    /// The name of this step.
    name: []const u8,

    /// The filename (not the path) of the file to create. This will
    /// be placed in a unique hashed directory. Use out_path to access.
    out_name: []const u8,

    /// Library files (.a) to combine.
    sources: []LazyPath,
};

/// The step to depend on.
step: *Step,

/// The output file from the libtool run.
output: LazyPath,

/// Run libtool against a list of library files to combine into a single
/// static library.
pub fn create(b: *std.Build, opts: Options) *LibtoolStep {
    const self = b.allocator.create(LibtoolStep) catch @panic("OOM");

    const write_files = b.addWriteFiles();
    const helper = write_files.add("libtool-step.sh",
        \\set -eu
        \\
        \\out="$1"
        \\shift
        \\
        \\workdir="$(mktemp -d "${TMPDIR:-/tmp}/yen-libtool.XXXXXX")"
        \\trap 'chmod -R u+rwX "$workdir" 2>/dev/null || true; rm -rf "$workdir"' EXIT HUP INT TERM
        \\
        \\object_list="$workdir/objects.list"
        \\: >"$object_list"
        \\
        \\i=0
        \\for source in "$@"; do
        \\    i=$((i + 1))
        \\    extracted_dir="$workdir/src-$i"
        \\    mkdir -p "$extracted_dir"
        \\
        \\    case "$source" in
        \\        /*) source_path="$source" ;;
        \\        *) source_path="$PWD/$source" ;;
        \\    esac
        \\
        \\    if ar -t "$source_path" >/dev/null 2>&1; then
        \\        (
        \\            cd "$extracted_dir"
        \\            ar -x "$source_path"
        \\        )
        \\    else
        \\        cp "$source_path" "$extracted_dir/"
        \\    fi
        \\
        \\    find "$extracted_dir" -type f -name '*.o' -exec chmod u+rw {} \;
        \\    find "$extracted_dir" -type f -name '*.o' | LC_ALL=C sort >>"$object_list"
        \\done
        \\
        \\if [ ! -s "$object_list" ]; then
        \\    echo "libtool step: no object files found in inputs" >&2
        \\    exit 1
        \\fi
        \\
        \\libtool -static -D -o "$out" -filelist "$object_list"
        \\
    );

    const run_step = RunStep.create(b, b.fmt("libtool {s}", .{opts.name}));
    run_step.addArgs(&.{"sh"});
    run_step.addFileArg(helper);
    const output = run_step.addOutputFileArg(opts.out_name);
    for (opts.sources) |source| run_step.addFileArg(source);

    self.* = .{
        .step = &run_step.step,
        .output = output,
    };

    return self;
}
