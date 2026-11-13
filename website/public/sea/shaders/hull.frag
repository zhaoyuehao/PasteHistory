in vec3 normal,pigment,modelPosition;
in float windowGlow;
uniform vec4 climate;
uniform vec3 lamp;
out vec4 colorOut;
void main(){
    vec3 view = vec3(0,-0.61,0.79);
    vec3 n = normalize(normal);
    if (dot(n,view) < 0.) n = -n;
    vec3 sun = normalize(vec3(-0.68,0.55,0.76));
    float diffuse = sat(dot(n,sun));
    float sky = 0.43 + 0.16 * sat(n.z);
    // Thin sunlit sailcloth transmits more skylight than painted hulls.
    sky += smoothstep(19.,32.,modelPosition.z) * 0.18;
    vec3 reflectedSea = vec3(0.01,0.047,0.055) * (1. - sat(n.z));
    float spec = pow(sat(dot(n,normalize(sun+view))),38.);
    float contact = mix(0.77,1.,smoothstep(0.,6.,modelPosition.z));
    float direct = climate.x*(1.-.90*climate.z);
    vec3 paint = contact * (pigment * (sky + mix(.17+.16*diffuse,.51*diffuse,direct)) + reflectedSea) + .10*spec*direct;
    vec3 toLamp = lamp.xyz - modelPosition;
    float warm = .64 / (1. + dot(toLamp,toLamp)/82.);
    vec3 illumination = warm*vec3(1.,.74,.42);
    float night = 1.-smoothstep(.12,.90,climate.x);
    colorOut=vec4(ambientLight(paint,climate) + night * (pigment * illumination + windowGlow*vec3(.96,.71,.40)),1);
}
