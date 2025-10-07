import Foundation
import NIOCore
import NIOPosix
import NIOHTTP1
import SDLKit

final class HTTPHandler: ChannelInboundHandler {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private var bodyData = Data()
    private let agent = SDLKitJSONAgent()

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = self.unwrapInboundIn(data)
        switch part {
        case .head:
            bodyData.removeAll(keepingCapacity: false)
        case .body(let buf):
            var b = buf
            if let bytes = b.readBytes(length: b.readableBytes) {
                bodyData.append(contentsOf: bytes)
            }
        case .end:
            // Route by path; forward to SDLKitJSONAgent
            let reqBody = bodyData
            let path = context.channel.pipeline.context(name: "HTTPHandler").flatMap { _ in context.channel.parent }.map { _ in "" }
            // We cannot get the path from here directly; install a separate handler to capture head if needed.
            // For simplicity, require body to contain { "_path": "/agent/gui/window/open", ... }
            let responseData: Data
            if let json = try? JSONSerialization.jsonObject(with: reqBody) as? [String: Any], let p = json["_path"] as? String {
                var clean = json
                clean.removeValue(forKey: "_path")
                let body = try! JSONSerialization.data(withJSONObject: clean)
                responseData = agent.handle(path: p, body: body)
            } else {
                let err = ["code": "invalid_request", "message": "body must include _path"]
                responseData = try! JSONSerialization.data(withJSONObject: err)
            }
            var headers = HTTPHeaders()
            headers.add(name: "content-type", value: "application/json")
            headers.add(name: "content-length", value: String(responseData.count))
            context.write(self.wrapOutboundOut(.head(.init(version: .http1_1, status: .ok, headers: headers))), promise: nil)
            var buf = context.channel.allocator.buffer(capacity: responseData.count)
            buf.writeBytes(responseData)
            context.write(self.wrapOutboundOut(.body(.byteBuffer(buf))), promise: nil)
            context.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)
        }
    }
}

let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
defer { try? group.syncShutdownGracefully() }
let port = Int(ProcessInfo.processInfo.environment["SDLKIT_NIO_PORT"] ?? "8723") ?? 8723

let bootstrap = ServerBootstrap(group: group)
    .serverChannelOption(ChannelOptions.backlog, value: 256)
    .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
    .childChannelInitializer { channel in
        channel.pipeline.configureHTTPServerPipeline().flatMap {
            channel.pipeline.addHandler(HTTPHandler())
        }
    }
    .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
    .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 1)
    .childChannelOption(ChannelOptions.recvAllocator, value: AdaptiveRecvByteBufferAllocator())

let channel = try bootstrap.bind(host: "127.0.0.1", port: port).wait()
print("SDLKitNIO listening on http://127.0.0.1:\(port)")
try channel.closeFuture.wait()

