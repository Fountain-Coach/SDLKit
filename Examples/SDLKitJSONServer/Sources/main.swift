import NIO
import NIOHTTP1
import Foundation
import SDLKit

final class HTTPHandler: ChannelInboundHandler {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private var requestHead: HTTPRequestHead?
    private var bodyBuffer: ByteBuffer?
    private let agent: SDLKitJSONAgent = SDLKitJSONAgent()

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = self.unwrapInboundIn(data)
        switch part {
        case .head(let head):
            self.requestHead = head
            self.bodyBuffer = context.channel.allocator.buffer(capacity: 0)
        case .body(var chunk):
            self.bodyBuffer?.writeBuffer(&chunk)
        case .end:
            handleRequest(context: context)
        }
    }

    private func handleRequest(context: ChannelHandlerContext) {
        guard let head = self.requestHead else { return }
        let keepAlive = head.isKeepAlive
        let responseHead: HTTPResponseHead
        var responseBody = context.channel.allocator.buffer(capacity: 0)

        if head.method == .POST || (head.method == .GET && (head.uri == "/openapi.yaml" || head.uri == "/openapi.json" || head.uri == "/health" || head.uri == "/version")) {
            let path = head.uri
            let data = bodyBuffer.flatMap { Data($0.readableBytesView) } ?? Data()
            if let addr = context.remoteAddress { print("[HTTP] \(head.method) \(path) from \(addr) bytes=\(data.count)") } else { print("[HTTP] \(head.method) \(path) bytes=\(data.count)") }
            let res = agent.handle(path: path, body: data)
            let contentType = path.hasSuffix(".yaml") ? "application/yaml" : "application/json"
            responseHead = HTTPResponseHead(version: head.version, status: .ok, headers: ["Content-Type": contentType])
            responseBody.writeBytes(res)
        } else {
            responseHead = HTTPResponseHead(version: head.version, status: .ok, headers: ["Content-Type": "text/plain; charset=utf-8"])
            responseBody.writeString("SDLKit JSON Server\nPOST endpoints under /agent/gui/...\n")
        }
        context.write(self.wrapOutboundOut(.head(responseHead)), promise: nil)
        context.write(self.wrapOutboundOut(.body(.byteBuffer(responseBody))), promise: nil)
        let promise: EventLoopPromise<Void>? = keepAlive ? nil : context.eventLoop.makePromise()
        if !keepAlive { promise?.futureResult.whenComplete { _ in context.close(promise: nil) } }
        context.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: promise)
        self.requestHead = nil
        self.bodyBuffer = nil
    }
}

@main
enum Main {
    static func main() throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        let host = ProcessInfo.processInfo.environment["SDLKIT_SERVER_HOST"] ?? "127.0.0.1"
        let port = Int(ProcessInfo.processInfo.environment["SDLKIT_SERVER_PORT"] ?? "8080") ?? 8080
        defer { try? group.syncShutdownGracefully() }

        let server = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.configureHTTPServerPipeline().flatMap {
                    channel.pipeline.addHandler(HTTPHandler())
                }
            }
            .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 1)
            .childChannelOption(ChannelOptions.allowRemoteHalfClosure, value: true)

        let channel = try server.bind(host: host, port: port).wait()
        print("SDLKit JSON Server listening on http://\(host):\(port)")
        try channel.closeFuture.wait()
    }
}
