const std = @import("std");
const builtin = @import("builtin");
const c = @cImport({
        @cInclude("time.h");
});

const MemStats = struct {
    os: []const u8,
    used_mb: u64,
    total_mb: u64,
    timestamp: i64,
};

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.gpa;

    const address = try std.Io.net.IpAddress.parseIp4("127.0.0.1", 8080);
    var server = try address.listen(io, .{});
    defer server.deinit(io);

    std.debug.print("Memory Service listening on 127.0.0.1:8080...\n", .{});
    while (true) {
        const stream = server.accept(io) catch |err| {
            std.debug.print("Accept error: {}\n", .{err});
            continue;
        };
        defer stream.close(io);

        const stats = try getMemoryStats(io);
        std.debug.print("{any}\n", .{stats});
        const json_str = try std.fmt.allocPrint(
            allocator,
            "{f}\n",
            .{std.json.fmt(stats, .{})},
        );
        defer allocator.free(json_str);
        std.debug.print("{s}\n", .{json_str});

        var wbuf: [4096]u8 = undefined;
        var writer_impl = stream.writer(io, &wbuf);
        const writer = &writer_impl.interface;
        try writer.writeAll(json_str);
        try writer.flush();
    }
}


fn getMemoryStats(io: std.Io) !MemStats {
    var ts: c.struct_timespec = undefined;
    _ = c.clock_gettime(c.CLOCK_REALTIME, &ts);

    var stats = MemStats{
        .os = @tagName(builtin.os.tag),
        .used_mb = 0,
        .total_mb = 0,
        .timestamp = @as(i64, ts.tv_sec),
    };
    const file = try std.Io.Dir.cwd().openFile(
        io,
        "/proc/meminfo",
        .{},
    );
    defer file.close(io);
    var buf: [4096]u8 = undefined;
    const n = try file.readPositionalAll(io, &buf, 0);
    const content = buf[0..n];
    var total_kb: u64 = 0;
    var avail_kb: u64 = 0;
    var lines = std.mem.tokenizeScalar(u8, content, '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "MemTotal:")) total_kb = parseNumber(line);
        if (std.mem.startsWith(u8, line, "MemAvailable:")) avail_kb = parseNumber(line);
    }
    stats.total_mb = total_kb / 1024;
    stats.used_mb = (total_kb - avail_kb) / 1024;
    return stats;
}

fn parseNumber(line: []const u8) u64 {
    var parts = std.mem.tokenizeAny(u8, line, " .:");
    while (parts.next()) |part| {
        if (std.fmt.parseInt(u64, part, 10)) |val| return val else |_| continue;
            }
        return 0;
}
