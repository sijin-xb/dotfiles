#!/usr/bin/env bash
# Extract a single frame from a video as the freedesktop-spec thumbnail
# for the given size bucket.
#
# Crucially, the cache path is computed inside this script from the
# source path (md5 of file://<video>), so the ffmpeg -i and the final
# `mv -f ... "$out"` can NEVER disagree due to a QML binding-order race:
# one input, one derived target. mktemp guarantees a unique tmp file.
#
# Usage:
#   generate-video-thumbnail.sh <video> <size> [--force]
#   generate-video-thumbnail.sh --dir <dir> <size> [--force]   # iterate *.mp4/webm/mkv/avi/mov
#
# Exit: 0 success / already cached, 2 ffmpeg failed, 1 invalid args.

set -euo pipefail

usage() {
    echo "usage: $0 <video> <size> [--force] | --dir <dir> <size> [--force]" >&2
    exit 1
}

force=0
case "${1:-}" in
    --dir)
        [[ $# -ge 3 ]] || usage
        dir="$2"
        size="$3"
        [[ "${4:-}" == "--force" ]] && force=1
        case "$size" in
            normal|large|x-large|xx-large) ;;
            *) echo "bad size '$size'" >&2; exit 1 ;;
        esac
        [[ -d "$dir" ]] || { echo "no dir '$dir'" >&2; exit 1; }
        shopt -s nullglob nocaseglob
        for v in "$dir"/*.mp4 "$dir"/*.webm "$dir"/*.mkv "$dir"/*.avi "$dir"/*.mov; do
            "$0" "$v" "$size" $([ "$force" = 1 ] && echo --force) || true
        done
        exit 0
        ;;
    *)
        [[ $# -ge 2 ]] || usage
        video="$1"
        size="$2"
        [[ "${3:-}" == "--force" ]] && force=1
        ;;
esac

case "$size" in
    normal)   max=128  ;;
    large)    max=256  ;;
    x-large)  max=512  ;;
    xx-large) max=1024 ;;
    *) echo "bad size '$size'" >&2; exit 1 ;;
esac

[[ -f "$video" ]] || { echo "no video '$video'" >&2; exit 1; }

# Cache path keyed off the source path so target can never mismatch input.
md5="$(printf 'file://%s' "$video" | md5sum | awk '{print $1}')"
out="$HOME/.cache/thumbnails/$size/$md5.png"
mkdir -p "$(dirname "$out")"

if [[ -s "$out" && "$force" != "1" ]]; then
    exit 0
fi
[[ "$force" == "1" ]] && rm -f "$out"

tmp="$(mktemp "$(dirname "$out")/vidthumb-XXXXXX.png")"
# mktemp sometimes 0600; QML Image needs read.
chmod 0644 "$tmp" 2>/dev/null || true
trap 'rm -f "$tmp"' EXIT

filter="scale=$max:$max:force_original_aspect_ratio=decrease"
# Try frame at 1s first (skips black intros), fall back to 0s.
if ffmpeg -nostdin -loglevel error -y -ss 1 -i "$video" \
        -frames:v 1 -an -sn -threads 1 -vf "$filter" "$tmp" \
   || ffmpeg -nostdin -loglevel error -y -ss 0 -i "$video" \
        -frames:v 1 -an -sn -threads 1 -vf "$filter" "$tmp"; then
    if [[ -s "$tmp" ]]; then
        mv -f "$tmp" "$out"
        trap - EXIT
        exit 0
    fi
fi
echo "ffmpeg failed for $video" >&2
exit 2