import Foundation
import NIOCore
import NIOPosix
import NIOHTTP1
import SDLKit

final class HTTPHandler: ChannelInboundHandler {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private var bodyData = Data()
    private var currentPath: String?
    private let agent = SDLKitJSONAgent()

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = self.unwrapInboundIn(data)
        switch part {
        case .head(let request):
            bodyData.removeAll(keepingCapacity: false)
            // Parse URI path only (ignore query for now)
            if let qidx = request.uri.firstIndex(of: "?") {
                currentPath = String(request.uri[..<qidx])
            } else {
                currentPath = request.uri
            }
        case .body(let buf):
            var b = buf
            if let bytes = b.readBytes(length: b.readableBytes) {
                bodyData.append(contentsOf: bytes)
            }
        case .end:
            // Route by path; forward to SDLKitJSONAgent
            let reqBody = bodyData
            let path = currentPath ?? "/health"
            let responseData: Data = agent.handle(path: path, body: reqBody)
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
