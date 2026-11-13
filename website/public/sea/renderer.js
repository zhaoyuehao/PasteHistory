import { parameters, updateBands } from "./waves.js";
const resource = (path) => new URL(path, import.meta.url);
const fullVertex = `out vec2 screenUV;
void main(){
 vec2 p=vec2((gl_VertexID<<1)&2,gl_VertexID&2);
 screenUV=p;gl_Position=vec4(p*vec2(2,-2)+vec2(-1,1),0,1);
}`;
const meshVertex = `
layout(location=0) in vec3 pos;
layout(location=1) in vec3 norm;
layout(location=2) in vec3 paint;
layout(location=3) in float glow;
uniform vec4 pose; uniform vec2 viewport; uniform float modelScale;
uniform int shadow;
out vec3 normal,pigment,modelPosition;out float windowGlow;
vec2 turn(vec2 v,float a){return vec2(v.x*cos(a)-v.y*sin(a),v.x*sin(a)+v.y*cos(a));}
void main(){
 vec3 p=pos,n=norm;p.yz=turn(p.yz,pose.w);n.yz=turn(n.yz,pose.w);
 p.xy=turn(p.xy,pose.z);n.xy=turn(n.xy,pose.z);
 vec2 projected=vec2(p.x,.79*p.y+.61*p.z);
 if(shadow!=0)projected=(p.xy-max(0.,p.z)*vec2(-.68,.55)/.76)*vec2(1,.79);
 float depth=shadow!=0?.84:clamp(.63-.0026*p.z,.02,.76);
 gl_Position=vec4((pose.xy+projected*modelScale)/viewport*2.-1.,depth*2.-1.,1.);
 normal=n;pigment=paint;modelPosition=pos;windowGlow=glow;
}`;
const wakeVertex = `
uniform vec4 pose;uniform vec2 viewport;uniform float modelScale;
out vec2 local;
void main(){
 local=(vec2(gl_VertexID&1,gl_VertexID>>1)*2.-1.)*vec2(70,23)-vec2(19,0);
 float c=cos(pose.z),s=sin(pose.z);
 vec2 rotated=vec2(c*local.x-s*local.y,s*local.x+c*local.y);
 gl_Position=vec4((pose.xy+rotated*vec2(1,.79)*modelScale)/viewport*2.-1.,.88,1.);
}`;
const wakeFragment = `
in vec2 local;uniform float speed,time;uniform vec4 climate;uniform sampler2D ripples;out vec4 colorOut;
void main(){
 float grain=(texture(ripples,gl_FragCoord.xy/640.+time*vec2(.013,-.009)).r-.5)*.25;
 float contact=.43*(1.-smoothstep(.58,1.,length((local-vec2(1,-1))/vec2(49,16))));
 float run=-local.x-26., throttle=clamp(speed/18.,0.,1.);
 float fade=smoothstep(0.,8.,run)*(1.-smoothstep(7.,15.+43.*throttle,run));
 float edge=abs(local.y)-(8.+.14*run+24.*grain);
 float foam=fade*exp(-edge*edge/5.)*smoothstep(-.032,.032,grain)*(.09+.40*throttle)*smoothstep(0.,3.,speed);
 float alpha=contact*(1.-foam)+foam;
 colorOut=vec4((vec3(.024,.086,.10)*contact*(1.-foam)+ambientLight(vec3(.74,.85,.81),climate)*foam)/max(.0001,alpha),alpha);
}`;
const lamps = {
  sloop: [5, 0, 51.5],
  freighter: [-20.6, 0, 17.4],
  cruiser: [-1, 0, 19.4],
  launch: [16, 0, 12.6],
};
const lanternVertex = `
uniform vec2 viewport;uniform vec4 pose;uniform vec3 lamp;uniform float modelScale;
out vec2 local;flat out int reflected;
void main(){
 local=vec2(gl_VertexID&1,gl_VertexID>>1)*2.-1.;reflected=gl_InstanceID;
 vec3 p=lamp;p.yz=mat2(cos(pose.w),sin(pose.w),-sin(pose.w),cos(pose.w))*p.yz;
 p.xy=mat2(cos(pose.z),sin(pose.z),-sin(pose.z),cos(pose.z))*p.xy;
 vec2 offset=vec2(p.x,.79*p.y+.61*p.z)+local*13.5;
 if(reflected!=0)offset=vec2(p.x,.79*p.y-.61*p.z)+local*vec2(9,16);
 float depth=reflected!=0?.78:.628-.0026*p.z;
 gl_Position=vec4((pose.xy+offset*modelScale)/viewport*2.-1.,depth*2.-1.,1.);
}`;
const lanternFragment = `
in vec2 local;flat in int reflected;uniform vec4 climate;uniform sampler2D ripples;uniform float time;out vec4 colorOut;
void main(){
 float r2=dot(local,local);vec3 tint=vec3(1.,.73,.37);
 float night=1.-smoothstep(.12,.90,climate.x);
 vec3 light=1.20*exp(-r2*35.)*mix(tint,vec3(1),.4)+exp(-r2*5.)*(1.-smoothstep(.65,1.,r2))*.47*tint;
 if(reflected!=0){float g=(texture(ripples,gl_FragCoord.xy/640.+time*vec2(.013,-.009)).r-.5)*.25;
 light=.39*exp(-3.8*r2)*(.09+.91*smoothstep(-.006,.028,g))*tint;}
 colorOut=vec4(light*night,0.);
}`;
async function get(path, format) {
  const r = await fetch(resource(path));
  if (!r.ok) throw Error(path + ": " + r.status);
  return r[format]();
}
export async function createRenderer(gl, images) {
  const [climate, sea, hull, binary] = await Promise.all([
    get("shaders/climate.glsl", "text"),
    get("shaders/sea.frag", "text"),
    get("shaders/hull.frag", "text"),
    get("assets/boats.bin", "arrayBuffer"),
  ]);
  function program(vs, fs) {
    const p = gl.createProgram(),
      prefix = "#version 300 es\nprecision highp float;\n";
    for (const [type, src] of [
      [gl.VERTEX_SHADER, vs],
      [gl.FRAGMENT_SHADER, fs],
    ]) {
      const s = gl.createShader(type);
      gl.shaderSource(s, prefix + src);
      gl.compileShader(s);
      if (!gl.getShaderParameter(s, gl.COMPILE_STATUS))
        throw Error(gl.getShaderInfoLog(s));
      gl.attachShader(p, s);
      gl.deleteShader(s);
    }
    gl.linkProgram(p);
    if (!gl.getProgramParameter(p, gl.LINK_STATUS))
      throw Error(gl.getProgramInfoLog(p));
    const u = {};
    for (let i = 0; i < gl.getProgramParameter(p, gl.ACTIVE_UNIFORMS); i++) {
      const name = gl.getActiveUniform(p, i).name;
      u[name.replace("[0]", "")] = gl.getUniformLocation(p, name);
    }
    return { p, u };
  }
  const surface = program(fullVertex, climate + sea),
    model = program(meshVertex, climate + hull),
    shadow = program(
      meshVertex,
      "uniform vec4 climate;out vec4 colorOut;void main(){colorOut=vec4(.014,.080,.10,.27*climate.x*(1.-climate.z)*(1.-.85*climate.z));}",
    ),
    wake = program(wakeVertex, climate + wakeFragment),
    lantern = program(lanternVertex, lanternFragment);
  const textures = images.map((image, i) => {
    const tex = gl.createTexture();
    gl.activeTexture(gl.TEXTURE0 + i);
    gl.bindTexture(gl.TEXTURE_2D, tex);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGB, gl.RGB, gl.UNSIGNED_BYTE, image);
    for (const k of [gl.TEXTURE_WRAP_S, gl.TEXTURE_WRAP_T])
      gl.texParameteri(
        gl.TEXTURE_2D,
        k,
        i === 2 ? gl.REPEAT : gl.CLAMP_TO_EDGE,
      );
    gl.texParameteri(
      gl.TEXTURE_2D,
      gl.TEXTURE_MIN_FILTER,
      gl.LINEAR_MIPMAP_LINEAR,
    );
    gl.generateMipmap(gl.TEXTURE_2D);
    return tex;
  });
  const meshes = {},
    view = new DataView(binary);
  let offset = 0;
  for (const key of Object.keys(lamps))
    for (let variant = 0; variant < 4; variant++) {
      const vertices = view.getUint32(offset, true),
        count = view.getUint32(offset + 4, true);
      offset += 8;
      const vao = gl.createVertexArray();
      gl.bindVertexArray(vao);
      gl.bindBuffer(gl.ARRAY_BUFFER, gl.createBuffer());
      gl.bufferData(
        gl.ARRAY_BUFFER,
        new Float32Array(binary, offset, vertices * 10),
        gl.STATIC_DRAW,
      );
      offset += vertices * 40;
      for (let i = 0; i < 4; i++) {
        gl.enableVertexAttribArray(i);
        gl.vertexAttribPointer(i, i === 3 ? 1 : 3, gl.FLOAT, false, 40, i * 12);
      }
      gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, gl.createBuffer());
      gl.bufferData(
        gl.ELEMENT_ARRAY_BUFFER,
        new Uint16Array(binary, offset, count),
        gl.STATIC_DRAW,
      );
      offset = (offset + count * 2 + 3) & ~3;
      meshes[key + variant] = { vao, count };
    }
  gl.bindVertexArray(null);
  return (geometry, t, strength, sky, boats) => {
    gl.viewport(0, 0, gl.canvas.width, gl.canvas.height);
    gl.depthMask(true);
    gl.clear(gl.DEPTH_BUFFER_BIT);
    gl.disable(gl.DEPTH_TEST);
    gl.disable(gl.BLEND);
    gl.useProgram(surface.p);
    textures.forEach((tex, i) => {
      gl.activeTexture(gl.TEXTURE0 + i);
      gl.bindTexture(gl.TEXTURE_2D, tex);
    });
    const u = surface.u;
    gl.uniform1i(u.painting, 0);
    gl.uniform1i(u.shore, 1);
    gl.uniform1i(u.ripples, 2);
    updateBands(t, strength);
    gl.uniform4fv(u.bands, parameters);
    gl.uniform4fv(u.geometry, geometry);
    gl.uniform4fv(u.sky, sky);
    gl.uniform1f(u.flowPhase, (t / 5.6) % 1);
    gl.drawArrays(gl.TRIANGLES, 0, 3);
    function draw(pass) {
      const u = pass.u;
      gl.useProgram(pass.p);
      gl.uniform2f(u.viewport, geometry[0], geometry[1]);
      gl.uniform4fv(u.climate, sky);
      gl.uniform1f(u.modelScale, geometry[0] < 600 ? 0.78 : 1);
      if (u.ripples) gl.uniform1i(u.ripples, 2);
      if (u.time) gl.uniform1f(u.time, t);
      if (u.shadow) gl.uniform1i(u.shadow, pass === shadow ? 1 : 0);
      for (const b of boats) {
        gl.uniform4fv(u.pose, b.pose);
        if (u.lamp) gl.uniform3fv(u.lamp, lamps[b.kind]);
        if (pass === wake) {
          gl.uniform1f(u.speed, Math.hypot(b.vx || 0, b.vy || 0));
          gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
        } else if (pass === lantern)
          gl.drawArraysInstanced(gl.TRIANGLE_STRIP, 0, 4, 2);
        else {
          const m = meshes[b.kind + b.variant];
          gl.bindVertexArray(m.vao);
          gl.drawElements(gl.TRIANGLES, m.count, gl.UNSIGNED_SHORT, 0);
        }
      }
      gl.bindVertexArray(null);
    }
    gl.enable(gl.BLEND);
    gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);
    draw(wake);
    gl.enable(gl.DEPTH_TEST);
    gl.depthFunc(gl.LESS);
    if (sky[0] * (1 - sky[2]) > 0.01) draw(shadow);
    gl.disable(gl.BLEND);
    gl.depthFunc(gl.LEQUAL);
    draw(model);
    if (sky[0] < 0.9) {
      gl.enable(gl.BLEND);
      gl.blendFunc(gl.ONE, gl.ONE);
      gl.depthMask(false);
      draw(lantern);
    }
  };
}
