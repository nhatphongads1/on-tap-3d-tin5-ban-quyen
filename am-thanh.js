/* Âm thanh nền cho khuôn viên 3D: tiếng nước chảy, chim hót (ban ngày), dế kêu (ban đêm), nhạc nhẹ.
   Toàn bộ được tạo bằng mã (Web Audio API), không dùng tệp âm thanh bên ngoài, nên không vướng bản quyền.
   Trình duyệt chỉ cho phát tiếng sau khi người dùng bấm vào trang một lần. */
(function () {
  'use strict';
  var AC = window.AudioContext || window.webkitAudioContext;
  var KEY = 'ontap3d_amthanh';
  var want = true;
  try { if (localStorage.getItem(KEY) === 'tat') want = false; } catch (e) {}
  var ctx = null, master, musicBus, waterBus, birdBus, cricketBus, started = false, speaking = 0, duckTimer = 0;
  var lakeX = -12, lakeZ = 5;

  function rnd(a, b) { return a + Math.random() * (b - a); }
  function clamp(x, a, b) { return Math.min(b, Math.max(a, x)); }
  function hz(m) { return 440 * Math.pow(2, (m - 69) / 12); }
  function now() { return ctx.currentTime; }
  function smooth(node, v, tc) { try { node.gain.setTargetAtTime(v, now(), tc || 0.6); } catch (e) {} }

  function noise(sec, brown) {
    var n = Math.floor(ctx.sampleRate * sec), b = ctx.createBuffer(1, n, ctx.sampleRate), d = b.getChannelData(0), last = 0;
    for (var i = 0; i < n; i++) {
      var w = Math.random() * 2 - 1;
      if (brown) { last = (last + 0.02 * w) / 1.02; d[i] = last * 3.5; } else d[i] = w;
    }
    return b;
  }
  function panner(p) {
    if (!ctx.createStereoPanner) return null;
    var s = ctx.createStereoPanner(); s.pan.value = p; return s;
  }

  /* ---------- tiếng nước ---------- */
  function buildWater() {
    waterBus = ctx.createGain(); waterBus.gain.value = 0.0; waterBus.connect(master);
    var white = ctx.createBufferSource(); white.buffer = noise(3, false); white.loop = true;
    var hp = ctx.createBiquadFilter(); hp.type = 'highpass'; hp.frequency.value = 450;
    var bp = ctx.createBiquadFilter(); bp.type = 'bandpass'; bp.frequency.value = 1300; bp.Q.value = 0.7;
    var g1 = ctx.createGain(); g1.gain.value = 0.32;
    white.connect(hp); hp.connect(bp); bp.connect(g1); g1.connect(waterBus);
    var lfo = ctx.createOscillator(); lfo.frequency.value = 0.19;
    var depth = ctx.createGain(); depth.gain.value = 420; lfo.connect(depth); depth.connect(bp.frequency);
    var lfo2 = ctx.createOscillator(); lfo2.frequency.value = 0.37;
    var d2 = ctx.createGain(); d2.gain.value = 0.1; lfo2.connect(d2); d2.connect(g1.gain);
    var brown = ctx.createBufferSource(); brown.buffer = noise(4, true); brown.loop = true;
    var lp = ctx.createBiquadFilter(); lp.type = 'lowpass'; lp.frequency.value = 380;
    var g2 = ctx.createGain(); g2.gain.value = 0.55;
    brown.connect(lp); lp.connect(g2); g2.connect(waterBus);
    white.start(); brown.start(); lfo.start(); lfo2.start();
    (function bubble() {
      if (!ctx) return;
      if (ctx.state === 'running') {
        var t = now(), o = ctx.createOscillator(), g = ctx.createGain(), f = rnd(700, 2300);
        o.type = 'sine'; o.frequency.setValueAtTime(f, t); o.frequency.exponentialRampToValueAtTime(f * rnd(1.3, 1.9), t + 0.06);
        g.gain.setValueAtTime(0.0001, t); g.gain.exponentialRampToValueAtTime(rnd(0.02, 0.05), t + 0.01); g.gain.exponentialRampToValueAtTime(0.0001, t + 0.09);
        o.connect(g); g.connect(waterBus); o.start(t); o.stop(t + 0.12);
      }
      setTimeout(bubble, rnd(120, 650));
    })();
  }

  /* ---------- chim hót ---------- */
  function note(t, f0, f1, dur, peak, vib, pan) {
    var o = ctx.createOscillator(), g = ctx.createGain(), pn = panner(pan);
    o.type = 'sine'; o.frequency.setValueAtTime(f0, t); o.frequency.exponentialRampToValueAtTime(Math.max(60, f1), t + dur);
    if (vib) {
      var v = ctx.createOscillator(), vg = ctx.createGain(); v.frequency.value = vib.rate; vg.gain.value = vib.depth;
      v.connect(vg); vg.connect(o.frequency); v.start(t); v.stop(t + dur + 0.05);
    }
    g.gain.setValueAtTime(0.0001, t); g.gain.exponentialRampToValueAtTime(peak, t + 0.008); g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    o.connect(g); if (pn) { g.connect(pn); pn.connect(birdBus); } else g.connect(birdBus);
    o.start(t); o.stop(t + dur + 0.05);
  }
  function birdPhrase() {
    var t = now() + 0.05, pan = rnd(-0.8, 0.8), kind = Math.random(), i, k;
    if (kind < 0.35) {            // tít-tít lên cao
      k = 2 + Math.floor(Math.random() * 3); var b = rnd(2600, 3400);
      for (i = 0; i < k; i++) note(t + i * 0.13, b, b * 1.3, 0.08, 0.5, null, pan);
    } else if (kind < 0.65) {     // líu lo rung
      k = 4 + Math.floor(Math.random() * 5); var s = rnd(3800, 4600);
      for (i = 0; i < k; i++) note(t + i * 0.06, s - i * 90, s - i * 90 - 700, 0.05, 0.4, { rate: 28, depth: 160 }, pan);
    } else if (kind < 0.92) {     // huýt hai nốt
      var a = rnd(2000, 2500);
      note(t, a, a * 0.75, 0.22, 0.5, null, pan);
      note(t + 0.26, a * 0.75, a * 1.15, 0.17, 0.5, null, pan);
    } else {                      // cu cu trầm
      note(t, 720, 620, 0.22, 0.6, null, pan); note(t + 0.32, 700, 600, 0.24, 0.55, null, pan);
    }
  }
  function buildBirds() {
    birdBus = ctx.createGain(); birdBus.gain.value = 0.0; birdBus.connect(master);
    (function loop() {
      if (!ctx) return;
      if (ctx.state === 'running' && birdBus.gain.value > 0.02) { birdPhrase(); if (Math.random() < 0.3) setTimeout(function () { if (ctx && ctx.state === 'running') birdPhrase(); }, rnd(250, 900)); }
      setTimeout(loop, rnd(1800, 5200));
    })();
  }

  /* ---------- dế đêm ---------- */
  function buildCrickets() {
    cricketBus = ctx.createGain(); cricketBus.gain.value = 0.0; cricketBus.connect(master);
    function voice(freq, rate, chop, pan) {
      var car = ctx.createOscillator(); car.type = 'sine'; car.frequency.value = freq;
      var amp = ctx.createGain(); amp.gain.value = 0.5;
      var l1 = ctx.createOscillator(); l1.type = 'square'; l1.frequency.value = rate;
      var d1 = ctx.createGain(); d1.gain.value = 0.5; l1.connect(d1); d1.connect(amp.gain);
      var grp = ctx.createGain(); grp.gain.value = 0.5;
      var l2 = ctx.createOscillator(); l2.type = 'square'; l2.frequency.value = chop;
      var d2 = ctx.createGain(); d2.gain.value = 0.5; l2.connect(d2); d2.connect(grp.gain);
      var out = ctx.createGain(); out.gain.value = 0.05;
      car.connect(amp); amp.connect(grp); grp.connect(out);
      var pn = panner(pan); if (pn) { out.connect(pn); pn.connect(cricketBus); } else out.connect(cricketBus);
      car.start(); l1.start(); l2.start();
    }
    voice(4300, 38, 1.1, -0.6); voice(4800, 44, 0.8, 0.6);
  }

  /* ---------- nhạc nhẹ ---------- */
  function buildMusic() {
    musicBus = ctx.createGain(); musicBus.gain.value = 0.55; musicBus.connect(master);
    var dly = ctx.createDelay(1.0); dly.delayTime.value = 0.42;
    var fb = ctx.createGain(); fb.gain.value = 0.36;
    var dlp = ctx.createBiquadFilter(); dlp.type = 'lowpass'; dlp.frequency.value = 2400;
    var wet = ctx.createGain(); wet.gain.value = 0.5;
    dly.connect(dlp); dlp.connect(fb); fb.connect(dly); dlp.connect(wet); wet.connect(musicBus);
    var padLp = ctx.createBiquadFilter(); padLp.type = 'lowpass'; padLp.frequency.value = 900; padLp.connect(musicBus);
    var chords = [[48, 55, 62], [45, 52, 60], [41, 48, 57], [43, 50, 59]], ci = 0;
    function chord() {
      if (!ctx) return;
      if (ctx.state === 'running') {
        var t = now(), c = chords[ci++ % chords.length];
        c.forEach(function (m, i) {
          var o = ctx.createOscillator(), g = ctx.createGain();
          o.type = i === 0 ? 'triangle' : 'sine'; o.frequency.value = hz(m); o.detune.value = rnd(-6, 6);
          g.gain.setValueAtTime(0.0001, t); g.gain.linearRampToValueAtTime(0.05, t + 2.6); g.gain.linearRampToValueAtTime(0.0001, t + 8.6);
          o.connect(g); g.connect(padLp); o.start(t); o.stop(t + 9);
        });
      }
      setTimeout(chord, 8000);
    }
    var pent = [0, 2, 4, 7, 9];
    function pluck() {
      if (!ctx) return;
      if (ctx.state === 'running' && Math.random() < 0.65) {
        var t = now(), m = 60 + pent[Math.floor(Math.random() * 5)] + (Math.random() < 0.4 ? 12 : 0);
        var o = ctx.createOscillator(), g = ctx.createGain();
        o.type = 'triangle'; o.frequency.value = hz(m);
        g.gain.setValueAtTime(0.0001, t); g.gain.exponentialRampToValueAtTime(0.07, t + 0.012); g.gain.exponentialRampToValueAtTime(0.0001, t + 2.0);
        o.connect(g); g.connect(musicBus); g.connect(dly); o.start(t); o.stop(t + 2.1);
      }
      setTimeout(pluck, rnd(900, 2000));
    }
    chord(); setTimeout(pluck, 1200);
  }

  /* ---------- điều chỉnh theo cảnh ---------- */
  function tune() {
    if (!ctx || !started) return;
    /* trò chơi công bố giờ (tv), mùa tuyết (winter) và vị trí nhân vật qua window.__gs mỗi khung hình */
    var gs = window.__gs || {};
    var night = typeof gs.tv === 'number' ? clamp(gs.tv - 0.35, 0, 1) : 0;
    var wk = typeof gs.winter === 'number' ? clamp(gs.winter, 0, 1) : 0;
    smooth(birdBus, 0.9 * (1 - night) * (1 - 0.8 * wk), 1.0);
    smooth(cricketBus, 0.8 * night * (1 - wk), 1.0);
    var wv = 0.45;
    if (typeof gs.x === 'number') { var d = Math.hypot(gs.x - lakeX, gs.z - lakeZ); wv = 0.2 + 0.8 * clamp(1 - (d - 6) / 30, 0, 1); }
    smooth(waterBus, wv * (1 - 0.5 * wk), 0.8);
  }
  function duck(delta) {
    speaking = Math.max(0, speaking + delta);
    clearTimeout(duckTimer);
    if (speaking > 0) duckTimer = setTimeout(function () { speaking = 0; applyDuck(); }, 20000);
    applyDuck();
  }
  function applyDuck() { if (musicBus) smooth(musicBus, speaking > 0 ? 0.12 : 0.55, 0.2); if (waterBus && speaking > 0) { /* giữ nguyên */ } }

  /* ---------- khởi động và nút bật/tắt ---------- */
  function build() {
    ctx = new AC();
    master = ctx.createGain(); master.gain.value = 0; master.connect(ctx.destination);
    buildWater(); buildBirds(); buildCrickets(); buildMusic();
    started = true; setInterval(tune, 500); tune();
  }
  function setBtn() {
    var b = document.getElementById('bSound'); if (!b) return;
    b.textContent = 'Âm thanh: ' + (want ? 'Bật' : 'Tắt');
    b.classList.toggle('on', want); b.setAttribute('aria-pressed', want ? 'true' : 'false');
  }
  function apply() {
    if (!ctx) return;
    if (want) { ctx.resume(); smooth(master, 0.85, 0.5); } else { smooth(master, 0, 0.2); setTimeout(function () { if (!want && ctx) ctx.suspend(); }, 900); }
  }
  function start() {
    if (!AC || !want) return;
    if (!ctx) { try { build(); } catch (e) { return; } }
    apply();
  }
  function init() {
    var b = document.getElementById('bSound');
    if (!AC) { if (b) b.hidden = true; return; }
    setBtn();
    if (b) b.addEventListener('click', function () {
      want = !want; try { localStorage.setItem(KEY, want ? 'bat' : 'tat'); } catch (e) {}
      setBtn();
      if (want) start(); else apply();
    });
    ['pointerdown', 'keydown', 'touchstart'].forEach(function (ev) {
      window.addEventListener(ev, function once() { window.removeEventListener(ev, once, true); start(); }, true);
    });
    document.addEventListener('visibilitychange', function () {
      if (!ctx) return;
      if (document.hidden) ctx.suspend(); else if (want) ctx.resume();
    });
    if (window.speechSynthesis && window.speechSynthesis.speak) {
      var os = window.speechSynthesis.speak.bind(window.speechSynthesis);
      window.speechSynthesis.speak = function (u) {
        try { duck(1); var done = function () { duck(-1); }; u.addEventListener('end', done); u.addEventListener('error', done); } catch (e) {}
        return os(u);
      };
    }
    window.AmThanh = { trangThai: function () { var r = function (n) { return n ? Math.round(n.gain.value * 1000) / 1000 : null; }; return { ctx: ctx ? ctx.state : null, bat: want, master: r(master), nuoc: r(waterBus), chim: r(birdBus), de: r(cricketBus), nhac: r(musicBus) }; } };
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init); else init();
})();
