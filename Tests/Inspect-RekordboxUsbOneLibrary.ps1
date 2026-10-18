param(
    [Parameter(Mandatory = $true)]
    [string]$DatabasePath,

    [Parameter(Mandatory = $true)]
    [string]$ReportPath,

    [string]$VolumeRoot = "E:\"
)

$ErrorActionPreference = 'Stop'
$python = 'D:\CRIVO-USB-LAB\tools\pyrekordbox-venv\Scripts\python.exe'

if (-not (Test-Path -LiteralPath $python)) {
    throw "Ambiente de análise OneLibrary não encontrado: $python"
}
if (-not (Test-Path -LiteralPath $DatabasePath)) {
    throw "Banco OneLibrary não encontrado: $DatabasePath"
}

$script = @'
import json
import sys
from pathlib import Path, PurePosixPath

from pyrekordbox import OneLibrary
from pyrekordbox.onelibrary import Content, Playlist, PlaylistContent, Property

db_path = Path(sys.argv[1])
report_path = Path(sys.argv[2])
volume_root = Path(sys.argv[3])

def resolve_device_path(raw):
    text = (raw or '').replace('\\', '/').strip()
    parts = [part for part in PurePosixPath(text).parts if part not in ('/', '\\')]
    if parts and parts[0].endswith(':'):
        parts = parts[1:]
    return volume_root.joinpath(*parts)

with OneLibrary(db_path) as db:
    contents = list(db.query(Content).all())
    playlists = list(db.query(Playlist).all())
    playlist_contents = list(db.query(PlaylistContent).all())
    properties = list(db.query(Property).all())

    content_ids = {int(item.content_id) for item in contents}
    playlist_ids = {int(item.playlist_id) for item in playlists}
    playlist_by_id = {int(item.playlist_id): item for item in playlists}

    def playlist_path(item):
        names = [str(item.name)]
        parent_id = item.playlist_id_parent
        seen = {int(item.playlist_id)}
        while parent_id is not None and int(parent_id) in playlist_by_id and int(parent_id) not in seen:
            parent_id = int(parent_id)
            seen.add(parent_id)
            parent = playlist_by_id[parent_id]
            names.append(str(parent.name))
            parent_id = parent.playlist_id_parent
        return ' / '.join(reversed(names))

    counts = {}
    broken_references = []
    for item in playlist_contents:
        pid = int(item.playlist_id)
        cid = int(item.content_id)
        counts[pid] = counts.get(pid, 0) + 1
        if pid not in playlist_ids or cid not in content_ids:
            broken_references.append({
                'playlist_id': pid,
                'content_id': cid,
                'sequence': int(item.sequenceNo),
                'playlist_exists': pid in playlist_ids,
                'content_exists': cid in content_ids,
            })

    missing_paths = []
    content_rows = []
    for item in contents:
        physical = resolve_device_path(item.path)
        exists = physical.exists()
        if not exists:
            missing_paths.append({
                'content_id': int(item.content_id),
                'title': item.title,
                'path': item.path,
                'resolved_path': str(physical),
            })
        content_rows.append({
            'content_id': int(item.content_id),
            'title': item.title,
            'artist': item.artist_name,
            'path': item.path,
            'physical_exists': exists,
        })

    playlist_rows = [{
        'playlist_id': int(item.playlist_id),
        'parent_id': None if item.playlist_id_parent is None else int(item.playlist_id_parent),
        'name': item.name,
        'path': playlist_path(item),
        'attribute': item.attribute,
        'entry_count': counts.get(int(item.playlist_id), 0),
    } for item in playlists]

    property_rows = [{
        'device_name': item.deviceName,
        'db_version': item.dbVersion,
        'declared_content_count': item.numberOfContents,
        'created_date': None if item.createdDate is None else str(item.createdDate),
    } for item in properties]

report = {
    'database': str(db_path),
    'volume_root': str(volume_root),
    'content_count': len(contents),
    'playlist_count': len(playlists),
    'playlist_entry_count': len(playlist_contents),
    'broken_reference_count': len(broken_references),
    'missing_physical_path_count': len(missing_paths),
    'properties': property_rows,
    'playlists': playlist_rows,
    'broken_references': broken_references,
    'missing_physical_paths': missing_paths,
    'contents': content_rows,
}

report_path.parent.mkdir(parents=True, exist_ok=True)
report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
print(json.dumps({key: report[key] for key in (
    'content_count', 'playlist_count', 'playlist_entry_count',
    'broken_reference_count', 'missing_physical_path_count', 'properties'
)}, ensure_ascii=False))
'@

$script | & $python - $DatabasePath $ReportPath $VolumeRoot
if ($LASTEXITCODE -ne 0) {
    throw "Falha ao analisar o banco OneLibrary (código $LASTEXITCODE)."
}

