param(
    [Parameter(Mandatory = $true)]
    [string]$DatabasePath,

    [Parameter(Mandatory = $true)]
    [string]$ReportPath,

    [string]$VolumeRoot = "E:\"
)

$ErrorActionPreference = 'Stop'

$python = 'C:\Users\EmanuelPereiraFraga\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
$parserRoot = 'D:\CRIVO-USB-LAB\tools\rekordbox-pdb\src'

if (-not (Test-Path -LiteralPath $python)) {
    throw "Python de análise não encontrado: $python"
}
if (-not (Test-Path -LiteralPath $DatabasePath)) {
    throw "Banco legado não encontrado: $DatabasePath"
}

$script = @'
import json
import os
import sys
from pathlib import Path

from rekordbox_pdb import Database

db_path = Path(sys.argv[1])
report_path = Path(sys.argv[2])
volume_root = Path(sys.argv[3])

db = Database.from_file(db_path)
tracks = list(db.tracks)
nodes = list(db.playlist_tree)
entries = list(db.playlist_entries)

track_by_id = {int(track.id): track for track in tracks}
children = {}
for node in nodes:
    children.setdefault(int(node.parent_id), []).append(node)

def node_path(node):
    names = [str(node.name)]
    parent_id = int(node.parent_id)
    seen = {int(node.id)}
    by_id = {int(item.id): item for item in nodes}
    while parent_id and parent_id in by_id and parent_id not in seen:
        seen.add(parent_id)
        parent = by_id[parent_id]
        names.append(str(parent.name))
        parent_id = int(parent.parent_id)
    return ' / '.join(reversed(names))

entries_by_playlist = {}
missing_track_references = []
missing_paths = []
for entry in entries:
    playlist_id = int(entry.playlist_id)
    track_id = int(entry.track_id)
    entries_by_playlist.setdefault(playlist_id, []).append(track_id)
    if track_id not in track_by_id:
        missing_track_references.append({
            'playlist_id': playlist_id,
            'track_id': track_id,
            'entry_index': int(entry.entry_index),
        })

for track in tracks:
    raw_path = str(track.file_path)
    relative = raw_path.replace('\\', '/').lstrip('/')
    physical = volume_root / Path(relative)
    if not physical.exists():
        missing_paths.append({
            'track_id': int(track.id),
            'title': str(track.title),
            'path': raw_path,
            'resolved_path': str(physical),
        })

playlists = []
for node in nodes:
    node_id = int(node.id)
    playlists.append({
        'id': node_id,
        'parent_id': int(node.parent_id),
        'name': str(node.name),
        'path': node_path(node),
        'is_folder': bool(node.is_folder),
        'entry_count': len(entries_by_playlist.get(node_id, [])),
    })

report = {
    'database': str(db_path),
    'volume_root': str(volume_root),
    'track_count': len(tracks),
    'playlist_node_count': len(nodes),
    'playlist_entry_count': len(entries),
    'missing_track_reference_count': len(missing_track_references),
    'missing_physical_path_count': len(missing_paths),
    'playlists': playlists,
    'missing_track_references': missing_track_references,
    'missing_physical_paths': missing_paths,
}

report_path.parent.mkdir(parents=True, exist_ok=True)
report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
print(json.dumps({key: report[key] for key in (
    'track_count', 'playlist_node_count', 'playlist_entry_count',
    'missing_track_reference_count', 'missing_physical_path_count'
)}, ensure_ascii=False))
'@

$env:PYTHONPATH = $parserRoot
$script | & $python - $DatabasePath $ReportPath $VolumeRoot
if ($LASTEXITCODE -ne 0) {
    throw "Falha ao analisar o banco legado (código $LASTEXITCODE)."
}

