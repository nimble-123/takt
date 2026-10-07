import './style.css'
import { gsap } from 'gsap'
import { ScrollTrigger } from 'gsap/ScrollTrigger'
import { SplitText } from 'gsap/SplitText'
import Lenis from 'lenis'
import { animate, press } from 'motion'
import { applyLanguage, pickLanguage } from './i18n.js'

gsap.registerPlugin(ScrollTrigger, SplitText)

const reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches
const root = document.documentElement
const $ = (s, el = document) => el.querySelector(s)
const $$ = (s, el = document) => [...el.querySelectorAll(s)]

// --- language and version ----------------------------------------------------------

const lang = pickLanguage()
const t = applyLanguage(lang)
const version = __TAKT_VERSION__
for (const el of $$('[data-version]')) el.textContent = version
$('[data-dmg]').href = `https://github.com/nimble-123/takt/releases/download/v${version}/Takt-${version}-arm64.dmg`

$('[data-lang]').addEventListener('click', () => {
  const next = lang === 'de' ? 'en' : 'de'
  try {
    localStorage.setItem('takt-lang', next)
  } catch {
    // Without storage the query parameter still carries the choice.
  }
  const url = new URL(location.href)
  url.searchParams.set('lang', next)
  location.replace(url)
})

// --- smooth scroll, one ticker ---------------------------------------------------------

const lenis = reduced ? null : new Lenis({ lerp: 0.1, wheelMultiplier: 0.9 })
if (lenis) lenis.on('scroll', ScrollTrigger.update)

const canvas = $('.field')
// three.js is the heaviest dependency; load it next to the fonts so text never waits on it.
let field = null
const fieldReady = import('./particles.js')
  .then(({ createField }) => {
    field = createField(canvas, { reduced })
    if (!field) root.classList.add('no-webgl')
  })
  .catch(() => root.classList.add('no-webgl'))

gsap.ticker.add((time) => {
  lenis?.raf(time * 1000)
  field?.frame(performance.now())
})
gsap.ticker.lagSmoothing(0)

for (const a of $$('a[href^="#"]')) {
  a.addEventListener('click', (e) => {
    const target = $(a.getAttribute('href'))
    if (!target) return
    e.preventDefault()
    if (lenis) lenis.scrollTo(target, { duration: 1.6 })
    else target.scrollIntoView()
    if (a.classList.contains('skip')) {
      target.setAttribute('tabindex', '-1')
      target.focus({ preventScroll: true })
    }
  })
}

ScrollTrigger.create({
  start: 40,
  end: 'max',
  onToggle: (self) => $('[data-nav]').classList.toggle('scrolled', self.isActive),
})

// --- live timer: you've been tracking since the page opened -------------------------------

const opened = performance.now()
const liveTime = $('[data-live-time]')
function tick() {
  const s = Math.floor((performance.now() - opened) / 1000)
  liveTime.textContent = `${Math.floor(s / 3600)}:${String(Math.floor(s / 60) % 60).padStart(2, '0')}:${String(s % 60).padStart(2, '0')}`
}
tick()
setInterval(tick, 1000)

// --- micro-interactions (Motion springs, interruptible by design) ----------------------------

const springy = { type: 'spring', stiffness: 520, damping: 30, mass: 0.6 }
press('[data-press]', (el) => {
  animate(el, { scale: 0.97 }, springy)
  return () => animate(el, { scale: 1 }, springy)
})

const copy = $('[data-copy]')
let copyTimer
copy.addEventListener('click', async () => {
  try {
    await navigator.clipboard.writeText(copy.dataset.copy)
  } catch {
    return
  }
  const label = $('[data-copy-label]', copy)
  clearTimeout(copyTimer)
  copy.classList.add('done')
  label.textContent = t['install.copied']
  animate(label, { y: [8, 0], opacity: [0, 1] }, springy)
  copyTimer = setTimeout(() => {
    copy.classList.remove('done')
    label.textContent = t['install.copy']
    animate(label, { y: [-8, 0], opacity: [0, 1] }, springy)
  }, 1600)
})

// --- headline: split, then the full stop becomes the record light ----------------------------

const title = $('[data-hero-title]')
const beatLine = $('[data-beat-line]')

function addBeat(host) {
  const node = [...host.childNodes].reverse().find((n) => n.nodeType === 3 && n.textContent.trim()) ?? host.lastChild
  if (node && node.nodeType === 3 && node.textContent.trimEnd().endsWith('.')) {
    node.textContent = node.textContent.trimEnd().slice(0, -1)
    const dot = document.createElement('span')
    dot.className = 'beat'
    dot.setAttribute('aria-hidden', 'true')
    host.append(dot)
    return dot
  }
  return null
}

function fontsReady() {
  return Promise.race([document.fonts.ready, new Promise((r) => setTimeout(r, 1500))])
}

// --- feature showcase ----------------------------------------------------------------------

const panels = $$('[data-panel]')
const rails = $$('[data-rail]')
const stepNum = $('[data-step-num]')
let step = -1
let panelSplits = []

function showStep(i, immediate = false) {
  if (i === step) return
  const prev = step
  step = i
  stepNum.textContent = String(i + 1).padStart(2, '0')
  rails.forEach((r, k) => r.classList.toggle('on', k === i))
  const dir = i > prev ? 1 : -1
  panels.forEach((p, k) => {
    if (k === i) return
    gsap.to(p, { autoAlpha: 0, y: -24 * dir, duration: immediate ? 0 : 0.3, ease: 'power2.in', overwrite: 'auto' })
  })
  const panel = panels[i]
  const split = panelSplits[i]
  gsap.set(panel, { autoAlpha: 1, y: 0, overwrite: 'auto' })
  if (immediate || !split) return
  gsap.fromTo(split.lines, { yPercent: 105 * dir }, { yPercent: 0, duration: 0.9, stagger: 0.07, ease: 'expo.out', delay: 0.12, overwrite: 'auto' })
  gsap.fromTo(
    $$('.kicker, .body, .keys, .legend', panel),
    { autoAlpha: 0, y: 18 * dir },
    { autoAlpha: 1, y: 0, duration: 0.7, stagger: 0.05, ease: 'power3.out', delay: 0.22, overwrite: 'auto' },
  )
}

function setupShowcase() {
  if (reduced) {
    // No pinning: each panel switches the formation when it reaches the middle of the screen.
    panels.forEach((panel, i) =>
      ScrollTrigger.create({
        trigger: panel,
        start: 'top 60%',
        end: 'bottom 40%',
        onToggle: (self) => self.isActive && field?.setProgress(i + 1),
        onLeaveBack: () => i === 0 && field?.setProgress(0),
      }),
    )
    return
  }
  panelSplits = panels.map((p) => SplitText.create($('.title', p), { type: 'lines', mask: 'lines' }))
  showStep(0, true)
  ScrollTrigger.create({
    trigger: '.showcase',
    start: 'top top',
    end: '+=400%',
    pin: '[data-stage]',
    onUpdate(self) {
      const q = self.progress * 4
      const i = Math.min(3, Math.floor(q))
      const f = Math.min(1, q - i)
      field?.setProgress(i + Math.min(1, f / 0.4))
      rails.forEach((r, k) => r.firstElementChild.style.setProperty('--p', k < i ? 1 : k === i ? f : 0))
      showStep(i)
    },
  })
}

// Fade the field out as the story slides over it, then stop rendering.
function setupFieldFade() {
  ScrollTrigger.create({
    trigger: '.story',
    start: 'top bottom',
    end: 'top top',
    onUpdate(self) {
      canvas.style.opacity = String(1 - self.progress)
      field?.setRunning(self.progress < 1)
    },
  })
}

// --- story: one day, three moments -----------------------------------------------------------

const DAY_START = 8 * 60
const DAY_END = 18 * 60
const hm = (h, m) => h * 60 + m
const segments = [
  { lane: 0, from: hm(9, 12), to: hm(11, 40), c: 'var(--dev)' },
  { lane: 0, from: hm(11, 40), to: hm(12, 18), hatch: true },
  { lane: 0, from: hm(12, 18), to: hm(15, 5), c: 'var(--dev)' },
  { lane: 1, from: hm(13, 30), to: hm(14, 15), c: 'var(--meeting)' },
  { lane: 0, from: hm(15, 10), to: hm(17, 30), c: 'var(--review)' },
]
const pct = (m) => ((m - DAY_START) / (DAY_END - DAY_START)) * 100

const lanes = $('[data-lanes]')
const segEls = segments.map((s) => {
  const el = document.createElement('i')
  el.className = `seg lane-${s.lane}${s.hatch ? ' hatch' : ''}`
  el.style.left = `${pct(s.from)}%`
  el.style.width = `${pct(s.to) - pct(s.from)}%`
  if (s.c) el.style.setProperty('--c', s.c)
  lanes.append(el)
  return el
})
const now = document.createElement('i')
now.className = 'now'
lanes.append(now)
const hours = $('[data-hours]')
for (let h = 8; h <= 18; h += 2) {
  const span = document.createElement('span')
  span.textContent = `${String(h).padStart(2, '0')}:00`
  span.style.left = `${pct(h * 60)}%`
  hours.append(span)
}

const clock = $('[data-clock]')
const sum = $('[data-sum]')
const fmt = (m) => `${String(Math.floor(m / 60)).padStart(2, '0')}:${String(Math.round(m) % 60).padStart(2, '0')}`
const dur = (m) => `${Math.floor(m / 60)}:${String(Math.round(m) % 60).padStart(2, '0')}`

function setDay(minutes) {
  clock.textContent = fmt(minutes)
  now.style.left = `${pct(minutes)}%`
  let total = 0
  segments.forEach((s, i) => {
    const k = gsap.utils.clamp(0, 1, (minutes - s.from) / (s.to - s.from))
    segEls[i].style.transform = `scaleX(${k})`
    if (!s.hatch) total += k * (s.to - s.from)
  })
  sum.textContent = dur(total)
}

// Scroll position → time of day, with a hold on each moment.
const dayKeys = [
  [0, hm(8, 40)],
  [0.1, hm(9, 12)],
  [0.27, hm(9, 12)],
  [0.42, hm(11, 40)],
  [0.58, hm(11, 58)],
  [0.78, hm(17, 30)],
  [1, hm(17, 30)],
]
function dayAt(p) {
  for (let k = 1; k < dayKeys.length; k++) {
    const [p1, m1] = dayKeys[k]
    const [p0, m0] = dayKeys[k - 1]
    if (p <= p1) return m0 + (m1 - m0) * gsap.parseEase('power1.inOut')((p - p0) / (p1 - p0 || 1))
  }
  return dayKeys.at(-1)[1]
}

const moments = $$('[data-moment]')
const cards = $$('[data-card]')
const typed = $('[data-typed]')
let moment = -1
let momentSplits = []

function playMomentExtras(i) {
  if (i === 0) {
    const word = t['story.search']
    typed.textContent = ''
    gsap.to({ n: 0 }, {
      n: word.length,
      duration: 0.5,
      delay: 0.35,
      ease: 'steps(' + word.length + ')',
      onUpdate() {
        typed.textContent = word.slice(0, Math.round(this.targets()[0].n))
      },
    })
  }
  if (i === 2) {
    const num = $('[data-ado-num]')
    const dec = lang === 'de' ? ',' : '.'
    gsap.fromTo({ v: 6.25 }, { v: 6.25 }, {
      v: 8.5,
      duration: 1.1,
      delay: 0.3,
      ease: 'expo.out',
      onUpdate() {
        num.textContent = this.targets()[0].v.toFixed(2).replace('.', dec)
      },
    })
    gsap.fromTo('[data-ado-bar]', { scaleX: 0.735 }, { scaleX: 1, duration: 1.1, delay: 0.3, ease: 'expo.out' })
    gsap.fromTo('.ado-delta', { scale: 0.6, autoAlpha: 0 }, { scale: 1, autoAlpha: 1, duration: 0.9, delay: 0.45, ease: 'back.out(2.2)' })
  }
  segEls.forEach((el, k) => el.classList.toggle('booked', i === 2 && !segments[k].hatch))
}

function showMoment(i, immediate = false) {
  if (i === moment) return
  const prev = moment
  moment = i
  const dir = i > prev ? 1 : -1
  moments.forEach((m, k) => {
    if (k === i || !momentSplits[k]) return
    gsap.to(momentSplits[k].chars, { yPercent: -110 * dir, duration: 0.35, stagger: 0.012, ease: 'power2.in', overwrite: 'auto' })
    gsap.to($('.body', m), { autoAlpha: 0, duration: 0.25, overwrite: 'auto' })
    gsap.set(m, { autoAlpha: 0, delay: 0.36 })
  })
  cards.forEach((c, k) => {
    if (k === i) return
    gsap.to(c, { autoAlpha: 0, y: -40 * dir, rotateX: 14 * dir, scale: 0.94, duration: 0.4, ease: 'power2.in', overwrite: 'auto' })
  })
  const m = moments[i]
  gsap.killTweensOf(m)
  gsap.set(m, { autoAlpha: 1 })
  if (immediate) {
    gsap.set(momentSplits[i].chars, { yPercent: 0 })
    gsap.set(cards[i], { autoAlpha: 1 })
  } else {
    gsap.fromTo(
      momentSplits[i].chars,
      { yPercent: 110 * dir, '--wdth': 100, fontWeight: 300 },
      { yPercent: 0, '--wdth': 80, fontWeight: 780, duration: 1, stagger: 0.035, ease: 'expo.out', delay: 0.2, overwrite: 'auto' },
    )
    gsap.fromTo($('.body', m), { autoAlpha: 0, y: 16 }, { autoAlpha: 1, y: 0, duration: 0.7, delay: 0.45, ease: 'power3.out', overwrite: 'auto' })
    gsap.fromTo(
      cards[i],
      { autoAlpha: 0, y: 60 * dir, rotateX: -16 * dir, scale: 0.94 },
      { autoAlpha: 1, y: 0, rotateX: 0, scale: 1, duration: 1, delay: 0.25, ease: 'expo.out', overwrite: 'auto' },
    )
  }
  playMomentExtras(i)
}

function setupStory() {
  if (reduced) {
    setDay(hm(17, 30))
    typed.textContent = t['story.search']
    segEls.forEach((el, k) => el.classList.toggle('booked', !segments[k].hatch))
    return
  }
  momentSplits = moments.map((m) => SplitText.create($('.moment-title', m), { type: 'chars', mask: 'chars' }))
  setDay(dayKeys[0][1])
  showMoment(0, true)
  playMomentExtras(0)
  ScrollTrigger.create({
    trigger: '.story',
    start: 'top top',
    end: '+=300%',
    pin: '[data-story]',
    onUpdate(self) {
      const p = self.progress
      setDay(dayAt(p))
      showMoment(p < 0.35 ? 0 : p < 0.68 ? 1 : 2)
    },
  })
}

// --- look: the window tilts upright as it scrolls in --------------------------------------------

function setupLook() {
  if (reduced) return
  gsap.fromTo(
    '[data-window]',
    { rotateX: 26, scale: 0.86, y: 60 },
    { rotateX: 0, scale: 1, y: 0, ease: 'none', scrollTrigger: { trigger: '[data-look]', start: 'top 95%', end: 'top 30%', scrub: true } },
  )
  for (const el of $$('[data-float]')) {
    const d = Number(el.dataset.float)
    gsap.fromTo(
      el,
      { y: 140, rotate: 4 * d },
      { y: -60, rotate: -2 * d, ease: 'none', scrollTrigger: { trigger: '[data-look]', start: 'top bottom', end: 'bottom top', scrub: true } },
    )
  }
}

// --- page load: one orchestrated entrance ------------------------------------------------------

async function intro() {
  await Promise.all([fontsReady(), fieldReady])

  setupShowcase()
  setupStory()
  setupFieldFade()
  setupLook()

  if (reduced) {
    addBeat(beatLine)
    root.classList.add('ready')
    ScrollTrigger.refresh()
    return
  }

  const split = SplitText.create($$('.line', title), { type: 'words', mask: 'words', wordsClass: 'w' })
  for (const m of split.masks) m.classList.add('w-mask')
  title.classList.add('split')
  const lastWord = $$('.w', beatLine).at(-1)
  const dot = lastWord ? addBeat(lastWord) : addBeat(beatLine)
  const lede = SplitText.create($('[data-hero-lede]'), { type: 'lines', mask: 'lines' })

  gsap.set(split.words, { yPercent: 115, '--wdth': 100, fontWeight: 250 })
  gsap.set(lede.lines, { yPercent: 105 })
  gsap.set(['[data-hero-actions] > *', '[data-hero-live]', '[data-hero-meta]', '[data-nav]', '[data-hero-eyebrow]'], { autoAlpha: 0 })
  if (dot) gsap.set(dot, { scale: 0 })
  root.classList.add('ready')

  const tl = gsap.timeline({ defaults: { ease: 'expo.out' } })
  if (field) tl.add(field.intro(gsap, 2.8), 0)
  tl.fromTo('[data-hero-eyebrow]', { autoAlpha: 0, x: -12 }, { autoAlpha: 1, x: 0, duration: 0.9 }, 0.25)
    .to(split.words, { yPercent: 0, duration: 1.3, stagger: 0.075 }, 0.35)
    .to(split.words, { '--wdth': 82, fontWeight: 760, duration: 1.6, stagger: 0.075, ease: 'power3.out' }, 0.45)
    .to(lede.lines, { yPercent: 0, duration: 1.1, stagger: 0.08 }, 1.0)
    .fromTo('[data-hero-actions] > *', { autoAlpha: 0, y: 18, scale: 0.94 }, { autoAlpha: 1, y: 0, scale: 1, duration: 0.9, stagger: 0.08, ease: 'back.out(1.6)' }, 1.25)
    .fromTo('[data-hero-live]', { autoAlpha: 0, clipPath: 'inset(0 100% 0 0 round 20px)' }, { autoAlpha: 1, clipPath: 'inset(0 0% 0 0 round 20px)', duration: 1 }, 1.5)
    .fromTo('[data-nav]', { autoAlpha: 0, y: -14 }, { autoAlpha: 1, y: 0, duration: 1 }, 1.4)
    .to('[data-hero-meta]', { autoAlpha: 1, duration: 1 }, 1.7)
  if (dot) {
    // The dot lands on the beat and keeps the field's rhythm from then on.
    tl.to(dot, { scale: 1, duration: 0.7, ease: 'elastic.out(1.1, 0.45)' }, 1.55).call(
      () => {
        field?.beat()
        gsap.timeline({ repeat: -1 }).to(dot, { scale: 1.45, duration: 0.08, ease: 'power2.out' }).to(dot, { scale: 1, duration: 1.12, ease: 'expo.out' })
      },
      null,
      1.55,
    )
  }
  tl.call(() => ScrollTrigger.refresh(), null, 0.1)
}

intro()
