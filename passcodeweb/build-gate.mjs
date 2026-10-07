// passcodeweb: turns a static HTML page into a passcode-gated page for public hosting (e.g. GitHub Pages).
// Every <section class="block" id=".." data-for="..">, the section nav links and the audience switcher are AES-256-GCM
// encrypted (PBKDF2-SHA256, 600k iterations) and unlocked in the browser with the passcode. Nothing is sent anywhere.
//
//   node build-gate.mjs --src <page.html> --out <folder>             random passcode, printed once and never saved
//   SITE_PASSCODE=... node build-gate.mjs --src <page.html> --out <folder>   your own passcode (PowerShell: $env:SITE_PASSCODE="...")
//   node build-gate.mjs --src <page.html> --out <folder> --plain     ungated copy (removes the passcode)
//
// Defaults (this repo layout): --src ../Necklace Chain/docs/index.html  --out ../necklace-chain-site
// Writes <out>/index.html and <out>/.nojekyll only.
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { randomBytes, randomInt, pbkdf2Sync, createCipheriv } from "node:crypto";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const ITERATIONS = 600000;
const here = dirname(fileURLToPath(import.meta.url));

function arg(name, fallback) {
  const i = process.argv.indexOf("--" + name);
  return i !== -1 && process.argv[i + 1] ? process.argv[i + 1] : fallback;
}
function fail(msg) { console.error("build-gate: " + msg); process.exit(1); }
function must(cond, msg) { if (!cond) fail(msg); }

const srcFile = resolve(arg("src", join(here, "..", "Necklace Chain", "docs", "index.html")));
const outDir = resolve(arg("out", join(here, "..", "necklace-chain-site")));
const outFile = join(outDir, "index.html");
const plain = process.argv.includes("--plain");
must(srcFile !== outFile, "--out must not be the folder that holds the source page");

let html;
try { html = readFileSync(srcFile, "utf8"); } catch { fail("cannot read source page: " + srcFile); }
html = html.replace(/\r\n/g, "\n").replace(/<!--[\s\S]*?-->/g, "");
// Links to files that are not part of the published page become plain text.
html = html.replace(/<a href="(?:\.\.\/)?[A-Za-z0-9_\/.-]+\.md">([^<]*)<\/a>/g, "<code>$1</code>");
must(!/href="(\.\.\/|[^#h"][^"]*\.md)/.test(html), "a link to a private file is still present");
must(!/OneDrive|C:\\|\\Users\\/.test(html), "page contains a local path");

function write(content) {
  mkdirSync(outDir, { recursive: true });
  writeFileSync(outFile, content, "utf8");
  writeFileSync(join(outDir, ".nojekyll"), "", "utf8");
}

if (plain) {
  write(html.replace(/\n{3,}/g, "\n\n"));
  console.log("Wrote ungated " + outFile);
  process.exit(0);
}

let passcode = (process.env.SITE_PASSCODE ?? "").normalize("NFC");
let generated = false;
if (!passcode) {
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  const groups = Array.from({ length: 5 }, () => Array.from({ length: 4 }, () => alphabet[randomInt(alphabet.length)]).join(""));
  passcode = groups.join("-");
  generated = true;
}
if (passcode.length < 14) console.warn("WARNING: passcode is shorter than 14 characters. The encrypted page is public, so a short or guessable passcode can be cracked offline.");

const sectionRe = /<section class="block" id="([^"]+)" data-for="([^"]*)">[\s\S]*?<\/section>/g;
const sections = [];
let pub = html;
for (const m of html.matchAll(sectionRe)) {
  must((m[0].match(/<section/g) || []).length === 1, "nested <section> in " + m[1]);
  sections.push({ before: null, html: m[0] });
  pub = pub.replace(m[0], "");
}
must(sections.length === (html.match(/<section\b/g) || []).length && sections.length > 0, "section parser missed a section");

const linksRe = /(<div class="links">)([\s\S]*?)(<\/div>)/;
const lm = pub.match(linksRe);
must(lm, "nav links block not found");
const fullNav = lm[2].trim();
pub = pub.replace(linksRe, (_, a, _b, c) => a + c);

const audRe = /<div class="aud"[^>]*>[\s\S]*?<\/div>/;
must(audRe.test(pub), "audience switcher not found");
pub = pub.replace(audRe, (m) => m.replace('<div class="aud"', '<div class="aud" hidden') +
  '\n  <button type="button" id="unlock" class="lockbtn">Unlock</button>');

pub = pub.replace(/<main>\s*<\/main>/, '<main>\n<p id="locked-note" class="note">This page is protected. Select <b>Unlock</b> and enter the passcode.</p>\n</main>');
must(pub.includes("locked-note"), "main element not found");

pub = pub.replace("</title>", "</title>\n<meta name=\"robots\" content=\"noindex,nofollow\">\n<meta name=\"referrer\" content=\"no-referrer\">\n" +
  "<meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; img-src data:; base-uri 'none'; form-action 'none'\">");
pub = pub.replace("</style>", `
  .aud[hidden] { display: none; }
  .lockbtn { font: inherit; font-size: .88rem; padding: .3rem .8rem; border: 1px solid var(--line); background: transparent; color: var(--ink); border-radius: 999px; cursor: pointer; }
  .lockbtn[hidden] { display: none; }
  dialog#gate { border: 1px solid var(--line); border-radius: .75rem; background: var(--panel); color: var(--ink); padding: 1.25rem 1.5rem; max-width: 22rem; width: 90%; }
  dialog#gate::backdrop { background: rgba(0,0,0,.45); }
  dialog#gate h2 { font-size: 1.15rem; margin: 0 0 .6rem; }
  dialog#gate input { width: 100%; font: inherit; padding: .45rem .6rem; border: 1px solid var(--line); border-radius: .4rem; background: var(--bg); color: var(--ink); }
  dialog#gate .row { display: flex; gap: .5rem; margin-top: .75rem; justify-content: flex-end; }
  dialog#gate button { font: inherit; padding: .35rem .9rem; border-radius: .4rem; border: 1px solid var(--line); background: transparent; color: var(--ink); cursor: pointer; }
  dialog#gate button.go { background: var(--accent); border-color: var(--accent); color: #fff; }
  dialog#gate button:disabled { opacity: .6; cursor: wait; }
  #gate-msg { min-height: 1.3em; margin: .5rem 0 0; font-size: .88rem; color: var(--accent); }
</style>`);

const plaintext = Buffer.from(JSON.stringify({ nav: fullNav, sections }), "utf8");
const salt = randomBytes(16), iv = randomBytes(12);
const key = pbkdf2Sync(passcode, salt, ITERATIONS, 32, "sha256");
const cipher = createCipheriv("aes-256-gcm", key, iv);
const ct = Buffer.concat([cipher.update(plaintext), cipher.final(), cipher.getAuthTag()]);
const vault = JSON.stringify({ v: 1, iter: ITERATIONS, salt: salt.toString("base64"), iv: iv.toString("base64"), ct: ct.toString("base64") });

const gate = `
<dialog id="gate" aria-labelledby="gate-title">
  <form id="gate-form" method="dialog">
    <h2 id="gate-title">Enter passcode</h2>
    <label for="gate-pass">Passcode</label>
    <input id="gate-pass" type="password" autocomplete="off" required>
    <p id="gate-msg" role="status"></p>
    <div class="row"><button type="button" id="gate-cancel">Cancel</button><button type="submit" class="go" id="gate-go">Unlock</button></div>
  </form>
</dialog>
<script id="vault" type="application/json">${vault}</script>
`;

const script = `<script>
(function () {
  var main = document.querySelector('main');
  var links = document.querySelector('nav.bar .links');
  var aud = document.querySelector('.aud');
  var unlockBtn = document.getElementById('unlock');
  var gate = document.getElementById('gate');
  var form = document.getElementById('gate-form');
  var pass = document.getElementById('gate-pass');
  var msg = document.getElementById('gate-msg');
  var go = document.getElementById('gate-go');
  var unlocked = false;

  function bindCopy(root) {
    root.querySelectorAll('pre button.copy').forEach(function (btn) {
      btn.addEventListener('click', function () {
        var text = btn.parentElement.querySelector('code').innerText;
        if (navigator.clipboard) navigator.clipboard.writeText(text).then(function () { btn.textContent = 'Copied'; setTimeout(function () { btn.textContent = 'Copy'; }, 1200); });
      });
    });
  }

  function show(which) {
    aud.querySelectorAll('button').forEach(function (b) { b.setAttribute('aria-pressed', String(b.dataset.aud === which)); });
    document.querySelectorAll('section.block').forEach(function (s) {
      var list = (s.dataset['for'] || '').split(' ');
      s.hidden = !(which === 'all' || list.indexOf(which) !== -1);
    });
    try {
      var u = new URL(location.href);
      if (which === 'all') u.searchParams.delete('for'); else u.searchParams.set('for', which);
      history.replaceState(null, '', u.toString());
    } catch (e) {}
  }

  function b64(s) { var r = atob(s), a = new Uint8Array(r.length); for (var i = 0; i < r.length; i++) a[i] = r.charCodeAt(i); return a; }

  async function decrypt(pw) {
    var v = JSON.parse(document.getElementById('vault').textContent);
    var km = await crypto.subtle.importKey('raw', new TextEncoder().encode(pw.normalize('NFC')), 'PBKDF2', false, ['deriveKey']);
    var key = await crypto.subtle.deriveKey({ name: 'PBKDF2', salt: b64(v.salt), iterations: v.iter, hash: 'SHA-256' }, km, { name: 'AES-GCM', length: 256 }, false, ['decrypt']);
    var pt = await crypto.subtle.decrypt({ name: 'AES-GCM', iv: b64(v.iv) }, key, b64(v.ct));
    return JSON.parse(new TextDecoder().decode(pt));
  }

  function reveal(data) {
    var note = document.getElementById('locked-note');
    if (note) note.remove();
    data.sections.forEach(function (s) {
      var t = document.createElement('template');
      t.innerHTML = s.html;
      main.appendChild(t.content);
    });
    links.innerHTML = data.nav;
    bindCopy(main);
    aud.hidden = false;
    unlockBtn.hidden = true;
    unlocked = true;
    aud.querySelectorAll('button').forEach(function (b) { b.addEventListener('click', function () { show(b.dataset.aud); }); });
    var start = new URLSearchParams(location.search).get('for');
    if (['public', 'team', 'eng'].indexOf(start) !== -1) show(start);
  }

  function openGate() { msg.textContent = ''; if (!gate.open) gate.showModal(); pass.focus(); }
  unlockBtn.addEventListener('click', openGate);
  document.getElementById('gate-cancel').addEventListener('click', function () { gate.close(); });
  form.addEventListener('submit', async function (e) {
    e.preventDefault();
    if (unlocked) return;
    go.disabled = true; msg.textContent = 'Checking...';
    try {
      var data = await decrypt(pass.value);
      pass.value = '';
      reveal(data);
      gate.close();
    } catch (err) {
      msg.textContent = (window.crypto && crypto.subtle) ? 'Incorrect passcode.' : 'This browser cannot unlock the page (needs HTTPS).';
    }
    go.disabled = false;
  });
  openGate();
})();
</script>`;

const scriptRe = /<script>[\s\S]*?<\/script>/;
must(scriptRe.test(pub), "inline script not found");
pub = pub.replace(scriptRe, () => gate + script).replace(/\n{3,}/g, "\n\n");

write(pub);
console.log("Encrypted " + sections.length + " sections. Wrote " + outFile + " (" + Math.round(Buffer.byteLength(pub) / 1024) + " KB)");
if (generated) console.log("Temporary passcode (shown once, not saved anywhere): " + passcode);
