import Foundation

public enum SDLKitOpenAPI {
    public static let agentVersion = "sdlkit.gui.v1"
    public static let yaml: String = """
openapi: 3.1.0
info:
  title: SDLKit GUI Agent API
  version: 1.0.0
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
}
