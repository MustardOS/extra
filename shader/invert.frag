// Name: Invert
// Author: MustardOS
// Version: 2

void main() {
    vec4 c = texture2D(u_tex, v_uv);
    float l = dot(c.rgb, vec3(0.299, 0.587, 0.114));

    gl_FragColor = vec4(2.0 * l - c.rgb, c.a);
}
