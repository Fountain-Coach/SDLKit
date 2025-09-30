#version 450
layout(location = 0) in vec3 aPosition;
layout(location = 1) in vec3 aColor;
layout(location = 0) out vec3 vColor;

layout(push_constant) uniform PushConstants {
    mat4 uMVP;
} pc;

void main() {
    gl_Position = pc.uMVP * vec4(aPosition, 1.0);
    vColor = aColor;
}

