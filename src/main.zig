const std = @import("std");

const Server = @import("server.zig").Server;

const ip = "localhost";
const port = 8015;

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
    server = &srv;
    try srv.listen();
    std.log.debug("Ending...", .{});
}

fn handleSigInt(_: c_int) callconv(.C) void {
    std.log.debug("\nSigint moment", .{});
    if (server) |srv| {
        srv.deinit();
    }
    std.log.debug("Sigint complete", .{});
}
