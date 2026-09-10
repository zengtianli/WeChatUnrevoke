#!/usr/bin/env python3
"""Edit explicitly selected real recording excerpts, with visible Chinese captions.

Usage: python3 scripts/render-demo.py build/tutorial/edit.json
Raw recordings remain local; the public edit manifest contains only relative names.
"""
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
WORK = ROOT / "build/tutorial"
OUT = ROOT / "docs/demo"


def run(*args):
    subprocess.run(list(map(str, args)), check=True, cwd=ROOT)


def stamp(seconds):
    ms = round(seconds * 1000)
    return f"{ms // 3600000:02}:{ms // 60000 % 60:02}:{ms // 1000 % 60:02}.{ms % 1000:03}"


def main():
    edit = json.loads(Path(sys.argv[1]).read_text())
    run("swiftc", ROOT / "scripts/demo-caption.swift", "-o", WORK / "caption")
    for name, pieces in edit.items():
        parts, cues, elapsed = [], ["WEBVTT\n"], 0
        for i, piece in enumerate(pieces):
            prefix = WORK / f"{name}-{i}"
            spec = prefix.with_suffix(".json")
            spec.write_text(json.dumps({k: piece[k] for k in ("title", "line1", "line2")}, ensure_ascii=False))
            overlay = prefix.with_suffix(".png")
            run(WORK / "caption", spec, overlay)
            segment = prefix.with_suffix(".mp4")
            if piece.get("dialog"):
                layout = "crop=iw-46:ih-46:23:16,scale=450:540:force_original_aspect_ratio=decrease,pad=720:840:(ow-iw)/2:130:color=0xf6f8f3"
            else:
                layout = "crop=620:640:23:16,pad=720:840:50:65:color=0xf6f8f3"
            run("ffmpeg", "-v", "error", "-ss", piece["start"], "-i", WORK / "raw" / piece["source"],
                "-loop", "1", "-i", overlay, "-filter_complex",
                f"[0:v]{layout},fps=24,setsar=1[body];[body][1:v]overlay=0:0:shortest=1[v]",
                "-map", "[v]", "-t", piece["duration"], "-an", "-c:v", "libx264", "-preset", "fast",
                "-crf", "20", "-pix_fmt", "yuv420p", "-movflags", "+faststart", "-y", segment)
            parts.append(segment)
            cues.append(f"{stamp(elapsed)} --> {stamp(elapsed + piece['duration'])}\n{piece['line1']}\n{piece['line2']}\n")
            elapsed += piece["duration"]
        concat = WORK / f"{name}-concat.txt"
        concat.write_text("".join(f"file '{p}'\n" for p in parts))
        run("ffmpeg", "-v", "error", "-f", "concat", "-safe", "0", "-i", concat,
            "-c", "copy", "-movflags", "+faststart", "-y", OUT / f"{name}.mp4")
        (OUT / f"{name}.vtt").write_text("\n".join(cues))
        print(f"Rendered {name}: {elapsed}s")
    names = ("enable", "partial", "restore")
    if all((OUT / f"{name}.mp4").is_file() for name in names):
        concat = WORK / "tutorial-concat.txt"
        concat.write_text("".join(f"file '{OUT / name}.mp4'\n" for name in names))
        run("ffmpeg", "-v", "error", "-f", "concat", "-safe", "0", "-i", concat,
            "-c", "copy", "-movflags", "+faststart", "-y", OUT / "tutorial.mp4")


if __name__ == "__main__":
    main()
