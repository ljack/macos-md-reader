(function () {
  'use strict';

  const root = () => document.getElementById('content');

  function slug(text, seen) {
    let s = text.trim().toLowerCase()
      .replace(/[^\p{L}\p{N}\s-]/gu, '')
      .replace(/\s+/g, '-');
    const base = s || 'section';
    s = base;
    let i = 1;
    while (seen.has(s)) s = base + '-' + (i++);
    seen.add(s);
    return s;
  }

  function copyText(text) {
    if (navigator.clipboard && navigator.clipboard.writeText) {
      return navigator.clipboard.writeText(text);
    }
    return new Promise((resolve) => {
      const ta = document.createElement('textarea');
      ta.value = text;
      ta.style.position = 'fixed';
      ta.style.opacity = '0';
      document.body.appendChild(ta);
      ta.select();
      try { document.execCommand('copy'); } catch (e) {}
      ta.remove();
      resolve();
    });
  }

  function enhance() {
    const el = root();
    if (!el) return;

    // GitHub-style heading anchors so #links work.
    const seen = new Set();
    el.querySelectorAll('h1,h2,h3,h4,h5,h6').forEach((h) => {
      if (!h.id) h.id = slug(h.textContent, seen); else seen.add(h.id);
    });

    // Syntax highlighting + copy button.
    if (window.hljs) hljs.configure({ ignoreUnescapedHTML: true });
    el.querySelectorAll('pre > code').forEach((code) => {
      if (window.hljs && !code.dataset.highlighted && /\blanguage-/.test(code.className)) {
        try { hljs.highlightElement(code); } catch (e) {}
      }
      const pre = code.parentElement;
      if (!pre.querySelector('.copy-btn')) {
        const btn = document.createElement('button');
        btn.className = 'copy-btn';
        btn.type = 'button';
        btn.textContent = 'Copy';
        btn.addEventListener('click', () => {
          copyText(code.innerText).then(() => {
            btn.textContent = 'Copied';
            setTimeout(() => { btn.textContent = 'Copy'; }, 1200);
          });
        });
        pre.appendChild(btn);
      }
    });

    // Wide tables scroll instead of overflowing the page.
    el.querySelectorAll('table:not(.frontmatter)').forEach((t) => {
      if (t.parentElement.classList.contains('table-wrap')) return;
      const wrap = document.createElement('div');
      wrap.className = 'table-wrap';
      t.replaceWith(wrap);
      wrap.appendChild(t);
    });
  }

  function update(html) {
    const y = window.scrollY;
    const el = root();
    if (!el) return;
    el.innerHTML = html;
    enhance();
    window.scrollTo(0, y);
  }

  window.__md = { update, enhance };
  enhance();
})();
