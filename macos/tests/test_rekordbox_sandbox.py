from __future__ import annotations

import os
import shutil
from pathlib import Path

import pytest

import crivo_dj.rekordbox as rb
from crivo_dj.models import Track


def test_real_database_copy_can_read_write_and_remain_idempotent(tmp_path: Path, monkeypatch):
    """Opt-in integration test; it never opens the real database for writing."""
    configured = os.environ.get("CRIVO_REKORDBOX_TEST_DB", "")
    if not configured:
        pytest.skip("Defina CRIVO_REKORDBOX_TEST_DB para testar uma cópia do banco real.")
    real = Path(configured).expanduser().resolve()
    if not real.is_file():
        pytest.skip("O banco indicado não existe.")

    original_hash = rb.sha256(real)
    sandbox = tmp_path / "rekordbox"
    sandbox.mkdir()
    for name in rb.DATABASE_FILES:
        source = real.parent / name
        if source.is_file():
            shutil.copy2(source, sandbox / name)
    database = sandbox / "master.db"
    audio = tmp_path / "MANELZ0RD - Teste CRIVO.mp3"
    audio.write_bytes(b"ID3")
    monkeypatch.setattr(rb, "backup_root", lambda: tmp_path / "backups")
    track = Track(
        path=audio,
        title="Teste CRIVO macOS",
        artist="MANELZ0RD",
        album="Teste seguro",
        genre="House",
        year=2026,
        bitrate=320,
        sample_rate=44100,
    )

    first = rb.write_playlist(database, "CRIVO DJ - TESTE SANDBOX", [track])
    second = rb.write_playlist(database, "CRIVO DJ - TESTE SANDBOX", [track])

    assert first["tracksAddedToCollection"] == 1
    assert first["tracksAddedToPlaylist"] == 1
    assert second["tracksAddedToCollection"] == 0
    assert second["tracksAddedToPlaylist"] == 0
    assert second["tracksAlreadyPresent"] == 1
    assert rb.sha256(real) == original_hash

