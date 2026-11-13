// The shoreline distance map shares the photograph's cover transform with both the shader and navigation.
export async function ocean(canvas) {
  const load = (path) =>
    new Promise((resolve, reject) => {
      const img = new Image();
      img.onload = () => resolve(img);
      img.onerror = reject;
      img.src = "assets/" + path;
    });
  const [photo, shore, ripple] = await Promise.all(
    ["cove.webp", "shore.png", "ripples.png"].map(load),
  );
  const map = document.createElement("canvas");
  map.width = shore.width;
  map.height = shore.height;
  const ctx = map.getContext("2d", { willReadFrequently: true });
  ctx.drawImage(shore, 0, 0);
  const pixels = ctx.getImageData(0, 0, map.width, map.height).data;
  let width = 0,
    height = 0,
    fw = 0,
    fh = 0,
    paint = () => {};
  const gl = canvas.getContext("webgl", {
    alpha: false,
    antialias: false,
    preserveDrawingBuffer: false,
  });
  if (gl) {
    const vs =
      "attribute vec2 pos; varying vec2 p; void main(){p=vec2(pos.x,-pos.y)*.5+.5;gl_Position=vec4(pos,0.,1.);}";
    const fs = `precision highp float; varying vec2 p;
      uniform vec2 fit; uniform float t,wind; uniform sampler2D coast,shore,grain;
      void main(){
        vec2 uv=(p-.5)*fit+.5;
        float sea=smoothstep(.49,.63,texture2D(shore,uv).r);
        vec2 dir=vec2(.83,-.55), side=vec2(.55,.83);
        float a=dot(uv,dir)*150.-t*1.35, b=dot(uv,side)*73.+t*.48;
        vec2 offset=wind*sea*(dir*sin(a+.74*sin(b))*.00085+side*cos(b+a*.34)*.00034);
        vec3 base=texture2D(coast,uv+offset).rgb;
        float f1=texture2D(grain,fract(uv*4.5-dir*t*.016+offset)).r;
        float f0=texture2D(grain,fract(uv*4.5)).r;
        gl_FragColor=vec4(base+(f1-f0)*vec3(.065,.105,.10)*sea*wind,1.);
      }`;
    try {
      const program = gl.createProgram();
      for (const [kind, source] of [
        [gl.VERTEX_SHADER, vs],
        [gl.FRAGMENT_SHADER, fs],
      ]) {
        const shader = gl.createShader(kind);
        gl.shaderSource(shader, source);
        gl.compileShader(shader);
        if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS))
          throw Error(gl.getShaderInfoLog(shader));
        gl.attachShader(program, shader);
      }
      gl.linkProgram(program);
      if (!gl.getProgramParameter(program, gl.LINK_STATUS))
        throw Error("shader link");
      gl.useProgram(program);
      gl.bindBuffer(gl.ARRAY_BUFFER, gl.createBuffer());
      gl.bufferData(
        gl.ARRAY_BUFFER,
        new Float32Array([-1, -1, 1, -1, -1, 1, 1, 1]),
        gl.STATIC_DRAW,
      );
      const pos = gl.getAttribLocation(program, "pos");
      gl.enableVertexAttribArray(pos);
      gl.vertexAttribPointer(pos, 2, gl.FLOAT, false, 0, 0);
      [photo, shore, ripple].forEach((img, i) => {
        gl.activeTexture(gl.TEXTURE0 + i);
        gl.bindTexture(gl.TEXTURE_2D, gl.createTexture());
        gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGB, gl.RGB, gl.UNSIGNED_BYTE, img);
        for (const key of [gl.TEXTURE_MIN_FILTER, gl.TEXTURE_MAG_FILTER])
          gl.texParameteri(gl.TEXTURE_2D, key, gl.LINEAR);
        for (const key of [gl.TEXTURE_WRAP_S, gl.TEXTURE_WRAP_T])
          gl.texParameteri(gl.TEXTURE_2D, key, gl.CLAMP_TO_EDGE);
        gl.uniform1i(
          gl.getUniformLocation(program, ["coast", "shore", "grain"][i]),
          i,
        );
      });
      const uniform = (k) => gl.getUniformLocation(program, k),
        fit = uniform("fit"),
        time = uniform("t"),
        strength = uniform("wind");
      paint = (t, wind) => {
        gl.viewport(0, 0, canvas.width, canvas.height);
        gl.uniform2f(fit, width / fw, height / fh);
        gl.uniform1f(time, t);
        gl.uniform1f(strength, wind);
        gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
      };
    } catch {
      canvas.hidden = true;
    }
  } else canvas.hidden = true;
  return {
    resize(w, h) {
      width = w;
      height = h;
      fw = Math.max(w, (h * photo.width) / photo.height);
      fh = (fw * photo.height) / photo.width;
      const scale = Math.min(devicePixelRatio, 1.4, 2200 / Math.max(w, h));
      canvas.width = Math.round(w * scale);
      canvas.height = Math.round(h * scale);
    },
    depth(x, y) {
      const u = (x - width / 2) / fw + 0.5,
        v = (y - height / 2) / fh + 0.5;
      const col = Math.max(
        0,
        Math.min(map.width - 1, Math.floor(u * map.width)),
      );
      const row = Math.max(
        0,
        Math.min(map.height - 1, Math.floor(v * map.height)),
      );
      return pixels[(row * map.width + col) * 4] - 128;
    },
    paint,
  };
}

export function precipitation(canvas, depth) {
  const ctx = canvas.getContext("2d");
  let drops = [],
    w = 0,
    h = 0,
    acc = 0;
  return {
    resize(width, height) {
      w = canvas.width = width;
      h = canvas.height = height;
      drops = [];
    },
    paint(dt, weather) {
      ctx.clearRect(0, 0, w, h);
      if (weather !== "rain" && weather !== "snow") {
        drops = [];
        return;
      }
      const snow = weather === "snow";
      acc += dt * Math.min(240, (w * h) / 4000);
      while (acc >= 1) {
        acc--;
        const x = Math.random() * w,
          y = Math.random() * h;
        if (depth(x, y) < 5) continue;
        drops.push({
          x,
          y,
          age: 0,
          size: 0.5 + Math.random(),
          flight: snow ? 1.7 : 0.36,
          snow,
        });
      }
      drops = drops.filter((p) => p.snow === snow && p.age < p.flight + 0.55);
      for (const p of drops) {
        p.age += dt;
        const left = p.flight - p.age;
        if (left > 0) {
          const x = p.x - left * (snow ? 10 : 52),
            y = p.y - left * (snow ? 30 : 235);
          ctx.beginPath();
          if (snow) {
            ctx.fillStyle = "#ffffffe0";
            ctx.arc(
              x + 2 * Math.sin(left * 4),
              y,
              1.9 * p.size,
              0,
              2 * Math.PI,
            );
            ctx.fill();
          } else {
            ctx.strokeStyle = "rgba(220,241,255,.7)";
            ctx.lineWidth = p.size;
            ctx.moveTo(x - 2 * p.size, y - 9 * p.size);
            ctx.lineTo(x, y);
            ctx.stroke();
          }
        } else {
          const age = -left;
          ctx.strokeStyle =
            "rgba(216,246,255," + (1 - age / 0.55) * (snow ? 0.2 : 0.65) + ")";
          ctx.lineWidth = 0.9;
          ctx.beginPath();
          ctx.ellipse(
            p.x,
            p.y,
            1 + age * 16 * p.size,
            1 + age * 7 * p.size,
            0,
            0,
            2 * Math.PI,
          );
          ctx.stroke();
        }
      }
    },
  };
}
