#!/usr/bin/env python3
"""
servidor_web.py — Servidor do portal LabLivre (porta 8080), desde 4.2.3

Serve a pasta web/ como o antigo "python3 -m http.server" e acrescenta
uma pequena API para as páginas ficarem SEMPRE atuais e para o painel do
Modo Prova ter botões:

  GET  /api/info        → {"local": bool, "mapa_idade_s": int, "tarefa": {...}}
  POST /api/atualizar   → remapeia a rede se o mapa tiver mais de N segundos
                          corpo: {"se_mais_velho_que": 300}   (mínimo 30 s)
  POST /api/prova       → {"acao": "ativar"|"liberar"|"reaplicar"|"status",
                           "horas": 1..24}   ← SÓ da própria máquina (localhost)
  GET  /api/tarefa      → andamento da tarefa atual/última (saída ao vivo)

Segurança:
  * só roda scripts fixos do LabLivre, com argumentos validados;
  * o Modo Prova só aceita pedidos vindos de 127.0.0.1 (o professor, no
    orquestrador) — alunos que abrirem o portal pela rede só VEEM;
  * todo POST exige o cabeçalho "X-LabLivre: 1" (outra página aberta no
    navegador não consegue mandar esse cabeçalho sem permissão);
  * uma tarefa por vez; remapear tem intervalo mínimo.

Uso: python3 modulos/servidor_web.py [--porta 8080]
"""

import json
import os
import subprocess
import sys
import threading
import time
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WEB = os.path.join(RAIZ, "web")
IPS = os.path.join(RAIZ, "ips_atuais.txt")
INTERVALO_MINIMO = 30          # segundos entre dois mapeamentos
MAX_LINHAS = 400               # saída guardada da tarefa

_trava = threading.Lock()
_tarefa = {"id": 0, "nome": "", "rodando": False, "rc": None,
           "inicio": 0, "fim": 0, "saida": []}


_meus_ips = {"t": 0, "ips": set()}


def meus_ips():
    """IPs desta máquina (cache de 60 s): o professor pode abrir o portal
    pelo IP da rede em vez de localhost e continua sendo "local"."""
    if time.time() - _meus_ips["t"] > 60:
        try:
            saida = subprocess.run(["hostname", "-I"], capture_output=True, text=True, timeout=3).stdout
            _meus_ips["ips"] = set(saida.split())
        except Exception:  # noqa: BLE001
            _meus_ips["ips"] = set()
        _meus_ips["t"] = time.time()
    return _meus_ips["ips"]


def admins_extras():
    """IPs liberados para os botões do Modo Prova além desta máquina:
    LAB_WEB_ADMINS="10.158.28.50 10.158.28.51" no configs/lablivre.conf
    (ex.: o notebook do professor). Lido a cada pedido — sem reiniciar."""
    try:
        with open(os.path.join(RAIZ, "configs", "lablivre.conf"), encoding="utf-8") as f:
            for linha in f:
                linha = linha.strip()
                if linha.startswith("LAB_WEB_ADMINS="):
                    return set(linha.split("=", 1)[1].strip().strip('"\'').split())
    except OSError:
        pass
    return set()


def idade_mapa():
    try:
        return int(time.time() - os.path.getmtime(IPS))
    except OSError:
        return 10 ** 9


def estado_tarefa():
    with _trava:
        t = dict(_tarefa)
        t["saida"] = "\n".join(_tarefa["saida"])
    return t


def iniciar_tarefa(nome, comando):
    """Começa uma tarefa em segundo plano. Devolve False se já há outra."""
    with _trava:
        if _tarefa["rodando"]:
            return False
        _tarefa.update(id=_tarefa["id"] + 1, nome=nome, rodando=True, rc=None,
                       inicio=int(time.time()), fim=0, saida=[])

    def rodar():
        rc = 1
        try:
            proc = subprocess.Popen(comando, cwd=RAIZ, stdin=subprocess.DEVNULL,
                                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                    text=True, errors="replace")
            for linha in proc.stdout:
                with _trava:
                    _tarefa["saida"].append(linha.rstrip("\n"))
                    del _tarefa["saida"][:-MAX_LINHAS]
            rc = proc.wait()
        except Exception as e:  # noqa: BLE001 — qualquer falha vira saída da tarefa
            with _trava:
                _tarefa["saida"].append(f"[ERRO] {e}")
        with _trava:
            _tarefa.update(rodando=False, rc=rc, fim=int(time.time()))

    threading.Thread(target=rodar, daemon=True).start()
    return True


class Manipulador(SimpleHTTPRequestHandler):
    def __init__(self, *a, **kw):
        super().__init__(*a, directory=WEB, **kw)

    # ---------- utilidades ----------
    def eh_local(self):
        ip = self.client_address[0]
        if ip.startswith("::ffff:"):
            ip = ip[7:]
        return ip in ("127.0.0.1", "::1") or ip in meus_ips() or ip in admins_extras()

    def responder(self, codigo, dados):
        corpo = json.dumps(dados, ensure_ascii=False).encode("utf-8")
        self.send_response(codigo)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(corpo)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(corpo)

    def ler_json(self):
        try:
            n = int(self.headers.get("Content-Length") or 0)
            return json.loads(self.rfile.read(n) or b"{}") if n else {}
        except (ValueError, json.JSONDecodeError):
            return {}

    def end_headers(self):
        # JSON e páginas nunca do cache: o navegador sempre pega o estado novo
        if self.path.split("?")[0].endswith((".json", ".html", "/")):
            self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def log_message(self, fmt, *args):  # sem uma linha no journal por requisição
        pass

    # ---------- GET ----------
    def do_GET(self):
        caminho = self.path.split("?")[0]
        if caminho == "/api/info":
            return self.responder(200, {"local": self.eh_local(),
                                        "ip": self.client_address[0].replace("::ffff:", ""),
                                        "mapa_idade_s": idade_mapa(),
                                        "tarefa": estado_tarefa()})
        if caminho == "/api/tarefa":
            return self.responder(200, estado_tarefa())
        return super().do_GET()

    # ---------- POST ----------
    def do_POST(self):
        caminho = self.path.split("?")[0]
        if self.headers.get("X-LabLivre") != "1":
            return self.responder(403, {"erro": "cabeçalho X-LabLivre ausente"})
        dados = self.ler_json()

        if caminho == "/api/atualizar":
            try:
                limite = max(INTERVALO_MINIMO, int(dados.get("se_mais_velho_que", 300)))
            except (TypeError, ValueError):
                limite = 300
            t = estado_tarefa()
            if t["rodando"]:
                return self.responder(200, {"iniciado": False, "motivo": "ocupado", "tarefa": t})
            if idade_mapa() < limite:
                return self.responder(200, {"iniciado": False, "motivo": "recente",
                                            "mapa_idade_s": idade_mapa()})
            iniciar_tarefa("mapear", ["bash", "modulos/atualizar_ips.sh"])
            return self.responder(202, {"iniciado": True, "tarefa": estado_tarefa()})

        if caminho == "/api/prova":
            if not self.eh_local():
                return self.responder(403, {"erro": "O Modo Prova só pode ser comandado na máquina do professor."})
            acao = dados.get("acao")
            if acao not in ("ativar", "liberar", "reaplicar", "status"):
                return self.responder(400, {"erro": "ação inválida"})
            cmd = ["bash", "modulos/modo_prova.sh", acao]
            if acao == "ativar":
                try:
                    horas = int(dados.get("horas", 0))
                except (TypeError, ValueError):
                    horas = 0
                if not 1 <= horas <= 24:
                    return self.responder(400, {"erro": "duração inválida (1 a 24 horas)"})
                cmd.append(str(horas))
            # status/reaplicar/ativar/liberar usam o mapa: remapeia antes se velho
            if idade_mapa() > 120:
                cmd = ["bash", "-c", "bash modulos/atualizar_ips.sh && " + " ".join(cmd)]
            if not iniciar_tarefa("prova-" + acao, cmd):
                return self.responder(409, {"erro": "Já há uma tarefa em andamento. Aguarde.",
                                            "tarefa": estado_tarefa()})
            return self.responder(202, {"iniciado": True, "tarefa": estado_tarefa()})

        return self.responder(404, {"erro": "não encontrado"})


def main():
    porta = 8080
    if "--porta" in sys.argv:
        porta = int(sys.argv[sys.argv.index("--porta") + 1])
    os.makedirs(WEB, exist_ok=True)
    # marcador: permite saber que quem responde na porta é ESTA instalação
    with open(os.path.join(WEB, "lablivre-raiz.txt"), "w") as f:
        f.write(RAIZ + "\n")
    ThreadingHTTPServer.allow_reuse_address = True
    ThreadingHTTPServer.daemon_threads = True
    srv = ThreadingHTTPServer(("0.0.0.0", porta), Manipulador)
    print(f"LabLivre web: http://localhost:{porta}/  (pasta {WEB})", flush=True)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
