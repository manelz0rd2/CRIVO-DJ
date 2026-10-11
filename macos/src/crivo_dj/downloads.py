from __future__ import annotations

import re
import subprocess
import sys
import os
from pathlib import Path
from urllib.parse import urlparse

from .models import Track


def _bundled_ffmpeg() -> str:
    import imageio_ffmpeg

    executable = imageio_ffmpeg.get_ffmpeg_exe()
    os.environ["PATH"] = str(Path(executable).parent) + os.pathsep + os.environ.get("PATH", "")
    return executable


def _spotdl_command() -> list[str]:
    if getattr(sys, "frozen", False):
        bundle = Path(getattr(sys, "_MEIPASS", Path(sys.executable).parent))
        helper = bundle / "crivo-spotdl-helper"
        if not helper.is_file():
            raise FileNotFoundError("O componente interno do Spotify não foi encontrado no aplicativo.")
        return [str(helper)]
    return [sys.executable, "-m", "spotdl"]


def source_name(url: str) -> str:
    host = urlparse(url).netloc.lower().removeprefix("www.")
    if "youtube" in host or "youtu.be" in host:
        return "YouTube"
    if "soundcloud" in host:
        return "SoundCloud"
    if "spotify" in host:
        return "Spotify"
    return host or "Link"


def validate_url(url: str) -> str:
    url = url.strip()
    parsed = urlparse(url)
    if parsed.scheme not in {"http", "https"} or not parsed.netloc:
        raise ValueError("Cole um link válido do YouTube, SoundCloud ou Spotify.")
    if not any(name in parsed.netloc.lower() for name in ("youtube", "youtu.be", "soundcloud", "spotify")):
        raise ValueError("Esta versão aceita YouTube, SoundCloud e Spotify.")
    return url


def _entry_track(entry: dict, fallback_url: str) -> Track:
    title = str(entry.get("track") or entry.get("title") or "Track").strip()
    artist = str(entry.get("artist") or entry.get("uploader") or entry.get("creator") or "").strip()
    url = str(entry.get("webpage_url") or entry.get("url") or fallback_url)
    thumbnails = entry.get("thumbnails") or []
    artwork = str(entry.get("thumbnail") or (thumbnails[-1].get("url") if thumbnails else "") or "")
    return Track(
        source_url=url,
        title=title,
        artist=artist,
        duration=float(entry.get("duration") or 0),
        artwork_url=artwork,
        source=source_name(fallback_url),
    )


def resolve_url(url: str) -> list[Track]:
    url = validate_url(url)
    if "spotify" in urlparse(url).netloc.lower():
        label = "Playlist do Spotify" if "/playlist/" in url else "Track do Spotify"
        return [Track(source_url=url, title=label, source="Spotify", status="Será resolvida pelo spotDL")]
    from yt_dlp import YoutubeDL

    options = {
        "quiet": True,
        "no_warnings": True,
        "extract_flat": "in_playlist",
        "skip_download": True,
        "socket_timeout": 20,
    }
    with YoutubeDL(options) as ydl:
        info = ydl.extract_info(url, download=False)
    entries = [entry for entry in (info.get("entries") or []) if entry] if isinstance(info, dict) else []
    if entries:
        return [_entry_track(entry, url) for entry in entries]
    return [_entry_track(info, url)]


def download_track(track: Track, destination: Path) -> list[Path]:
    destination.mkdir(parents=True, exist_ok=True)
    url = validate_url(track.source_url)
    ffmpeg = _bundled_ffmpeg()
    if "spotify" in urlparse(url).netloc.lower():
        before = {path.resolve() for path in destination.rglob("*") if path.is_file()}
        command = _spotdl_command() + [
            "download",
            url,
            "--output",
            str(destination / "{artist} - {title}.{output-ext}"),
            "--format",
            "mp3",
            "--bitrate",
            "320k",
            "--ffmpeg",
            ffmpeg,
        ]
        subprocess.run(command, check=True)
        return [path for path in destination.rglob("*") if path.is_file() and path.resolve() not in before]

    from yt_dlp import YoutubeDL

    output = str(destination / "%(artist,uploader)s - %(title)s.%(ext)s")
    options = {
        "format": "bestaudio/best",
        "outtmpl": output,
        "writethumbnail": True,
        "postprocessors": [
            {"key": "FFmpegExtractAudio", "preferredcodec": "mp3", "preferredquality": "320"},
            {"key": "FFmpegMetadata", "add_metadata": True},
            {"key": "EmbedThumbnail"},
        ],
        "noplaylist": True,
        "quiet": True,
        "no_warnings": True,
        "ffmpeg_location": ffmpeg,
    }
    before = {path.resolve() for path in destination.rglob("*") if path.is_file()}
    with YoutubeDL(options) as ydl:
        ydl.download([url])
    return [path for path in destination.rglob("*") if path.is_file() and path.resolve() not in before]

