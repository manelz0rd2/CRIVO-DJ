from pathlib import Path

from crivo_dj.paths import find_rekordbox_database, rekordbox_database_candidates


def test_standard_macos_candidate(tmp_path: Path):
    expected = tmp_path / "Library" / "Application Support" / "Pioneer" / "rekordbox" / "master.db"
    expected.parent.mkdir(parents=True)
    expected.write_bytes(b"test")
    assert expected in rekordbox_database_candidates(tmp_path)
    assert find_rekordbox_database(tmp_path) == expected.resolve()


def test_options_json_can_point_to_database(tmp_path: Path):
    expected = tmp_path / "Custom" / "master.db"
    expected.parent.mkdir(parents=True)
    expected.write_bytes(b"test")
    options = tmp_path / "Library" / "Application Support" / "Pioneer" / "rekordboxAgent" / "storage" / "options.json"
    options.parent.mkdir(parents=True)
    options.write_text('{"databasePath": "' + str(expected) + '"}', encoding="utf-8")
    assert find_rekordbox_database(tmp_path) == expected.resolve()

