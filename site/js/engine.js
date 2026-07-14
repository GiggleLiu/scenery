// scenery-engine in the browser.
//
// The very same `scenery_engine.wasm` that Typst loads as a plugin, driven here
// from JavaScript. It speaks the `wasm-minimal-protocol` ABI (byte buffers in,
// byte buffers out) over CBOR: we hand it a scene + camera and it returns the
// primitives in back-to-front draw order, with translucent faces BSP-split and
// segments clipped behind spheres — all the hard geometry, computed in wasm.
//
// This file is the mechanical bridge only: protocol host, a tiny CBOR codec for
// exactly the shapes the engine's schema uses, and the projection mirror of
// `scenery/src/camera.typ`. Drawing lives in render.js.

// ---------------------------------------------------------------------------
// Minimal CBOR — just the subset the engine's schema needs: f64 numbers,
// integers, text keys, arrays, maps, bool, null. (No bignums, tags, or
// indefinite lengths.)
// ---------------------------------------------------------------------------
const CBOR = {
  encode(value) {
    const bytes = [];
    const push = (...b) => bytes.push(...b);
    const u8 = new Uint8Array(8);
    const dv = new DataView(u8.buffer);

    const head = (major, n) => {
      const mt = major << 5;
      if (n < 24) push(mt | n);
      else if (n < 0x100) push(mt | 24, n);
      else if (n < 0x10000) push(mt | 25, n >> 8, n & 0xff);
      else push(mt | 26, (n >>> 24) & 0xff, (n >> 16) & 0xff, (n >> 8) & 0xff, n & 0xff);
    };

    const enc = (v) => {
      if (v === null || v === undefined) { push(0xf6); return; }
      if (v === true) { push(0xf5); return; }
      if (v === false) { push(0xf4); return; }
      if (typeof v === "number") {
        // Integers that fit go out as CBOR ints; everything else as f64. The
        // engine accepts f64 for its float fields either way, but ints keep
        // small values compact and unambiguous.
        if (Number.isInteger(v) && v >= 0 && v < 0x100000000) { head(0, v); return; }
        if (Number.isInteger(v) && v < 0 && v >= -0x100000000) { head(1, -v - 1); return; }
        push(0xfb); dv.setFloat64(0, v, false); for (let i = 0; i < 8; i++) push(u8[i]); return;
      }
      if (typeof v === "string") {
        const s = new TextEncoder().encode(v);
        head(3, s.length); push(...s); return;
      }
      if (Array.isArray(v)) {
        head(4, v.length); for (const e of v) enc(e); return;
      }
      if (typeof v === "object") {
        const keys = Object.keys(v);
        head(5, keys.length);
        for (const k of keys) { enc(k); enc(v[k]); }
        return;
      }
      throw new Error("CBOR: cannot encode " + typeof v);
    };
    enc(value);
    return new Uint8Array(bytes);
  },

  decode(bytes) {
    const dv = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
    let pos = 0;
    const readHead = () => {
      const b = dv.getUint8(pos++); const major = b >> 5; const info = b & 0x1f;
      let n;
      if (info < 24) n = info;
      else if (info === 24) n = dv.getUint8(pos++);
      else if (info === 25) { n = dv.getUint16(pos, false); pos += 2; }
      else if (info === 26) { n = dv.getUint32(pos, false); pos += 4; }
      else if (info === 27) { n = Number(dv.getBigUint64(pos, false)); pos += 8; }
      else n = info;
      return { major, info, n };
    };
    const read = () => {
      const { major, info, n } = readHead();
      switch (major) {
        case 0: return n;
        case 1: return -n - 1;
        case 3: { const s = new TextDecoder().decode(new Uint8Array(bytes.buffer, bytes.byteOffset + pos, n)); pos += n; return s; }
        case 4: { const a = []; for (let i = 0; i < n; i++) a.push(read()); return a; }
        case 5: { const o = {}; for (let i = 0; i < n; i++) { const k = read(); o[k] = read(); } return o; }
        case 7:
          if (info === 20) return false;
          if (info === 21) return true;
          if (info === 22 || info === 23) return null;
          if (info === 25) { const f = getFloat16(dv, pos - 2); return f; }
          if (info === 26) { const f = dv.getFloat32(pos - 4, false); return f; }
          if (info === 27) { const f = dv.getFloat64(pos - 8, false); return f; }
          return null;
        default: throw new Error("CBOR: unsupported major " + major);
      }
    };
    return read();
  },
};

function getFloat16(dv, offset) {
  const h = dv.getUint16(offset, false);
  const sign = (h & 0x8000) ? -1 : 1;
  const exp = (h >> 10) & 0x1f;
  const frac = h & 0x3ff;
  if (exp === 0) return sign * Math.pow(2, -14) * (frac / 1024);
  if (exp === 31) return frac ? NaN : sign * Infinity;
  return sign * Math.pow(2, exp - 15) * (1 + frac / 1024);
}

// ---------------------------------------------------------------------------
// wasm-minimal-protocol host. Each exported function takes the byte-lengths of
// its arguments and returns 0 (ok) or 1 (error); the payload travels through
// the two `typst_env` callbacks. See the ABI in scenery-engine's wasm imports.
// ---------------------------------------------------------------------------
class SceneryEngine {
  constructor(instance) {
    this.instance = instance;
    this.exports = instance.exports;
    this._args = null;   // Uint8Array staged for write_args_to_buffer
    this._result = null; // Uint8Array captured from send_result_to_host
  }

  static _imports(holder) {
    return {
      typst_env: {
        wasm_minimal_protocol_write_args_to_buffer(ptr) {
          const e = holder.engine;
          new Uint8Array(e.exports.memory.buffer, ptr, e._args.length).set(e._args);
        },
        wasm_minimal_protocol_send_result_to_host(ptr, len) {
          const e = holder.engine;
          e._result = new Uint8Array(e.exports.memory.buffer, ptr, len).slice();
        },
      },
    };
  }

  // Instantiate from raw bytes (ArrayBuffer / TypedArray). Host-agnostic — used
  // by load() and by the node smoke test.
  static async fromBytes(bytes) {
    const holder = {};
    const { instance } = await WebAssembly.instantiate(bytes, SceneryEngine._imports(holder));
    holder.engine = new SceneryEngine(instance);
    return holder.engine;
  }

  static async load(url) {
    const holder = {};
    const imports = SceneryEngine._imports(holder);
    let instance;
    if (typeof WebAssembly.instantiateStreaming === "function") {
      try {
        ({ instance } = await WebAssembly.instantiateStreaming(fetch(url), imports));
      } catch (_) {
        const buf = await (await fetch(url)).arrayBuffer();
        ({ instance } = await WebAssembly.instantiate(buf, imports));
      }
    } else {
      const buf = await (await fetch(url)).arrayBuffer();
      ({ instance } = await WebAssembly.instantiate(buf, imports));
    }
    holder.engine = new SceneryEngine(instance);
    return holder.engine;
  }

  _call(name, ...argBufs) {
    const total = argBufs.reduce((n, a) => n + a.length, 0);
    const merged = new Uint8Array(total);
    let off = 0;
    for (const a of argBufs) { merged.set(a, off); off += a.length; }
    this._args = merged;
    this._result = null;
    const code = this.exports[name](...argBufs.map((a) => a.length));
    const result = this._result;
    this._args = null; this._result = null;
    if (code !== 0) throw new Error("scenery-engine: " + new TextDecoder().decode(result || new Uint8Array()));
    return result || new Uint8Array();
  }

  version() {
    return new TextDecoder().decode(this._call("version"));
  }

  // prims: [{k, ...}], camera: see makeCamera(), opts: {bsp, cull}
  // Returns the OutRec array: [{i, d, a?, b?, head?, pts?}, ...] in draw order.
  sortScene(prims, camera, opts = {}) {
    const request = {
      camera,
      bsp: opts.bsp ?? false,
      cull: opts.cull ?? null,
      prims,
    };
    return CBOR.decode(this._call("sort_scene", CBOR.encode(request)));
  }
}

// ---------------------------------------------------------------------------
// Camera + projection — the exact mirror of scenery/src/camera.typ (and
// scenery-engine/src/camera.rs). Trig is precomputed into cos/sin coefficients,
// which is also exactly what crosses the CBOR boundary.
// ---------------------------------------------------------------------------
function makeCamera(azimuthRad, elevationRad, distance = null) {
  const c = {
    "cos-az": Math.cos(azimuthRad),
    "sin-az": Math.sin(azimuthRad),
    "cos-el": Math.cos(elevationRad),
    "sin-el": Math.sin(elevationRad),
  };
  if (distance != null) return { mode: "perspective", ...c, distance };
  return { mode: "orthographic", ...c };
}

function projectScale(camera, depth) {
  if (camera.mode === "perspective") {
    const d = camera.distance;
    return d / (d - depth);
  }
  return 1.0;
}

// world [x,y,z] -> {sx, sy, depth}
function project(camera, p) {
  const [x, y, z] = p;
  if (camera.mode === "2d") return { sx: x, sy: y, depth: 0.0 };
  const ca = camera["cos-az"], sa = camera["sin-az"], ce = camera["cos-el"], se = camera["sin-el"];
  const x1 = x * ca + y * sa;
  const y1 = -x * sa + y * ca;
  let sx = x1;
  let sy = -y1 * se + z * ce;
  const depth = y1 * ce + z * se;
  if (camera.mode === "perspective") {
    const s = projectScale(camera, depth);
    sx *= s; sy *= s;
  }
  return { sx, sy, depth };
}

export { SceneryEngine, CBOR, makeCamera, project, projectScale };
