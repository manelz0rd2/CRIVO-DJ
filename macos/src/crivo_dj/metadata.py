from __future__ import annotations

from pathlib import Path

from mutagen import File as MutagenFile

from .models import Track


AUDIO_EXTENSIONS = {".mp3", ".wav", ".flac", ".aiff", ".aif", ".m4a", ".aac", ".ogg", ".wma"}


def _first(tags: object, names: tuple[str, ...]) -> str:
    if tags is None:
        return ""
    for name in names:
        try:
            value = tags.get(name)
        except AttributeError:
            value = None
        if value:
            if isinstance(value, (list, tuple)):
                value = value[0] if value else ""
            return str(value).strip()
    return ""


def read_track(path: Path) -> Track:
    audio = MutagenFile(path, easy=True)
    tags = getattr(audio, "tags", None)
    info = getattr(audio, "info", None)
    title = _first(tags, ("title", "TITLE")) or path.stem
    artist = _first(tags, ("artist", "albumartist", "ARTIST"))
    year_text = _first(tags, ("date", "year", "DATE"))
    try:
        year = int(year_text[:4]) if year_text else None
    except ValueError:
        year = None
    return Track(
        path=path.resolve(),
        title=title,
        artist=artist,
        album=_first(tags, ("album", "ALBUM")),
        genre=_first(tags, ("genre", "GENRE")),
        year=year,
        bpm=float(_first(tags, ("bpm", "BPM")) or 0) or None,
        key=_first(tags, ("initialkey", "key", "INITIALKEY")),
        bitrate=int(getattr(info, "bitrate", 0) or 0) // 1000,
        sample_rate=int(getattr(info, "sample_rate", 0) or 0),
        duration=float(getattr(info, "length", 0) or 0),
        source="Arquivo local",
    )


def scan_audio(directory: Path) -> list[Track]:
    if not directory.is_dir():
        raise NotADirectoryError(f"Pasta não encontrada: {directory}")
    tracks: list[Track] = []
    for path in sorted(directory.rglob("*")):
        if path.is_file() and path.suffix.lower() in AUDIO_EXTENSIONS:
            try:
                tracks.append(read_track(path))
            except Exception:
                tracks.append(Track(path=path.resolve(), title=path.stem, source="Arquivo local", status="Dados parciais"))
    return tracks


def missing_fields(track: Track) -> list[str]:
    fields = []
    for label, value in (
        ("título", track.title),
        ("artista", track.artist),
        ("álbum", track.album),
        ("gênero", track.genre),
        ("ano", track.year),
    ):
        if not value:
            fields.append(label)
    return fields

