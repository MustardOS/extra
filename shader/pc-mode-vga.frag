// Name: PC Mode - VGA
// Author: MustardOS
// Version: 2

vec2 snap_uv(vec2 uv) {
    vec2 native = max(u_native_resolution, vec2(1.0));
    return (floor(uv * native) + 0.5) / native;
}

void main() {
    const vec3 LUMA = vec3(0.299, 0.587, 0.114);

    vec3 c = texture2D(u_tex, snap_uv(v_uv)).rgb;
    float l = dot(c, LUMA);
    vec3 cube = floor(c * 5.0 + 0.5) / 5.0;
    float v = floor(l * 23.0 + 0.5) / 23.0;

    gl_FragColor = vec4(mix(cube, vec3(v), step(0.85, l)), 1.0);
}
