from __future__ import annotations

import re
import shutil
from pathlib import Path

from .models import Track


def safe_component(value: str, fallback: str) -> str:
    value = re.sub(r"[/:\x00]", "-", value).strip().strip(".")
    return value or fallback


def organize_tracks(tracks: list[Track], destination: Path, copy_files: bool = True) -> list[Track]:
    destination.mkdir(parents=True, exist_ok=True)
    results: list[Track] = []
    for track in tracks:
        if not track.path or not track.path.is_file():
            raise FileNotFoundError(f"Arquivo não encontrado: {track.path}")
        genre = safe_component(track.genre, "Gênero não informado")
        artist = safe_component(track.artist, "Artista não informado")
        title = safe_component(track.title, track.path.stem)
        folder = destination / genre
        folder.mkdir(parents=True, exist_ok=True)
        target = folder / f"{artist} - {title}{track.path.suffix.lower()}"
        if target.exists() and target.resolve() != track.path.resolve():
            index = 2
            while True:
                alternative = target.with_stem(f"{target.stem} ({index})")
                if not alternative.exists():
                    target = alternative
                    break
                index += 1
        if target.resolve() != track.path.resolve():
            if copy_files:
                shutil.copy2(track.path, target)
            else:
                shutil.move(track.path, target)
        track.path = target.resolve()
        track.status = "Organizada"
        results.append(track)
    return results

