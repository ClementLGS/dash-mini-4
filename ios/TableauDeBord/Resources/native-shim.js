/* Pont « window.Native » pour iPad (WKWebView). Injecté au démarrage de la page, avant son propre code.
   Même interface que le pont Java de l'appli Android. Les appels qui doivent répondre tout de suite
   (cfgGet, battery, bleAvailable, sha256Hex…) sont servis sans aller-retour : état injecté par l'appli
   (mis à jour par window.__tdbState) et SHA-256 / HMAC calculés ici. Le reste passe par
   webkit.messageHandlers.native et la réponse revient par window.__nat(id, statut, corps, erreur). ES5. */
(function () {
  "use strict";
  if (window.Native) { return; }
  var ST = __STATE__;
  var mh = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.native;
  function post(m, a) { try { mh.postMessage({ m: m, a: a }); } catch (e) { } }
  function late(id, err) { setTimeout(function () { if (window.__nat) { window.__nat(id, 0, "", err); } }, 0); }

  /* ---- SHA-256 et HMAC-SHA-256 (octets -> octets) ---- */
  var K = [0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da, 0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2];
  function rotr(x, n) { return (x >>> n) | (x << (32 - n)); }
  function sha256(src) {
    var H = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19];
    var m = src.slice(0), len = src.length, hi = Math.floor(len / 536870912), lo = (len << 3) >>> 0;
    var w = [], i, off, a, b, c, d, e, f, g, h, s0, s1, ch, mj, t1, t2, out = [];
    m.push(0x80);
    while (m.length % 64 !== 56) { m.push(0); }
    m.push((hi >>> 24) & 255, (hi >>> 16) & 255, (hi >>> 8) & 255, hi & 255, (lo >>> 24) & 255, (lo >>> 16) & 255, (lo >>> 8) & 255, lo & 255);
    for (off = 0; off < m.length; off += 64) {
      for (i = 0; i < 16; i++) { w[i] = (m[off + 4 * i] << 24) | (m[off + 4 * i + 1] << 16) | (m[off + 4 * i + 2] << 8) | m[off + 4 * i + 3]; }
      for (i = 16; i < 64; i++) {
        s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >>> 3);
        s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >>> 10);
        w[i] = (w[i - 16] + s0 + w[i - 7] + s1) | 0;
      }
      a = H[0]; b = H[1]; c = H[2]; d = H[3]; e = H[4]; f = H[5]; g = H[6]; h = H[7];
      for (i = 0; i < 64; i++) {
        s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
        ch = (e & f) ^ (~e & g);
        t1 = (h + s1 + ch + K[i] + w[i]) | 0;
        s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
        mj = (a & b) ^ (a & c) ^ (b & c);
        t2 = (s0 + mj) | 0;
        h = g; g = f; f = e; e = (d + t1) | 0; d = c; c = b; b = a; a = (t1 + t2) | 0;
      }
      H[0] = (H[0] + a) | 0; H[1] = (H[1] + b) | 0; H[2] = (H[2] + c) | 0; H[3] = (H[3] + d) | 0;
      H[4] = (H[4] + e) | 0; H[5] = (H[5] + f) | 0; H[6] = (H[6] + g) | 0; H[7] = (H[7] + h) | 0;
    }
    for (i = 0; i < 8; i++) { out.push((H[i] >>> 24) & 255, (H[i] >>> 16) & 255, (H[i] >>> 8) & 255, H[i] & 255); }
    return out;
  }
  function bytes(s) { var b = unescape(encodeURIComponent(String(s))), o = [], i; for (i = 0; i < b.length; i++) { o.push(b.charCodeAt(i) & 255); } return o; }
  function hex(a) { var s = "", i; for (i = 0; i < a.length; i++) { s += (a[i] < 16 ? "0" : "") + a[i].toString(16); } return s; }
  function hmac(key, msg) {
    var k = key.length > 64 ? sha256(key) : key.slice(0), i, ip = [], op = [];
    while (k.length < 64) { k.push(0); }
    for (i = 0; i < 64; i++) { ip.push(k[i] ^ 0x36); op.push(k[i] ^ 0x5c); }
    return sha256(op.concat(sha256(ip.concat(msg))));
  }

  /* ---- interface identique au pont Android ---- */
  var NO_OTA = "err:mises à jour de l'interface désactivées sur iPad : recompile et réinstalle l'appli";
  window.Native = {
    http: function (id, method, url, headers, body, timeout) { post("http", [id, method, url, headers, body, timeout]); },
    sha256Hex: function (s) { return hex(sha256(bytes(s))); },
    hmacSha256Hex: function (k, m) { return hex(hmac(bytes(k), bytes(m))); },
    cfgGet: function (k) { var v = ST.cfg[k]; return (v === undefined || v === null) ? "" : String(v); },
    cfgSet: function (k, v) { ST.cfg[k] = String(v); post("cfgSet", [k, String(v)]); },
    bleAvailable: function () { return !!ST.ble; },
    bleWrite: function (id, addr, csv, timeout) { post("bleWrite", [id, addr, csv, timeout]); },
    battery: function () { return ST.battery || ""; },
    setSleep: function (on) { post("setSleep", [!!on]); return "lum:ok;eco:non (iPad)"; },
    appCode: function () { return ST.appCode; },
    otaSave: function () { return NO_OTA; },
    otaSaveSigned: function () { return NO_OTA; },
    otaClear: function () { },
    reloadUi: function () { post("reloadUi", []); },
    readDropped: function () { return ""; },
    readFile: function (rel) {
      var b = String(rel || "").toLowerCase(), i = b.lastIndexOf("/"), d;
      if (i >= 0) { b = b.substr(i + 1); }
      d = b.lastIndexOf("."); if (d > 0) { b = b.substr(0, d); }
      return (ST.files && ST.files[b]) ? String(ST.files[b]) : "";
    },
    apkInstall: function (id) { late(id, "installation d'appli non disponible sur iPad"); },
    apkInstallSigned: function (id) { late(id, "installation d'appli non disponible sur iPad"); }
  };
  /* mise à jour de l'état depuis l'appli (batterie, Bluetooth, fichiers déposés) */
  window.__tdbState = function (o) { var k; for (k in o) { if (o.hasOwnProperty(k)) { ST[k] = o[k]; } } };

  /* message de l'import automatique des réglages (affiché quelques secondes, une seule fois) */
  try {
    if (ST.toast) {
      var toastMsg = String(ST.toast);
      ST.toast = "";
      document.addEventListener("DOMContentLoaded", function () {
        setTimeout(function () {
          var t = document.createElement("div");
          t.textContent = toastMsg;
          t.style.cssText = "position:fixed;left:50%;bottom:28px;-webkit-transform:translateX(-50%);transform:translateX(-50%);max-width:80%;padding:12px 20px;border-radius:14px;background:rgba(30,34,40,.96);border:1px solid #3a4150;color:#d8dde6;font:16px -apple-system,sans-serif;z-index:2147483647;pointer-events:none;text-align:center";
          document.body.appendChild(t);
          setTimeout(function () { if (t.parentNode) { t.parentNode.removeChild(t); } }, 7000);
        }, 600);
      });
    }
  } catch (e) { }

  /* iPad : pas de zoom au double appui ni au pincement, pas de menu de sélection */
  try {
    var css = document.createElement("style");
    css.textContent = "html,body{touch-action:manipulation;-webkit-touch-callout:none}";
    (document.head || document.documentElement).appendChild(css);
  } catch (e) { }
})();
