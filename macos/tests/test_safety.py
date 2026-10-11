from pathlib import Path

from crivo_dj.rekordbox import create_backup, restore_backup, sha256


def test_backup_is_verified_and_restorable(tmp_path: Path, monkeypatch):
    database_dir = tmp_path / "rekordbox"
    database_dir.mkdir()
    database = database_dir / "master.db"
    database.write_bytes(b"original database")
    backups = tmp_path / "backups"
    monkeypatch.setattr("crivo_dj.rekordbox.backup_root", lambda: backups)
    backup = create_backup(database)
    assert sha256(backup / "master.db") == sha256(database)
    database.write_bytes(b"changed")
    restore_backup(database, backup)
    assert database.read_bytes() == b"original database"

