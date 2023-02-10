const std = @import("std");

const Server = @import("server.zig").Server;
const debug = std.log.debug;

const ip = "localhost";
const port = 8018;

var server: ?*Server = null;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(!gpa.deinit());
    var ally = gpa.allocator();

    try std.os.sigaction(std.os.SIG.INT, &std.os.Sigaction{
        .handler = .{ .handler = handleSigInt },
        .mask = std.os.empty_sigset,
        .flags = 0,
    }, null);

    var srv = try Server.init(ip, port, ally);
    defer srv.deinit();
    server = &srv;
    try srv.listen();
    debug("Ending...", .{});
}

fn handleSigInt(_: c_int) callconv(.C) void {
    debug("\nSigint moment", .{});
    if (server) |srv| {
        srv.deinit();
    }
    debug("Sigint complete", .{});
}

comptime {
    _ = @import("http.zig");
}
