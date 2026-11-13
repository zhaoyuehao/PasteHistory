float sat(float x){return clamp(x,0.,1.);}
vec3 ambientLight(vec3 pigment, vec4 sky) {
    float luma = dot(pigment, vec3(.2126,.7152,.0722));
    vec3 overcast = mix(pigment, vec3(luma), .43) * vec3(.78,.82,.88);
    vec3 day = mix(pigment, overcast, sky.z);
    vec3 night = mix(pigment, vec3(luma), .55) * vec3(.24,.40,.60) + vec3(.012,.024,.044);
    vec3 result = mix(night, day, sky.x);
    result += sky.y * (1.0 - .72 * sky.z) * (.12 + luma) * vec3(.30,.102,.012);
    return result;
}
