#!/usr/bin/env python3
"""
zzz-mouse-autofix.py
====================
Daemon assíncrono para recuperação automática e imperceptível de mouse drag
no Zenless Zone Zero (AppID 4162040) em Hyprland 0.57.0 (Lua Config) / XWayland.

Implementa arquitetura de Gatilho por Foco Voluntário:
- Monitoramento não-bloqueante via Hyprland socket2.
- Debounce assíncrono cancelável (zero impacto enquanto o usuário está em outros apps).
- Compatibilidade nativa com dispatchers Lua do Hyprland 0.57.0 (hl.dsp.focus).
- Resolução de condições de corrida (activewindowv2 precoce / escaneamento inicial).
- Máquina de estados cíclica resiliente (re-armamento pós-saída para outras aplicações).
- Suporte a gatilho manual sob demanda (SIGUSR1 / --force-pulse).
- Preservação estrita das configurações de animações do usuário (RAII / try-finally).
- Conformidade total com o padrão XDG para logs (~/.local/state/zzz-autofix/autofix.log).
"""

import argparse
import asyncio
import json
import logging
import os
import signal
import sys
import time
from pathlib import Path
from typing import Optional

# Configuração XDG
STATE_DIR = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / "zzz-autofix"
STATE_DIR.mkdir(parents=True, exist_ok=True)
LOG_FILE = STATE_DIR / "autofix.log"

logger = logging.getLogger("zzz-autofix")

# Estados da máquina
STATE_IDLE = "IDLE"
STATE_ARMED = "ARMED"
STATE_DEBOUNCING = "DEBOUNCING"
STATE_DISPATCHING = "DISPATCHING"
STATE_RECOVERED = "RECOVERED"


class ZZZAutoFixDaemon:
    def __init__(
        self,
        dry_run: bool = False,
        dwell_time: float = 0.08,
        debounce_time: float = 0.40,
        cooldown_time: float = 2.0,
        target_class: str = "steam_app_4162040",
        target_title: str = "ZenlessZoneZero",
    ):
        self.dry_run = dry_run
        self.dwell_time = dwell_time
        self.debounce_time = debounce_time
        self.cooldown_time = cooldown_time
        self.target_class = target_class
        self.target_title = target_title

        self.state = STATE_IDLE
        self.zzz_addr: Optional[str] = None
        self.zzz_ws: Optional[str] = None
        self.debounce_task: Optional[asyncio.Task] = None
        self.original_anim_enabled: bool = True
        self.anim_altered: bool = False
        self.running: bool = True
        self.last_pulse_time: float = 0.0

    async def run_hyprctl(self, *args: str) -> tuple[int, str]:
        """Executa um comando hyprctl assincronamente capturando stdout e stderr."""
        try:
            proc = await asyncio.create_subprocess_exec(
                "hyprctl",
                *args,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
            stdout, stderr = await proc.communicate()
            out_str = stdout.decode().strip()
            err_str = stderr.decode().strip()
            full_out = f"{out_str} {err_str}".strip()
            return proc.returncode, full_out
        except Exception as e:
            logger.error(f"Erro ao executar hyprctl {' '.join(args)}: {e}")
            return -1, str(e)

    async def query_animation_setting(self) -> bool:
        """Consulta o valor real atual de animations:enabled."""
        rc, out = await self.run_hyprctl("getoption", "animations:enabled", "-j")
        if rc == 0:
            try:
                data = json.loads(out)
                return bool(data.get("bool", True))
            except Exception as e:
                logger.warning(f"Falha ao interpretar json de animations:enabled: {e}")
        return True

    async def set_animation_setting(self, enabled: bool) -> bool:
        """Altera dinamicamente animations:enabled via Lua eval."""
        val = "true" if enabled else "false"
        lua_cmd = f"hl.config({{ animations = {{ enabled = {val} }} }})"
        rc, out = await self.run_hyprctl("eval", lua_cmd)
        if rc != 0 or "error" in out.lower():
            logger.error(f"Erro ao aplicar hl.config animations={val}: {out}")
            return False
        return True

    async def switch_workspace(self, ws: str) -> bool:
        """Alterna workspace com suporte resiliente a Hyprland 0.57+ (Lua) e modo clássico."""
        # 1. Tenta formato Lua nativo do Hyprland 0.55+ (hl.dsp.focus)
        lua_dsp = f'hl.dsp.focus({{ workspace = "{ws}" }})'
        rc, out = await self.run_hyprctl("dispatch", lua_dsp)
        if rc == 0 and "error" not in out.lower():
            return True

        # 2. Fallback: avaliação explícita no runtime Lua
        rc, out = await self.run_hyprctl("eval", f'hl.dispatch(hl.dsp.focus({{ workspace = "{ws}" }}))')
        if rc == 0 and "error" not in out.lower():
            return True

        # 3. Fallback: comando de despacho legado (para ambientes não-Lua)
        rc, out = await self.run_hyprctl("dispatch", "workspace", str(ws))
        if rc == 0 and "error" not in out.lower():
            return True

        logger.error(f"Falha crítica ao alternar para workspace '{ws}': rc={rc}, out={out}")
        return False

    async def execute_recovery_sequence(self, target_ws: str) -> bool:
        """Executa a sequência de pulso para forçar FocusOut(None) -> FocusIn(NotifyDetailNone)."""
        logger.info(
            f"Iniciando sequência de recuperação de foco (Workspace alvo: {target_ws}, "
            f"Dwell: {self.dwell_time}s, Dry-run: {self.dry_run})..."
        )
        prev_state = self.state
        self.state = STATE_DISPATCHING

        if self.dry_run:
            logger.info("[DRY-RUN] Simulação de pulso concluída sem despachar comandos reais.")
            self.state = STATE_RECOVERED
            self.last_pulse_time = time.monotonic()
            return True

        # 1. Consulta estado original de animações
        self.original_anim_enabled = await self.query_animation_setting()
        logger.debug(f"Estado de animação original: {self.original_anim_enabled}")

        success = False
        try:
            # 2. Desativa animações temporariamente para mitigar efeito visual
            if self.original_anim_enabled:
                await self.set_animation_setting(False)
                self.anim_altered = True

            # 3. Despacha transição para workspace vazio (seletor nativo emptym)
            logger.debug("Despachando transição para workspace vazio (emptym)...")
            ok_empty = await self.switch_workspace("emptym")
            if not ok_empty:
                logger.error("Abortando pulso: não foi possível mudar para workspace vazio.")
                return False

            # 4. Dwell time seguro para que XWayland e Wine processem o evento de foco nulo
            if self.dwell_time > 0:
                await asyncio.sleep(self.dwell_time)

            # 5. Retorna à workspace do jogo
            logger.debug(f"Retornando ao workspace do ZZZ ({target_ws})...")
            ok_return = await self.switch_workspace(str(target_ws))
            if not ok_return:
                logger.error(f"Erro grave: falha ao retornar ao workspace do ZZZ ({target_ws})!")
                return False

            success = True
            self.last_pulse_time = time.monotonic()
            self.state = STATE_RECOVERED
            logger.info(
                f"Sequência de pulso concluída com sucesso no compositor (Dwell: {self.dwell_time}s). "
                "Estado: RECOVERED (Mouse drag restaurado; monitorando foco)."
            )
            return True
        except Exception as e:
            logger.error(f"Exceção durante execução da sequência de recuperação: {e}", exc_info=True)
            self.state = STATE_ARMED
            return False
        finally:
            # 6. Restaura deterministamente o estado original de animações
            if self.anim_altered:
                await self.set_animation_setting(self.original_anim_enabled)
                self.anim_altered = False
                logger.debug(f"Animações restauradas com sucesso para {self.original_anim_enabled}.")
            if not success and self.state == STATE_DISPATCHING:
                self.state = prev_state

    async def on_window_focused(self, addr: str):
        """Trata evento activewindowv2."""
        normalized_addr = "0x" + addr.lstrip("0x").lower() if addr else ""

        # Caso o foco esteja na janela do ZZZ
        if self.zzz_addr and normalized_addr == self.zzz_addr:
            if self.state in (STATE_ARMED, STATE_IDLE):
                now = time.monotonic()
                if now - self.last_pulse_time < self.cooldown_time:
                    logger.debug(
                        f"Foco no ZZZ dentro da janela de cooldown ({now - self.last_pulse_time:.2f}s < "
                        f"{self.cooldown_time}s). Ignorando pulso redundante."
                    )
                    self.state = STATE_RECOVERED
                    return

                logger.info(
                    f"Foco voluntário detectado na janela do ZZZ ({addr}). "
                    f"Iniciando debounce assíncrono de {self.debounce_time}s..."
                )
                self.state = STATE_DEBOUNCING
                self.cancel_debounce()
                self.debounce_task = asyncio.create_task(self._debounce_worker())
            elif self.state == STATE_RECOVERED:
                # O usuário já está no jogo e já recebeu o pulso; não interfere
                pass
        else:
            # O foco mudou para outro aplicativo ou para vazio
            if self.state == STATE_DEBOUNCING:
                logger.debug(f"Foco transferido para {addr} durante debounce. Cancelando debounce.")
                self.cancel_debounce()
                self.state = STATE_ARMED
            elif self.state == STATE_RECOVERED and normalized_addr != "":
                # Se o usuário saiu do ZZZ para outro aplicativo, re-arma a máquina
                # para que quando ele retornar ao jogo, receba o pulso e não sofra com a perda de XI2
                logger.info(
                    f"Foco saiu da janela do ZZZ para aplicação {addr}. "
                    "Re-armando sentinela (ARMED) para restaurar foco no retorno."
                )
                self.state = STATE_ARMED

    async def _debounce_worker(self):
        """Worker do temporizador de debounce assíncrono."""
        try:
            await asyncio.sleep(self.debounce_time)

            # Confirmação pós-debounce: o ZZZ ainda é a janela ativa no compositor?
            rc, out = await self.run_hyprctl("activewindow", "-j")
            if rc == 0:
                data = json.loads(out)
                current_active = "0x" + data.get("address", "").lstrip("0x").lower()
                if self.zzz_addr and current_active == self.zzz_addr:
                    # Determina workspace ativa
                    rc_ws, out_ws = await self.run_hyprctl("activeworkspace", "-j")
                    target_ws = self.zzz_ws
                    if rc_ws == 0:
                        ws_data = json.loads(out_ws)
                        target_ws = ws_data.get("name", self.zzz_ws)

                    await self.execute_recovery_sequence(str(target_ws))
                else:
                    logger.info("Foco alterado durante a janela de debounce. Mantendo estado ARMED.")
                    self.state = STATE_ARMED
        except asyncio.CancelledError:
            logger.debug("Tarefa de debounce cancelada.")
        except Exception as e:
            logger.error(f"Erro no debounce worker: {e}", exc_info=True)
            self.state = STATE_ARMED

    def cancel_debounce(self):
        """Cancela com segurança qualquer tarefa de debounce em andamento."""
        if self.debounce_task and not self.debounce_task.done():
            self.debounce_task.cancel()
            self.debounce_task = None

    async def on_window_opened(self, addr: str, ws: str, wclass: str, title: str):
        """Trata evento openwindow com proteção contra race conditions."""
        if wclass == self.target_class or title == self.target_title:
            self.zzz_addr = "0x" + addr.lstrip("0x").lower()
            self.zzz_ws = ws
            self.state = STATE_ARMED
            logger.info(
                f"Janela do ZZZ detectada (Addr: {self.zzz_addr}, WS: {self.zzz_ws}, Class: {wclass}, Title: {title}). "
                "Estado: ARMED (aguardando foco voluntário sem interferir no usuário)."
            )

            # Prevenção de race condition: o compositor pode ter focado a janela antes do openwindow
            # ou a janela já foi aberta diretamente em foco. Verifica activewindow imediatamente.
            try:
                rc, out = await self.run_hyprctl("activewindow", "-j")
                if rc == 0:
                    data = json.loads(out)
                    active_addr = "0x" + data.get("address", "").lstrip("0x").lower()
                    if active_addr == self.zzz_addr:
                        logger.info("Janela do ZZZ já é a janela ativa no momento do registro. Iniciando debounce...")
                        await self.on_window_focused(addr)
            except Exception as e:
                logger.debug(f"Verificação de activewindow pós-openwindow ignorada: {e}")

    def on_window_closed(self, addr: str):
        """Trata evento closewindow."""
        normalized = "0x" + addr.lstrip("0x").lower()
        if self.zzz_addr and normalized == self.zzz_addr:
            logger.info("Janela do ZZZ foi fechada. Resetando estado para IDLE.")
            self.cancel_debounce()
            self.state = STATE_IDLE
            self.zzz_addr = None
            self.zzz_ws = None

    async def scan_existing_windows(self):
        """Varre janelas ativas ao inicializar ou reconectar o daemon."""
        logger.debug("Escaneando clientes existentes via hyprctl clients...")
        rc, out = await self.run_hyprctl("clients", "-j")
        if rc == 0:
            try:
                clients = json.loads(out)
                for c in clients:
                    wclass = c.get("class", "")
                    title = c.get("title", "")
                    if wclass == self.target_class or title == self.target_title:
                        addr = c.get("address", "")
                        ws = c.get("workspace", {}).get("name", "3")
                        await self.on_window_opened(addr, ws, wclass, title)
                        break
            except Exception as e:
                logger.error(f"Erro ao interpretar saída de hyprctl clients: {e}")

    async def handle_event(self, line: str):
        """Despacha eventos de linha lidos do socket2."""
        if not line or ">>" not in line:
            return
        ev_type, payload = line.split(">>", 1)

        if ev_type == "openwindow":
            parts = payload.split(",")
            if len(parts) >= 4:
                await self.on_window_opened(parts[0], parts[1], parts[2], parts[3])
        elif ev_type == "activewindowv2":
            await self.on_window_focused(payload.strip())
        elif ev_type == "closewindow":
            self.on_window_closed(payload.strip())

    def get_socket_path(self) -> Optional[Path]:
        """Localiza o socket2 do Hyprland dinamicamente."""
        sig = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
        runtime_dir = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}"))
        hypr_base = runtime_dir / "hypr"

        if sig:
            candidate = hypr_base / sig / ".socket2.sock"
            if candidate.exists():
                return candidate

        # Procura em instâncias ativas caso sig tenha mudado
        if hypr_base.exists():
            for sub in hypr_base.iterdir():
                sock = sub / ".socket2.sock"
                if sock.is_socket():
                    return sock

        return None

    async def run(self):
        """Loop principal assíncrono com reconexão automática."""
        logger.info(
            f"Iniciando ZZZ AutoFix Daemon (Dry-run: {self.dry_run}, "
            f"Dwell: {self.dwell_time}s, Debounce: {self.debounce_time}s, Cooldown: {self.cooldown_time}s)"
        )

        while self.running:
            sock_path = self.get_socket_path()
            if not sock_path:
                logger.warning("Socket IPC do Hyprland (.socket2.sock) não encontrado. Tentando em 2s...")
                await asyncio.sleep(2)
                continue

            try:
                logger.info(f"Conectando a {sock_path}...")
                reader, writer = await asyncio.open_unix_connection(str(sock_path))
                logger.info("Conectado com sucesso ao socket de eventos do Hyprland.")

                # Sincroniza janelas já em execução
                await self.scan_existing_windows()

                while self.running:
                    line = await reader.readline()
                    if not line:
                        logger.warning("Conexão fechada pelo compositor (EOF recebido).")
                        break
                    await self.handle_event(line.decode("utf-8", errors="replace").strip())

                writer.close()
                await writer.wait_closed()
            except asyncio.CancelledError:
                break
            except Exception as e:
                logger.error(f"Erro na conexão IPC: {e}. Tentando reconectar em 2s...")
                await asyncio.sleep(2)

    async def cleanup(self):
        """Garante cancelamento de tarefas e reversão de animações na saída."""
        logger.info("Executando cleanup do daemon...")
        self.cancel_debounce()
        if self.anim_altered:
            logger.info("Restaurando animações para o estado original...")
            await self.set_animation_setting(self.original_anim_enabled)
            self.anim_altered = False
        logger.info("Cleanup concluído.")


async def trigger_manual_pulse(daemon: ZZZAutoFixDaemon):
    """Aciona um pulso de recuperação imediato mantendo as garantias de foco."""
    rc, out = await daemon.run_hyprctl("activeworkspace", "-j")
    target_ws = daemon.zzz_ws or "3"
    if rc == 0:
        try:
            target_ws = json.loads(out).get("name", target_ws)
        except Exception:
            pass
    logger.info(f"Pulso manual acionado para a workspace {target_ws}...")
    await daemon.execute_recovery_sequence(str(target_ws))


async def async_main():
    parser = argparse.ArgumentParser(description="Daemon de recuperação do mouse drag no ZZZ")
    parser.add_argument("--dry-run", action="store_true", help="Monitora eventos sem despachar comandos de foco")
    parser.add_argument("--dwell", type=float, default=0.08, help="Tempo de permanência (segundos) no workspace vazio (default: 0.08)")
    parser.add_argument("--debounce", type=float, default=0.40, help="Tempo de estabilização de foco (segundos) (default: 0.40)")
    parser.add_argument("--cooldown", type=float, default=2.0, help="Tempo de cooldown entre pulsos automáticos (segundos) (default: 2.0)")
    parser.add_argument("--force-pulse", action="store_true", help="Executa um único pulso imediato na workspace atual e sai")
    args = parser.parse_args()

    daemon = ZZZAutoFixDaemon(
        dry_run=args.dry_run,
        dwell_time=args.dwell,
        debounce_time=args.debounce,
        cooldown_time=args.cooldown,
    )

    if args.force_pulse:
        rc, out = await daemon.run_hyprctl("activeworkspace", "-j")
        current_ws = "3"
        if rc == 0:
            try:
                current_ws = json.loads(out).get("name", "3")
            except Exception:
                pass
        logger.info(f"Modo --force-pulse acionado para a workspace {current_ws}...")
        ok = await daemon.execute_recovery_sequence(current_ws)
        sys.exit(0 if ok else 1)

    loop = asyncio.get_running_loop()

    def handle_signal(sig_name: str):
        logger.info(f"Sinal {sig_name} recebido. Finalizando graceful shutdown...")
        daemon.running = False
        for task in asyncio.all_tasks(loop):
            if task is not asyncio.current_task():
                task.cancel()

    for s in (signal.SIGTERM, signal.SIGINT):
        loop.add_signal_handler(s, lambda s=s: handle_signal(signal.Signals(s).name))

    # Suporte a SIGUSR1 para forçar um pulso manual em tempo de execução
    def handle_sigusr1():
        logger.info("Sinal SIGUSR1 recebido. Despachando pulso manual sob demanda...")
        asyncio.create_task(trigger_manual_pulse(daemon))

    try:
        loop.add_signal_handler(signal.SIGUSR1, handle_sigusr1)
    except Exception as e:
        logger.debug(f"Não foi possível registrar handler para SIGUSR1: {e}")

    try:
        await daemon.run()
    finally:
        await daemon.cleanup()


def main():
    logging.basicConfig(
        level=logging.INFO,
        format="[%(asctime)s] [%(levelname)s] [zzz-autofix] %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
        handlers=[
            logging.FileHandler(LOG_FILE, encoding="utf-8"),
            logging.StreamHandler(sys.stderr),
        ],
    )
    try:
        asyncio.run(async_main())
    except (KeyboardInterrupt, asyncio.CancelledError):
        pass


if __name__ == "__main__":
    main()
