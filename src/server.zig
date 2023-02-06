const std = @import("std");

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
        //const ip = "github.com";
        //const port = 443;
        const ip = "localhost";
        const port = 8000;
        var buffer: [2048]u8 = undefined;

        var client = try net.tcpConnectToHost(self.ally, ip, port);
        defer client.close();

        {
            debug("Reading from connection", .{});
            const n = try conn.stream.read(&buffer);
            const request = buffer[0..n];
            debug("Forwarding {} bytes: \n\n'{s}'\n", .{ n, request });
            _ = try client.write(request);
        }

        {
            const n = try client.read(&buffer);
            const partial_response = buffer[0..n];
            debug("Recieved {} bytes: \n\n'{s}'\n", .{ n, partial_response });
            _ = try conn.stream.write(partial_response);
        }

        while (true) {
            const n = try client.read(&buffer);
            const partial_response = buffer[0..n];
            debug("Recieved {} bytes: \n\n'{s}'\n", .{ n, partial_response });
            _ = try conn.stream.write(partial_response);

            if (n < buffer.len) {
                break;
            }
        }

        debug("Transfer complete", .{});
    }
};

fn readHttpHeader(bytes: []const u8) void {
    var it = std.mem.tokenize(u8, bytes, "\n\r");
    var header: []const u8 = undefined;
    if (it.next()) |slice| {
        header = slice;
    } else {
        return;
    }

    it = std.mem.tokenize(u8, header, " ");
}
