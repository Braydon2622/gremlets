import Foundation

/// The chat page served on 127.0.0.1 (opened from the menu, by double-clicking a Gremlet, or gremlets://chat).
/// Everything it does goes back to the app through header-protected POSTs on the same origin.
enum ChatPage {
    static func html(portraitsJSON: String) -> String {
        """
        <!doctype html><html lang="en"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Chat with your Gremlets</title>
        <style>
        :root { --bg:#f3f6ef; --panel:#fff; --fg:#1f2a22; --muted:#5c6b5f; --line:#d5dfd2; --accent:#3f7d4e; --you:#3f7d4e; --you-fg:#fff; --them:#eef3ea; --warn:#a3561f; }
        @media (prefers-color-scheme: dark) { :root { --bg:#141b16; --panel:#1c251f; --fg:#e4ece3; --muted:#9db0a1; --line:#2e3b31; --accent:#7cc48f; --you:#2f6b3f; --you-fg:#f2fff4; --them:#243028; --warn:#f0a35f; } }
        * { box-sizing: border-box; }
        body { margin:0; font:15px/1.5 -apple-system, system-ui, sans-serif; background:var(--bg); color:var(--fg); height:100vh; display:grid; grid-template-columns: 240px 1fr; }
        aside { border-right:1px solid var(--line); padding:16px; display:flex; flex-direction:column; gap:14px; overflow:auto; }
        h1 { font-size:1.05rem; margin:0; }
        .who { display:flex; flex-direction:column; gap:4px; }
        .g { display:grid; grid-template-columns:44px 1fr; gap:10px; align-items:center; padding:6px 8px; border-radius:8px; border:1px solid transparent; background:none; color:inherit; font:inherit; text-align:left; cursor:pointer; }
        .g:hover { background:var(--them); }
        .g[aria-current="true"] { border-color:var(--accent); background:var(--panel); }
        .g img { width:44px; height:44px; image-rendering:pixelated; }
        .g b { display:block; font-size:.95rem; } .g small { color:var(--muted); font-size:.78rem; }
        .day { display:grid; grid-template-columns:1fr 1fr; gap:6px; font-size:.8rem; color:var(--muted); }
        .day div { background:var(--panel); border:1px solid var(--line); border-radius:6px; padding:6px 8px; }
        .day b { display:block; color:var(--fg); font-size:1.05rem; font-variant-numeric:tabular-nums; }
        details { font-size:.85rem; } summary { cursor:pointer; color:var(--muted); }
        details label { display:block; margin:10px 0 4px; color:var(--muted); }
        input[type=text], input[type=password] { width:100%; padding:7px 9px; border-radius:6px; border:1px solid var(--line); background:var(--panel); color:var(--fg); font:inherit; }
        .row { display:flex; gap:6px; margin-top:6px; }
        button.s { font:inherit; font-size:.82rem; padding:5px 10px; border-radius:6px; border:1px solid var(--line); background:var(--panel); color:var(--fg); cursor:pointer; }
        .ai { font-size:.8rem; color:var(--muted); } .ai.on { color:var(--accent); } .warn { color:var(--warn); font-size:.8rem; }
        main { display:grid; grid-template-rows:auto 1fr auto; height:100vh; min-width:0; }
        header { padding:14px 20px; border-bottom:1px solid var(--line); display:flex; align-items:center; gap:12px; }
        header img { width:40px; height:40px; image-rendering:pixelated; }
        header b { font-size:1.05rem; } header small { color:var(--muted); display:block; }
        #log { overflow:auto; padding:20px; display:flex; flex-direction:column; gap:10px; }
        .m { max-width:min(560px, 80%); padding:9px 13px; border-radius:14px; white-space:pre-wrap; overflow-wrap:anywhere; }
        .m.user { align-self:flex-end; background:var(--you); color:var(--you-fg); border-bottom-right-radius:4px; }
        .m.gremlet { align-self:flex-start; background:var(--them); border-bottom-left-radius:4px; }
        .m.typing { color:var(--muted); font-style:italic; }
        .empty { color:var(--muted); text-align:center; margin:auto; max-width:380px; }
        .chips { display:flex; flex-wrap:wrap; gap:6px; justify-content:center; margin-top:10px; }
        form { display:flex; gap:8px; padding:14px 20px; border-top:1px solid var(--line); }
        form input { flex:1; padding:10px 12px; border-radius:10px; border:1px solid var(--line); background:var(--panel); color:var(--fg); font:inherit; }
        form button { padding:10px 16px; border-radius:10px; border:0; background:var(--accent); color:var(--bg); font:inherit; font-weight:600; cursor:pointer; }
        :focus-visible { outline:2px solid var(--accent); outline-offset:2px; }
        @media (max-width:640px) { body { grid-template-columns:1fr; } aside { border-right:0; border-bottom:1px solid var(--line); max-height:42vh; } main { height:58vh; } }
        </style></head><body>
        <aside>
          <h1>Your Gremlets</h1>
          <div class="who" id="who"></div>
          <div class="day" id="day"></div>
          <details id="settings">
            <summary>Settings</summary>
            <label for="me">What should they call you?</label>
            <input type="text" id="me" maxlength="30" placeholder="Your name">
            <label for="nick">Nickname for this Gremlet</label>
            <input type="text" id="nick" maxlength="24" placeholder="Leave empty for its real name">
            <div class="row"><button class="s" id="save">Save</button><button class="s" id="forget">Forget this chat</button></div>
            <label for="key">Anthropic API key (stored in your Mac's Keychain)</label>
            <input type="password" id="key" autocomplete="off" placeholder="sk-ant-…">
            <div class="row"><button class="s" id="savekey">Save key</button><button class="s" id="clearkey">Remove key</button></div>
            <p class="ai" id="aistatus"></p>
          </details>
        </aside>
        <main>
          <header><img id="hpic" alt=""><div><b id="hname">…</b><small id="hsub"></small></div></header>
          <div id="log" aria-live="polite"></div>
          <form id="f"><input id="t" maxlength="800" autocomplete="off" placeholder="Say something…" aria-label="Message"><button>Send</button></form>
        </main>
        <script>
        const pics = \(portraitsJSON);
        const H = { 'X-Gremlets': '1', 'Content-Type': 'text/plain' };
        let state = null, target = location.hash.slice(1), waiting = 0;
        const $ = (id) => document.getElementById(id);
        async function api(path, body) {
          const r = await fetch(path, { method: 'POST', headers: H, body: body ?? '' });
          return r.json();
        }
        async function load() {
          state = await api('/chat/state?name=' + encodeURIComponent(target));
          if (!target) target = state.target;
          render();
        }
        function render() {
          const g = state.gremlets.find((x) => x.id === target) || state.gremlets[0];
          if (!g) { $('log').innerHTML = '<p class="empty">No Gremlets are out. Add one from the menu bar.</p>'; return; }
          target = g.id;
          $('who').replaceChildren(...state.gremlets.map((x) => {
            const b = document.createElement('button');
            b.className = 'g'; b.setAttribute('aria-current', x.id === target);
            const img = document.createElement('img'); img.src = pics[x.id] || ''; img.alt = '';
            const d = document.createElement('div');
            const n = document.createElement('b'); n.textContent = x.nick || x.name;
            const s = document.createElement('small'); s.textContent = x.bond + ' · ' + x.doing;
            d.append(n, s); b.append(img, d);
            b.onclick = () => { target = x.id; location.hash = x.id; load(); };
            return b;
          }));
          $('hpic').src = pics[g.id] || '';
          $('hname').textContent = g.nick || g.name;
          $('hsub').textContent = `${g.element} ${g.family} · ${g.bond}`;
          const d = state.day;
          $('day').innerHTML = '';
          [['Focused today', d.focus + ' min'], ['Streak', d.streak + ' days'], ['Grown today', d.plants], ['Seed book', d.seeds + '/' + d.seedsTotal], ['Claude tasks', d.claude], ['Out now', state.gremlets.length]].forEach(([k, v]) => {
            const el = document.createElement('div'); const b = document.createElement('b'); b.textContent = v; el.append(b, k); $('day').append(el);
          });
          $('me').value = $('me').value || state.me;
          if (document.activeElement !== $('nick')) $('nick').value = g.nick;
          const st = $('aistatus');
          st.className = 'ai' + (state.ai ? ' on' : '');
          st.textContent = state.ai ? 'AI replies are on (Claude).' : 'No key: they answer with built-in lines (and can still start a focus session, garden, dance…).';
          if (state.problem) { const w = document.createElement('div'); w.className = 'warn'; w.textContent = '⚠︎ ' + state.problem; st.append(w); }
          const log = $('log');
          log.innerHTML = '';
          if (!state.history.length) {
            const e = document.createElement('div'); e.className = 'empty';
            e.textContent = `Say hi to ${g.nick || g.name}! It knows how your day is going and can help you focus, garden, or just keep you company.`;
            const chips = document.createElement('div'); chips.className = 'chips';
            ['How was my day?', 'Help me focus', 'Let\\u2019s garden', 'Tell me about yourself'].forEach((t) => {
              const c = document.createElement('button'); c.className = 's'; c.textContent = t; c.onclick = () => send(t); chips.append(c);
            });
            e.append(chips); log.append(e);
          }
          for (const m of state.history) {
            const el = document.createElement('div'); el.className = 'm ' + (m.role === 'user' ? 'user' : 'gremlet'); el.textContent = m.text; log.append(el);
          }
          if (waiting) { const el = document.createElement('div'); el.className = 'm gremlet typing'; el.textContent = (g.nick || g.name) + ' is thinking…'; log.append(el); }
          log.scrollTop = log.scrollHeight;
        }
        async function send(text) {
          if (!text.trim()) return;
          const before = state.history.length;
          state.history.push({ role: 'user', text }); waiting = 1; render();
          await api('/chat/send?name=' + encodeURIComponent(target), text);
          for (let i = 0; i < 40; i++) {
            await new Promise((r) => setTimeout(r, 900));
            const s = await api('/chat/state?name=' + encodeURIComponent(target));
            if (s.history.length >= before + 2) { state = s; break; }
          }
          waiting = 0; render();
        }
        $('f').onsubmit = (e) => { e.preventDefault(); const t = $('t').value; $('t').value = ''; send(t); };
        $('save').onclick = async () => { await api('/chat/me', $('me').value); await api('/chat/nick?name=' + encodeURIComponent(target), $('nick').value); load(); };
        $('forget').onclick = async () => { await api('/chat/forget?name=' + encodeURIComponent(target)); load(); };
        $('savekey').onclick = async () => { const k = $('key').value.trim(); if (!k) return; await api('/chat/key', k); $('key').value = ''; load(); };
        $('clearkey').onclick = async () => { await api('/chat/key', ''); load(); };
        load();
        setInterval(() => { if (!waiting) load(); }, 8000);
        </script></body></html>
        """
    }
}
