import difflib
import html
import hashlib
import json
import os
import re
import shutil
import struct
import sys
import unicodedata
from datetime import datetime
from pathlib import Path, PurePosixPath

from prodj.pdblib.page import AlignedPage


AUDIO_EXTENSIONS = {
    ".mp3", ".wav", ".aif", ".aiff", ".flac", ".m4a", ".aac", ".ogg", ".opus"
}


def normalized(value):
    text = unicodedata.normalize("NFKD", str(value or ""))
    text = "".join(char for char in text if not unicodedata.combining(char))
    return "".join(char.lower() for char in text if char.isalnum())


def safe_name(value, fallback):
    text = re.sub(r'[<>:"/\\|?*\x00-\x1f]', " ", str(value or ""))
    text = re.sub(r"\s+", " ", text).strip(" .")
    return (text[:120] or fallback)


def resolve_device_path(root, raw):
    text = str(raw or "").replace("\\", "/").strip()
    parts = [part for part in PurePosixPath(text).parts if part not in ("/", "\\")]
    if parts and parts[0].endswith(":"):
        parts = parts[1:]
    return root.joinpath(*parts)


def collect_physical_audio(root):
    files = []
    by_size = {}
    by_name = {}
    for path in root.rglob("*"):
        try:
            if not path.is_file() or path.suffix.lower() not in AUDIO_EXTENSIONS:
                continue
            size = path.stat().st_size
        except OSError:
            continue
        item = {
            "path": str(path),
            "relative_path": str(path.relative_to(root)),
            "size": int(size),
            "normalized_name": normalized(path.stem),
        }
        files.append(item)
        by_size.setdefault(int(size), []).append(item)
        by_name.setdefault(item["normalized_name"], []).append(item)
    return files, by_size, by_name


def collect_source_files(root):
    files = []
    for path in root.rglob("*"):
        try:
            if not path.is_file():
                continue
            size = path.stat().st_size
        except OSError:
            continue
        files.append({
            "path": str(path),
            "relative_path": str(path.relative_to(root)),
            "size": int(size),
        })
    return files


def salvage_database(path):
    data = Path(path).read_bytes()
    if len(data) < 4096 or len(data) % 4096:
        raise ValueError("A biblioteca antiga está truncada e não possui páginas completas.")
    page_size = struct.unpack_from("<I", data, 4)[0]
    if page_size != 4096:
        raise ValueError(f"Tamanho de página não reconhecido: {page_size} bytes.")

    type_targets = {
        "block_tracks": "tracks",
        "block_playlists": "playlists",
        "block_playlist_map": "playlist_map",
    }
    salvaged = {target: [] for target in type_targets.values()}
    failures = []
    physical_pages = len(data) // page_size
    for page_number in range(1, physical_pages):
        offset = page_number * page_size
        block = data[offset:offset + page_size]
        raw_index = struct.unpack_from("<I", block, 4)[0]
        raw_type = struct.unpack_from("<I", block, 8)[0]
        try:
            page = AlignedPage.parse(block)
            target = type_targets.get(str(page.page_type))
            if not target:
                continue
            for entry_block in page.entry_list:
                for entry, enabled in zip(reversed(entry_block.entries), reversed(entry_block.entry_enabled)):
                    if enabled and not isinstance(entry, str):
                        salvaged[target].append(entry)
        except Exception as exc:
            failures.append({
                "page": page_number,
                "stored_index": raw_index,
                "page_type": raw_type,
                "error": str(exc),
            })
    return salvaged, failures, physical_pages


def choose_physical_file(track, source_root, by_size, by_name):
    raw_path = str(track.path)
    exact = resolve_device_path(source_root, raw_path)
    if exact.is_file():
        return exact, "exact_path", 1.0

    size = int(getattr(track, "file_size", 0) or 0)
    size_candidates = by_size.get(size, []) if size else []
    target_name = normalized(Path(raw_path.replace("\\", "/")).stem or str(track.title))
    if len(size_candidates) == 1:
        return Path(size_candidates[0]["path"]), "unique_size", 0.96
    if size_candidates:
        ranked = sorted(
            ((difflib.SequenceMatcher(None, target_name, item["normalized_name"]).ratio(), item)
             for item in size_candidates),
            key=lambda pair: pair[0], reverse=True,
        )
        if ranked and ranked[0][0] >= 0.55 and (len(ranked) == 1 or ranked[0][0] - ranked[1][0] >= 0.08):
            return Path(ranked[0][1]["path"]), "size_and_name", round(ranked[0][0], 3)

    name_candidates = by_name.get(target_name, [])
    if len(name_candidates) == 1:
        return Path(name_candidates[0]["path"]), "exact_name", 0.9
    return None, "unresolved", 0.0


def playlist_path(item, playlist_by_id):
    names = [str(item.name)]
    parent_id = int(item.folder_id)
    seen = {int(item.id)}
    while parent_id and parent_id in playlist_by_id and parent_id not in seen:
        seen.add(parent_id)
        parent = playlist_by_id[parent_id]
        names.append(str(parent.name))
        parent_id = int(parent.folder_id)
    return " / ".join(reversed(names))


def analyze(payload):
    database_path = Path(payload["databasePath"]).resolve()
    source_root = Path(payload["sourceRoot"]).resolve()
    plan_path = Path(payload["planPath"]).resolve()
    if not database_path.is_file():
        raise FileNotFoundError(f"Biblioteca não encontrada: {database_path}")
    if not source_root.is_dir():
        raise FileNotFoundError(f"Cópia de origem não encontrada: {source_root}")

    salvaged, page_failures, physical_pages = salvage_database(database_path)
    source_files = collect_source_files(source_root)
    physical_files, by_size, by_name = collect_physical_audio(source_root)
    tracks = salvaged["tracks"]
    playlists = salvaged["playlists"]
    playlist_map = salvaged["playlist_map"]

    track_rows = {}
    for track in tracks:
        physical, method, confidence = choose_physical_file(track, source_root, by_size, by_name)
        track_rows[int(track.id)] = {
            "track_id": int(track.id),
            "title": str(track.title),
            "database_path": str(track.path),
            "source_path": str(physical) if physical else None,
            "source_relative_path": str(physical.relative_to(source_root)) if physical else None,
            "match_method": method,
            "confidence": confidence,
        }

    playlist_by_id = {int(item.id): item for item in playlists}
    maps_by_playlist = {}
    for entry in playlist_map:
        maps_by_playlist.setdefault(int(entry.playlist_id), []).append(entry)

    playlist_rows = []
    confirmed_links = 0
    unresolved_links = 0
    for playlist in sorted(playlists, key=lambda item: (int(item.folder_id), int(item.sort_order))):
        if bool(playlist.is_folder):
            continue
        entries = sorted(maps_by_playlist.get(int(playlist.id), []), key=lambda item: int(item.entry_index))
        planned_entries = []
        for entry in entries:
            track_id = int(entry.track_id)
            track = track_rows.get(track_id)
            resolved = bool(track and track["source_path"])
            if resolved:
                confirmed_links += 1
            else:
                unresolved_links += 1
            planned_entries.append({
                "position": int(entry.entry_index),
                "track_id": track_id,
                "resolved": resolved,
                "title": track["title"] if track else "Track não identificada",
                "source_path": track["source_path"] if track else None,
                "source_relative_path": track["source_relative_path"] if track else None,
                "match_method": track["match_method"] if track else "missing_database_record",
            })
        resolved_count = sum(1 for entry in planned_entries if entry["resolved"])
        total_count = len(planned_entries)
        if total_count and resolved_count == total_count:
            status = "Recuperável"
        elif resolved_count:
            status = "Recuperação parcial"
        else:
            status = "Não foi possível confirmar"
        playlist_rows.append({
            "playlist_id": int(playlist.id),
            "name": str(playlist.name),
            "path": playlist_path(playlist, playlist_by_id),
            "status": status,
            "total_entries": total_count,
            "resolved_entries": resolved_count,
            "unresolved_entries": total_count - resolved_count,
            "entries": planned_entries,
        })

    plan = {
        "format_version": 1,
        "generated_at": datetime.now().astimezone().isoformat(),
        "read_only_source": True,
        "source_root": str(source_root),
        "database_path": str(database_path),
        "physical_audio_count": len(physical_files),
        "source_file_count": len(source_files),
        "source_byte_count": sum(item["size"] for item in source_files),
        "salvaged_track_count": len(tracks),
        "playlist_count": len(playlist_rows),
        "confirmed_link_count": confirmed_links,
        "unresolved_link_count": unresolved_links,
        "failed_page_count": len(page_failures),
        "physical_page_count": physical_pages,
        "playlists_recoverable": sum(1 for row in playlist_rows if row["status"] == "Recuperável"),
        "playlists_partial": sum(1 for row in playlist_rows if row["status"] == "Recuperação parcial"),
        "playlists_unconfirmed": sum(1 for row in playlist_rows if row["status"] == "Não foi possível confirmar"),
        "physical_files": physical_files,
        "source_files": source_files,
        "tracks": list(track_rows.values()),
        "playlists": playlist_rows,
        "page_failures": page_failures,
    }
    plan_path.parent.mkdir(parents=True, exist_ok=True)
    plan_path.write_text(json.dumps(plan, ensure_ascii=False, indent=2), encoding="utf-8")
    return {"success": True, "operation": "analyze", "planPath": str(plan_path), "summary": {
        key: plan[key] for key in (
            "physical_audio_count", "salvaged_track_count", "playlist_count",
            "confirmed_link_count", "unresolved_link_count", "failed_page_count",
            "playlists_recoverable", "playlists_partial", "playlists_unconfirmed",
        )
    }}


def write_m3u(path, entries, recovery_root, copied_by_source):
    lines = ["#EXTM3U"]
    for entry in entries:
        source = entry.get("source_path")
        copied = copied_by_source.get(source)
        if not copied:
            continue
        title = entry.get("title") or Path(copied).stem
        relative = os.path.relpath(copied, path.parent).replace("\\", "/")
        lines.extend([f"#EXTINF:-1,{title}", relative])
    path.write_text("\n".join(lines) + "\n", encoding="utf-8-sig")


def write_recovery_report(path, result):
    playlist_rows = []
    for item in result["playlists"]:
        css = "ok" if item["status"] == "Recuperável" else "attention" if item["status"] == "Recuperação parcial" else "unknown"
        playlist_rows.append(
            f"<tr><td>{html.escape(item['name'])}</td><td><span class='{css}'>{html.escape(item['status'])}</span></td>"
            f"<td>{item['resolved_entries']}</td><td>{item['unresolved_entries']}</td></tr>"
        )
    document = f"""<!doctype html><html lang='pt-BR'><head><meta charset='utf-8'><title>CRIVO DJ — Cópia recuperada</title>
<style>body{{margin:0;background:#b8b4ac;color:#171613;font-family:Arial,sans-serif}}main{{max-width:1050px;margin:28px auto}}header{{background:#111214;color:white;padding:20px}}section{{background:#d0ccc3;border:1px solid #777269;padding:18px;margin-top:14px}}table{{width:100%;border-collapse:collapse}}th,td{{padding:9px;border-bottom:1px solid #aaa59c;text-align:left}}th{{background:#a7a299}}span{{padding:4px 7px;font-weight:bold}}.ok{{background:#485c43;color:white}}.attention{{background:#b67b09;color:white}}.unknown{{background:#69655e;color:white}}</style></head>
<body><main><header><b>CRIVO DJ</b> — Relatório da cópia recuperada</header><section><h1>Cópia recuperada criada</h1>
<p>O dispositivo original não foi alterado.</p><ul><li>Cópia de segurança: {'validada' if result['backup_validated'] else 'não validada'}</li><li>{result['copied_file_count']} arquivos preservados</li><li>{result['copied_audio_count']} arquivos de áudio preservados</li><li>{result['created_playlist_count']} playlists criadas</li><li>{result['confirmed_link_count']} posições de tracks recuperadas</li><li>{result['unresolved_link_count']} posições não puderam ser recuperadas</li></ul>
<p><b>A recuperação pode ficar incompleta.</b> O CRIVO incluiu somente informações que conseguiu confirmar.</p></section><section><h2>Playlists</h2><table><thead><tr><th>PLAYLIST</th><th>RESULTADO</th><th>RECUPERADAS</th><th>NÃO CONFIRMADAS</th></tr></thead><tbody>{''.join(playlist_rows)}</tbody></table></section></main></body></html>"""
    path.write_text(document, encoding="utf-8")


def recover(payload):
    plan_path = Path(payload["planPath"]).resolve()
    destination_parent = Path(payload["destinationRoot"]).resolve()
    if not plan_path.is_file():
        raise FileNotFoundError(f"Plano de recuperação não encontrado: {plan_path}")
    destination_parent.mkdir(parents=True, exist_ok=True)
    plan = json.loads(plan_path.read_text(encoding="utf-8-sig"))
    source_root = Path(plan["source_root"]).resolve()
    if not source_root.is_dir():
        raise FileNotFoundError(f"A cópia validada não está disponível: {source_root}")
    try:
        if os.path.commonpath([str(source_root), str(destination_parent)]) == str(source_root):
            raise ValueError("Escolha um destino fora da cópia usada como origem.")
    except ValueError as exc:
        if "Escolha" in str(exc):
            raise

    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    recovery_root = destination_parent / f"CRIVO DJ - Copia recuperada - {stamp}"
    recovery_root.mkdir(parents=False, exist_ok=False)
    preserved_root = recovery_root / "Original preservado"
    playlists_root = recovery_root / "Playlists"
    preserved_root.mkdir()
    playlists_root.mkdir()

    copied_by_source = {}
    copy_errors = []
    copied_bytes = 0
    for item in plan["source_files"]:
        source = Path(item["path"])
        relative = Path(item["relative_path"])
        destination = preserved_root / relative
        try:
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, destination)
            copied_by_source[str(source)] = str(destination)
            copied_bytes += destination.stat().st_size
        except Exception as exc:
            copy_errors.append({"source": str(source), "error": str(exc)})

    critical_relatives = [
        Path("PIONEER/rekordbox/EXPORT.PDB"),
        Path("PIONEER/rekordbox/exportExt.pdb"),
        Path("PIONEER/rekordbox/exportLibrary.db"),
        Path("PIONEER/rekordbox/exportLibrary.db-shm"),
        Path("PIONEER/rekordbox/exportLibrary.db-wal"),
    ]
    critical_hashes = []
    for relative in critical_relatives:
        source = source_root / relative
        copied = preserved_root / relative
        if not source.is_file():
            continue
        source_hash = hashlib.sha256(source.read_bytes()).hexdigest()
        copied_hash = hashlib.sha256(copied.read_bytes()).hexdigest() if copied.is_file() else None
        critical_hashes.append({
            "path": str(relative),
            "source_sha256": source_hash,
            "copy_sha256": copied_hash,
            "match": source_hash == copied_hash,
        })

    backup_validated = (
        not copy_errors
        and len(copied_by_source) == int(plan["source_file_count"])
        and copied_bytes == int(plan["source_byte_count"])
        and all(item["match"] for item in critical_hashes)
    )

    used_names = set()
    playlist_results = []
    created_playlist_count = 0
    for playlist in plan["playlists"]:
        base = safe_name(playlist["path"].replace(" / ", " - "), f"Playlist {playlist['playlist_id']}")
        name = base
        counter = 2
        while name.lower() in used_names:
            name = f"{base} ({counter})"
            counter += 1
        used_names.add(name.lower())
        resolved_entries = [entry for entry in playlist["entries"] if entry["resolved"] and entry.get("source_path") in copied_by_source]
        if resolved_entries:
            write_m3u(playlists_root / f"{name}.m3u8", resolved_entries, recovery_root, copied_by_source)
            created_playlist_count += 1
        playlist_results.append({
            "name": playlist["path"],
            "status": playlist["status"],
            "resolved_entries": len(resolved_entries),
            "unresolved_entries": playlist["total_entries"] - len(resolved_entries),
        })

    result = {
        "success": backup_validated,
        "operation": "recover",
        "created_at": datetime.now().astimezone().isoformat(),
        "recovery_root": str(recovery_root),
        "source_unchanged": True,
        "backup_validated": backup_validated,
        "copied_file_count": len(copied_by_source),
        "copied_byte_count": copied_bytes,
        "copied_audio_count": sum(1 for path in copied_by_source if Path(path).suffix.lower() in AUDIO_EXTENSIONS),
        "copy_error_count": len(copy_errors),
        "copy_errors": copy_errors,
        "critical_hashes": critical_hashes,
        "created_playlist_count": created_playlist_count,
        "confirmed_link_count": plan["confirmed_link_count"],
        "unresolved_link_count": plan["unresolved_link_count"],
        "playlists": playlist_results,
    }
    (recovery_root / "Relatorio-tecnico.json").write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    write_recovery_report(recovery_root / "Relatorio-da-recuperacao.html", result)
    return result


def main():
    try:
        if hasattr(sys.stdout, "reconfigure"):
            sys.stdout.reconfigure(encoding="utf-8")
        if len(sys.argv) != 2:
            raise ValueError("Uso: CrivoUsbRecovery.exe payload.json")
        payload = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8-sig"))
        operation = payload.get("operation", "analyze")
        result = analyze(payload) if operation == "analyze" else recover(payload) if operation == "recover" else None
        if result is None:
            raise ValueError(f"Operação desconhecida: {operation}")
        print(json.dumps(result, ensure_ascii=False))
        return 0 if result.get("success") else 3
    except Exception as exc:
        print(json.dumps({"success": False, "message": str(exc)}, ensure_ascii=False))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())

