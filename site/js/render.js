// The live viewer: the committed scenery_engine.wasm (the byte-identical
// binary Typst loads as a plugin) driving a <canvas>. engine.js is the
// verified wasm bridge, scene.js is the structure; this file lazy-loads the
// engine when the section scrolls into view, re-invokes it whenever the
// camera moves, and paints the returned draw records.
//
// Paint math mirrors scenery/src/render.typ so the canvas matches the
// compiled plates: the five-stop specular sphere gradient (focal point at
// (35%, 30%) of the bounding box, radius 110% — i.e. focal (-0.3r, -0.4r),
// outer 2.2r), two-tone bonds darkened 10%, faces transparentized 55% with a
// 35%-darkened facet stroke, cell edges luma(120) at 0.7pt.
//
// The plate stays LIGHT in both site themes (same call as the PNG plates, and
// the .plate token itself stays light), so the atom art uses the same fixed
// colors as the compiled figures; only the plate background is re-read from
// the --plate token, and a repaint is triggered on any theme change.
//
// Failure of any kind (no WebAssembly, fetch error, engine error) leaves the
// static compiled plate <img> in place — nothing throws into the page.

import { SceneryEngine, makeCamera, project, projectScale } from "./engine.js";
import { buildScene } from "./scene.js";

(function () {
  "use strict";

  const canvas = document.getElementById("live-canvas");
  const fallback = document.getElementById("live-fallback");
  const statusEl = document.getElementById("live-status");
  const noteEl = document.getElementById("live-version");
  if (!canvas || !fallback) return;

  // ---- color helpers (sRGB approximations of Typst's mixes) ---------------
  const rgbOf = (hex) => [
    parseInt(hex.slice(1, 3), 16),
    parseInt(hex.slice(3, 5), 16),
    parseInt(hex.slice(5, 7), 16),
  ];
  const mixWhite = (c, f) => c.map((v) => Math.round(255 * f + v * (1 - f)));
  const darken = (c, f) => c.map((v) => Math.round(v * (1 - f)));
  const css = (c, a) =>
    a == null ? `rgb(${c[0]},${c[1]},${c[2]})` : `rgba(${c[0]},${c[1]},${c[2]},${a})`;
  const INK = [35, 39, 47]; // legend/triad ink on the always-light plate
  const CELL = [120, 120, 120]; // luma(120), wyckoff's cell-edge gray

  // ---- state ---------------------------------------------------------------
  const DEG = Math.PI / 180;
  const EL_MAX = 85 * DEG;
  const SPIN = 0.10; // rad/s idle spin — gentle
  let az = 25 * DEG, el = 15 * DEG; // wyckoff's default view (Plate I)
  let engine = null, scene = null, ctx = null;
  let live = false, visible = false, dragging = false, spin = true;
  let raf = 0, lastT = 0, resumeTimer = 0, last = null;
  const painted = { az: NaN, el: NaN, w: 0, h: 0, plate: "" };
  const reduced = window.matchMedia("(prefers-reduced-motion: reduce)");

  function fail(err) {
    try { console.warn("scenery live viewer: falling back to the static plate —", err); } catch (_) {}
    live = false;
    canvas.hidden = true;
    fallback.hidden = false;
    if (statusEl) statusEl.hidden = true;
    if (noteEl) noteEl.textContent =
      "The live engine could not start here, so this is the CI-built plate instead.";
  }

  // ---- lazy init on scroll into view ----------------------------------------
  let started = false;
  function start() {
    if (started) return;
    started = true;
    init().catch(fail); // init has its own try/catch; this is the belt to its braces
  }
  if ("IntersectionObserver" in window) {
    const io = new IntersectionObserver((entries) => {
      for (const en of entries) {
        visible = en.isIntersecting;
        if (visible) { start(); schedule(); }
      }
    }, { rootMargin: "200px" });
    io.observe(canvas.parentElement);
  } else {
    visible = true;
    start();
  }

  async function init() {
    try {
      if (typeof WebAssembly === "undefined") { fail("WebAssembly unavailable"); return; }
      if (statusEl) statusEl.hidden = false;
      engine = await SceneryEngine.load("assets/scenery_engine.wasm");
      scene = buildScene();
      // Prove the whole round trip before touching the page: if this throws,
      // the static plate never blinks.
      const recs = engine.sortScene(scene.prims, makeCamera(az, el), { bsp: true, cull: null });
      if (!Array.isArray(recs) || recs.length === 0) throw new Error("engine returned no records");
      ctx = canvas.getContext("2d");
      if (!ctx) throw new Error("no 2d context");
      live = true;
      canvas.hidden = false;
      fallback.hidden = true;
      if (statusEl) statusEl.hidden = true;
      if (noteEl) noteEl.textContent =
        "Running " + engine.version() + " in this tab — drag the plate to rotate.";
      hookInput();
      hookEnvironment();
      schedule();
    } catch (e) {
      fail(e);
    }
  }

  // ---- render loop: only re-sort when the camera (or canvas) changed --------
  function schedule() {
    if (live && !raf) raf = requestAnimationFrame(tick);
  }

  function tick(t) {
    raf = 0;
    if (!live) return;
    const dt = lastT ? Math.min((t - lastT) / 1000, 0.1) : 0;
    lastT = t;
    const spinning = spin && !dragging && visible && !reduced.matches;
    if (spinning) az += SPIN * dt;
    try { drawIfChanged(); } catch (e) { fail(e); return; }
    if (spinning) raf = requestAnimationFrame(tick);
    else lastT = 0;
  }

  function drawIfChanged() {
    const w = canvas.clientWidth, h = canvas.clientHeight;
    if (w === 0 || h === 0) return;
    const plate = getComputedStyle(document.documentElement)
      .getPropertyValue("--plate").trim() || "#ffffff";
    if (az === painted.az && el === painted.el && w === painted.w &&
        h === painted.h && plate === painted.plate) return;
    paint(w, h, plate);
    painted.az = az; painted.el = el; painted.w = w; painted.h = h; painted.plate = plate;
  }

  function paint(w, h, plate) {
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    const pw = Math.round(w * dpr), ph = Math.round(h * dpr);
    if (canvas.width !== pw || canvas.height !== ph) { canvas.width = pw; canvas.height = ph; }
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.fillStyle = plate;
    ctx.fillRect(0, 0, w, h);

    const cam = makeCamera(az, el);

    // wyckoff parity: push polyhedra faces back by 0.01 along the camera-forward
    // direction so face/bond depth ties resolve the same way the plates do.
    const gx = -Math.sin(az) * Math.cos(el);
    const gy = Math.cos(az) * Math.cos(el);
    const gz = Math.sin(el);
    for (const f of scene.faces) {
      scene.prims[f.i].pts = f.base.map((p) =>
        [p[0] - 0.01 * gx, p[1] - 0.01 * gy, p[2] - 0.01 * gz]);
    }

    // The wasm engine does the geometry: depth sort, sphere clipping, BSP splits.
    const records = engine.sortScene(scene.prims, cam, { bsp: true, cull: null });

    // Rotation-stable fit: scene.bound is a world-space bounding radius.
    const s = (Math.min(w, h) / 2 - 16) / scene.bound;
    const cx = w / 2, cy = h / 2;
    const px = (q) => cx + q.sx * s;
    const py = (q) => cy - q.sy * s; // scene +sy is up; canvas y grows down

    for (const rec of records) {
      const p = scene.prims[rec.i];
      const st = scene.styles[rec.i];
      if (p.k === "sphere") {
        const q = project(cam, p.c);
        drawBall(px(q), py(q), p.r * projectScale(cam, q.depth) * s, rgbOf(st.color));
      } else if (p.k === "seg") {
        const a = project(cam, rec.a || p.a);
        const b = project(cam, rec.b || p.b);
        const wd = p.w * projectScale(cam, (a.depth + b.depth) / 2) * s;
        ctx.beginPath();
        ctx.moveTo(px(a), py(a));
        ctx.lineTo(px(b), py(b));
        ctx.lineCap = "round";
        ctx.lineWidth = wd;
        ctx.strokeStyle = css(darken(rgbOf(st.color), 0.10)); // two-tone halves, darkened 10%
        ctx.stroke();
      } else if (p.k === "edge") {
        const a = project(cam, rec.a || p.a);
        const b = project(cam, rec.b || p.b);
        ctx.beginPath();
        ctx.moveTo(px(a), py(a));
        ctx.lineTo(px(b), py(b));
        ctx.lineCap = "butt";
        ctx.lineWidth = 0.9; // 0.7pt
        ctx.strokeStyle = css(CELL);
        ctx.stroke();
      } else if (p.k === "face") {
        const pts = (rec.pts || p.pts).map((v) => project(cam, v));
        const col = rgbOf(st.color);
        ctx.beginPath();
        ctx.moveTo(px(pts[0]), py(pts[0]));
        for (let i = 1; i < pts.length; i++) ctx.lineTo(px(pts[i]), py(pts[i]));
        ctx.closePath();
        ctx.fillStyle = css(col, 0.45); // transparentize(55%)
        ctx.fill();
        ctx.lineWidth = 0.7;
        ctx.lineCap = "butt";
        ctx.strokeStyle = css(darken(col, 0.35));
        ctx.stroke();
      }
      // (no arrows or labels in this scene)
    }

    drawLegend(w);
    drawTriad(cam, h);
  }

  // The exact five-stop specular gradient of scenery's _sphere-gradient:
  // focal at (-0.3r, -0.4r) from the centre, outer radius 2.2r.
  function drawBall(x, y, r, col) {
    const fx = x - 0.3 * r, fy = y - 0.4 * r;
    const g = ctx.createRadialGradient(fx, fy, 0, fx, fy, 2.2 * r);
    g.addColorStop(0.00, css(mixWhite(col, 0.92)));
    g.addColorStop(0.12, css(mixWhite(col, 0.70)));
    g.addColorStop(0.30, css(mixWhite(col, 0.25)));
    g.addColorStop(0.58, css(col));
    g.addColorStop(1.00, css(darken(col, 0.35)));
    ctx.beginPath();
    ctx.arc(x, y, r, 0, 2 * Math.PI);
    ctx.fillStyle = g;
    ctx.fill();
    ctx.lineWidth = 0.7; // 0.5pt outline
    ctx.strokeStyle = css(darken(col, 0.40));
    ctx.stroke();
  }

  function serifFont(px) {
    const fam = getComputedStyle(document.documentElement)
      .getPropertyValue("--serif").trim() || "serif";
    return px + "px " + fam;
  }

  function drawLegend(w) {
    const x = w - 58;
    let y = 30;
    ctx.font = serifFont(14);
    ctx.textBaseline = "middle";
    ctx.textAlign = "left";
    for (const item of scene.legend) {
      drawBall(x, y, 8, rgbOf(item.color));
      ctx.fillStyle = css(INK);
      ctx.fillText(item.label, x + 15, y + 1);
      y += 26;
    }
  }

  // The a/b/c axes triad, bottom-left — projected live so it turns with the
  // scene. Axes pointing nearly into the screen are skipped.
  function drawTriad(cam, h) {
    const ox = 34, oy = h - 32, L = 22;
    const axes = [["a", [1, 0, 0]], ["b", [0, 1, 0]], ["c", [0, 0, 1]]];
    ctx.font = "italic " + serifFont(13);
    ctx.textAlign = "center";
    ctx.textBaseline = "middle";
    for (const [name, v] of axes) {
      const q = project(cam, v);
      const len = Math.hypot(q.sx, q.sy);
      if (len < 0.2) continue;
      const dx = (q.sx / len) * L, dy = (-q.sy / len) * L;
      ctx.beginPath();
      ctx.moveTo(ox, oy);
      ctx.lineTo(ox + dx, oy + dy);
      ctx.lineWidth = 1.1;
      ctx.lineCap = "round";
      ctx.strokeStyle = css(INK);
      ctx.stroke();
      // small arrowhead
      const ang = Math.atan2(dy, dx);
      ctx.beginPath();
      ctx.moveTo(ox + dx, oy + dy);
      ctx.lineTo(ox + dx - 5 * Math.cos(ang - 0.42), oy + dy - 5 * Math.sin(ang - 0.42));
      ctx.moveTo(ox + dx, oy + dy);
      ctx.lineTo(ox + dx - 5 * Math.cos(ang + 0.42), oy + dy - 5 * Math.sin(ang + 0.42));
      ctx.stroke();
      ctx.fillStyle = css(INK);
      ctx.fillText(name, ox + dx * 1.45, oy + dy * 1.45);
    }
  }

  // ---- interaction: pointer drag rotates; idle auto-spin pauses -------------
  function hookInput() {
    canvas.addEventListener("pointerdown", (e) => {
      if (!e.isPrimary) return;
      dragging = true;
      spin = false;
      clearTimeout(resumeTimer);
      last = [e.clientX, e.clientY];
      try { canvas.setPointerCapture(e.pointerId); } catch (_) {}
      canvas.classList.add("dragging");
    });
    canvas.addEventListener("pointermove", (e) => {
      if (!dragging || !last) return;
      const dx = e.clientX - last[0];
      const dy = e.clientY - last[1];
      last = [e.clientX, e.clientY];
      az += dx * 0.008;
      el = Math.max(-EL_MAX, Math.min(EL_MAX, el + dy * 0.008));
      schedule();
    });
    const release = () => {
      if (!dragging) return;
      dragging = false;
      last = null;
      canvas.classList.remove("dragging");
      // resume the idle spin a moment after the hand lets go
      clearTimeout(resumeTimer);
      resumeTimer = setTimeout(() => { spin = true; lastT = 0; schedule(); }, 3000);
    };
    canvas.addEventListener("pointerup", release);
    canvas.addEventListener("pointercancel", release);
    canvas.addEventListener("lostpointercapture", release);
  }

  // ---- environment: repaint on resize / theme change / motion pref ----------
  function hookEnvironment() {
    if ("ResizeObserver" in window) {
      new ResizeObserver(() => schedule()).observe(canvas);
    } else {
      window.addEventListener("resize", () => schedule());
    }
    // theme toggle stamps data-theme on <html>; the system scheme can flip too
    new MutationObserver(() => schedule())
      .observe(document.documentElement, { attributes: true, attributeFilter: ["data-theme"] });
    const dark = window.matchMedia("(prefers-color-scheme: dark)");
    if (dark.addEventListener) dark.addEventListener("change", () => schedule());
    if (reduced.addEventListener) reduced.addEventListener("change", () => { lastT = 0; schedule(); });
  }
})();
