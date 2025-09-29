import Foundation

public enum SDLKitOpenAPI {
    public static let agentVersion = "sdlkit.gui.v1"
    public static let specVersion = "1.1.0"
    public static let yaml: String = """
openapi: 3.1.0
info:
  title: SDLKit GUI Agent API
  version: 1.1.0
  description: |
    OpenAPI for SDLKit GUI tools. Agent version: sdlkit.gui.v1
servers:
  - url: http://localhost:8080
paths:
  /agent/gui/window/open:
    post:
      operationId: openWindow
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/OpenWindowRequest'
      responses:
        '200':
          description: OK
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/OpenWindowResponse'
        '400': { $ref: '#/components/responses/Error' }

  /agent/gui/window/close:
    post:
      operationId: closeWindow
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/WindowOnlyRequest'
      responses:
        '200': { $ref: '#/components/responses/Ok' }
        '400': { $ref: '#/components/responses/Error' }

  /agent/gui/present:
    post:
      operationId: present
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/WindowOnlyRequest'
      responses:
        '200': { $ref: '#/components/responses/Ok' }
        '400': { $ref: '#/components/responses/Error' }

  /agent/gui/drawRectangle:
    post:
      operationId: drawRectangle
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/RectRequest'
      responses:
        '200': { $ref: '#/components/responses/Ok' }
        '400': { $ref: '#/components/responses/Error' }

  /agent/gui/clear:
    post:
      operationId: clear
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/ColorRequest'
      responses:
        '200': { $ref: '#/components/responses/Ok' }
        '400': { $ref: '#/components/responses/Error' }

  /agent/gui/drawLine:
    post:
      operationId: drawLine
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/LineRequest'
      responses:
        '200': { $ref: '#/components/responses/Ok' }
        '400': { $ref: '#/components/responses/Error' }

  /agent/gui/drawCircleFilled:
    post:
      operationId: drawCircleFilled
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/CircleRequest'
      responses:
        '200': { $ref: '#/components/responses/Ok' }
        '400': { $ref: '#/components/responses/Error' }

  /agent/gui/drawText:
    post:
      operationId: drawText
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/TextRequest'
      responses:
        '200': { $ref: '#/components/responses/Ok' }
        '400': { $ref: '#/components/responses/Error' }

  /agent/gui/screenshot/capture:
    post:
      summary: Capture window screenshot
      description: Captures the current window contents and returns either raw ABGR pixels or a Base64 PNG depending on the requested format.
      operationId: screenshotCapture
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/ScreenshotCaptureRequest'
      responses:
        '200':
          description: OK
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/ScreenshotCaptureResponse'
        '400': { $ref: '#/components/responses/Error' }

  /agent/gui/captureEvent:
    post:
      operationId: captureEvent
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/CaptureEventRequest'
      responses:
        '200':
          description: OK
          content:
            application/json:
              schema:
                type: object
                properties:
                  event:
                    $ref: '#/components/schemas/Event'
        '400': { $ref: '#/components/responses/Error' }

components:
  responses:
    Ok:
      description: OK
      content:
        application/json:
          schema:
            $ref: '#/components/schemas/OkResponse'
    Error:
      description: Error
      content:
        application/json:
          schema:
            $ref: '#/components/schemas/ErrorResponse'

  schemas:
    OkResponse:
      type: object
      properties:
        ok: { type: boolean }
      required: [ok]

    ErrorResponse:
      type: object
      properties:
        error:
          type: object
          properties:
            code: { type: string }
            details: { type: string, nullable: true }
          required: [code]
      required: [error]

    WindowOnlyRequest:
      type: object
      properties:
        window_id: { type: integer, minimum: 1 }
      required: [window_id]

    OpenWindowRequest:
      type: object
      properties:
        title: { type: string }
        width: { type: integer, minimum: 1 }
        height: { type: integer, minimum: 1 }
      required: [title, width, height]

    OpenWindowResponse:
      type: object
      properties:
        window_id: { type: integer, minimum: 1 }
      required: [window_id]

    Color:
      oneOf:
        - type: string
          description: CSS color name or hex (#RRGGBB or #AARRGGBB)
        - type: integer
          description: ARGB as 0xAARRGGBB

    ColorRequest:
      type: object
      properties:
        window_id: { type: integer, minimum: 1 }
        color: { $ref: '#/components/schemas/Color' }
      required: [window_id, color]

    RectRequest:
      type: object
      properties:
        window_id: { type: integer, minimum: 1 }
        x: { type: integer }
        y: { type: integer }
        width: { type: integer, minimum: 1 }
        height: { type: integer, minimum: 1 }
        color: { $ref: '#/components/schemas/Color' }
      required: [window_id, x, y, width, height, color]

    LineRequest:
      type: object
      properties:
        window_id: { type: integer, minimum: 1 }
        x1: { type: integer }
        y1: { type: integer }
        x2: { type: integer }
        y2: { type: integer }
        color: { $ref: '#/components/schemas/Color' }
      required: [window_id, x1, y1, x2, y2, color]

    CircleRequest:
      type: object
      properties:
        window_id: { type: integer, minimum: 1 }
        cx: { type: integer }
        cy: { type: integer }
        radius: { type: integer, minimum: 0 }
        color: { $ref: '#/components/schemas/Color' }
      required: [window_id, cx, cy, radius, color]

    TextRequest:
      type: object
      properties:
        window_id: { type: integer, minimum: 1 }
        text: { type: string }
        x: { type: integer }
        y: { type: integer }
        font: { type: string, nullable: true, description: "file path, system:default, or name:<id>" }
        size: { type: integer, minimum: 1, nullable: true }
        color:
          type: integer
          description: ARGB as 0xAARRGGBB (optional; default white)
          nullable: true
      required: [window_id, text, x, y]

    ScreenshotCaptureRequest:
      type: object
      properties:
        window_id: { type: integer, minimum: 1 }
        format:
          type: string
          enum: [raw, png]
          default: raw
      required: [window_id]

    RawScreenshot:
      type: object
      properties:
        raw_base64: { type: string, description: ABGR8888 pixel data, row-major }
        width: { type: integer }
        height: { type: integer }
        pitch: { type: integer }
        format: { type: string, enum: [ABGR8888] }
      required: [raw_base64, width, height, pitch, format]

    PNGScreenshot:
      type: object
      properties:
        png_base64: { type: string, description: PNG image bytes encoded in Base64 }
        width: { type: integer }
        height: { type: integer }
        format: { type: string, enum: [PNG] }
      required: [png_base64, width, height, format]

    ScreenshotCaptureResponse:
      oneOf:
        - $ref: '#/components/schemas/RawScreenshot'
        - $ref: '#/components/schemas/PNGScreenshot'

    CaptureEventRequest:
      type: object
      properties:
        window_id: { type: integer, minimum: 1 }
        timeout_ms: { type: integer, minimum: 0, nullable: true }
      required: [window_id]

    Event:
      type: object
      properties:
        type:
          type: string
          enum: [key_down, key_up, mouse_down, mouse_up, mouse_move, quit, window_closed]
        x: { type: integer, nullable: true }
        y: { type: integer, nullable: true }
        key: { type: string, nullable: true }
        button: { type: integer, nullable: true }
      required: [type]
"""

    // JSON representation of the same spec
    public static let json: Data = {
        let spec: [String: Any] = [
            "openapi": "3.1.0",
            "info": [
                "title": "SDLKit GUI Agent API",
                "version": specVersion,
                "description": "OpenAPI for SDLKit GUI tools. Agent version: \(agentVersion)"
            ],
            "servers": [["url": "http://localhost:8080"]],
            "paths": pathsJSON(),
            "components": componentsJSON()
        ]
        return (try? JSONSerialization.data(withJSONObject: spec, options: [.prettyPrinted, .sortedKeys])) ?? Data("{}".utf8)
    }()

    private static func okResponseRef() -> [String: Any] { ["$ref": "#/components/responses/Ok"] }
    private static func errResponseRef() -> [String: Any] { ["$ref": "#/components/responses/Error"] }

    private static func reqRef(_ name: String) -> [String: Any] { ["$ref": "#/components/schemas/\(name)"] }

    private static func jsonRequest(_ schemaRef: [String: Any]) -> [String: Any] {
        [
            "required": true,
            "content": [
                "application/json": [
                    "schema": schemaRef
                ]
            ]
        ]
    }

    private static func okErrResponses() -> [String: Any] {
        [
            "200": okResponseRef(),
            "400": errResponseRef()
        ]
    }

    private static func pathsJSON() -> [String: Any] {
        return [
            "/agent/gui/window/open": [
                "post": [
                    "operationId": "openWindow",
                    "requestBody": jsonRequest(reqRef("OpenWindowRequest")),
                    "responses": [
                        "200": [
                            "description": "OK",
                            "content": [
                                "application/json": [
                                    "schema": reqRef("OpenWindowResponse")
                                ]
                            ]
                        ],
                        "400": errResponseRef()
                    ]
                ]
            ],
            "/agent/gui/window/close": [
                "post": [
                    "operationId": "closeWindow",
                    "requestBody": jsonRequest(reqRef("WindowOnlyRequest")),
                    "responses": okErrResponses()
                ]
            ],
            "/agent/gui/present": [
                "post": [
                    "operationId": "present",
                    "requestBody": jsonRequest(reqRef("WindowOnlyRequest")),
                    "responses": okErrResponses()
                ]
            ],
            "/agent/gui/drawRectangle": [
                "post": [
                    "operationId": "drawRectangle",
                    "requestBody": jsonRequest(reqRef("RectRequest")),
                    "responses": okErrResponses()
                ]
            ],
            "/agent/gui/clear": [
                "post": [
                    "operationId": "clear",
                    "requestBody": jsonRequest(reqRef("ColorRequest")),
                    "responses": okErrResponses()
                ]
            ],
            "/agent/gui/drawLine": [
                "post": [
                    "operationId": "drawLine",
                    "requestBody": jsonRequest(reqRef("LineRequest")),
                    "responses": okErrResponses()
                ]
            ],
            "/agent/gui/drawCircleFilled": [
                "post": [
                    "operationId": "drawCircleFilled",
                    "requestBody": jsonRequest(reqRef("CircleRequest")),
                    "responses": okErrResponses()
                ]
            ],
            "/agent/gui/drawText": [
                "post": [
                    "operationId": "drawText",
                    "requestBody": jsonRequest(reqRef("TextRequest")),
                    "responses": okErrResponses()
                ]
            ],
            "/agent/gui/screenshot/capture": [
                "post": [
                    "summary": "Capture window screenshot",
                    "description": "Captures the current window contents and returns either raw ABGR pixels or a Base64 PNG depending on the requested format.",
                    "operationId": "screenshotCapture",
                    "requestBody": jsonRequest(reqRef("ScreenshotCaptureRequest")),
                    "responses": [
                        "200": [
                            "description": "OK",
                            "content": [
                                "application/json": [
                                    "schema": reqRef("ScreenshotCaptureResponse")
                                ]
                            ]
                        ],
                        "400": errResponseRef()
                    ]
                ]
            ],
            "/agent/gui/captureEvent": [
                "post": [
                    "operationId": "captureEvent",
                    "requestBody": jsonRequest(reqRef("CaptureEventRequest")),
                    "responses": [
                        "200": [
                            "description": "OK",
                            "content": [
                                "application/json": [
                                    "schema": [
                                        "type": "object",
                                        "properties": ["event": reqRef("Event")]
                                    ]
                                ]
                            ]
                        ],
                        "400": errResponseRef()
                    ]
                ]
            ]
        ]
    }

    private static func componentsJSON() -> [String: Any] {
        let responses: [String: Any] = [
            "Ok": [
                "description": "OK",
                "content": [
                    "application/json": [
                        "schema": reqRef("OkResponse")
                    ]
                ]
            ],
            "Error": [
                "description": "Error",
                "content": [
                    "application/json": [
                        "schema": reqRef("ErrorResponse")
                    ]
                ]
            ]
        ]
        let colorSchema: [String: Any] = [
            "oneOf": [
                ["type": "string", "description": "CSS color name or hex (#RRGGBB or #AARRGGBB)"],
                ["type": "integer", "description": "ARGB as 0xAARRGGBB"]
            ]
        ]
        let schemas: [String: Any] = [
            "OkResponse": [
                "type": "object",
                "properties": ["ok": ["type": "boolean"]],
                "required": ["ok"]
            ],
            "ErrorResponse": [
                "type": "object",
                "properties": [
                    "error": [
                        "type": "object",
                        "properties": [
                            "code": ["type": "string"],
                            "details": ["type": "string", "nullable": true]
                        ],
                        "required": ["code"]
                    ]
                ],
                "required": ["error"]
            ],
            "WindowOnlyRequest": [
                "type": "object",
                "properties": ["window_id": ["type": "integer", "minimum": 1]],
                "required": ["window_id"]
            ],
            "OpenWindowRequest": [
                "type": "object",
                "properties": [
                    "title": ["type": "string"],
                    "width": ["type": "integer", "minimum": 1],
                    "height": ["type": "integer", "minimum": 1]
                ],
                "required": ["title", "width", "height"]
            ],
            "OpenWindowResponse": [
                "type": "object",
                "properties": ["window_id": ["type": "integer", "minimum": 1]],
                "required": ["window_id"]
            ],
            "Color": colorSchema,
            "ColorRequest": [
                "type": "object",
                "properties": [
                    "window_id": ["type": "integer", "minimum": 1],
                    "color": reqRef("Color")
                ],
                "required": ["window_id", "color"]
            ],
            "RectRequest": [
                "type": "object",
                "properties": [
                    "window_id": ["type": "integer", "minimum": 1],
                    "x": ["type": "integer"],
                    "y": ["type": "integer"],
                    "width": ["type": "integer", "minimum": 1],
                    "height": ["type": "integer", "minimum": 1],
                    "color": reqRef("Color")
                ],
                "required": ["window_id", "x", "y", "width", "height", "color"]
            ],
            "LineRequest": [
                "type": "object",
                "properties": [
                    "window_id": ["type": "integer", "minimum": 1],
                    "x1": ["type": "integer"],
                    "y1": ["type": "integer"],
                    "x2": ["type": "integer"],
                    "y2": ["type": "integer"],
                    "color": reqRef("Color")
                ],
                "required": ["window_id", "x1", "y1", "x2", "y2", "color"]
            ],
            "CircleRequest": [
                "type": "object",
                "properties": [
                    "window_id": ["type": "integer", "minimum": 1],
                    "cx": ["type": "integer"],
                    "cy": ["type": "integer"],
                    "radius": ["type": "integer", "minimum": 0],
                    "color": reqRef("Color")
                ],
                "required": ["window_id", "cx", "cy", "radius", "color"]
            ],
            "TextRequest": [
                "type": "object",
                "properties": [
                    "window_id": ["type": "integer", "minimum": 1],
                    "text": ["type": "string"],
                    "x": ["type": "integer"],
                    "y": ["type": "integer"],
                    "font": ["type": "string", "nullable": true, "description": "file path, system:default, or name:<id>"],
                    "size": ["type": "integer", "minimum": 1, "nullable": true],
                    "color": ["type": "integer", "nullable": true, "description": "ARGB as 0xAARRGGBB (optional; default white)"]
                ],
                "required": ["window_id", "text", "x", "y"]
            ],
            "ScreenshotCaptureRequest": [
                "type": "object",
                "properties": [
                    "window_id": ["type": "integer", "minimum": 1],
                    "format": [
                        "type": "string",
                        "enum": ["raw", "png"],
                        "default": "raw"
                    ]
                ],
                "required": ["window_id"]
            ],
            "RawScreenshot": [
                "type": "object",
                "properties": [
                    "raw_base64": ["type": "string", "description": "ABGR8888 pixel data, row-major"],
                    "width": ["type": "integer"],
                    "height": ["type": "integer"],
                    "pitch": ["type": "integer"],
                    "format": ["type": "string", "enum": ["ABGR8888"]]
                ],
                "required": ["raw_base64", "width", "height", "pitch", "format"]
            ],
            "PNGScreenshot": [
                "type": "object",
                "properties": [
                    "png_base64": ["type": "string", "description": "PNG image bytes encoded in Base64"],
                    "width": ["type": "integer"],
                    "height": ["type": "integer"],
                    "format": ["type": "string", "enum": ["PNG"]]
                ],
                "required": ["png_base64", "width", "height", "format"]
            ],
            "ScreenshotCaptureResponse": [
                "oneOf": [
                    reqRef("RawScreenshot"),
                    reqRef("PNGScreenshot")
                ]
            ],
            "CaptureEventRequest": [
                "type": "object",
                "properties": [
                    "window_id": ["type": "integer", "minimum": 1],
                    "timeout_ms": ["type": "integer", "minimum": 0, "nullable": true]
                ],
                "required": ["window_id"]
            ],
            "Event": [
                "type": "object",
                "properties": [
                    "type": ["type": "string", "enum": ["key_down", "key_up", "mouse_down", "mouse_up", "mouse_move", "quit", "window_closed"]],
                    "x": ["type": "integer", "nullable": true],
                    "y": ["type": "integer", "nullable": true],
                    "key": ["type": "string", "nullable": true],
                    "button": ["type": "integer", "nullable": true]
                ],
                "required": ["type"]
            ]
        ]
        return ["responses": responses, "schemas": schemas]
    }
}
