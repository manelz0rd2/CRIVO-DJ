from __future__ import annotations

import hashlib
import json
import os
import shutil
import time
from contextlib import contextmanager
from datetime import datetime
from pathlib import Path

import psutil

from .models import Track
from .paths import backup_root


DATABASE_FILES = ("master.db", "master.db-wal", "master.db-shm", "masterPlaylists6.xml", "master.backup.db")


def _database_class():
    from pyrekordbox import Rekordbox6Database

    return Rekordbox6Database


def ensure_rekordbox_closed() -> None:
    blocked = []
    for process in psutil.process_iter(["name"]):
        try:
            name = (process.info.get("name") or "").lower().removesuffix(".exe")
            if name in {"rekordbox", "rekordboxagent"}:
                blocked.append(name)
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            continue
    if blocked:
        raise RuntimeError("Feche completamente o Rekordbox e o rekordboxAgent antes de continuar.")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def create_backup(database_path: Path) -> Path:
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S-%f")
    target = backup_root() / stamp
    target.mkdir(parents=True, exist_ok=False)
    manifest: dict[str, object] = {"database": str(database_path), "created": datetime.now().isoformat(), "files": {}}
    for name in DATABASE_FILES:
        source = database_path.parent / name
        if source.is_file():
            copied = target / name
            shutil.copy2(source, copied)
            source_hash = sha256(source)
            copied_hash = sha256(copied)
            if source_hash != copied_hash:
                raise IOError(f"O backup de {name} não passou na verificação de integridade.")
            manifest["files"][name] = {"sha256": copied_hash, "size": copied.stat().st_size}
    if "master.db" not in manifest["files"]:
        raise FileNotFoundError("O master.db não pôde ser incluído no backup.")
    (target / "manifest.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False), encoding="utf-8")
    return target


def restore_backup(database_path: Path, backup: Path) -> None:
    for name in DATABASE_FILES:
        saved = backup / name
        destination = database_path.parent / name
        if saved.is_file():
            last_error: OSError | None = None
            for _ in range(20):
                try:
                    shutil.copy2(saved, destination)
                    last_error = None
                    break
                except OSError as exc:
                    last_error = exc
                    time.sleep(0.1)
            if last_error is not None:
                raise last_error
        elif destination.is_file() and name in {"master.db-wal", "master.db-shm"}:
            destination.unlink()


@contextmanager
def exclusive_write(database_path: Path):
    lock_path = database_path.parent / ".crivo-dj.lock"
    descriptor = os.open(lock_path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    try:
        os.write(descriptor, str(os.getpid()).encode("ascii"))
        yield
    finally:
        os.close(descriptor)
        lock_path.unlink(missing_ok=True)


def _related(item: object, relation: str, field: str = "Name") -> str:
    try:
        value = getattr(item, relation, None)
        return str(getattr(value, field, "") or "") if value else ""
    except Exception:
        return ""


def _file_state(path: Path) -> str:
    """Return present, missing or inaccessible without aborting a full audit."""
    try:
        return "present" if path.is_file() else "missing"
    except (OSError, PermissionError):
        return "inaccessible"


def audit_database(database_path: Path) -> dict:
    database_path = database_path.expanduser().resolve()
    if not database_path.is_file():
        raise FileNotFoundError(f"Banco do Rekordbox não encontrado: {database_path}")
    Database = _database_class()
    db = Database(path=database_path, db_dir=database_path.parent)
    try:
        playlist_rows = list(db.get_playlist())
        playlist_by_id = {str(item.ID): item for item in playlist_rows if getattr(item, "ID", None)}

        def playlist_path(item: object) -> str:
            names: list[str] = []
            visited: set[str] = set()
            current = item
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
            return " / ".join(reversed(names))

        memberships: dict[str, list[str]] = {}
        for playlist in playlist_rows:
            try:
                songs = list(playlist.Songs)
            except Exception:
                songs = []
            for song in songs:
                content_id = str(getattr(song, "ContentID", "") or "")
                if content_id:
                    memberships.setdefault(content_id, []).append(playlist_path(playlist))

        tracks = []
        healthy = missing_files = attention = 0
        for content in db.get_content():
            location = Path(str(getattr(content, "FolderPath", "") or ""))
            problems: list[str] = []
            file_state = _file_state(location)
            if file_state == "missing":
                problems.append("Sem arquivo físico")
                missing_files += 1
            elif file_state == "inaccessible":
                problems.append("Arquivo inacessível")
                missing_files += 1
            for label, value in (
                ("título", getattr(content, "Title", "")),
                ("artista", _related(content, "Artist")),
                ("gênero", _related(content, "Genre")),
            ):
                if not value:
                    problems.append(f"Sem {label}")
            try:
                analysis = ", ".join(sorted(str(key).upper() for key in db.get_anlz_paths(content).keys()))
            except Exception:
                analysis = ""
            if not analysis:
                problems.append("Sem análise")
            if problems:
                attention += 1
            else:
                healthy += 1
            track_id = str(getattr(content, "ID", "") or "")
            tracks.append(
                {
                    "trackID": track_id,
                    "title": str(getattr(content, "Title", "") or ""),
                    "artist": _related(content, "Artist"),
                    "album": _related(content, "Album"),
                    "genre": _related(content, "Genre"),
                    "location": str(location),
                    "problems": problems,
                    "playlists": memberships.get(track_id, []),
                    "analysis": analysis,
                }
            )
        return {
            "databasePath": str(database_path),
            "tracks": tracks,
            "summary": {"total": len(tracks), "healthy": healthy, "attention": attention, "missingFiles": missing_files},
        }
    finally:
        _close_database(db)


def _normal_path(value: str | Path) -> str:
    # Do not resolve the filesystem here: a collection can legitimately refer
    # to an offline external volume. Path comparison must not abort the write.
    return os.path.normcase(os.path.abspath(os.path.expanduser(os.fspath(value))))


def _close_database(db) -> None:
    """Close the SQLAlchemy session and release SQLCipher file handles."""
    if db is None:
        return
    try:
        if getattr(db, "session", None) is not None:
            db.close()
    finally:
        engine = getattr(db, "engine", None)
        if engine is not None:
            engine.dispose()


def _get_or_create(db, kind: str, name: str, artist=None):
    if not name:
        return None
    if kind == "artist":
        return db.get_artist(Name=name).one_or_none() or db.add_artist(name=name)
    if kind == "genre":
        return db.get_genre(Name=name).one_or_none() or db.add_genre(name=name)
    if kind == "album":
        return db.get_album(Name=name).first() or db.add_album(name=name, artist=artist)
    raise ValueError(kind)


def _create_content(db, track: Track):
    if track.path is None:
        raise ValueError("Track sem arquivo local.")
    kwargs: dict[str, object] = {"Title": track.title or track.path.stem}
    if track.bpm:
        kwargs["BPM"] = int(round(track.bpm * 100))
    if track.year:
        kwargs["ReleaseYear"] = int(track.year)
    if track.bitrate:
        kwargs["BitRate"] = int(track.bitrate)
    if track.sample_rate:
        kwargs["SampleRate"] = int(track.sample_rate)
    artist = _get_or_create(db, "artist", track.artist.strip())
    genre = _get_or_create(db, "genre", track.genre.strip())
    album = _get_or_create(db, "album", track.album.strip(), artist)
    if artist:
        kwargs["ArtistID"] = artist.ID
    if genre:
        kwargs["GenreID"] = genre.ID
    if album:
        kwargs["AlbumID"] = album.ID
    return db.add_content(track.path, **kwargs)


def write_playlist(database_path: Path, playlist_name: str, tracks: list[Track]) -> dict:
    ensure_rekordbox_closed()
    database_path = database_path.expanduser().resolve()
    if not database_path.is_file():
        raise FileNotFoundError(f"Banco do Rekordbox não encontrado: {database_path}")
    playlist_name = playlist_name.strip() or "CRIVO DJ — Organizado"
    if not tracks:
        raise ValueError("Nenhuma track foi recebida para a playlist.")
    for track in tracks:
        if not track.path or not track.path.is_file():
            raise FileNotFoundError(f"Track não encontrada: {track.path}")

    with exclusive_write(database_path):
        backup = create_backup(database_path)
        Database = _database_class()
        db = None
        committed = False
        try:
            db = Database(path=database_path, db_dir=database_path.parent)
            playlist = db.get_playlist(Name=playlist_name, ParentID="root").first()
            created = playlist is None
            if created:
                playlist = db.create_playlist(playlist_name)
            content_by_path = {
                _normal_path(content.FolderPath): content
                for content in db.get_content()
                if getattr(content, "FolderPath", None)
            }
            existing_ids = {str(song.ContentID) for song in playlist.Songs}
            added_collection = added_playlist = already_present = 0
            for track in tracks:
                content = content_by_path.get(_normal_path(track.path))
                if content is None:
                    content = _create_content(db, track)
                    content_by_path[_normal_path(track.path)] = content
                    added_collection += 1
                if str(content.ID) in existing_ids:
                    already_present += 1
                    continue
                db.add_to_playlist(playlist, content)
                existing_ids.add(str(content.ID))
                added_playlist += 1
            playlist_id = str(playlist.ID)
            db.commit()
            committed = True
        except Exception:
            if db is not None and not committed:
                try:
                    db.rollback()
                except Exception:
                    pass
            if db is not None:
                _close_database(db)
                db = None
            restore_backup(database_path, backup)
            raise
        finally:
            if db is not None:
                _close_database(db)

        try:
            verify = Database(path=database_path, db_dir=database_path.parent)
            try:
                playlist = verify.get_playlist(ID=playlist_id)
                verified_count = len(playlist.Songs)
                verified_ids = {str(song.ContentID) for song in playlist.Songs}
                if len(verified_ids) != verified_count:
                    raise RuntimeError("A playlist gravada contém associações duplicadas.")
            finally:
                _close_database(verify)
        except Exception:
            restore_backup(database_path, backup)
            raise RuntimeError("A verificação posterior falhou; o backup original foi restaurado.")

    return {
        "playlistName": playlist_name,
        "playlistCreated": created,
        "tracksInPlaylist": verified_count,
        "tracksAddedToCollection": added_collection,
        "tracksAddedToPlaylist": added_playlist,
        "tracksAlreadyPresent": already_present,
        "backup": str(backup),
    }

