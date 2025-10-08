#if canImport(OpenAPIRuntime) && canImport(SDLKitAPI) && canImport(SDLKit)
import Foundation
import Foundation
import OpenAPIRuntime
import HTTPTypes
import SDLKitAPI
import SDLKit

// Generated-server adapter that forwards OpenAPI operations to SDLKitJSONAgent.
public struct SDLKitAPIServerAdapter: APIProtocol {
    public init() {}
    private func onMain<T: Sendable>(_ body: @MainActor @escaping () -> T) -> T {
        var result: T! = nil
        DispatchQueue.main.sync { result = MainActor.assumeIsolated { body() } }
        return result
    }
    private func call(_ path: String, body: Data) -> OpenAPIRuntime.UndocumentedPayload {
        let data: Data = onMain { SDLKitJSONAgent().handle(path: path, body: body) }
        var fields = HTTPFields()
        fields[.contentType] = "application/json"
        return .init(headerFields: fields, body: HTTPBody(data))
    }
    public func openWindow(_ input: Operations.openWindow.Input) async throws -> Operations.openWindow.Output {
        let req: Data
        switch input.body {
        case .json(let payload):
            req = try JSONEncoder().encode(payload)
        }
        let payload = call("/agent/gui/window/open", body: req)
        return .undocumented(statusCode: 200, payload)
    }

    public func closeWindow(_ input: Operations.closeWindow.Input) async throws -> Operations.closeWindow.Output {
        let req: Data
        switch input.body {
        case .json(let payload):
            req = try JSONEncoder().encode(payload)
        }
        let payload = call("/agent/gui/window/close", body: req)
        return .undocumented(statusCode: 200, payload)
    }

    public func showWindow(_ input: Operations.showWindow.Input) async throws -> Operations.showWindow.Output {
        let req: Data
        switch input.body {
        case .json(let payload):
            req = try JSONEncoder().encode(payload)
        }
        let payload = call("/agent/gui/window/show", body: req)
        return .undocumented(statusCode: 200, payload)
    }

    public func hideWindow(_ input: Operations.hideWindow.Input) async throws -> Operations.hideWindow.Output {
        let req: Data
        switch input.body {
        case .json(let payload):
            req = try JSONEncoder().encode(payload)
        }
        let payload = call("/agent/gui/window/hide", body: req)
        return .undocumented(statusCode: 200, payload)
    }

    public func resizeWindow(_ input: Operations.resizeWindow.Input) async throws -> Operations.resizeWindow.Output {
        let req: Data
        switch input.body {
        case .json(let payload):
            req = try JSONEncoder().encode(payload)
        }
        let payload = call("/agent/gui/window/resize", body: req)
        return .undocumented(statusCode: 200, payload)
    }

    public func getWindowInfo(_ input: Operations.getWindowInfo.Input) async throws -> Operations.getWindowInfo.Output {
        let req: Data
        switch input.body {
        case .json(let payload):
            req = try JSONEncoder().encode(payload)
        }
        let payload = call("/agent/gui/window/getInfo", body: req)
        return .undocumented(statusCode: 200, payload)
    }

    public func setWindowTitle(_ input: Operations.setWindowTitle.Input) async throws -> Operations.setWindowTitle.Output {
        let req: Data
        switch input.body {
        case .json(let payload):
            req = try JSONEncoder().encode(payload)
        }
        let payload = call("/agent/gui/window/setTitle", body: req)
        return .undocumented(statusCode: 200, payload)
    }

    public func setWindowPosition(_ input: Operations.setWindowPosition.Input) async throws -> Operations.setWindowPosition.Output {
        let req: Data
        switch input.body {
        case .json(let payload):
            req = try JSONEncoder().encode(payload)
        }
        let payload = call("/agent/gui/window/setPosition", body: req)
        return .undocumented(statusCode: 200, payload)
    }

    public func maximizeWindow(_ input: Operations.maximizeWindow.Input) async throws -> Operations.maximizeWindow.Output {
        let req: Data
        switch input.body {
        case .json(let payload):
            req = try JSONEncoder().encode(payload)
        }
        let payload = call("/agent/gui/window/maximize", body: req)
        return .undocumented(statusCode: 200, payload)
    }

    public func minimizeWindow(_ input: Operations.minimizeWindow.Input) async throws -> Operations.minimizeWindow.Output {
        let req: Data
        switch input.body {
        case .json(let payload):
            req = try JSONEncoder().encode(payload)
        }
        let payload = call("/agent/gui/window/minimize", body: req)
        return .undocumented(statusCode: 200, payload)
    }

    public func restoreWindow(_ input: Operations.restoreWindow.Input) async throws -> Operations.restoreWindow.Output {
        let req: Data
        switch input.body {
        case .json(let payload):
            req = try JSONEncoder().encode(payload)
        }
        let payload = call("/agent/gui/window/restore", body: req)
        return .undocumented(statusCode: 200, payload)
    }

    public func centerWindow(_ input: Operations.centerWindow.Input) async throws -> Operations.centerWindow.Output {
        let req: Data
        switch input.body {
        case .json(let payload):
            req = try JSONEncoder().encode(payload)
        }
        let payload = call("/agent/gui/window/center", body: req)
        return .undocumented(statusCode: 200, payload)
    }

    public func setWindowFullscreen(_ input: Operations.setWindowFullscreen.Input) async throws -> Operations.setWindowFullscreen.Output {
        let req: Data
        switch input.body {
        case .json(let payload):
            req = try JSONEncoder().encode(payload)
        }
        let payload = call("/agent/gui/window/setFullscreen", body: req)
        return .undocumented(statusCode: 200, payload)
    }

    public func setWindowOpacity(_ input: Operations.setWindowOpacity.Input) async throws -> Operations.setWindowOpacity.Output {
        let req: Data
        switch input.body {
        case .json(let payload):
            req = try JSONEncoder().encode(payload)
        }
        let payload = call("/agent/gui/window/setOpacity", body: req)
        return .undocumented(statusCode: 200, payload)
    }

    public func setWindowAlwaysOnTop(_ input: Operations.setWindowAlwaysOnTop.Input) async throws -> Operations.setWindowAlwaysOnTop.Output {
        let req: Data
        switch input.body {
        case .json(let payload):
            req = try JSONEncoder().encode(payload)
        }
        let payload = call("/agent/gui/window/setAlwaysOnTop", body: req)
        return .undocumented(statusCode: 200, payload)
    }

    public func clear(_ input: Operations.clear.Input) async throws -> Operations.clear.Output {
        let req: Data
        switch input.body {
        case .json(let payload):
            req = try JSONEncoder().encode(payload)
        }
        let payload = call("/agent/gui/clear", body: req)
        return .undocumented(statusCode: 200, payload)
    }

    public func drawRectangle(_ input: Operations.drawRectangle.Input) async throws -> Operations.drawRectangle.Output {
        let req: Data
        switch input.body {
        case .json(let payload):
            req = try JSONEncoder().encode(payload)
        }
        let payload = call("/agent/gui/drawRectangle", body: req)
        return .undocumented(statusCode: 200, payload)
    }

    public func drawLine(_ input: Operations.drawLine.Input) async throws -> Operations.drawLine.Output {
        let req: Data
        switch input.body {
        case .json(let payload):
            req = try JSONEncoder().encode(payload)
        }
        let payload = call("/agent/gui/drawLine", body: req)
        return .undocumented(statusCode: 200, payload)
    }

    public func drawCircleFilled(_ input: Operations.drawCircleFilled.Input) async throws -> Operations.drawCircleFilled.Output {
        let req: Data
        switch input.body {
        case .json(let payload):
            req = try JSONEncoder().encode(payload)
        }
        let payload = call("/agent/gui/drawCircleFilled", body: req)
        return .undocumented(statusCode: 200, payload)
    }

    public func present(_ input: Operations.present.Input) async throws -> Operations.present.Output {
        let req: Data
        switch input.body {
        case .json(let payload):
            req = try JSONEncoder().encode(payload)
        }
        let payload = call("/agent/gui/present", body: req)
        return .undocumented(statusCode: 200, payload)
    }

    public func drawText(_ input: Operations.drawText.Input) async throws -> Operations.drawText.Output {
        let req: Data
        switch input.body {
        case .json(let payload):
            req = try JSONEncoder().encode(payload)
        }
        let payload = call("/agent/gui/drawText", body: req)
        return .undocumented(statusCode: 200, payload)
    }

    public func captureScreenshot(_ input: Operations.captureScreenshot.Input) async throws -> Operations.captureScreenshot.Output {
        let req: Data
        switch input.body {
        case .json(let payload):
            req = try JSONEncoder().encode(payload)
        }
        let payload = call("/agent/gui/screenshot/capture", body: req)
        return .undocumented(statusCode: 200, payload)
    }

    public func captureEvent(_ input: Operations.captureEvent.Input) async throws -> Operations.captureEvent.Output {
        let req: Data
        switch input.body {
        case .json(let payload):
            req = try JSONEncoder().encode(payload)
        }
        let payload = call("/agent/gui/captureEvent", body: req)
        return .undocumented(statusCode: 200, payload)
    }

    public func clipboardGet(_ input: Operations.clipboardGet.Input) async throws -> Operations.clipboardGet.Output {
        let req = Data("{}".utf8)
        let payload = call("/agent/gui/clipboard/get", body: req)
        return .undocumented(statusCode: 200, payload)
    }

    public func clipboardSet(_ input: Operations.clipboardSet.Input) async throws -> Operations.clipboardSet.Output {
        let req: Data
        switch input.body {
        case .json(let payload):
            req = try JSONEncoder().encode(payload)
        }
        let payload = call("/agent/gui/clipboard/set", body: req)
        return .undocumented(statusCode: 200, payload)
    }

    public func getKeyboardState(_ input: Operations.getKeyboardState.Input) async throws -> Operations.getKeyboardState.Output {
        let req = Data("{}".utf8)
        let payload = call("/agent/gui/input/getKeyboardState", body: req)
        return .undocumented(statusCode: 200, payload)
    }

    public func getMouseState(_ input: Operations.getMouseState.Input) async throws -> Operations.getMouseState.Output {
        let req = Data("{}".utf8)
        let payload = call("/agent/gui/input/getMouseState", body: req)
        return .undocumented(statusCode: 200, payload)
    }

    public func listDisplays(_ input: Operations.listDisplays.Input) async throws -> Operations.listDisplays.Output {
        let req = Data("{}".utf8)
        let payload = call("/agent/gui/display/list", body: req)
        return .undocumented(statusCode: 200, payload)
    }

    public func getDisplayInfo(_ input: Operations.getDisplayInfo.Input) async throws -> Operations.getDisplayInfo.Output {
        let req: Data
        switch input.body {
        case .json(let payload):
            req = try JSONEncoder().encode(payload)
        }
        let payload = call("/agent/gui/display/getInfo", body: req)
        return .undocumented(statusCode: 200, payload)
    }

    public func textureLoad(_ input: Operations.textureLoad.Input) async throws -> Operations.textureLoad.Output {
        let req: Data
        switch input.body {
        case .json(let payload):
            req = try JSONEncoder().encode(payload)
        }
        let payload = call("/agent/gui/texture/load", body: req)
        return .undocumented(statusCode: 200, payload)
    }

    public func textureDraw(_ input: Operations.textureDraw.Input) async throws -> Operations.textureDraw.Output {
        let req: Data
        switch input.body {
        case .json(let payload):
            req = try JSONEncoder().encode(payload)
        }
        let payload = call("/agent/gui/texture/draw", body: req)
        return .undocumented(statusCode: 200, payload)
    }

    public func textureDrawTiled(_ input: Operations.textureDrawTiled.Input) async throws -> Operations.textureDrawTiled.Output {
        let req: Data
        switch input.body {
        case .json(let payload):
            req = try JSONEncoder().encode(payload)
        }
        let payload = call("/agent/gui/texture/drawTiled", body: req)
        return .undocumented(statusCode: 200, payload)
    }

    public func textureDrawRotated(_ input: Operations.textureDrawRotated.Input) async throws -> Operations.textureDrawRotated.Output {
        let req: Data
        switch input.body {
        case .json(let payload):
            req = try JSONEncoder().encode(payload)
        }
        let payload = call("/agent/gui/texture/drawRotated", body: req)
        return .undocumented(statusCode: 200, payload)
    }

    public func textureFree(_ input: Operations.textureFree.Input) async throws -> Operations.textureFree.Output {
        let req: Data
        switch input.body {
        case .json(let payload):
            req = try JSONEncoder().encode(payload)
        }
        let payload = call("/agent/gui/texture/free", body: req)
        return .undocumented(statusCode: 200, payload)
    }

    public func renderGetOutputSize(_ input: Operations.renderGetOutputSize.Input) async throws -> Operations.renderGetOutputSize.Output {
        let req: Data
        switch input.body {
        case .json(let payload):
            req = try JSONEncoder().encode(payload)
        }
        let payload = call("/agent/gui/render/getOutputSize", body: req)
        return .undocumented(statusCode: 200, payload)
    }

    public func renderGetScale(_ input: Operations.renderGetScale.Input) async throws -> Operations.renderGetScale.Output {
        let req: Data
        switch input.body {
        case .json(let payload):
            req = try JSONEncoder().encode(payload)
        }
        let payload = call("/agent/gui/render/getScale", body: req)
        return .undocumented(statusCode: 200, payload)
    }

    public func renderSetScale(_ input: Operations.renderSetScale.Input) async throws -> Operations.renderSetScale.Output {
        let req: Data
        switch input.body {
        case .json(let payload):
            req = try JSONEncoder().encode(payload)
        }
        let payload = call("/agent/gui/render/setScale", body: req)
        return .undocumented(statusCode: 200, payload)
    }

    public func renderGetDrawColor(_ input: Operations.renderGetDrawColor.Input) async throws -> Operations.renderGetDrawColor.Output {
        let req: Data
        switch input.body {
        case .json(let payload):
            req = try JSONEncoder().encode(payload)
        }
        let payload = call("/agent/gui/render/getDrawColor", body: req)
        return .undocumented(statusCode: 200, payload)
    }

    public func renderSetDrawColor(_ input: Operations.renderSetDrawColor.Input) async throws -> Operations.renderSetDrawColor.Output {
        let req: Data
        switch input.body {
        case .json(let payload):
            req = try JSONEncoder().encode(payload)
        }
        let payload = call("/agent/gui/render/setDrawColor", body: req)
        return .undocumented(statusCode: 200, payload)
    }

    public func renderGetViewport(_ input: Operations.renderGetViewport.Input) async throws -> Operations.renderGetViewport.Output {
        let req: Data
        switch input.body {
        case .json(let payload):
            req = try JSONEncoder().encode(payload)
        }
        let payload = call("/agent/gui/render/getViewport", body: req)
        return .undocumented(statusCode: 200, payload)
    }

    public func renderSetViewport(_ input: Operations.renderSetViewport.Input) async throws -> Operations.renderSetViewport.Output {
        let req: Data
        switch input.body {
        case .json(let payload):
            req = try JSONEncoder().encode(payload)
        }
        let payload = call("/agent/gui/render/setViewport", body: req)
        return .undocumented(statusCode: 200, payload)
    }

    public func renderGetClipRect(_ input: Operations.renderGetClipRect.Input) async throws -> Operations.renderGetClipRect.Output {
        let req: Data
        switch input.body {
        case .json(let payload):
            req = try JSONEncoder().encode(payload)
        }
        let payload = call("/agent/gui/render/getClipRect", body: req)
        return .undocumented(statusCode: 200, payload)
    }

    public func renderSetClipRect(_ input: Operations.renderSetClipRect.Input) async throws -> Operations.renderSetClipRect.Output {
        let req: Data
        switch input.body {
        case .json(let payload):
            req = try JSONEncoder().encode(payload)
        }
        let payload = call("/agent/gui/render/setClipRect", body: req)
        return .undocumented(statusCode: 200, payload)
    }

    public func renderDisableClipRect(_ input: Operations.renderDisableClipRect.Input) async throws -> Operations.renderDisableClipRect.Output {
        let req: Data
        switch input.body {
        case .json(let payload):
            req = try JSONEncoder().encode(payload)
        }
        let payload = call("/agent/gui/render/disableClipRect", body: req)
        return .undocumented(statusCode: 200, payload)
    }

    public func drawPoints(_ input: Operations.drawPoints.Input) async throws -> Operations.drawPoints.Output {
        let req: Data
        switch input.body {
        case .json(let payload):
            req = try JSONEncoder().encode(payload)
        }
        let payload = call("/agent/gui/drawPoints", body: req)
        return .undocumented(statusCode: 200, payload)
    }

    public func drawLines(_ input: Operations.drawLines.Input) async throws -> Operations.drawLines.Output {
        let req: Data
        switch input.body {
        case .json(let payload):
            req = try JSONEncoder().encode(payload)
        }
        let payload = call("/agent/gui/drawLines", body: req)
        return .undocumented(statusCode: 200, payload)
    }

    public func drawRects(_ input: Operations.drawRects.Input) async throws -> Operations.drawRects.Output {
        let req: Data
        switch input.body {
        case .json(let payload):
            req = try JSONEncoder().encode(payload)
        }
        let payload = call("/agent/gui/drawRects", body: req)
        return .undocumented(statusCode: 200, payload)
    }

    public func audioDevices(_ input: Operations.audioDevices.Input) async throws -> Operations.audioDevices.Output {
        let req: Data
        switch input.body {
        case .json(let payload):
            req = try JSONEncoder().encode(payload)
        }
        let payload = call("/agent/audio/devices", body: req)
        return .undocumented(statusCode: 200, payload)
    }

    public func audioCaptureOpen(_ input: Operations.audioCaptureOpen.Input) async throws -> Operations.audioCaptureOpen.Output {
        let req: Data
        switch input.body {
        case .some(.json(let payload)):
            req = try JSONEncoder().encode(payload)
        case .none:
            req = Data("{}".utf8)
        }
        let payload = call("/agent/audio/capture/open", body: req)
        return .undocumented(statusCode: 200, payload)
    }

    public func audioCaptureRead(_ input: Operations.audioCaptureRead.Input) async throws -> Operations.audioCaptureRead.Output {
        let req: Data
        switch input.body {
        case .json(let payload):
            req = try JSONEncoder().encode(payload)
        }
        let payload = call("/agent/audio/capture/read", body: req)
        return .undocumented(statusCode: 200, payload)
    }

    public func audioPlaybackOpen(_ input: Operations.audioPlaybackOpen.Input) async throws -> Operations.audioPlaybackOpen.Output {
        let req: Data
        switch input.body {
        case .some(.json(let payload)):
            req = try JSONEncoder().encode(payload)
        case .none:
            req = Data("{}".utf8)
        }
        let payload = call("/agent/audio/playback/open", body: req)
        return .undocumented(statusCode: 200, payload)
    }

    public func audioPlaybackSine(_ input: Operations.audioPlaybackSine.Input) async throws -> Operations.audioPlaybackSine.Output {
        let req: Data
        switch input.body {
        case .json(let payload):
            req = try JSONEncoder().encode(payload)
        }
        let payload = call("/agent/audio/playback/sine", body: req)
        return .undocumented(statusCode: 200, payload)
    }

    public func audioPlaybackQueueOpen(_ input: Operations.audioPlaybackQueueOpen.Input) async throws -> Operations.audioPlaybackQueueOpen.Output {
        let req: Data
        switch input.body {
        case .json(let payload):
            req = try JSONEncoder().encode(payload)
        }
        let payload = call("/agent/audio/playback/queue/open", body: req)
        return .undocumented(statusCode: 200, payload)
    }

    public func audioPlaybackQueueEnqueue(_ input: Operations.audioPlaybackQueueEnqueue.Input) async throws -> Operations.audioPlaybackQueueEnqueue.Output {
        let req: Data
        switch input.body {
        case .json(let payload):
            req = try JSONEncoder().encode(payload)
        }
        let payload = call("/agent/audio/playback/queue/enqueue", body: req)
        return .undocumented(statusCode: 200, payload)
    }

    public func audioPlaybackPlayWAV(_ input: Operations.audioPlaybackPlayWAV.Input) async throws -> Operations.audioPlaybackPlayWAV.Output {
        let req: Data
        switch input.body {
        case .json(let payload):
            req = try JSONEncoder().encode(payload)
        }
        let payload = call("/agent/audio/playback/play_wav", body: req)
        return .undocumented(statusCode: 200, payload)
    }

    public func audioMonitorStart(_ input: Operations.audioMonitorStart.Input) async throws -> Operations.audioMonitorStart.Output {
        let req: Data
        switch input.body {
        case .json(let payload):
            req = try JSONEncoder().encode(payload)
        }
        let payload = call("/agent/audio/monitor/start", body: req)
        return .undocumented(statusCode: 200, payload)
    }

    public func audioMonitorStop(_ input: Operations.audioMonitorStop.Input) async throws -> Operations.audioMonitorStop.Output {
        let req: Data
        switch input.body {
        case .json(let payload):
            req = try JSONEncoder().encode(payload)
        }
        let payload = call("/agent/audio/monitor/stop", body: req)
        return .undocumented(statusCode: 200, payload)
    }

    public func midiStart(_ input: Operations.midiStart.Input) async throws -> Operations.midiStart.Output {
        let req: Data
        switch input.body {
        case .some(.json(let payload)):
            req = try JSONEncoder().encode(payload)
        case .none:
            req = Data("{}".utf8)
        }
        let payload = call("/agent/midi/start", body: req)
        return .undocumented(statusCode: 200, payload)
    }

    public func midiStop(_ input: Operations.midiStop.Input) async throws -> Operations.midiStop.Output {
        let req = Data("{}".utf8)
        let payload = call("/agent/midi/stop", body: req)
        return .undocumented(statusCode: 200, payload)
    }

    public func midiDestinations(_ input: Operations.midiDestinations.Input) async throws -> Operations.midiDestinations.Output {
        let req = Data("{}".utf8)
        let payload = call("/agent/midi/destinations", body: req)
        return .undocumented(statusCode: 200, payload)
    }

    public func midiSelect(_ input: Operations.midiSelect.Input) async throws -> Operations.midiSelect.Output {
        let req: Data
        switch input.body {
        case .json(let payload):
            req = try JSONEncoder().encode(payload)
        }
        let payload = call("/agent/midi/select", body: req)
        return .undocumented(statusCode: 200, payload)
    }

    public func midiSelectByName(_ input: Operations.midiSelectByName.Input) async throws -> Operations.midiSelectByName.Output {
        let req: Data
        switch input.body {
        case .json(let payload):
            req = try JSONEncoder().encode(payload)
        }
        let payload = call("/agent/midi/selectByName", body: req)
        return .undocumented(statusCode: 200, payload)
    }

    public func midiChannel(_ input: Operations.midiChannel.Input) async throws -> Operations.midiChannel.Output {
        let req: Data
        switch input.body {
        case .json(let payload):
            req = try JSONEncoder().encode(payload)
        }
        let payload = call("/agent/midi/channel", body: req)
        return .undocumented(statusCode: 200, payload)
    }

    public func health(_ input: Operations.health.Input) async throws -> Operations.health.Output {
        let req = Data("{}".utf8)
        let payload = call("/health", body: req)
        if let body = payload.body {
            if let data = try? await Data(collecting: body, upTo: .max),
               let obj = try? JSONDecoder().decode([String: Bool].self, from: data),
               obj["ok"] ?? true {
                return .ok(.init(body: .json(.init(ok: true))))
            }
        }
        return .ok(.init(body: .json(.init(ok: true))))
    }

    public func version(_ input: Operations.version.Input) async throws -> Operations.version.Output {
        let req = Data("{}".utf8)
        let payload = call("/version", body: req)
        if let body = payload.body {
            if let data = try? await Data(collecting: body, upTo: .max),
               let obj = try? JSONDecoder().decode([String: String].self, from: data),
               let ver = obj["version"] {
                return .ok(.init(body: .json(.init(version: ver))))
            }
        }
        return .ok(.init(body: .json(.init(version: "unknown"))))
    }

}
#endif