#!/usr/bin/env python3
"""SPlayer WebSocket → stdout JSON 桥接（供 Quickshell 桌面歌词使用）。

SPlayer 开启「WebSocket 服务」后（默认端口 25885）会推送：
  welcome / song-change / lyric-change / progress-change / status-change
本脚本把其中歌词相关的部分整理成每行一个 JSON，写到 stdout：

  {"type":"hello"}
  {"type":"song","title":...,"artist":...,"album":...,"duration":ms}
  {"type":"lyric","lines":[{"start":ms,"end":ms,"text":"...","translation":"..."}]}
  {"type":"progress","position":ms,"duration":ms}
  {"type":"state","playing":true|false}

连接断开会自动重连（SPlayer 重启后无需干预）。
"""
from __future__ import annotations

import argparse
import base64
import json
import os
import re
import socket
import struct
import sys
import time

HOST = "127.0.0.1"


def emit(obj: dict) -> None:
    """输出一行 JSON 并立即 flush（Quickshell 按行读取）。"""
    sys.stdout.write(json.dumps(obj, ensure_ascii=False) + "\n")
    sys.stdout.flush()


class WsClient:
    """极简 WebSocket 客户端（只依赖标准库）。"""

    def __init__(self, host: str, port: int, path: str = "/") -> None:
        self.host = host
        self.port = port
        self.path = path
        self.sock: socket.socket | None = None

    def connect(self) -> bool:
        try:
            sock = socket.create_connection((self.host, self.port), timeout=5)
        except OSError:
            return False
        key = base64.b64encode(os.urandom(16)).decode()
        req = (
            f"GET {self.path} HTTP/1.1\r\n"
            f"Host: {self.host}:{self.port}\r\n"
            "Upgrade: websocket\r\nConnection: Upgrade\r\n"
            f"Sec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n"
            "Origin: http://127.0.0.1\r\n\r\n"
        )
        sock.sendall(req.encode())
        resp = b""
        while b"\r\n\r\n" not in resp:
            chunk = sock.recv(4096)
            if not chunk:
                sock.close()
                return False
            resp += chunk
        if b"101" not in resp.split(b"\r\n")[0]:
            sock.close()
            return False
        sock.settimeout(None)
        self.sock = sock
        return True

    def _send_frame(self, opcode: int, payload: bytes) -> None:
        assert self.sock is not None
        mask = os.urandom(4)
        masked = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
        header = bytes([0x80 | opcode])
        n = len(payload)
        if n < 126:
            header += bytes([0x80 | n])
        elif n < 65536:
            header += bytes([0x80 | 126]) + struct.pack(">H", n)
        else:
            header += bytes([0x80 | 127]) + struct.pack(">Q", n)
        self.sock.sendall(header + mask + masked)

    def recv(self) -> tuple[int, bytes] | None:
        assert self.sock is not None
        try:
            hdr = self.sock.recv(2)
        except OSError:
            return None
        if len(hdr) < 2:
            return None
        opcode = hdr[0] & 0x0F
        length = hdr[1] & 0x7F
        if length == 126:
            length = struct.unpack(">H", self.sock.recv(2))[0]
        elif length == 127:
            length = struct.unpack(">Q", self.sock.recv(8))[0]
        data = b""
        while len(data) < length:
            chunk = self.sock.recv(length - len(data))
            if not chunk:
                return None
            data += chunk
        return opcode, data

    def pong(self, payload: bytes) -> None:
        try:
            self._send_frame(0x0A, payload)
        except OSError:
            pass

    def close(self) -> None:
        if self.sock is not None:
            try:
                self.sock.close()
            except OSError:
                pass
            self.sock = None


def line_text(line: dict) -> str:
    """把一行歌词拼成纯文本（yrc 是按字分词的，需要拼起来）。"""
    words = line.get("words")
    if isinstance(words, list) and words:
        joined = "".join(str(w.get("word", "")) for w in words if isinstance(w, dict))
        if joined.strip():
            return joined.strip()
    for key in ("text", "content", "lyric", "word"):
        value = line.get(key)
        if isinstance(value, str) and value.strip():
            return value.strip()
    return ""


LRC_TIME_RE = re.compile(r"\[(\d{1,2}):(\d{1,2})(?:[.:](\d{1,3}))?\]")


def parse_lrc_text(text: str) -> list[dict]:
    """解析纯文本 LRC（"[00:12.34]歌词" 形式）。

    有些歌 SPlayer 只拿得到 LRC 文本，lrcData 会是字符串而不是行数组；
    之前只处理数组，这类歌就会解析成空、歌词完全不跟。
    """
    lines: list[dict] = []
    for raw in text.splitlines():
        stamps = LRC_TIME_RE.findall(raw)
        if not stamps:
            continue
        content = LRC_TIME_RE.sub("", raw).strip()
        if not content:
            continue
        for minute, second, frac in stamps:
            ms = int(minute) * 60000 + int(second) * 1000
            if frac:
                ms += int(frac.ljust(3, "0")[:3])
            lines.append({"start": ms, "end": ms, "text": content, "translation": ""})
    lines.sort(key=lambda x: x["start"])
    # 每行的结束时间取下一行的开始时间
    for i, line in enumerate(lines[:-1]):
        line["end"] = lines[i + 1]["start"]
    return lines


def normalize_lyrics(data: dict) -> list[dict]:
    """把 lrcData / yrcData 归一成 [{start, end, text, translation}]（时间单位 ms）。"""
    raw = None
    for key in ("yrcData", "lrcData"):
        value = data.get(key)
        # 字符串 = 纯文本 LRC（SPlayer 在只有 LRC 没有逐字歌词时会这样推）
        if isinstance(value, str) and value.strip():
            parsed = parse_lrc_text(value)
            if parsed:
                return parsed
        if isinstance(value, list) and value:
            raw = value
            break
    if raw is None:
        return []

    lines: list[dict] = []
    for item in raw:
        if not isinstance(item, dict):
            continue
        # 时间字段可能在外层，也可能嵌在 line 里
        inner = item.get("line") if isinstance(item.get("line"), dict) else item
        start = inner.get("startTime", inner.get("start", item.get("startTime")))
        end = inner.get("endTime", inner.get("end", item.get("endTime")))
        if start is None:
            continue
        text = line_text(item if line_text(item) else inner)
        if not text:
            continue
        try:
            start_ms = int(start)
            end_ms = int(end) if end is not None else start_ms
        except (TypeError, ValueError):
            continue
        translation = item.get("translatedLyric") or inner.get("translatedLyric") or ""
        # 音译：SPlayer 给的是整行的 romanLyric，或逐字的 words[].romanWord
        roman = item.get("romanLyric") or inner.get("romanLyric") or ""
        if not roman:
            words = inner.get("words")
            if isinstance(words, list):
                roman = " ".join(
                    str(w.get("romanWord", "")) for w in words
                    if isinstance(w, dict) and w.get("romanWord")
                )
        lines.append({
            "start": start_ms,
            "end": end_ms,
            "text": text,
            "translation": str(translation).strip(),
            "roman": str(roman).strip(),
        })
    lines.sort(key=lambda x: x["start"])
    return lines


def handle_message(client: WsClient, msg: dict, last: dict) -> None:
    kind = msg.get("type")
    data = msg.get("data") or {}

    if kind == "welcome":
        emit({"type": "hello"})
        return

    if kind == "song-change":
        last["duration"] = data.get("duration") or last.get("duration") or 0
        emit({
            "type": "song",
            "title": data.get("title") or data.get("name") or "",
            "artist": data.get("artist") or "",
            "album": data.get("album") or "",
            "duration": last["duration"],
        })
        return

    if kind == "lyric-change":
        lines = normalize_lyrics(data)
        last["lines"] = lines
        emit({"type": "lyric", "lines": lines})
        return

    if kind == "progress-change":
        position = data.get("currentTime")
        duration = data.get("duration") or last.get("duration") or 0
        last["duration"] = duration
        if position is None:
            return
        now = time.monotonic()
        # 限流：进度每 ~250ms 上报一次就够歌词跟词了
        if now - last.get("progress_at", 0) < 0.25:
            return
        last["progress_at"] = now
        emit({"type": "progress", "position": int(position), "duration": int(duration)})
        return

    if kind in ("status-change", "play-state"):
        status = data.get("status")
        emit({"type": "state", "playing": bool(status)})


def main() -> int:
    parser = argparse.ArgumentParser(description="SPlayer WebSocket → stdout JSON 桥接")
    parser.add_argument("--host", default=HOST)
    parser.add_argument("--port", type=int, default=25885)
    parser.add_argument("--path", default="/")
    parser.add_argument("--retry", type=float, default=3.0, help="重连间隔（秒）")
    parser.add_argument("--debug", default="", help="把原始 WS 报文追加写到此文件，用于排查")
    args = parser.parse_args()

    last: dict = {"lines": [], "duration": 0}
    while True:
        client = WsClient(args.host, args.port, args.path)
        if not client.connect():
            emit({"type": "disconnected"})
            time.sleep(args.retry)
            continue
        try:
            while True:
                frame = client.recv()
                if frame is None:
                    break
                opcode, payload = frame
                if opcode == 0x1:
                    if args.debug:
                        try:
                            with open(args.debug, "a", encoding="utf-8") as dbg:
                                dbg.write(payload.decode("utf-8", "replace")[:20000] + "\n")
                        except OSError:
                            pass
                    try:
                        handle_message(client, json.loads(payload.decode("utf-8", "replace")), last)
                    except (ValueError, TypeError) as exc:
                        emit({"type": "error", "message": str(exc)})
                elif opcode == 0x9:
                    client.pong(payload)
                elif opcode == 0x8:
                    break
        except OSError as exc:
            emit({"type": "error", "message": str(exc)})
        finally:
            client.close()
        emit({"type": "disconnected"})
        time.sleep(args.retry)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        raise SystemExit(0)
