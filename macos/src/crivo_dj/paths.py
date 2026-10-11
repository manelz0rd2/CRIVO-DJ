from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Iterable

APP_NAME = "CRIVO DJ"


def app_data_dir() -> Path:
    # Native macOS location. Keeping this explicit also makes the application
    # independent from environment-specific configuration libraries.
    path = Path.home() / "Library" / "Application Support" / APP_NAME
    path.mkdir(parents=True, exist_ok=True)
    return path


def backup_root() -> Path:
    path = app_data_dir() / "Backups" / "Rekordbox"
    path.mkdir(parents=True, exist_ok=True)
    return path


def _strings(value: object) -> Iterable[str]:
    if isinstance(value, str):
        yield value
    elif isinstance(value, dict):
        for child in value.values():
            yield from _strings(child)
    elif isinstance(value, list):
        for child in value:
            yield from _strings(child)


def _options_candidates(home: Path) -> list[Path]:
    support = home / "Library" / "Application Support"
    return [
        support / "Pioneer" / "rekordboxAgent" / "storage" / "options.json",
        support / "rekordbox" / "rekordboxAgent" / "storage" / "options.json",
    ]


def _database_from_options(path: Path) -> list[Path]:
    if not path.is_file():
        return []
    try:
        data = json.loads(path.read_text(encoding="utf-8-sig"))
    except (OSError, ValueError):
        return []
    found: list[Path] = []
    for value in _strings(data):
        expanded = Path(os.path.expandvars(os.path.expanduser(value)))
        if expanded.name.lower() == "master.db":
            found.append(expanded)
        elif expanded.name.lower() in {"rekordbox", "database", "db"}:
            found.append(expanded / "master.db")
    return found


def rekordbox_database_candidates(home: Path | None = None) -> list[Path]:
    home = home or Path.home()
    support = home / "Library" / "Application Support"
    candidates: list[Path] = []
    for options in _options_candidates(home):
        candidates.extend(_database_from_options(options))
    candidates.extend(
        [
            support / "Pioneer" / "rekordbox" / "master.db",
            support / "Pioneer" / "rekordbox6" / "master.db",
            support / "Pioneer" / "rekordbox7" / "master.db",
            support / "rekordbox" / "master.db",
        ]
    )
    unique: list[Path] = []
    seen: set[str] = set()
    for candidate in candidates:
        key = str(candidate.expanduser()).casefold()
        if key not in seen:
            unique.append(candidate.expanduser())
            seen.add(key)
    return unique


def find_rekordbox_database(home: Path | None = None) -> Path:
    candidates = rekordbox_database_candidates(home)
    existing = [path.resolve() for path in candidates if path.is_file()]
    if existing:
        return max(existing, key=lambda item: item.stat().st_mtime)

    root = (home or Path.home()) / "Library" / "Application Support" / "Pioneer"
    if root.is_dir():
        discovered = list(root.glob("**/master.db"))
        if discovered:
            return max(discovered, key=lambda item: item.stat().st_mtime).resolve()
    raise FileNotFoundError(
        "O master.db do Rekordbox não foi localizado. Escolha o arquivo manualmente."
    )

