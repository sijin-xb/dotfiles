#!/usr/bin/env python3
"""
Kugou Music KRC/LRC Lyric Fetcher for Quickshell Desktop Lyrics.
Searches Kugou API for time-synced KRC lyrics (with per-word timestamps
and optional Chinese translations), decrypts XOR/zlib, with fallback
to lrclib.net and local disk caching.

Speed notes (song-switch latency):
  - The krcs hash lookup for niche songs often comes back empty for the
    first few audio hashes; probing them ONE BY ONE used to cost ~0.9s per
    miss (worst case ~4.5s just searching). The top 3 hashes are now probed
    in parallel, capping the whole search phase at ~0.9s. Results are picked
    by search rank (NOT by which response arrives first — that race once
    cached the wrong song's lyrics under the right key).
  - Do NOT constrain searches by player duration: the KRC timeline length
    often differs from the MPRIS length by >10s, and a duration filter
    then returns zero candidates.
  - Some players (e.g. MoeKoeMusic) report title/artist swapped; if the
    (title, artist) search scores no confident match, (artist, title) is
    tried too. A search result only counts when its songname/singername
    actually match the query, and unmatched results are never cached —
    one bad cache write used to poison the song forever.
  - The plain krcs keyword search is unreliable (fails outright for many
    artist/title combos), so it is only a last-ditch fallback; per-thread
    keep-alive connections shave TCP handshakes off repeated requests.

Output protocol: when invoked with a generation id (argv[4]), the first
stdout line is "@@KRCGEN <id>" so the caller can discard output from a
superseded (killed) fetch.
"""

import sys
import os
import re
import json
import base64
import zlib
import hashlib
import threading
import urllib.parse
from http.client import HTTPConnection, HTTPSConnection

CACHE_DIR = os.path.expanduser("~/.cache/quickshell/kugou_lyrics")
XOR_KEY = [64, 71, 97, 119, 94, 50, 116, 71, 81, 54, 49, 45, 206, 210, 110, 105]
USER_AGENT = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36"

# ---------- HTTP with per-thread keep-alive ----------

_TLS = threading.local()

def _fetch_once(url: str, timeout: float) -> str:
    parsed = urllib.parse.urlsplit(url)
    path = parsed.path + ("?" + parsed.query if parsed.query else "")
    pool = getattr(_TLS, "conns", None)
    if pool is None:
        pool = _TLS.conns = {}
    key = f"{parsed.scheme}://{parsed.netloc}"
    conn = pool.get(key)
    fresh = conn is None
    if fresh:
        cls = HTTPSConnection if parsed.scheme == "https" else HTTPConnection
        conn = cls(parsed.netloc, timeout=timeout)
    try:
        conn.request("GET", path, headers={"User-Agent": USER_AGENT, "Accept": "*/*"})
        resp = conn.getresponse()
        data = resp.read()
        if resp.will_close:
            conn.close()
            pool.pop(key, None)
        elif fresh:
            pool[key] = conn
        return data.decode("utf-8", errors="ignore")
    except Exception:
        try:
            conn.close()
        except Exception:
            pass
        pool.pop(key, None)
        raise

def http_get_text(url: str, timeout: float = 4) -> str:
    """GET with one retry (a pooled connection can go stale between songs)."""
    for attempt in (0, 1):
        try:
            return _fetch_once(url, timeout)
        except Exception:
            if attempt:
                return ""
    return ""

def http_get_json(url: str, timeout: float = 4):
    text = http_get_text(url, timeout)
    try:
        if text:
            return json.loads(text)
    except Exception:
        pass
    return {}

# ---------- KRC decryption ----------

def clean_name(s: str) -> str:
    if not s:
        return ""
    # Remove common clutter in song titles like (feat. ...), [feat. ...], (Live), (Remastered...)
    s = re.sub(r"\(feat\.[^)]*\)", "", s, flags=re.IGNORECASE)
    s = re.sub(r"\[feat\.[^\]]*\]", "", s, flags=re.IGNORECASE)
    s = re.sub(r"\(remastered[^)]*\)", "", s, flags=re.IGNORECASE)
    s = re.sub(r"\[remastered[^\]]*\]", "", s, flags=re.IGNORECASE)
    return s.strip()

def decrypt_krc(b64_content: str) -> str:
    try:
        raw = bytearray(base64.b64decode(b64_content))
        if len(raw) <= 4:
            return ""
        # Check if it is already plain text (some files returned as plain base64 LRC)
        if raw[:4] != b"krc1":
            try:
                text = raw.decode("utf-8")
                if "[" in text and "]" in text:
                    return text
            except Exception:
                pass

        for i in range(4, len(raw)):
            raw[i] ^= XOR_KEY[(i - 4) % len(XOR_KEY)]

        return zlib.decompress(raw[4:]).decode("utf-8", errors="ignore")
    except Exception:
        return ""

# ---------- Candidate search ----------

def norm_text(s: str) -> str:
    """Lowercase and strip all spaces/punctuation, for fuzzy name matching."""
    return re.sub(r"[\s\W_]+", "", (s or "").lower())

def score_song(song: dict, title: str, artist: str, duration_sec: float) -> int:
    """How well does a kugou search hit match the metadata we were given?"""
    name = norm_text(song.get("songname"))
    singer = norm_text(song.get("singername"))
    t, a = norm_text(title), norm_text(artist)
    score = 0
    if t and name:
        if name == t:
            score += 3
        elif t in name or name in t:
            score += 2
    if a and singer:
        if singer == a:
            score += 3
        elif a in singer or singer in a:
            score += 2
    if duration_sec > 0 and song.get("duration"):
        if abs(float(song["duration"]) - duration_sec) <= 5:
            score += 1
    return score

def search_songs(kw: str) -> list:
    try:
        url = (f"http://msearchcdn.kugou.com/api/v3/search/song"
               f"?keyword={urllib.parse.quote(kw)}&page=1&pagesize=5")
        return http_get_json(url, timeout=3).get("data", {}).get("info", []) or []
    except Exception:
        return []

def _probe_hash(h: str, box: dict) -> None:
    url = (f"http://krcs.kugou.com/search?ver=1&man=yes&client=mobi"
           f"&keyword=&duration=0&hash={h}")
    try:
        candidates = http_get_json(url, timeout=3).get("candidates", []) or []
    except Exception:
        return
    if candidates:
        box[h] = candidates

def pick_candidates(songs: list, title: str, artist: str, duration_sec: float):
    """Rank search hits by metadata match, probe their hashes in parallel and
    return (candidates, matched). `matched` means the best hit actually
    corresponds to the requested song — only then may results be cached."""
    if not songs:
        return [], False
    ranked = sorted(songs, key=lambda s: score_song(s, title, artist, duration_sec),
                    reverse=True)
    matched = score_song(ranked[0], title, artist, duration_sec) > 0
    hashes = [s.get("hash") for s in ranked[:3] if s.get("hash")]
    if hashes:
        box = {}
        threads = [threading.Thread(target=_probe_hash, args=(h, box), daemon=True)
                   for h in hashes]
        for t in threads:
            t.start()
        for t in threads:
            t.join(timeout=4)
        for h in hashes:  # respect search rank, ignore response arrival order
            if box.get(h):
                return box[h], matched
    return [], matched

def fetch_candidates(kw: str) -> list:
    """Legacy entry kept for ad-hoc debugging: plain search + probe."""
    candidates, _ = pick_candidates(search_songs(kw), kw, "", 0.0)
    return candidates

def fetch_kugou_lyrics(title: str, artist: str, duration_sec: float):
    """Returns (lyrics, matched). `matched` = a search hit verified against
    title/artist; unmatched lyrics are served but never cached."""
    attempts = [(title, artist)]
    if artist and norm_text(artist) != norm_text(title):
        attempts.append((artist, title))  # some players swap the fields

    unmatched = []
    for t, a in attempts:
        kw = f"{t} {a}".strip()
        if not kw:
            continue
        candidates, matched = pick_candidates(search_songs(kw), t, a, duration_sec)
        if not candidates:
            continue
        lyrics = download_lyrics(candidates)
        if lyrics:
            return lyrics, matched
        if matched:
            unmatched.extend(candidates)

    # Last-ditch fallback: plain keyword search (first word only — adding
    # more makes this endpoint miss songs that the hash flow finds).
    try:
        url = (f"http://krcs.kugou.com/search?ver=1&man=yes&client=mobi"
               f"&keyword={urllib.parse.quote(title.split(' ')[0])}&duration=0&hash=")
        candidates = http_get_json(url, timeout=3).get("candidates", []) or []
        if candidates:
            return download_lyrics(candidates), False
    except Exception:
        pass
    return "", False

def has_timed_lines(text: str) -> bool:
    """Guard against garbage: lyrics must contain at least one timed line."""
    return bool(re.search(r"\[\d+:\d+", text) or re.search(r"^\[\d+,\d+\]", text, re.M))

def download_lyrics(candidates: list) -> str:
    for best in candidates[:2]:
        cand_id = best.get("id")
        access_key = best.get("accesskey")
        if not cand_id or not access_key:
            continue
        fmt = best.get("fmt") or "krc"
        down_url = (f"http://krcs.kugou.com/download?ver=1&client=mobi"
                    f"&id={cand_id}&accesskey={access_key}&fmt={fmt}&charset=utf8")
        down_data = http_get_json(down_url, timeout=4)
        content_b64 = down_data.get("content", "")
        if not content_b64:
            continue

        decrypted = decrypt_krc(content_b64)
        if not decrypted or not has_timed_lines(decrypted):
            continue

        # Embed the translation block if the KRC lacks one
        trans_b64 = down_data.get("trans", "")
        if trans_b64 and "[language:" not in decrypted:
            try:
                raw_trans = base64.b64decode(trans_b64).decode("utf-8", errors="ignore")
                if raw_trans.strip().startswith("{") and "content" in raw_trans:
                    decrypted = f"{decrypted.strip()}\n[language:{trans_b64.strip()}]\n"
            except Exception:
                pass
        return decrypted
    return ""

def fetch_lrclib(title: str, artist: str, duration_sec: float) -> str:
    urls = []
    if duration_sec > 0:
        urls.append(f"https://lrclib.net/api/get?track_name={urllib.parse.quote(title)}&artist_name={urllib.parse.quote(artist)}&duration={int(duration_sec)}")
    urls.append(f"https://lrclib.net/api/search?track_name={urllib.parse.quote(title)}&artist_name={urllib.parse.quote(artist)}")
    urls.append(f"https://lrclib.net/api/search?q={urllib.parse.quote(title + ' ' + artist)}")

    for url in urls:
        data = http_get_json(url, timeout=3)
        if isinstance(data, list) and data:
            data = data[0]
        if isinstance(data, dict):
            synced = data.get("syncedLyrics")
            if synced and synced.strip():
                return synced.strip()
    return ""

def main():
    argv = [a for a in sys.argv[1:] if a != "--refresh"]
    refresh = len(argv) != len(sys.argv) - 1
    if len(argv) < 1:
        sys.exit(0)

    raw_title = argv[0].strip()
    raw_artist = argv[1].strip() if len(argv) > 1 else ""
    duration = float(argv[2]) if len(argv) > 2 and argv[2].replace(".", "", 1).isdigit() else 0.0
    gen = argv[3].strip() if len(argv) > 3 else ""

    def emit(lyrics: str):
        if gen:
            print(f"@@KRCGEN {gen}")
        if lyrics:
            print(lyrics, end="", flush=True)

    if not raw_title:
        emit("")
        return

    title = clean_name(raw_title)
    artist = clean_name(raw_artist)

    # Check disk cache
    os.makedirs(CACHE_DIR, exist_ok=True)
    cache_key = hashlib.md5(f"{title.lower()}_{artist.lower()}".encode("utf-8")).hexdigest()
    cache_file = os.path.join(CACHE_DIR, f"{cache_key}.krc")

    if not refresh and os.path.isfile(cache_file) and os.path.getsize(cache_file) > 10:
        try:
            with open(cache_file, "r", encoding="utf-8") as f:
                emit(f.read())
            return
        except Exception:
            pass

    # 1. Primary: Kugou Music API (KRC format with per-word karaoke and translations)
    lyrics, matched = fetch_kugou_lyrics(title, artist, duration)

    # 2. Fallback: lrclib.net (Standard LRC format)
    if not lyrics:
        lyrics = fetch_lrclib(title, artist, duration)
        matched = bool(lyrics)  # lrclib matches by exact names

    # Cache only verified results: one wrong cache write used to poison a
    # song until the cache was cleared by hand. (--refresh therefore keeps
    # re-fetching unmatched songs instead of locking a wrong result in.)
    if lyrics and matched:
        try:
            with open(cache_file, "w", encoding="utf-8") as f:
                f.write(lyrics)
        except Exception:
            pass
    emit(lyrics)

if __name__ == "__main__":
    main()
