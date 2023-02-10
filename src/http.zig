const std = @import("std");

pub const Method = enum {
    Get,
    Post,
    Put,
    Delete,

    pub fn parse(str: []const u8) ?Method {
        const eql = std.mem.eql;
        if (eql(u8, str, "GET")) {
            return .Get;
        } else if (eql(u8, str, "POST")) {
            return .Post;
        } else if (eql(u8, str, "PUT")) {
            return .Put;
        } else if (eql(u8, str, "DELETE")) {
            return .Delete;
        }
        return null;
    }
};

pub const Response = struct {
    method: Method,
    path: []const u8,
    headers: []const u8,
    body: []const u8,
};

pub fn parse(bytes: []const u8) ?Response {
    var response: Response = undefined;
    if (!parseLine(&response, bytes)) {
        return null;
    }

    var rest: []const u8 = undefined;

    {
        var it = std.mem.split(u8, bytes, "\r\n");
        _ = it.next() orelse return null;
        rest = it.rest();
    }

    {
        const begin = rest.ptr;
        var it = std.mem.split(u8, rest, "\r\n");
        while (it.next()) |header| {
            if (header.len == 0) {
                break;
            }
        }

        const end = it.rest().ptr;
        const header_body_split = @ptrToInt(end) - @ptrToInt(begin);

        if (header_body_split > rest.len) {
            return null;
        }

        response.headers = rest[0 .. header_body_split - 2];
        response.body = rest[header_body_split..];
    }

    return response;
}

fn parseLine(response: *Response, bytes: []const u8) bool {
    var it = std.mem.split(u8, bytes, " ");
    const method = it.next() orelse return false;
    const path = it.next() orelse return false;
    response.method = Method.parse(method) orelse return false;
    response.path = path;
    return true;
}

const example_line = "GET /images/branding/googlelogo/1x/googlelogo_white_background_color_272x92dp.png HTTP/1.1";
const example_headers = "Host: localhost:8018\r\nUser-Agent: Mozilla/5.0 (X11; Linux x86_64; rv:109.0) Gecko/20100101 Firefox/109.0\r\nAccept: image/avif,image/webp,*/*\r\nAccept-Language: en-US,en;q=0.5\r\nAccept-Encoding: gzip, deflate, br\r\nConnection: keep-alive\r\nReferer: http://localhost:8018/\r\nSec-Fetch-Dest: image\r\nSec-Fetch-Mode: no-cors\r\nSec-Fetch-Site: same-origin\r\n";
const example_body = "{}";

const example = example_line ++ "\r\n" ++ example_headers ++ "\r\n" ++ example_body;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

test "parse test" {
    const response = parse(example);
    try expect(response != null);
    try expectEqual(Method.Get, response.?.method);
    try expectEqualStrings("/images/branding/googlelogo/1x/googlelogo_white_background_color_272x92dp.png", response.?.path);
    try expectEqualStrings(example_headers, response.?.headers);
    try expectEqualStrings(example_body, response.?.body);
}
