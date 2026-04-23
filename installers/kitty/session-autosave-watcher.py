from __future__ import annotations

from typing import Any
import os
import re
import shlex
import time
from pathlib import Path

from kitty.boss import Boss
try:
    from kitty.fast_data_types import (
        CLOSE_BEING_CONFIRMED,
        IMPERATIVE_CLOSE_REQUESTED,
        add_timer,
        current_application_quit_request,
    )
except Exception:
    from kitty.fast_data_types import add_timer
    CLOSE_BEING_CONFIRMED = None
    IMPERATIVE_CLOSE_REQUESTED = None
    current_application_quit_request = None
from kitty.window import Window

# ------------------------------------------------------------
# Manual settings (edit these)
# ------------------------------------------------------------

# Toggle logging by editing this value:
LOG_ENABLED = True
LOG_EVENTS = True

# Default session/log paths if env vars are not set:
DEFAULT_SESSION_PATH = os.path.expanduser("~/.config/kitty/quake.session")
DEFAULT_LOG_PATH = os.path.expanduser("~/.config/kitty/quake.session.log")

# Rate limit for noisy events (resize). New windows and close events are not rate-limited.
RESIZE_MIN_INTERVAL_MS = 250

# Save after close events, but debounce to avoid overwriting the session while quitting.
SAVE_ON_CLOSE = True
# How long to wait after the last close event before saving (ms).
CLOSE_DEBOUNCE_MS = 300

# Optional: enable --use-foreground-process (risky on restore). Keep False unless you know why you want it.
USE_FOREGROUND_PROCESS = False

# ------------------------------------------------------------
# Env overrides (optional)
# ------------------------------------------------------------
SESSION_PATH_ENV = "KITTY_AUTOSAVE_SESSION_PATH"
LOG_PATH_ENV = "KITTY_AUTOSAVE_LOG_PATH"

# Heuristic: save after commands that typically change cwd
CWD_CMD_RE = re.compile(r'(^|[;&|() \t])(cd|pushd|popd)\b')

_last_save_ts = 0.0
_autosave_disabled = False
_close_save_seq = 0


def _log_path() -> str:
    p = os.environ.get(LOG_PATH_ENV, "").strip() or DEFAULT_LOG_PATH
    p = os.path.expanduser(os.path.expandvars(p))
    try:
        Path(p).parent.mkdir(parents=True, exist_ok=True)
    except Exception:
        pass
    return p


def _log(msg: str) -> None:
    if not LOG_ENABLED:
        return
    try:
        with open(_log_path(), "a", encoding="utf-8") as f:
            f.write(msg + "\n")
    except Exception:
        pass


def _log_event(msg: str) -> None:
    if LOG_ENABLED and LOG_EVENTS:
        _log(msg)


def _session_path_arg() -> str:
    raw = os.environ.get(SESSION_PATH_ENV, "").strip()
    p = raw or DEFAULT_SESSION_PATH
    p = os.path.expanduser(os.path.expandvars(p))
    try:
        Path(p).parent.mkdir(parents=True, exist_ok=True)
    except Exception:
        pass
    return shlex.quote(p)


def _save_as_session_action() -> str:
    parts: list[str] = ["save_as_session", "--save-only", "--relocatable"]

    if USE_FOREGROUND_PROCESS:
        parts.append("--use-foreground-process")

    parts.append(_session_path_arg())
    return " ".join(parts)


def _is_window_usable(w: Window | None) -> bool:
    return w is not None and not getattr(w, "destroyed", False)


def _pick_window_for_save(boss: Boss, preferred: Window | None) -> Window | None:
    if _is_window_usable(preferred):
        return preferred
    w = getattr(boss, "window_for_dispatch", None)
    if _is_window_usable(w):
        return w
    w = getattr(boss, "active_window", None)
    if _is_window_usable(w):
        return w
    for w in boss.all_windows:
        if _is_window_usable(w):
            return w
    return None


def _count_windows(boss: Boss) -> int:
    return sum(1 for w in boss.all_windows if _is_window_usable(w))


def _is_quitting() -> bool:
    if current_application_quit_request is None:
        return False
    try:
        req = current_application_quit_request()
    except Exception:
        return False
    if IMPERATIVE_CLOSE_REQUESTED is None and CLOSE_BEING_CONFIRMED is None:
        return bool(req)
    return req in (IMPERATIVE_CLOSE_REQUESTED, CLOSE_BEING_CONFIRMED)


def _rate_limited(min_interval_s: float) -> bool:
    global _last_save_ts
    now = time.monotonic()
    if min_interval_s > 0 and (now - _last_save_ts) < min_interval_s:
        return True
    _last_save_ts = now
    return False


def _save(boss: Boss, window: Window, reason: str, min_interval_s: float) -> None:
    global _autosave_disabled
    if _autosave_disabled:
        _log_event(f"{time.strftime('%F %T')} skip save reason={reason} (autosave_disabled)")
        return

    if _rate_limited(min_interval_s):
        _log_event(f"{time.strftime('%F %T')} skip save reason={reason} (rate_limited)")
        return

    w = _pick_window_for_save(boss, window)
    if w is None:
        _log(f"{time.strftime('%F %T')} skip save reason={reason} (no windows)")
        return

    action_str = _save_as_session_action()
    _log(f"{time.strftime('%F %T')} save reason={reason} action={action_str}")

    try:
        # Pass the whole action as a single string
        boss.call_remote_control(
            w,
            (
                "action",
                f"--match=id:{w.id}",
                action_str,
            ),
        )
    except Exception as e:
        # Safety fuse: prevent loops/overlays if something goes wrong.
        _autosave_disabled = True
        _log(f"{time.strftime('%F %T')} ERROR disabling autosave: {e!r}")


def on_start(boss: Boss, window: Window, data: dict[str, Any]) -> None:
    _log(f"{time.strftime('%F %T')} watcher loaded pid={os.getpid()} session={DEFAULT_SESSION_PATH}")
    _log_event(
        f"{time.strftime('%F %T')} config"
        f" save_on_close={SAVE_ON_CLOSE}"
        f" close_debounce_ms={CLOSE_DEBOUNCE_MS}"
        f" resize_min_ms={RESIZE_MIN_INTERVAL_MS}"
        f" use_foreground_process={USE_FOREGROUND_PROCESS}"
    )


def on_resize(boss: Boss, window: Window, data: dict[str, Any]) -> None:
    # Fires on real resizes and also on new window creation (new tab/split)
    og = data.get("old_geometry")
    is_new = (
        og is not None
        and getattr(og, "xnum", 1) == 0
        and getattr(og, "ynum", 1) == 0
    )

    if is_new:
        _save(boss, window, reason="new_window", min_interval_s=0.0)
    else:
        _save(
            boss,
            window,
            reason="resize",
            min_interval_s=max(RESIZE_MIN_INTERVAL_MS, 0) / 1000.0,
        )


def on_close(boss: Boss, window: Window, data: dict[str, Any]) -> None:
    if not SAVE_ON_CLOSE:
        return

    global _close_save_seq
    _close_save_seq += 1
    seq = _close_save_seq
    _log_event(
        f"{time.strftime('%F %T')} close event seq={seq}"
        f" windows={_count_windows(boss)}"
        f" quitting={_is_quitting()}"
    )

    def _cb(timer_id: int | None = None) -> None:
        if seq != _close_save_seq:
            _log_event(f"{time.strftime('%F %T')} skip save reason=close (superseded)")
            return
        if _is_quitting():
            _log(f"{time.strftime('%F %T')} skip save reason=close (quit_request)")
            return
        if _count_windows(boss) == 0:
            _log(f"{time.strftime('%F %T')} skip save reason=close (no windows)")
            return
        _save(boss, window, reason="close", min_interval_s=0.0)

    add_timer(_cb, max(CLOSE_DEBOUNCE_MS, 0) / 1000.0, False)


def on_cmd_startstop(boss: Boss, window: Window, data: dict[str, Any]) -> None:
    # Needs kitty shell integration to provide cmdline reliably
    if data.get("is_start"):
        return
    cmdline = (data.get("cmdline") or "").strip()
    if cmdline and CWD_CMD_RE.search(cmdline):
        _save(boss, window, reason=f"cwd_cmd:{cmdline}", min_interval_s=0.0)
