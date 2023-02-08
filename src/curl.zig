const std = @import("std");
const curl = @cImport(@cInclude("curl/curl.h"));
const Allocator = std.mem.Allocator;

pub const String = std.ArrayList(u8);

pub const Request = struct {
    string: std.ArrayList(u8) = undefined,

    pub fn deinit(self: *Request) void {
        self.string.deinit();
    }

    pub fn to(ally: Allocator, where: [:0]const u8) ?Request {
        var ctx = curl.curl_easy_init();
        defer curl.curl_easy_cleanup(ctx);
        if (ctx == null) {
            return null;
        }

        var request = Request{
            .string = std.ArrayList(u8).init(ally),
        };
        var res: curl.CURLcode = undefined;

        _ = curl.curl_easy_setopt(ctx, curl.CURLOPT_URL, where.ptr);
        _ = curl.curl_easy_setopt(ctx, curl.CURLOPT_HEADER, @as(c_uint, 1));
        //_ = curl.curl_easy_setopt(ctx, curl.CURLOPT_VERBOSE, @as(c_uint, 1));
        _ = curl.curl_easy_setopt(ctx, curl.CURLOPT_WRITEFUNCTION, writeCallback);
        _ = curl.curl_easy_setopt(ctx, curl.CURLOPT_WRITEDATA, &request);
        res = curl.curl_easy_perform(ctx);

        if (res != curl.CURLE_OK) {
            std.log.debug("curl_easy_perform() failed: {s}", .{curl.curl_easy_strerror(res)});
            return null;
        }
        std.log.debug("curl_easy_perform() success: {s}", .{curl.curl_easy_strerror(res)});
        std.log.debug("Data: {} bytes", .{request.string.items.len});
        return request;
    }
};

fn writeCallback(contents: [*]const u8, size: c_uint, nmemb: c_uint, userp: *anyopaque) callconv(.C) c_uint {
    var request = @ptrCast(*Request, @alignCast(@alignOf(Request), userp));
    const all = size * nmemb;
    const slice = contents[0..all];
    request.string.appendSlice(slice) catch unreachable;
    return all;
}
