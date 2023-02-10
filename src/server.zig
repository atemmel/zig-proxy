const std = @import("std");
const curl = @import("curl.zig");
const http = @import("http.zig");

const atomic = std.atomic;
const Thread = std.Thread;
const net = std.net;
const os = std.os;
const debug = std.log.debug;
const Allocator = std.mem.Allocator;

pub const Server = struct {
    stream: net.StreamServer,
    address: net.Address,
    ally: Allocator,
    should_die: atomic.Atomic(bool) = atomic.Atomic(bool).init(false),
    has_died: Thread.ResetEvent = Thread.ResetEvent{},

    pub fn init(addr: []const u8, port: u16, ally: Allocator) !Server {
        const addresses = try net.getAddressList(ally, addr, port);
        defer addresses.deinit();
        const server = Server{
            .stream = net.StreamServer.init(.{
                .reuse_address = true,
            }),
            .ally = ally,
            .address = addresses.addrs[0],
        };
        return server;
    }

    pub fn deinit(self: *Server) void {
        if (self.has_died.isSet()) {
            return;
        }
        defer self.stream.deinit();
        debug("Quit reading", .{});
        self.should_die.store(true, .SeqCst);
        debug("Sending dummy client", .{});
        var dummy = net.tcpConnectToAddress(self.stream.listen_address) catch null;
        if (dummy) |*sock| {
            debug("Closing dummy", .{});
            sock.close();
        }
        debug("Waiting...", .{});
        self.has_died.wait();
        debug("Wait complete", .{});
    }

    pub fn listen(self: *Server) !void {
        var thread = try Thread.spawn(.{}, listenImpl, .{self});
        thread.join();
    }

    fn listenImpl(self: *Server) !void {
        defer self.has_died.set();
        debug("Listening on address...", .{});
        try self.stream.listen(self.address);
        while (!self.should_die.load(.SeqCst)) {
            debug("Accepting new connections...", .{});
            var conn = self.stream.accept() catch {
                debug("Unable to accept connection", .{});
                continue;
            };

            var thread = Thread.spawn(.{}, transfer, .{ self, conn }) catch {
                debug("Unable to transfer data to client", .{});
                continue;
            };
            thread.detach();
        }
        debug("Shutting down...", .{});
    }

    fn transfer(self: *Server, conn: net.StreamServer.Connection) !void {
        defer conn.stream.close();
        var url_buffer: [512]u8 = undefined;
        var buffer: [4096]u8 = undefined;

        const n = try conn.stream.read(&buffer);
        const request_slice = buffer[0..n];

        const request = http.parse(request_slice) orelse {
            debug("Unable to parse request...", .{});
            return;
        };

        const url = try std.fmt.bufPrintZ(&url_buffer, "https://www.google.com{s}", .{request.path});

        var req = curl.Request.to(self.ally, url) orelse {
            debug("Unable to perform request...", .{});
            return;
        };
        defer req.deinit();

        _ = try conn.stream.write(req.string.items);
        debug("Transfer complete", .{});
    }
};
