/* ================================================================
 * lablivre.js — usado por todas as páginas do portal (desde 4.2.3)
 *
 * Mantém as páginas SEMPRE atuais: ao abrir (e a cada 30 s com a
 * página aberta), se o mapa da rede tiver mais de 5 min, pede ao
 * servidor um novo mapeamento e redesenha quando terminar.
 * Vários navegadores abertos não multiplicam o trabalho: o servidor
 * faz um mapeamento por vez e ignora pedidos com mapa recente.
 *
 *   LabLivre.manterAtual(redesenhar)          // na carga da página
 *   LabLivre.atualizarAgora(redesenhar)       // botão "Atualizar"
 *   LabLivre.tarefa(url, corpo, aoMudar)      // comandos (Modo Prova)
 * ================================================================ */
/* Botão "← Portal" em toda página que não seja o portal (e não tenha um próprio).
 * No TV Mode fica discreto e aparece ao passar o mouse. */
(function botaoPortal() {
  const por = () => {
    const pag = location.pathname.split('/').pop() || 'index.html';
    if (pag === 'index.html' || document.querySelector('a.voltar, [data-sem-voltar]')) return;
    const a = document.createElement('a');
    a.href = 'index.html'; a.textContent = '← Portal'; a.className = 'voltar';
    const discreto = /dashboard_tv/.test(pag);
    a.style.cssText = 'position:fixed;bottom:18px;left:18px;z-index:9999;text-decoration:none;' +
      'font:600 15px system-ui,sans-serif;color:#f5f5f7;background:rgba(20,20,29,.85);' +
      'border:1px solid rgba(255,255,255,.25);border-radius:10px;padding:8px 14px;' +
      (discreto ? 'opacity:.15;transition:opacity .2s;' : '');
    if (discreto) { a.onmouseenter = () => a.style.opacity = 1; a.onmouseleave = () => a.style.opacity = .15; }
    document.body.appendChild(a);
  };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', por); else por();
})();

const LabLivre = (() => {
  const IDADE_MAX = 300;   // segundos
  let ocupado = false;
  let aviso = null;

  function mostrarAviso(texto) {
    if (!aviso) {
      aviso = document.createElement('div');
      aviso.style.cssText = 'position:fixed;right:18px;bottom:18px;z-index:9999;' +
        'background:#14141d;color:#f5f5f7;border:1px solid #6366f1;border-radius:10px;' +
        'padding:10px 16px;font:13px system-ui,sans-serif;box-shadow:0 6px 24px rgba(0,0,0,.5)';
      document.body.appendChild(aviso);
    }
    aviso.textContent = texto;
    aviso.style.display = texto ? 'block' : 'none';
  }

  async function post(url, corpo) {
    const r = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'X-LabLivre': '1' },
      body: JSON.stringify(corpo || {})
    });
    let d = {};
    try { d = await r.json(); } catch (e) { /* servidor antigo */ }
    return { status: r.status, dados: d };
  }

  async function esperarTarefa(aoMudar) {
    for (;;) {
      const r = await fetch('api/tarefa?t=' + Date.now());
      const t = await r.json();
      if (aoMudar) aoMudar(t);
      if (!t.rodando) return t;
      await new Promise(ok => setTimeout(ok, 1500));
    }
  }

  async function pedirMapa(idade, redesenhar) {
    if (ocupado) return;
    ocupado = true;
    try {
      const { status, dados } = await post('api/atualizar', { se_mais_velho_que: idade });
      if (status >= 400 || !dados) return;              // servidor antigo: sem API
      if (dados.iniciado || (dados.motivo === 'ocupado' && dados.tarefa && dados.tarefa.nome === 'mapear')) {
        mostrarAviso('⟳ Atualizando o mapa da rede…');
        await esperarTarefa();
        mostrarAviso('');
        if (redesenhar) await redesenhar();
      }
    } catch (e) {
      mostrarAviso('');
    } finally {
      ocupado = false;
    }
  }

  return {
    manterAtual(redesenhar) {
      pedirMapa(IDADE_MAX, redesenhar);
      setInterval(() => pedirMapa(IDADE_MAX, redesenhar), 30000);
    },
    atualizarAgora(redesenhar) { return pedirMapa(0, redesenhar); },
    async info() {
      try { return await (await fetch('api/info?t=' + Date.now())).json(); }
      catch (e) { return { local: false, semApi: true }; }
    },
    async tarefa(url, corpo, aoMudar) {
      let { status, dados } = await post(url, corpo);
      if (status === 409) {                       // um mapeamento em andamento: espera e tenta de novo
        if (aoMudar) aoMudar({ rodando: true, saida: '⟳ Aguardando o mapeamento da rede terminar…' });
        await esperarTarefa();
        ({ status, dados } = await post(url, corpo));
      }
      if (status >= 400) throw new Error(dados.erro || ('erro ' + status));
      return esperarTarefa(aoMudar);
    },
    // "há 3 min" a partir de "2026-10-28 18:41:00"
    idade(quando) {
      const t = Date.parse(String(quando || '').replace(' ', 'T'));
      if (isNaN(t)) return '';
      const m = Math.round((Date.now() - t) / 60000);
      return m < 1 ? 'agora' : m < 60 ? `há ${m} min` : `há ${Math.floor(m / 60)} h ${m % 60} min`;
    }
  };
})();
