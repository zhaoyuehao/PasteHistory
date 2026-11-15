import { asset } from "./assets.js";

const wallpaper = import.meta.env.BASE_URL + "wallpaper-slate.jpg";
const foam = asset("assets/opening-foam.webp");

// OceanWaves.openingArrival in the native desktop. Both the swash and the
// loose files sample this field, in screen coordinates with +y pointing down.
export function openingContact(x, y) {
  y = Math.max(0, Math.min(1, y));
  const across = x - (0.36 + 0.09 * y);
  const downstream = (Math.sqrt(0.183 ** 2 + 0.192 * y) - 0.183) / 0.096;
  const lateral = (Math.hypot(across, 0.055) - 0.055) * (1.49 - 0.7 * y);
  const chop =
    0.031 * Math.sin(12.6 * x + 4 * y) + 0.019 * Math.sin(27 * x - 5.2 * y);
  return (
    0.497 +
    downstream +
    lateral +
    0.1 * across +
    chop * (0.24 + 0.76 * Math.min(1, y * 3.2))
  );
}

const vertex = `#version 300 es
out vec2 uv;
void main() {
  uv = vec2((gl_VertexID << 1) & 2, gl_VertexID & 2);
  gl_Position = vec4(uv*vec2(2.,-2.)+vec2(-1.,1.), 0., 1.);
}`;

const fragment = `#version 300 es
precision highp float;
in vec2 uv;
out vec4 pixel;
uniform sampler2D desktop, painting, shore, ripple, foamAtlas;
uniform vec2 size;
uniform float clock, daylight;

float arrival(vec2 p) {
  float y=clamp(p.y,0.,1.), across=p.x-(.36+.09*y);
  float down=(sqrt(.183*.183+.192*y)-.183)/.096;
  float side=(length(vec2(across,.055))-.055)*(1.49-.70*y)+.10*across;
  float chop=(.031*sin(12.6*p.x+4.*y)+.019*sin(27.*p.x-5.2*y))*(.24+.76*min(1.,3.2*y));
  return .497+down+side+chop;
}
vec2 cover(vec2 image) {
  return .5+(uv-.5)*size/(image*max(size.x/image.x,size.y/image.y));
}
float foamFrame(float index,vec2 local) {
  vec2 grid=vec2(4.,6.), tile=vec2(mod(index,4.),floor(index/4.));
  vec2 interior=vec2(textureSize(foamAtlas,0))/grid;
  return texture(foamAtlas,(tile+(.5+clamp(local,0.,1.)*(interior-1.))/interior)/grid).a;
}
void main() {
  vec2 duv=cover(vec2(textureSize(desktop,0)));
  vec3 dry=texture(desktop,duv).rgb;
  float age=clock-arrival(uv);
  if (age < -.012) { pixel=vec4(dry,1.); return; }
  vec2 p=uv*size*(982./size.y);
  float dist=age*982.*sqrt(.183*.183+.192*uv.y), time=clock-.48;
  vec2 flow=vec2(-.027,.22)*time, field=p*vec2(.0024,.0035)-flow;
  float r=texture(ripple,field).r;
  vec2 slope=vec2(texture(ripple,field+vec2(.008,0.)).r, texture(ripple,field+vec2(0.,.011)).r)-r;
  float grain=texture(ripple,p*vec2(.007,.008)-.72*flow).r;
  float bend=sin(.015*p.x+.016*p.y-.9*time), roll=1./(1.+pow(abs(dist-12.)/17.,2.));
  vec2 offset=(smoothstep(-3.,36.,dist)*(30.*slope+vec2(4.*(grain-.5),3.*bend))+
               roll*vec2(3.*bend,-8.))*size.y/(982.*size);

  vec3 transmitted=texture(desktop,clamp(duv+offset,0.,1.)).rgb*
      mix(vec3(1.),vec3(.38,.76,.87),smoothstep(.01,.85,age));
  vec3 surface=texture(painting,vec2(.52,.04)+vec2(.34,.23)*uv+.27*offset).rgb*daylight;
  vec3 water=mix(transmitted,surface,.08+.92*smoothstep(.11,1.04,age));
  water+=(.6*(r-.5)+.4*(grain-.5))*.07+max(0.,slope.y)*.13;
  float frame=clamp(time*5.,0.,22.999);
  float scan=40.+(dist-5.-4.*bend)*(1.+.08*sin(.28*time+12.*uv.x));
  vec2 local=vec2(uv.x+.004*sin(6.4*uv.x+time),scan/184.);
  float bubbles=mix(foamFrame(floor(frame),local),foamFrame(floor(frame)+1.,local),fract(frame));
  bubbles*=smoothstep(10.,36.,scan)*(1.-smoothstep(124.,182.,scan));
  float lip=.19/(1.+pow(abs(dist-2.4)/1.8,2.));
  water=mix(water,vec3(.86,.93,.93)*mix(.67,1.,daylight),clamp(.9*bubbles+lip*(.5+.8*r),0.,1.));

  float land=1.-smoothstep(.50,.99,texture(shore,cover(vec2(textureSize(shore,0)))).r);
  float scene=smoothstep(.42,1.25,age)*mix(1.,smoothstep(4.12,5.41,clock),land);
  pixel=vec4(mix(dry,water,smoothstep(-2.6,2.6,dist)),1.-scene*smoothstep(0.,2.6,dist));
}`;

// The fallback clips the very same wallpaper at the file-contact contour.
// Also used while WebGL textures are in flight or a context is lost.
function surfaceHeight(time, x) {
  const top = openingContact(x, 0),
    bottom = openingContact(x, 1);
  if (time <= top) return (time - top) * 0.183;
  if (time >= bottom) return 1 + (time - bottom) * 0.47;
  let low = 0,
    high = 1;
  for (let i = 0; i < 10; i++) {
    const mid = (low + high) / 2;
    if (openingContact(x, mid) < time) low = mid;
    else high = mid;
  }
  return (low + high) / 2;
}

function gpuSurface(canvas) {
  const gl = canvas.getContext("webgl2", {
    alpha: true,
    antialias: false,
    depth: false,
    premultipliedAlpha: false,
  });
  if (!gl) return null;
  const program = gl.createProgram(),
    textures = [];
  let alive = true,
    loaded = 0;
  function destroy() {
    if (!alive) return;
    alive = false;
    textures.forEach((tex) => gl.deleteTexture(tex));
    gl.deleteProgram(program);
    gl.getExtension("WEBGL_lose_context")?.loseContext();
  }
  for (const [type, source] of [
    [gl.VERTEX_SHADER, vertex],
    [gl.FRAGMENT_SHADER, fragment],
  ]) {
    const shader = gl.createShader(type);
    gl.shaderSource(shader, source);
    gl.compileShader(shader);
    gl.attachShader(program, shader);
    gl.deleteShader(shader);
  }
  gl.linkProgram(program);
  if (!gl.getProgramParameter(program, gl.LINK_STATUS)) {
    destroy();
    return null;
  }
  gl.useProgram(program);
  const uniform = (key) => gl.getUniformLocation(program, key);
  const fields = [
    ["desktop", wallpaper],
    ["painting", asset("assets/cove.webp")],
    ["shore", asset("assets/shore.png")],
    ["ripple", asset("assets/ripples.png")],
    ["foamAtlas", foam],
  ];
  fields.forEach(([name, url], index) => {
    const tex = gl.createTexture(),
      img = new Image();
    textures.push(tex);
    gl.uniform1i(uniform(name), index);
    img.onload = () => {
      if (!alive || gl.isContextLost()) return;
      gl.activeTexture(gl.TEXTURE0 + index);
      gl.bindTexture(gl.TEXTURE_2D, tex);
      for (const axis of [gl.TEXTURE_WRAP_S, gl.TEXTURE_WRAP_T])
        gl.texParameteri(
          gl.TEXTURE_2D,
          axis,
          name === "ripple" ? gl.REPEAT : gl.CLAMP_TO_EDGE,
        );
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
      gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, img);
      loaded++;
    };
    img.src = url;
  });
  const size = uniform("size"),
    clock = uniform("clock"),
    light = uniform("daylight");
  return {
    draw(time, w, h, exposure) {
      if (loaded !== fields.length || gl.isContextLost()) return false;
      const dpr = Math.min(devicePixelRatio, 1.5, 2000 / Math.max(w, h));
      const width = Math.max(1, Math.round(w * dpr)),
        height = Math.max(1, Math.round(h * dpr));
      if (canvas.width !== width || canvas.height !== height) {
        canvas.width = width;
        canvas.height = height;
        gl.viewport(0, 0, width, height);
      }
      gl.uniform2f(size, w, h);
      gl.uniform1f(clock, time);
      gl.uniform1f(light, exposure);
      gl.drawArrays(gl.TRIANGLES, 0, 3);
      return true;
    },
    destroy,
  };
}

function canvasSurface(canvas) {
  const ctx = canvas.getContext("2d");
  if (!ctx) return null;
  const paper = new Image(),
    bubbles = new Image();
  paper.src = wallpaper;
  bubbles.src = foam;

  function draw(time, w, h) {
    if (!paper.complete || !paper.naturalWidth) return false;
    const scale = Math.min(devicePixelRatio, 1.5, 1600 / Math.max(w, h));
    const width = Math.max(1, Math.round(w * scale)),
      height = Math.max(1, Math.round(h * scale));
    if (canvas.width !== width || canvas.height !== height) {
      canvas.width = width;
      canvas.height = height;
    }
    ctx.setTransform(width / w, 0, 0, height / h, 0, 0);
    ctx.clearRect(0, 0, w, h);

    const columns = 80,
      step = w / columns,
      unit = h / 982;
    const front = Array.from(
      { length: columns + 1 },
      (_, i) => h * surfaceHeight(time, i / columns),
    );
    const foamIndex = Math.min(22.999, Math.max(0, (time - 0.48) * 5));
    const dark = ctx.createLinearGradient(0, -150 * unit, 0, 0);
    dark.addColorStop(0, "rgba(19,79,89,0)");
    dark.addColorStop(0.6, "rgba(34,96,104,.30)");
    dark.addColorStop(0.95, "rgba(81,135,143,.38)");
    dark.addColorStop(1, "rgba(112,150,151,.12)");
    for (let i = 0; i < columns; i++) {
      if (front[i] < -unit * 30 || front[i] > h + unit * 200) continue;
      // Shear each slice along the crest, so neighboring pieces of the recorded
      // swash meet at the same height even where the wave crosses at an angle.
      ctx.save();
      ctx.transform(
        1,
        (front[i + 1] - front[i]) / step,
        0,
        1,
        i * step,
        front[i],
      );
      ctx.fillStyle = dark;
      ctx.fillRect(0, -150 * unit, step + 0.4, 150 * unit);
      if (bubbles.complete && bubbles.naturalWidth) {
        const tileW = bubbles.naturalWidth / 4,
          tileH = bubbles.naturalHeight / 6;
        const start = Math.floor(foamIndex),
          fraction = foamIndex - start;
        ctx.scale(1, -1);
        for (const [frame, opacity] of [
          [start, 1 - fraction],
          [start + 1, fraction],
        ]) {
          ctx.globalAlpha = opacity * 0.87;
          ctx.drawImage(
            bubbles,
            ((frame % 4) + i / columns) * tileW,
            Math.floor(frame / 4) * tileH,
            tileW / columns,
            tileH,
            0,
            -35 * unit,
            step + 0.4,
            184 * unit,
          );
        }
      }
      ctx.restore();
    }
    ctx.save();
    ctx.beginPath();
    ctx.moveTo(0, front[0]);
    for (let i = 1; i <= columns; i++) ctx.lineTo(i * step, front[i]);
    ctx.lineTo(w, Math.max(h, front[columns]));
    ctx.lineTo(w, h);
    ctx.lineTo(0, h);
    ctx.closePath();
    ctx.clip();
    const fit = Math.max(w / paper.naturalWidth, h / paper.naturalHeight);
    const pw = paper.naturalWidth * fit,
      ph = paper.naturalHeight * fit;
    ctx.drawImage(paper, (w - pw) / 2, (h - ph) / 2, pw, ph);
    ctx.restore();
    return true;
  }
  return { draw, destroy() {} };
}

export function createOpeningWater(canvas) {
  const backdrop = `#354858 url("${wallpaper}") center / cover no-repeat`;
  canvas.style.background = backdrop;
  const renderer = gpuSurface(canvas) ?? canvasSurface(canvas);
  let drawing = false;
  return {
    paint(time, w, h) {
      if (w <= 0 || h <= 0) return;
      if (time >= 5.5) {
        canvas.style.visibility = "hidden";
        return;
      }
      canvas.style.visibility = "";
      const exposure =
        Number(canvas.parentElement?.style.getPropertyValue("--light")) || 1;
      if (renderer?.draw(time, w, h, exposure)) {
        if (!drawing) {
          canvas.style.background = "transparent";
          canvas.style.clipPath = "";
        }
        drawing = true;
      } else {
        drawing = false;
        canvas.style.background = backdrop;
        const points = [];
        for (let i = 0; i <= 64; i++) {
          const y = Math.min(
            102,
            Math.max(-2, 100 * surfaceHeight(time, i / 64)),
          );
          points.push(`${(i / 64) * 100}% ${y.toFixed(2)}%`);
        }
        canvas.style.clipPath = `polygon(${points.join(",")}, 100% 100%, 0% 100%)`;
      }
    },
    destroy() {
      renderer?.destroy();
      canvas.style.background = "transparent";
    },
  };
}
