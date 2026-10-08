"""CRIVO DJ helper for transactional Rekordbox 6/7 playlist writes.

Input is a UTF-8 JSON file passed as the only argument. Output is one JSON object.
The caller is responsible for making and restoring a full database backup.
"""

from __future__ import annotations

import json
import logging
import os
import sys
from pathlib import Path

import psutil
from pyrekordbox import Rekordbox6Database


logging.disable(logging.CRITICAL)


def fail(message: str, code: int = 1) -> int:
    print(json.dumps({"success": False, "message": message}, ensure_ascii=True))
    return code


def normalized_path(value: str) -> str:
    return os.path.normcase(os.path.abspath(value))


def ensure_rekordbox_is_closed() -> None:
    blocked = []
    for process in psutil.process_iter(["name"]):
        try:
            name = (process.info.get("name") or "").lower()
            if name in {"rekordbox.exe", "rekordboxagent.exe"}:
                blocked.append(name)
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            continue
    if blocked:
        raise RuntimeError(
            "Feche completamente o Rekordbox e o rekordboxAgent antes da escrita direta."
        )


def get_or_create_artist(db: Rekordbox6Database, name: str):
    if not name:
        return None
    item = db.get_artist(Name=name).one_or_none()
    return item or db.add_artist(name=name)


def get_or_create_genre(db: Rekordbox6Database, name: str):
    if not name or name.startswith("_"):
        return None
    item = db.get_genre(Name=name).one_or_none()
    return item or db.add_genre(name=name)


def get_or_create_album(db: Rekordbox6Database, name: str, artist):
    if not name:
        return None
    item = db.get_album(Name=name).first()
    return item or db.add_album(name=name, artist=artist)


def rekordbox_key_name(value: str) -> str:
    """Accept both Rekordbox's traditional key names and Camelot notation."""
    camelot = {
        "1A": "Abm", "2A": "Ebm", "3A": "Bbm", "4A": "Fm", "5A": "Cm", "6A": "Gm",
        "7A": "Dm", "8A": "Am", "9A": "Em", "10A": "Bm", "11A": "F#m", "12A": "Dbm",
        "1B": "Ab", "2B": "Eb", "3B": "Bb", "4B": "F", "5B": "C", "6B": "G",
        "7B": "D", "8B": "A", "9B": "E", "10B": "B", "11B": "F#", "12B": "Db",
    }
    compact = value.strip().upper()
    return camelot.get(compact, value.strip())


def create_content(db: Rekordbox6Database, track: dict):
    path = Path(track["path"])
    kwargs = {}
    if track.get("title"):
        kwargs["Title"] = str(track["title"])
    if track.get("bpm"):
        kwargs["BPM"] = int(round(float(track["bpm"]) * 100))
    if track.get("year"):
        try:
            kwargs["ReleaseYear"] = int(track["year"])
        except (TypeError, ValueError):
            pass
    if track.get("bitrate"):
        kwargs["BitRate"] = int(track["bitrate"])
    if track.get("sampleRate"):
        kwargs["SampleRate"] = int(track["sampleRate"])

    artist = get_or_create_artist(db, str(track.get("artist") or "").strip())
    genre = get_or_create_genre(db, str(track.get("genre") or "").strip())
    album = get_or_create_album(
        db, str(track.get("album") or "").strip(), artist
    )
    if artist:
        kwargs["ArtistID"] = artist.ID
    if genre:
        kwargs["GenreID"] = genre.ID
    if album:
        kwargs["AlbumID"] = album.ID
    key_name = str(track.get("key") or "").strip()
    if key_name:
        key = db.get_key(ScaleName=key_name).one_or_none()
        if key:
            kwargs["KeyID"] = key.ID
    return db.add_content(path, **kwargs)


def related_name(item, relation: str, field: str = "Name") -> str:
    try:
        related = getattr(item, relation, None)
        return str(getattr(related, field, "") or "") if related else ""
    except Exception:
        return ""


def audit_database(payload: dict) -> dict:
    """Return a read-only, normalized snapshot for the CRIVO audit workflow."""
    database_path = Path(payload["databasePath"]).resolve()
    if not database_path.is_file():
        raise FileNotFoundError(f"Banco do Rekordbox não encontrado: {database_path}")

    db = Rekordbox6Database(path=database_path, db_dir=database_path.parent)
    try:
        playlist_counts: dict[str, int] = {}
        playlist_names: dict[str, list[str]] = {}
        playlists = []
        playlist_rows = list(db.get_playlist())
        playlist_by_id = {
            str(getattr(item, "ID", "") or ""): item
            for item in playlist_rows
            if str(getattr(item, "ID", "") or "")
        }

        def playlist_path(item) -> str:
            names = []
            current = item
            visited = set()
            while current is not None:
                current_id = str(getattr(current, "ID", "") or "")
                if current_id in visited:
                    break
                visited.add(current_id)
                name = str(getattr(current, "Name", "") or "").strip()
                if name:
                    names.append(name)
                parent_id = str(getattr(current, "ParentID", "") or "")
                if not parent_id or parent_id.lower() == "root":
                    break
                current = playlist_by_id.get(parent_id)
            return " / ".join(reversed(names)) or "Playlist"

        for playlist in playlist_rows:
            try:
                songs = list(playlist.Songs)
            except Exception:
                songs = []
            track_ids = []
            for song in songs:
                content_id = str(getattr(song, "ContentID", "") or "")
                if not content_id:
                    continue
                track_ids.append(content_id)
                playlist_counts[content_id] = playlist_counts.get(content_id, 0) + 1
                playlist_names.setdefault(content_id, []).append(playlist_path(playlist))
            if track_ids:
                name = str(getattr(playlist, "Name", "") or "Playlist")
                playlists.append(
                    {"name": name, "path": playlist_path(playlist), "trackCount": len(track_ids), "trackIDs": track_ids}
                )

        tracks = []
        for content in db.get_content():
            track_id = str(getattr(content, "ID", "") or "")
            try:
                analysis_paths = db.get_anlz_paths(content)
                analysis_types = sorted(str(key).upper() for key in analysis_paths.keys())
            except Exception:
                analysis_types = []
            raw_bpm = getattr(content, "BPM", 0) or 0
            try:
                bpm = float(raw_bpm) / 100.0 if float(raw_bpm) > 1000 else float(raw_bpm)
                bpm = int(round(bpm)) if bpm else ""
            except (TypeError, ValueError):
                bpm = ""
            tracks.append(
                {
                    "trackID": track_id,
                    "name": str(getattr(content, "Title", "") or ""),
                    "artist": related_name(content, "Artist"),
                    "album": related_name(content, "Album"),
                    "genre": related_name(content, "Genre"),
                    "year": int(getattr(content, "ReleaseYear", 0) or 0) or "",
                    "bpm": bpm,
                    "key": related_name(content, "Key", "ScaleName"),
                    "bitrate": int(getattr(content, "BitRate", 0) or 0),
                    "sampleRate": int(getattr(content, "SampleRate", 0) or 0),
                    "fileSize": int(getattr(content, "FileSize", 0) or 0),
                    "duration": int(getattr(content, "Length", 0) or 0),
                    "fileType": int(getattr(content, "FileType", 0) or 0),
                    "location": str(getattr(content, "FolderPath", "") or ""),
                    "playlistCount": playlist_counts.get(track_id, 0),
                    "playlists": playlist_names.get(track_id, []),
                    "analysis": ", ".join(analysis_types),
                    "artworkPath": str(getattr(content, "ImagePath", "") or ""),
                }
            )
    finally:
        db.close()

    return {
        "success": True,
        "operation": "audit",
        "databasePath": str(database_path),
        "product": "Rekordbox 6/7",
        "tracks": tracks,
        "playlists": playlists,
    }


def update_metadata(payload: dict) -> dict:
    """Update one existing collection item after an explicit user confirmation."""
    ensure_rekordbox_is_closed()
    database_path = Path(payload["databasePath"]).resolve()
    if not database_path.is_file():
        raise FileNotFoundError(f"Banco do Rekordbox não encontrado: {database_path}")

    track_id = str(payload.get("trackID") or "").strip()
    metadata = dict(payload.get("metadata") or {})
    if not track_id:
        raise ValueError("A track selecionada não possui um identificador do Rekordbox.")

    db = Rekordbox6Database(path=database_path, db_dir=database_path.parent)
    committed = False
    try:
        content = db.get_content(ID=track_id)
        if content is None:
            raise ValueError(f"A track {track_id} não foi encontrada no banco do Rekordbox.")

        title = str(metadata.get("title") or "").strip()
        artist_name = str(metadata.get("artist") or "").strip()
        album_name = str(metadata.get("album") or "").strip()
        genre_name = str(metadata.get("genre") or "").strip()
        key_name = rekordbox_key_name(str(metadata.get("key") or ""))
        if title:
            content.Title = title
        if artist_name:
            artist = get_or_create_artist(db, artist_name)
            content.ArtistID = artist.ID
        else:
            artist = getattr(content, "Artist", None)
        if album_name:
            album = get_or_create_album(db, album_name, artist)
            content.AlbumID = album.ID
        if genre_name:
            genre = get_or_create_genre(db, genre_name)
            if genre:
                content.GenreID = genre.ID
        if key_name:
            key = db.get_key(ScaleName=key_name).one_or_none()
            if key is None:
                raise ValueError(
                    f"A tonalidade '{key_name}' não existe na tabela de tonalidades do Rekordbox."
                )
            content.KeyID = key.ID
        bpm = metadata.get("bpm")
        if bpm not in (None, "", 0, "0"):
            content.BPM = int(round(float(bpm) * 100))
        year = metadata.get("year")
        if year not in (None, "", 0, "0"):
            content.ReleaseYear = int(year)

        db.commit()
        committed = True
    except Exception:
        if not committed:
            db.rollback()
        raise
    finally:
        db.close()

    verify = Rekordbox6Database(path=database_path, db_dir=database_path.parent)
    try:
        content = verify.get_content(ID=track_id)
        if content is None:
            raise RuntimeError("A atualização não pôde ser confirmada no banco do Rekordbox.")
        result = {
            "title": str(getattr(content, "Title", "") or ""),
            "artist": related_name(content, "Artist"),
            "album": related_name(content, "Album"),
            "genre": related_name(content, "Genre"),
            "year": int(getattr(content, "ReleaseYear", 0) or 0) or "",
            "key": related_name(content, "Key", "ScaleName"),
        }
        raw_bpm = int(getattr(content, "BPM", 0) or 0)
        result["bpm"] = raw_bpm / 100.0 if raw_bpm else ""
    finally:
        verify.close()
    return {
        "success": True,
        "operation": "update_metadata",
        "message": "Metadados gravados e confirmados no banco do Rekordbox.",
        "trackID": track_id,
        "metadata": result,
    }


def execute(payload: dict) -> dict:
    operation = str(payload.get("operation") or "").lower()
    if operation == "audit":
        return audit_database(payload)
    if operation == "update_metadata":
        return update_metadata(payload)
    ensure_rekordbox_is_closed()
    database_path = Path(payload["databasePath"]).resolve()
    if not database_path.is_file():
        raise FileNotFoundError(f"Banco do Rekordbox não encontrado: {database_path}")

    playlist_name = str(payload.get("playlistName") or "CRIVO DJ — Organizado").strip()
    tracks = list(payload.get("tracks") or [])
    if not tracks:
        raise ValueError("Nenhuma track foi recebida para a playlist.")
    for track in tracks:
        path = Path(str(track.get("path") or ""))
        if not path.is_file():
            raise FileNotFoundError(f"Track não encontrada: {path}")

    db = Rekordbox6Database(path=database_path, db_dir=database_path.parent)
    committed = False
    try:
        playlist = db.get_playlist(Name=playlist_name, ParentID="root").first()
        created_playlist = playlist is None
        if created_playlist:
            playlist = db.create_playlist(playlist_name)

        content_by_path = {
            normalized_path(str(content.FolderPath)): content
            for content in db.get_content()
            if content.FolderPath
        }
        existing_ids = {str(song.ContentID) for song in playlist.Songs}
        added_content = 0
        added_to_playlist = 0
        already_present = 0
        analyzed_tracks = 0
        tracks_needing_analysis = 0

        for track in tracks:
            key = normalized_path(str(track["path"]))
            content = content_by_path.get(key)
            if content is None:
                content = create_content(db, track)
                content_by_path[key] = content
                added_content += 1
                tracks_needing_analysis += 1
            else:
                try:
                    if db.get_anlz_paths(content):
                        analyzed_tracks += 1
                    else:
                        tracks_needing_analysis += 1
                except Exception:
                    tracks_needing_analysis += 1
            if str(content.ID) in existing_ids:
                already_present += 1
                continue
            db.add_to_playlist(playlist, content)
            existing_ids.add(str(content.ID))
            added_to_playlist += 1

        db.commit()
        committed = True
        playlist_id = str(playlist.ID)
    except Exception:
        if not committed:
            db.rollback()
        raise
    finally:
        db.close()

    verify = Rekordbox6Database(path=database_path, db_dir=database_path.parent)
    try:
        playlist = verify.get_playlist(ID=playlist_id)
        verified_count = len(playlist.Songs)
    finally:
        verify.close()

    return {
        "success": True,
        "message": "Playlist gravada e verificada diretamente no banco do Rekordbox.",
        "playlistName": playlist_name,
        "playlistId": playlist_id,
        "playlistCreated": created_playlist,
        "tracksInPlaylist": verified_count,
        "tracksAddedToCollection": added_content,
        "tracksAddedToPlaylist": added_to_playlist,
        "tracksAlreadyPresent": already_present,
        "analyzedTracks": analyzed_tracks,
        "tracksNeedingAnalysis": tracks_needing_analysis,
    }


def main() -> int:
    if len(sys.argv) != 2:
        return fail("Uso: ODT-RekordboxDirect.exe payload.json", 2)
    try:
        payload = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8-sig"))
        print(json.dumps(execute(payload), ensure_ascii=True))
        return 0
    except Exception as exc:  # The PowerShell caller restores the backup.
        return fail(str(exc), 1)


if __name__ == "__main__":
    raise SystemExit(main())
