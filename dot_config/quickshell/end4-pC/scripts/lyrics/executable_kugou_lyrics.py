#!/usr/bin/env python3
"""
Kugou Music KRC/LRC Lyric Fetcher for Quickshell Desktop Lyrics.
Searches Kugou API for time-synced KRC lyrics (with per-word timestamps
and optional Chinese translations), decrypts XOR/zlib, with fallback
to lrclib.net and local disk caching.
"""

import sys
import os
import re
import json
import base64
import zlib
import hashlib
import urllib.request
import urllib.parse

CACHE_DIR = os.path.expanduser("~/.cache/quickshell/kugou_lyrics")
XOR_KEY = [64, 71, 97, 119, 94, 50, 116, 71, 81, 54, 49, 45, 206, 210, 110, 105]
USER_AGENT = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36"

def clean_name(s: str) -> str:
    if not s:
        return ""
    # Remove common clutter in song titles like (feat. ...), [feat. ...], (Live), (Remastered...)
    s = re.sub(r"\(feat\.[^)]*\)", "", s, flags=re.IGNORECASE)
    s = re.sub(r"\[feat\.[^\]]*\]", "", s, flags=re.IGNORECASE)
    s = re.sub(r"\(remastered[^)]*\)", "", s, flags=re.IGNORECASE)
    s = re.sub(r"\[remastered[^\]]*\]", "", s, flags=re.IGNORECASE)
    return s.strip()

def http_get_json(url: str, timeout: int = 5) -> dict:
    try:
        req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            data = resp.read().decode("utf-8", errors="ignore")
            if data:
                return json.loads(data)
    except Exception:
        pass
    return {}

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

def fetch_kugou_lyrics(title: str, artist: str, duration_sec: float) -> str:
    kw = f"{title} {artist}".strip()
    if not kw:
        return ""

    # Step 1: Search song on Kugou CDN to get file hash
    search_url = f"http://msearchcdn.kugou.com/api/v3/search/song?keyword={urllib.parse.quote(kw)}&page=1&pagesize=5"
    data = http_get_json(search_url)
    songs = data.get("data", {}).get("info", [])

    candidates = []

    # If songs found, query lyric candidate using the best hash
    for song in songs:
        h = song.get("hash")
        dur_ms = int(float(song.get("duration", 0)) * 1000)
        if not h:
            continue
        cand_url = f"http://krcs.kugou.com/search?ver=1&man=yes&client=mobi&keyword=&duration={dur_ms}&hash={h}"
        cand_data = http_get_json(cand_url)
        c_list = cand_data.get("candidates", [])
        if c_list:
            candidates = c_list
            break

    # If hash search yielded nothing, fallback to keyword search on krcs
    if not candidates:
        dur_ms = int(duration_sec * 1000) if duration_sec > 0 else 0
        cand_url = f"http://krcs.kugou.com/search?ver=1&man=yes&client=mobi&keyword={urllib.parse.quote(kw)}&duration={dur_ms}&hash="
        cand_data = http_get_json(cand_url)
        candidates = cand_data.get("candidates", [])

    if not candidates and title:
        cand_url = f"http://krcs.kugou.com/search?ver=1&man=yes&client=mobi&keyword={urllib.parse.quote(title)}&duration=0&hash="
        cand_data = http_get_json(cand_url)
        candidates = cand_data.get("candidates", [])

    if not candidates:
        return ""

    # Step 2: Download the best candidate
    best = candidates[0]
    cand_id = best.get("id")
    access_key = best.get("accesskey")
    fmt = best.get("fmt", "krc")

    if not cand_id or not access_key:
        return ""

    down_url = f"http://krcs.kugou.com/download?ver=1&client=mobi&id={cand_id}&accesskey={access_key}&fmt={fmt}&charset=utf8"
    down_data = http_get_json(down_url)
    content_b64 = down_data.get("content", "")
    if not content_b64:
        return ""

    decrypted = decrypt_krc(content_b64)
    if not decrypted:
        return ""

    # Check if translation exists in the response and embed it if missing in KRC
    trans_b64 = down_data.get("trans", "")
    if trans_b64 and "[language:" not in decrypted:
        try:
            # If trans is valid json or text, we can append it or format as language tag
            raw_trans = base64.b64decode(trans_b64).decode("utf-8", errors="ignore")
            # If already json
            if raw_trans.strip().startswith("{") and "content" in raw_trans:
                decrypted = f"{decrypted.strip()}\n[language:{trans_b64.strip()}]\n"
        except Exception:
            pass

    return decrypted

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
    if len(sys.argv) < 2:
        sys.exit(0)

    raw_title = sys.argv[1].strip()
    raw_artist = sys.argv[2].strip() if len(sys.argv) > 2 else ""
    duration = float(sys.argv[3]) if len(sys.argv) > 3 and sys.argv[3].replace(".", "", 1).isdigit() else 0.0

    if not raw_title:
        sys.exit(0)

    title = clean_name(raw_title)
    artist = clean_name(raw_artist)

    # Check disk cache
    os.makedirs(CACHE_DIR, exist_ok=True)
    cache_key = hashlib.md5(f"{title.lower()}_{artist.lower()}".encode("utf-8")).hexdigest()
    cache_file = os.path.join(CACHE_DIR, f"{cache_key}.krc")

    if os.path.isfile(cache_file) and os.path.getsize(cache_file) > 10:
        try:
            with open(cache_file, "r", encoding="utf-8") as f:
                print(f.read(), end="", flush=True)
                sys.exit(0)
        except Exception:
            pass

    # 1. Primary: Kugou Music API (KRC format with per-word karaoke and translations)
    lyrics = fetch_kugou_lyrics(title, artist, duration)

    # 2. Fallback: lrclib.net (Standard LRC format)
    if not lyrics:
        lyrics = fetch_lrclib(title, artist, duration)

    if lyrics:
        try:
            with open(cache_file, "w", encoding="utf-8") as f:
                f.write(lyrics)
        except Exception:
            pass
        print(lyrics, end="", flush=True)
    else:
        sys.exit(0)

if __name__ == "__main__":
    main()
