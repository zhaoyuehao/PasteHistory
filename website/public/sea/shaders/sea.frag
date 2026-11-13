// Sea.metal: identical band phases, orbit, coastal wash, mip-filtered seabed and two-phase drifting crests.
in vec2 screenUV;
uniform sampler2D painting,shore,ripples;
uniform vec4 geometry, bands[16], sky;
uniform float flowPhase;
const vec2 sourceSize=vec2(3172.,1984.),sourceMask=vec2(1586.,992.);
out vec4 colorOut;
vec3 sceneClimate(vec3 color, vec2 uv, vec2 imageSize, vec4 sky) {
    color = ambientLight(color,sky);
    float haze = sky.w * (.37 + .45 * (1.0-uv.y));
    color = mix(color,mix(vec3(.16,.23,.30),vec3(.70,.76,.77),sky.x),haze);

    // The lantern is anchored to the glass room in the painting, so cropping
    // or moving the wallpaper to a wider display cannot displace the light.
    vec2 lamp = (uv-vec2(.139,.060)) * vec2(1.,imageSize.y/imageSize.x);
    float halo = exp(-length(lamp)*152.);
    float glass = exp(-length(lamp*vec2(1.,1.65))*560.);
    color += (1.-sky.x) * (halo*.23 + glass*.93) * vec3(1.,.74,.34);

    return color;
}

// Fade only displacement toward a texture edge. A wave can still travel
// along that edge without stretching the last row or column of pixels.
vec2 waterSampleUV(vec2 uv, vec2 delta) {
    vec2 room = mix(uv,1.-uv,greaterThan(delta,vec2(0.)));
    return uv + delta * smoothstep(vec2(0.), 2.*abs(delta) + 1e-6, room);
}


float surfaceDetail(vec2 uv,vec2 gx,vec2 gy,float variation){
    float a=textureGrad(ripples,uv,gx,gy).r;
    float b=textureGrad(ripples,.83*uv+vec2(.37,.61),gx*.83,gy*.83).r;
    return (mix(a,b,variation)-128./255.)*.25;
}
float driftingRipple(vec2 uv,vec2 p,vec2 crestDirection,vec2 rippleScale,vec2 gx,vec2 gy){
    float f = fract(flowPhase + .18*sin(dot(p,vec2(.0051,-.0039))));
    vec2 path = 32.*crestDirection*vec2(1,-1)/geometry.zw;
    vec2 bend = vec2(sin(dot(p,vec2(.0031,.0049))),sin(dot(p,vec2(.0053,-.0027))));
    vec2 surface = uv + 12.*bend/geometry.zw;
    float variation = .50 + .35*sin(dot(p,vec2(.0037,.0021)) + bend.x);
    float a = surfaceDetail((surface-(f-.5)*path)*rippleScale,gx,gy,variation);
    float b = surfaceDetail((surface-(fract(f+.5)-.5)*path)*rippleScale,gx,gy,variation);
    float weight = smoothstep(.23,.77,1.-abs(2.*f-1.));
    return mix(b,a,weight) * inversesqrt(weight*weight+(1.-weight)*(1.-weight));
}

void main(){
    vec2 uv = 0.5 + (screenUV - 0.5) * geometry.xy / geometry.zw;
    // The coastline distance and the wash are measured in mask pixels.
    vec2 texel = 1.0 / sourceMask;
    vec2 p = vec2(screenUV.x, 1. - screenUV.y) * geometry.xy;
    // Keep the texture footprint continuous across water/land branches. Using
    // implicit derivatives there can select a distant mip on shoreline pixels.
    vec2 gx=dFdx(uv),gy=dFdy(uv);
    vec2 rippleScale = sourceSize /
                         vec2(textureSize(ripples,0));

    float d = textureLod(shore, uv,0.).r * 255. - 128.; // source pixels, positive in water
    float sand = smoothstep(0.67,0.70,uv.x) * (1.-smoothstep(0.91,0.935,uv.x)) * smoothstep(0.68,0.73,uv.y);
    float water = mix(smoothstep(0.,10.,d),smoothstep(-21.,14.,d),sand);
    if (water < 0.001) { colorOut=vec4(sceneClimate(textureGrad(painting,uv,gx,gy).rgb,
                                                uv,geometry.zw,sky),1);return;}

    vec2 slope = vec2(0), orbit = vec2(0);
    vec2 crestDirection = bands[0].xy;
    float swell = 0.;
    for (int i=0; i<8; ++i) {
        vec4 b = bands[2*i], phase = bands[2*i+1];
        float along = dot(p,b.xy) * b.z;
        float side = dot(p,vec2(-b.y,b.x)) * b.z;
        float group = 0.66 + 0.34 * sin(along*0.19 + side*0.16 + phase.z);
        float bend = side*0.43 + phase.y;
        float chop = side*0.81 + along*0.09 + phase.w;
        float theta = along + phase.x + 0.92*sin(bend) + 0.38*sin(chop);
        if (i == 0) {
            // Gradient of this same swell phase points across its crest in the
            // propagation direction (its time phase decreases). Follow the
            // main swell, allowing its crests to bend across the cove.
            vec2 across = vec2(-b.y,b.x);
            crestDirection = normalize(b.xy*(1. + .38*.09*cos(chop))
                                      + across*(.92*.43*cos(bend) + .38*.81*cos(chop)));
        }
        float amplitude = b.w * group;
        orbit += b.xy * (amplitude * cos(theta));
        slope += b.xy * (amplitude * b.z * cos(theta));
        if (i < 3) swell += amplitude * sin(theta);
    }

    float shallow = 1. - smoothstep(12.,108.,d);
    // Move the painted seabed beneath the refracting surface. The original
    // waterline travels with the wash and dry sand and rock keep their detail.
    vec2 refract = (-0.80 * orbit - (5.2 + 6.0 * shallow) * slope) * vec2(1,-1);
    vec2 offset = water * refract / geometry.zw;
    if (sand > 0. && d < 65.) {
        vec2 grad = vec2(textureLod(shore,uv + vec2(texel.x*6.,0),0.).r -
                             textureLod(shore,uv - vec2(texel.x*6.,0),0.).r,
                             textureLod(shore,uv + vec2(0,texel.y*6.),0.).r -
                             textureLod(shore,uv - vec2(0,texel.y*6.),0.).r);
        vec2 normal = grad / max(length(grad), 0.002);
        float wash = (1.7 * swell + 1.5) * (1. - smoothstep(4.,58.,abs(d)));
        offset += texel * normal * wash * water * sand;
    }
    vec2 at = waterSampleUV(uv,offset);
    vec3 pigment = textureGrad(painting,at,gx,gy).rgb;
    // Keep photographed breakers at the waterline. Offshore, the photograph
    // supplies the water colour and visible seabed, never the moving crests.
    float offshore = smoothstep(2.,30.,d);
    // Keep the low-frequency water colour from sampling across the coastline.
    float sourceDistance = max(1.,d * sourceSize.x / sourceMask.x);
    vec3 local = textureLod(painting,at,min(6.,log2(sourceDistance))).rgb;
    float bottomVisible = smoothstep(-.008,.085,local.g-local.b);
    vec3 deep = local - max(0.,local.r-.065*local.g)*vec3(1.,.69,.61);
    vec3 bed = mix(deep,pigment,bottomVisible);

    // One seamless, zero-mean open-water detail map for the whole bay.
    // Both phases follow the local crest direction, including at image edges.
    float ripple = driftingRipple(uv + .20*offset,p,crestDirection,rippleScale,gx*rippleScale,gy*rippleScale);
    vec3 tint = mix(vec3(.46,1.,1.04),vec3(.42,.64,.60),bottomVisible);
    pigment = mix(pigment,bed + ripple*tint,offshore);

    float sun = smoothstep(.06,.90,sky.x) * (1. - .88*sky.z);
    float illumination = dot(slope,vec2(-.48,.88));
    vec3 normal = normalize(vec3(-slope,1.0));
    float ndh = sat(dot(normal,normalize(vec3(-.14,.29,1.0))));
    float grain = dot(pigment,vec3(.23,.65,.12));
    float specular = pow(ndh,350.) * (.27 + .73*smoothstep(.16,.55,grain));
    vec3 color = pigment * (1. + water*illumination*mix(.18,.31,sun));
    color += water * specular * sun * vec3(.21,.205,.145);
    colorOut=vec4(sceneClimate(color,uv,geometry.zw,sky),1);
}
