// Name: PC Mode - EGA
// Author: MustardOS
// Version: 2

const vec3 ega0  = vec3(0.0,    0.0,    0.0   );
const vec3 ega1  = vec3(0.0,    0.0,    0.6667);
const vec3 ega2  = vec3(0.0,    0.6667, 0.0   );
const vec3 ega3  = vec3(0.0,    0.6667, 0.6667);
const vec3 ega4  = vec3(0.6667, 0.0,    0.0   );
const vec3 ega5  = vec3(0.6667, 0.0,    0.6667);
const vec3 ega6  = vec3(0.6667, 0.3333, 0.0   );
const vec3 ega7  = vec3(0.6667, 0.6667, 0.6667);
const vec3 ega8  = vec3(0.3333, 0.3333, 0.3333);
const vec3 ega9  = vec3(0.3333, 0.3333, 1.0   );
const vec3 ega10 = vec3(0.3333, 1.0,    0.3333);
const vec3 ega11 = vec3(0.3333, 1.0,    1.0   );
const vec3 ega12 = vec3(1.0,    0.3333, 0.3333);
const vec3 ega13 = vec3(1.0,    0.3333, 1.0   );
const vec3 ega14 = vec3(1.0,    1.0,    0.3333);
const vec3 ega15 = vec3(1.0,    1.0,    1.0   );

vec2 snap_uv(vec2 uv) {
    vec2 native = max(u_native_resolution, vec2(1.0));
    return (floor(uv * native) + 0.5) / native;
}

vec3 pick(vec3 c) {
    vec3 best = ega0;
    float d = dot(c - ega0, c - ega0);
    float t;

    #define TRY(p) t = dot(c - p, c - p); if (t < d) { d = t; best = p; }
    TRY(ega1)  TRY(ega2)  TRY(ega3)  TRY(ega4)
    TRY(ega5)  TRY(ega6)  TRY(ega7)  TRY(ega8)
    TRY(ega9)  TRY(ega10) TRY(ega11) TRY(ega12)
    TRY(ega13) TRY(ega14) TRY(ega15)
    #undef TRY

    return best;
}

void main() {
    gl_FragColor = vec4(pick(texture2D(u_tex, snap_uv(v_uv)).rgb), 1.0);
}
