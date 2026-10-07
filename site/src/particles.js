import {
  AdditiveBlending,
  BufferAttribute,
  BufferGeometry,
  PerspectiveCamera,
  Points,
  Scene,
  ShaderMaterial,
  Vector2,
  WebGLRenderer,
  Group,
} from 'three'

// One particle field, five formations. Every formation is built from the
// same motif as the app icon: rounded segments of time.
//   0 logo · 1 dial (start) · 2 timeline (pauses, parallel) · 3 week bars · 4 one column (booked)

const C = {
  ink: '#061412',
  white: '#F4FFFC',
  mint: '#5EEAD4',
  teal: '#2DD4BF',
  deep: '#0F766E',
  coral: '#FF5A36',
  amber: '#FBBF24',
  dev: '#60A5FA',
  meeting: '#FB923C',
  review: '#A78BFA',
  support: '#F472B6',
  dim: '#7E9C96',
  track: '#1F4D46',
}

const rgb = (hex, k = 1) => {
  const n = parseInt(hex.slice(1), 16)
  return [(((n >> 16) & 255) / 255) * k, (((n >> 8) & 255) / 255) * k, ((n & 255) / 255) * k]
}
const lerp3 = (a, b, t) => [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t]

function mulberry32(seed) {
  let a = seed
  return () => {
    a |= 0
    a = (a + 0x6d2b79f5) | 0
    let t = Math.imul(a ^ (a >>> 15), 1 | a)
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}

// --- shapes -----------------------------------------------------------------

// Rounded rectangle centred at (cx, cy); r defaults to a full capsule.
function roundRect(cx, cy, w, h, color, { r = Math.min(w, h) / 2, density = 1, angle = 0, gradient, hatch, tag } = {}) {
  const inside = (x, y) => {
    const qx = Math.abs(x) - (w / 2 - r)
    const qy = Math.abs(y) - (h / 2 - r)
    const ox = Math.max(qx, 0)
    const oy = Math.max(qy, 0)
    return Math.hypot(ox, oy) + Math.min(Math.max(qx, qy), 0) <= r
  }
  const cos = Math.cos(angle)
  const sin = Math.sin(angle)
  return {
    area: w * h * (hatch ? 0.5 : 1) * density,
    tag,
    sample(rnd) {
      for (let i = 0; i < 64; i++) {
        const x = (rnd() - 0.5) * w
        const y = (rnd() - 0.5) * h
        if (!inside(x, y)) continue
        if (hatch && ((x + y) * 4.2 - Math.floor((x + y) * 4.2)) > 0.48) continue
        const col = gradient ? lerp3(rgb(gradient[0]), rgb(gradient[1]), gradient[2] === 'x' ? x / w + 0.5 : y / h + 0.5) : rgb(color)
        return { x: cx + x * cos - y * sin, y: cy + x * sin + y * cos, z: (rnd() - 0.5) * 0.18, c: col }
      }
      return { x: cx, y: cy, z: 0, c: rgb(color ?? C.white) }
    },
  }
}

// Outline of a rounded rectangle (the app icon's squircle).
function roundRectOutline(cx, cy, w, h, r, thickness, color, density = 1) {
  const straightW = w - 2 * r
  const straightH = h - 2 * r
  const arc = (Math.PI / 2) * r
  const perimeter = 2 * straightW + 2 * straightH + 4 * arc
  return {
    area: perimeter * thickness * density,
    sample(rnd) {
      let d = rnd() * perimeter
      let x
      let y
      let nx
      let ny
      const seg = [straightW, arc, straightH, arc, straightW, arc, straightH, arc]
      let i = 0
      while (d > seg[i]) d -= seg[i++]
      const t = d / seg[i]
      const hw = w / 2
      const hh = h / 2
      switch (i) {
        case 0: x = -hw + r + t * straightW; y = hh; nx = 0; ny = 1; break
        case 1: { const a = Math.PI / 2 - t * (Math.PI / 2); nx = Math.cos(a); ny = Math.sin(a); x = hw - r + nx * r; y = hh - r + ny * r; break }
        case 2: x = hw; y = hh - r - t * straightH; nx = 1; ny = 0; break
        case 3: { const a = -t * (Math.PI / 2); nx = Math.cos(a); ny = Math.sin(a); x = hw - r + nx * r; y = -hh + r + ny * r; break }
        case 4: x = hw - r - t * straightW; y = -hh; nx = 0; ny = -1; break
        case 5: { const a = -Math.PI / 2 - t * (Math.PI / 2); nx = Math.cos(a); ny = Math.sin(a); x = -hw + r + nx * r; y = -hh + r + ny * r; break }
        case 6: x = -hw; y = -hh + r + t * straightH; nx = -1; ny = 0; break
        default: { const a = Math.PI - t * (Math.PI / 2); nx = Math.cos(a); ny = Math.sin(a); x = -hw + r + nx * r; y = hh - r + ny * r }
      }
      const o = (rnd() - 0.5) * thickness
      return { x: cx + x + nx * o, y: cy + y + ny * o, z: (rnd() - 0.5) * 0.1, c: lerp3(rgb(color[0]), rgb(color[1]), 0.5 - y / h) }
    },
  }
}

// Annulus sector, angles in radians measured clockwise from 12 o'clock.
function arc(r0, r1, from, to, color, { density = 1, gradient } = {}) {
  const span = to - from
  return {
    area: span * ((r1 * r1 - r0 * r0) / 2) * density,
    sample(rnd) {
      const t = rnd()
      const a = from + t * span
      const r = Math.sqrt(r0 * r0 + rnd() * (r1 * r1 - r0 * r0))
      const col = gradient ? lerp3(rgb(gradient[0]), rgb(gradient[1]), t) : rgb(color)
      return { x: Math.sin(a) * r, y: Math.cos(a) * r, z: (rnd() - 0.5) * 0.12, c: col }
    },
  }
}

// Orbiting ring; position is stored as (radius, angle, height) and animated in the shader.
function orbit(r0, r1, colors, count) {
  return {
    fixed: count,
    tag: 'orbit',
    sample(rnd) {
      return {
        x: r0 + rnd() * (r1 - r0),
        y: rnd() * Math.PI * 2,
        z: (rnd() - 0.5) * 0.08,
        c: rgb(colors[Math.floor(rnd() * colors.length)]),
      }
    },
  }
}

function dust(rnd) {
  const k = 0.12 + rnd() * 0.22
  const hue = rnd() < 0.7 ? C.mint : rnd() < 0.5 ? C.white : C.review
  return { x: (rnd() - 0.5) * 22, y: (rnd() - 0.5) * 13, z: -4 + rnd() * 5.5, c: rgb(hue, k), dust: true }
}

// --- formations ---------------------------------------------------------------

function logo() {
  // Proportions measured from docs/assets/logo.png (squircle 822 px → 6 units).
  const s = 6 / 822
  const px = (x) => (x - 512) * s
  const py = (y) => -(y - 512) * s
  const h = 95 * s
  const pill = (x0, x1, y) => roundRect((px(x0) + px(x1)) / 2, py(y), (x1 - x0) * s, h, null, { gradient: [C.white, C.mint, 'x'], density: 1.6 })
  return [
    pill(269, 597, 415.5),
    pill(619, 755, 415.5),
    pill(269, 467, 607.5),
    pill(490, 755, 607.5),
    roundRect(0, 0, 6, 6, null, { r: 1.32, gradient: [C.deep, C.teal, 'y'], density: 0.075 }),
    roundRectOutline(0, 0, 6, 6, 1.32, 0.05, [C.mint, C.deep], 1.4),
  ]
}

function dial() {
  const shapes = []
  for (let i = 0; i < 60; i++) {
    const major = i % 5 === 0
    const len = major ? 0.44 : 0.2
    const a = (i / 60) * Math.PI * 2
    const r = 2.78 - len / 2
    shapes.push(roundRect(Math.sin(a) * r, Math.cos(a) * r, major ? 0.1 : 0.05, len, major ? C.white : C.dim, { angle: -a, density: major ? 2.2 : 1.6 }))
  }
  shapes.push(arc(2.02, 2.2, 0, Math.PI * 1.42, null, { gradient: [C.deep, C.mint], density: 1.7 }))
  shapes.push(arc(2.06, 2.16, Math.PI * 1.46, Math.PI * 1.98, C.track, { density: 1.1 }))
  shapes.push(roundRect(0, 0.92, 0.13, 2.1, C.coral, { density: 2.6, tag: 'hand' }))
  shapes.push(roundRect(0, 0, 0.34, 0.34, C.coral, { density: 2.6, tag: 'hand' }))
  return shapes
}

function timeline() {
  const lane = 0.6
  const y1 = 0.95
  const y2 = -0.25
  const seg = (x0, x1, y, color, opts = {}) => roundRect((x0 + x1) / 2, y, x1 - x0, lane, color, { density: 1.15, ...opts })
  const shapes = [
    seg(-3.6, -1.35, y1, C.dev),
    seg(-1.25, -0.25, y1, C.amber, { hatch: true, density: 1.5 }),
    seg(-0.15, 1.55, y1, C.dev),
    seg(1.65, 3.6, y1, C.review),
    seg(-1.05, 0.9, y2, C.meeting),
    seg(2.0, 3.05, y2, C.support),
    roundRect(2.45, 0.35, 0.05, 3.3, C.coral, { density: 2.4 }),
    roundRect(2.45, 2.04, 0.16, 0.16, C.coral, { density: 2.4 }),
  ]
  for (let i = 0; i <= 10; i++) {
    shapes.push(roundRect(-3.6 + i * 0.72, -1.3, 0.035, i % 2 ? 0.1 : 0.2, C.dim, { density: 2 }))
  }
  shapes.push(roundRect(0, -1.5, 7.2, 0.02, C.track, { density: 1.6 }))
  return shapes
}

function bars() {
  const week = [
    [[C.dev, 1.8], [C.meeting, 0.7], [C.review, 0.5], [C.support, 0.3]],
    [[C.dev, 2.4], [C.meeting, 0.5], [C.review, 0.9]],
    [[C.dev, 1.2], [C.meeting, 1.4], [C.support, 0.8], [C.review, 0.4]],
    [[C.dev, 2.8], [C.review, 0.6], [C.meeting, 0.3]],
    [[C.dev, 1.5], [C.support, 0.9], [C.review, 0.7], [C.meeting, 0.4]],
  ]
  const base = -2.45
  const shapes = []
  week.forEach((day, i) => {
    const x = -2.8 + i * 1.4
    let y = base
    day.forEach(([color, h]) => {
      shapes.push(roundRect(x, y + h / 2, 0.82, h - 0.08, color, { r: 0.14, density: 0.85 }))
      y += h
    })
  })
  for (let i = 0; i < 46; i++) {
    shapes.push(roundRect(-3.5 + i * 0.155, base + 3.7, 0.07, 0.025, C.mint, { density: 3 }))
  }
  shapes.push(roundRect(0, base - 0.18, 7.4, 0.02, C.track, { density: 1.6 }))
  return shapes
}

function column(count) {
  return [
    // Booked hours with the day's delta on top, one cumulative number like Completed Work.
    roundRect(0, -0.65, 0.95, 3.8, null, { r: 0.2, gradient: [C.deep, C.teal, 'y'], density: 1.25 }),
    roundRect(0, 1.82, 0.95, 1.05, null, { r: 0.2, gradient: [C.mint, C.white, 'y'], density: 1.6 }),
    orbit(2.15, 2.65, [C.dev, C.dev, C.meeting, C.review, C.support, C.mint], Math.round(count * 0.22)),
  ]
}

function build(shapes, count, rnd) {
  const density = 1500 * (count / 22000)
  const out = []
  const fixed = shapes.filter((s) => s.fixed)
  const fluid = shapes.filter((s) => !s.fixed)
  for (const s of fixed) for (let i = 0; i < s.fixed; i++) out.push({ ...s.sample(rnd), tag: s.tag })
  const budget = count - out.length
  const want = fluid.reduce((sum, s) => sum + s.area * density, 0)
  const k = Math.min(1, budget / want)
  for (const s of fluid) {
    const n = Math.round(s.area * density * k)
    for (let i = 0; i < n && out.length < count; i++) out.push({ ...s.sample(rnd), tag: s.tag })
  }
  while (out.length < count) out.push(dust(rnd))
  for (let i = out.length - 1; i > 0; i--) {
    const j = Math.floor(rnd() * (i + 1))
    ;[out[i], out[j]] = [out[j], out[i]]
  }
  return out
}

// --- shaders --------------------------------------------------------------------

const vertex = /* glsl */ `
  attribute vec3 p0; attribute vec3 p1; attribute vec3 p2; attribute vec3 p3; attribute vec3 p4;
  attribute vec3 c0; attribute vec3 c1; attribute vec3 c2; attribute vec3 c3; attribute vec3 c4;
  attribute vec3 pScatter;
  attribute vec4 aRand;   // delay, size, phase, dust
  attribute vec2 aTag;    // hand (formation 1), orbit (formation 4)

  uniform float uProgress;
  uniform float uTime;
  uniform float uIntro;
  uniform float uBeat;
  uniform float uMorph;
  uniform float uSize;
  uniform float uPixelRatio;
  uniform vec3 uMouse;

  varying vec3 vColor;
  varying float vAlpha;

  vec2 rot(vec2 v, float a) { float c = cos(a), s = sin(a); return vec2(c * v.x - s * v.y, s * v.x + c * v.y); }

  vec3 at(float i, vec3 a, vec3 b, vec3 c, vec3 d, vec3 e) {
    return i < 0.5 ? a : i < 1.5 ? b : i < 2.5 ? c : i < 3.5 ? d : e;
  }

  void main() {
    vec3 q1 = p1;
    if (aTag.x > 0.5) q1.xy = rot(q1.xy, -uTime * 0.55);

    vec3 q4 = p4;
    if (aTag.y > 0.5) {
      float a = p4.y + uTime * 0.32;
      vec3 o = vec3(cos(a) * p4.x, p4.z, sin(a) * p4.x);
      float t = 1.18;
      o = vec3(o.x, o.y * cos(t) - o.z * sin(t), o.y * sin(t) + o.z * cos(t));
      o.xy = rot(o.xy, -0.22);
      q4 = o + vec3(0.0, -0.15, 0.0);
    }

    float seg = clamp(floor(uProgress), 0.0, 3.0);
    float f = clamp(uProgress - seg, 0.0, 1.0);
    float delay = aRand.x;
    float e = smoothstep(0.0, 1.0, clamp((f - delay * 0.38) / 0.62, 0.0, 1.0));

    vec3 A = at(seg, p0, q1, p2, p3, q4);
    vec3 B = at(seg + 1.0, p0, q1, p2, p3, q4);
    vec3 CA = at(seg, c0, c1, c2, c3, c4);
    vec3 CB = at(seg + 1.0, c0, c1, c2, c3, c4);

    vec3 pos = mix(A, B, e);
    float flight = sin(e * 3.14159);
    pos += uMorph * flight * vec3(
      sin(delay * 41.0 + uTime * 0.7) * 0.8,
      cos(aRand.z * 29.0 + uTime * 0.5) * 0.6,
      sin(aRand.z * 17.0) * 1.6
    );
    pos += uMorph * vec3(sin(uTime * 0.6 + aRand.z * 6.28), cos(uTime * 0.5 + delay * 6.28), 0.0) * 0.018;

    float intro = smoothstep(delay * 0.55, delay * 0.55 + 0.45, uIntro);
    pos = mix(pScatter, pos, intro);

    vec2 diff = pos.xy - uMouse.xy;
    float dist = length(diff);
    float push = (1.0 - smoothstep(0.0, 1.5, dist)) * uMouse.z * (1.0 - aRand.w);
    pos.xy += normalize(diff + 1e-4) * push * 0.55;
    pos.z += push * 0.9;

    vec3 col = mix(CA, CB, e);
    float logo = 1.0 - clamp(uProgress, 0.0, 1.0);
    col *= 1.0 + uBeat * 0.55 * logo * (1.0 - aRand.w);
    col *= 0.55 + 0.45 * intro;
    vColor = col;
    vAlpha = mix(0.0, 1.0, intro) * (0.78 + 0.22 * sin(uTime * 1.7 + aRand.z * 40.0) * uMorph);

    vec4 mv = modelViewMatrix * vec4(pos, 1.0);
    gl_Position = projectionMatrix * mv;
    float size = uSize * aRand.y * (1.0 + flight * 0.6) * (1.0 + push * 0.8);
    gl_PointSize = size * uPixelRatio * (15.86 / -mv.z);
  }
`

const fragment = /* glsl */ `
  varying vec3 vColor;
  varying float vAlpha;
  void main() {
    float r = length(gl_PointCoord - 0.5);
    float a = smoothstep(0.5, 0.0, r);
    a = a * a;
    gl_FragColor = vec4(vColor * a * vAlpha, 1.0);
  }
`

// --- field --------------------------------------------------------------------

export function createField(canvas, { reduced = false } = {}) {
  let renderer
  try {
    renderer = new WebGLRenderer({ canvas, antialias: false, alpha: true, powerPreference: 'high-performance' })
  } catch {
    return null
  }
  if (!renderer.getContext()) return null

  const small = window.matchMedia('(max-width: 899px)').matches
  const count = small ? 11000 : 22000
  const rnd = mulberry32(7)

  const formations = [logo(), dial(), timeline(), bars(), column(count)].map((shapes) => build(shapes, count, rnd))

  const geometry = new BufferGeometry()
  formations.forEach((list, f) => {
    const pos = new Float32Array(count * 3)
    const col = new Float32Array(count * 3)
    list.forEach((p, i) => {
      pos.set([p.x, p.y, p.z], i * 3)
      col.set(p.c, i * 3)
    })
    geometry.setAttribute(`p${f}`, new BufferAttribute(pos, 3))
    geometry.setAttribute(`c${f}`, new BufferAttribute(col, 3))
  })
  const scatter = new Float32Array(count * 3)
  const rand = new Float32Array(count * 4)
  const tag = new Float32Array(count * 2)
  for (let i = 0; i < count; i++) {
    const a = rnd() * Math.PI * 2
    const r = 6 + rnd() * 9
    scatter.set([Math.cos(a) * r, Math.sin(a) * r * 0.6, -6 + rnd() * 8], i * 3)
    const isDust = formations[0][i].dust ? 1 : 0
    rand.set([rnd(), 0.55 + rnd() * 0.9 * (isDust ? 0.6 : 1), rnd(), isDust], i * 4)
    tag.set([formations[1][i].tag === 'hand' ? 1 : 0, formations[4][i].tag === 'orbit' ? 1 : 0], i * 2)
  }
  geometry.setAttribute('pScatter', new BufferAttribute(scatter, 3))
  geometry.setAttribute('aRand', new BufferAttribute(rand, 4))
  geometry.setAttribute('aTag', new BufferAttribute(tag, 2))
  // Positions come from the shader; give three.js a position attribute and a fixed bound.
  geometry.setAttribute('position', geometry.getAttribute('p0'))
  geometry.boundingSphere = null
  geometry.computeBoundingSphere()
  geometry.boundingSphere.radius = 30

  const material = new ShaderMaterial({
    vertexShader: vertex,
    fragmentShader: fragment,
    transparent: true,
    depthWrite: false,
    blending: AdditiveBlending,
    uniforms: {
      uProgress: { value: 0 },
      uTime: { value: 0 },
      uIntro: { value: reduced ? 1 : 0 },
      uBeat: { value: 0 },
      uMorph: { value: reduced ? 0 : 1 },
      uSize: { value: small ? 3.8 : 3.7 },
      uPixelRatio: { value: 1 },
      uMouse: { value: [99, 99, 0] },
    },
  })

  const scene = new Scene()
  const group = new Group()
  group.add(new Points(geometry, material))
  scene.add(group)
  const camera = new PerspectiveCamera(35, 1, 0.1, 100)
  camera.position.z = 15.86

  const state = {
    progress: 0,
    target: 0,
    intro: reduced ? 1 : 0,
    mouse: new Vector2(99, 99),
    mouseNdc: new Vector2(0, 0),
    mouseStrength: 0,
    running: true,
    beatStart: performance.now(),
    view: { w: 10, h: 10, scale: 1, x: 0, y: 0 },
    start: performance.now(),
  }

  function resize() {
    const w = canvas.clientWidth
    const h = canvas.clientHeight
    const dpr = Math.min(window.devicePixelRatio || 1, 1.75)
    renderer.setPixelRatio(dpr)
    renderer.setSize(w, h, false)
    material.uniforms.uPixelRatio.value = dpr
    camera.aspect = w / h
    camera.updateProjectionMatrix()
    const visH = 10
    const visW = visH * camera.aspect
    let scale
    let x
    let y
    if (w >= 900) {
      scale = Math.min(1.12, (visW * 0.5) / 7.6)
      x = visW * 0.22
      y = -0.1
    } else {
      scale = Math.min(0.62, (visW * 0.92) / 7.6)
      x = 0
      y = 2.2
    }
    group.scale.setScalar(scale)
    group.position.set(x, y, 0)
    state.view = { w: visW, h: visH, scale, x, y }
  }

  function onPointer(e) {
    if (reduced) return
    const rect = canvas.getBoundingClientRect()
    const nx = ((e.clientX - rect.left) / rect.width) * 2 - 1
    const ny = -((e.clientY - rect.top) / rect.height) * 2 + 1
    state.mouseNdc.set(nx, ny)
    const { w, h, scale, x, y } = state.view
    state.mouse.set((nx * w * 0.5 - x) / scale, (ny * h * 0.5 - y) / scale)
    state.mouseStrength = 1
  }

  const ro = new ResizeObserver(resize)
  ro.observe(canvas)
  window.addEventListener('pointermove', onPointer, { passive: true })
  resize()

  const smoothMouse = new Vector2(99, 99)
  let last = performance.now()
  let elapsed = 0

  function frame(now) {
    if (!state.running) return
    const dt = Math.min((now - last) / 1000, 0.05)
    last = now
    if (!reduced) elapsed += dt
    const u = material.uniforms
    // Critically damped approach keeps the morph interruptible: scroll back mid-flight and it simply turns around.
    if (reduced) state.progress = Math.round(state.target)
    else state.progress += (state.target - state.progress) * (1 - Math.exp(-dt * 6))
    u.uProgress.value = state.progress
    u.uTime.value = elapsed
    u.uIntro.value = state.intro
    const beat = ((now - state.beatStart) / 1000) % 1.2
    u.uBeat.value = reduced ? 0 : Math.exp(-beat * 7) * Math.min(1, state.intro * 1.2)
    smoothMouse.lerp(state.mouse, 1 - Math.exp(-dt * 10))
    state.mouseStrength *= Math.exp(-dt * 0.9)
    u.uMouse.value = [smoothMouse.x, smoothMouse.y, state.mouseStrength]
    group.rotation.y += (state.mouseNdc.x * 0.16 - group.rotation.y) * (1 - Math.exp(-dt * 3))
    group.rotation.x += (-state.mouseNdc.y * 0.1 - group.rotation.x) * (1 - Math.exp(-dt * 3))
    renderer.render(scene, camera)
  }

  return {
    frame,
    // Orchestrated entry: particles fly in from the dark and lock into the logo.
    intro: (gsap, duration = 2.4) => {
      if (reduced) return null
      return gsap.to(state, { intro: 1, duration, ease: 'power3.out' })
    },
    setProgress(p) {
      state.target = p
    },
    setRunning(on) {
      if (on && !state.running) last = performance.now()
      state.running = on
    },
    beat() {
      state.beatStart = performance.now()
    },
    get progress() {
      return state.progress
    },
    dispose() {
      ro.disconnect()
      window.removeEventListener('pointermove', onPointer)
      geometry.dispose()
      material.dispose()
      renderer.dispose()
    },
  }
}
