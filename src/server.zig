const std = @import("std");

const atomic = std.atomic;
const Thread = std.Thread;
const net = std.net;
const os = std.os;
const debug = std.log.debug;

pub const Server = struct {
    stream: std.net.StreamServer,
    address: net.Address,
    ally: std.mem.Allocator,
    should_die: std.atomic.Atomic(bool) = std.atomic.Atomic(bool).init(false),
    has_died: std.Thread.ResetEvent = std.Thread.ResetEvent{},

    pub fn init(addr: []const u8, port: u16, ally: std.mem.Allocator) !Server {
        const addresses = try net.getAddressList(ally, addr, port);
        defer addresses.deinit();
        const server = Server{
            .stream = net.StreamServer.init(.{
                //.reuse_address = true,
            }),
            .ally = ally,
            .address = addresses.addrs[0],
        };
        return server;
    }

    pub fn deinit(self: *Server) void {
        defer self.stream.deinit();
        debug("Quit reading", .{});
        self.should_die.store(true, .Release);
        debug("Sending dummy client", .{});
        var dummy = std.net.tcpConnectToAddress(self.stream.listen_address) catch {
            debug("whoops", .{});
            return;
        };
        debug("Closing dummy", .{});
        dummy.close();
        debug("Waiting...", .{});
        self.has_died.wait();
        debug("Wait complete", .{});
    }

    pub fn listen(self: *Server) !void {
        var nice_buffer: [2048]u8 = undefined;
        debug("Listening on address...", .{});
        try self.stream.listen(self.address);
        while (!self.should_die.load(.Acquire)) {
            debug("Accepting new connection...", .{});
            var conn = try self.stream.accept();
            defer conn.stream.close();

            debug("Reading from connection", .{});
            const n = try conn.stream.read(&nice_buffer);
            const bytes = nice_buffer[0..n];

            debug("Recieved {} bytes: \n\n{s}\n", .{ n, bytes });

            _ = try conn.stream.write("Test bytes");
        }
        debug("Shutting down...", .{});
        self.has_died.set();
    }
};