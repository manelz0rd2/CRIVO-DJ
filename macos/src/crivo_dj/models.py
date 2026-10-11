from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path


@dataclass(slots=True)
class Track:
    path: Path | None = None
    source_url: str = ""
    title: str = ""
    artist: str = ""
    album: str = ""
    genre: str = ""
    year: int | None = None
    bpm: float | None = None
    key: str = ""
    bitrate: int = 0
    sample_rate: int = 0
    duration: float = 0
    artwork_url: str = ""
    source: str = ""
    status: str = "Pronto"
    track_id: str = ""
    playlists: list[str] = field(default_factory=list)
    analysis: str = ""

    def rekordbox_payload(self) -> dict:
        if self.path is None:
            raise ValueError("A track ainda não possui arquivo local.")
        return {
            "path": str(self.path.resolve()),
            "title": self.title,
            "artist": self.artist,
            "album": self.album,
            "genre": self.genre,
            "year": self.year,
            "bpm": self.bpm,
            "key": self.key,
            "bitrate": self.bitrate,
            "sampleRate": self.sample_rate,
        }

