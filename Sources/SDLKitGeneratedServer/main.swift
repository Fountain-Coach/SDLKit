import Foundation
import NIOCore
import NIOPosix
import NIOHTTP1
import OpenAPIRuntime
import HTTPTypes
import SDLKitAPI
import SDLKitAPIServerAdapter

final class NIOHTTPHandler: ChannelInboundHandler {
  typealias InboundIn = HTTPServerRequestPart
  typealias OutboundOut = HTTPServerResponsePart

  struct RouteKey: Hashable { let method: String; let path: String }
  private let routes: [RouteKey: @Sendable (HTTPRequest, HTTPBody?, ServerRequestMetadata) async throws -> (HTTPResponse, HTTPBody?)]

  init(routes: [RouteKey: @Sendable (HTTPRequest, HTTPBody?, ServerRequestMetadata) async throws -> (HTTPResponse, HTTPBody?)]) {
    self.routes = routes
  }

  private var reqHead: HTTPRequestHead?
  private var bodyBuffer = ByteBufferAllocator().buffer(capacity: 0)

  func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    let part = unwrapInboundIn(data)
    switch part {
    case .head(let head):
      reqHead = head
      bodyBuffer.clear()
    case .body(var buf):
      if let bytes = buf.readBytes(length: buf.readableBytes) {
        bodyBuffer.writeBytes(bytes)
      }
    case .end:
      guard let head = reqHead else { return }
      let method = HTTPRequest.Method(head.method.rawValue) ?? HTTPRequest.Method("GET")!
      let path = head.uri
      var fields = HTTPFields()
      for h in head.headers { if let name = HTTPField.Name(h.name) { fields.append(HTTPField(name: name, value: h.value)) } }
      let req = HTTPRequest(method: method, scheme: nil, authority: nil, path: path, headerFields: fields)
      let bodyData = Data(bodyBuffer.readableBytesView)
      let body: HTTPBody? = bodyData.isEmpty ? nil : HTTPBody(bodyData)
      let full = head.uri
      let pOnly: String = {
        if let q = full.firstIndex(of: "?") { return String(full[..<q]) }
        if let f = full.firstIndex(of: "#") { return String(full[..<f]) }
        return full
      }()
      let key = RouteKey(method: head.method.rawValue.uppercased(), path: pOnly)
      let routeHandler = self.routes[key]
      var resp: HTTPResponse = HTTPResponse(status: .init(code: 404))
      var respBody: HTTPBody? = nil
      let sema = DispatchSemaphore(value: 0)
      Task {
        if let h = routeHandler {
          do {
            let r = try await h(req, body, ServerRequestMetadata())
            resp = r.0
            respBody = r.1
          } catch { resp = HTTPResponse(status: .init(code: 500)); respBody = nil }
        }
        sema.signal()
      }
      sema.wait()
      var headers = HTTPHeaders()
      for f in resp.headerFields { headers.add(name: f.name.canonicalName, value: f.value) }
      let headOut = HTTPResponseHead(version: head.version, status: .init(statusCode: resp.status.code), headers: headers)
      context.write(self.wrapOutboundOut(.head(headOut)), promise: nil)
      var collected: Data? = nil
      if let b = respBody {
        let cSema = DispatchSemaphore(value: 0)
        Task {
          let d = try? await Data(collecting: b, upTo: .max)
          collected = d
          cSema.signal()
        }
        cSema.wait()
      }
      if let data = collected {
        var out = context.channel.allocator.buffer(capacity: data.count)
        out.writeBytes(data)
        context.write(self.wrapOutboundOut(.body(.byteBuffer(out))), promise: nil)
      }
      context.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)
    }
  }
}

final class NIOTransport: ServerTransport {
  typealias RouteKey = NIOHTTPHandler.RouteKey
  private var routes: [RouteKey: @Sendable (HTTPRequest, HTTPBody?, ServerRequestMetadata) async throws -> (HTTPResponse, HTTPBody?)] = [:]

  func register(_ handler: @escaping @Sendable (HTTPRequest, HTTPBody?, ServerRequestMetadata) async throws -> (HTTPResponse, HTTPBody?), method: HTTPRequest.Method, path: String) throws {
    routes[.init(method: method.rawValue.uppercased(), path: path)] = handler
  }

  func makeHandler() -> NIOHTTPHandler { NIOHTTPHandler(routes: routes) }
}

@main
struct Main {
  static func main() throws {
    let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
    defer { try? group.syncShutdownGracefully() }

    let transport = NIOTransport()
    let handler = SDLKitAPIServerAdapter()
    try handler.registerHandlers(on: transport)

    let port = Int(ProcessInfo.processInfo.environment["SDLKIT_GENERATED_PORT"] ?? "8724") ?? 8724
    let bootstrap = ServerBootstrap(group: group)
      .serverChannelOption(ChannelOptions.backlog, value: 256)
      .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
      .childChannelInitializer { channel in
        channel.pipeline.configureHTTPServerPipeline().flatMap {
          channel.pipeline.addHandler(transport.makeHandler())
        }
      }
      .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
      .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 1)
      .childChannelOption(ChannelOptions.recvAllocator, value: AdaptiveRecvByteBufferAllocator())

    let channel = try bootstrap.bind(host: "127.0.0.1", port: port).wait()
    print("SDLKitGeneratedServer listening on http://127.0.0.1:\(port)")
    try channel.closeFuture.wait()
  }
}
