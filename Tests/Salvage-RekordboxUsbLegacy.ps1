param(
    [Parameter(Mandatory = $true)]
    [string]$DatabasePath,

    [Parameter(Mandatory = $true)]
    [string]$ReportPath,

    [string]$VolumeRoot = "E:\"
)

$ErrorActionPreference = 'Stop'
$python = 'D:\CRIVO-USB-LAB\tools\pyrekordbox-venv\Scripts\python.exe'
$parserRoot = 'D:\CRIVO-USB-LAB\tools\python-prodj-link'

if (-not (Test-Path -LiteralPath $python)) {
    throw "Ambiente de análise não encontrado: $python"
}
if (-not (Test-Path -LiteralPath $DatabasePath)) {
    throw "Banco legado não encontrado: $DatabasePath"
}

$script = @'
import json
import struct
import sys
from pathlib import Path, PurePosixPath

from prodj.pdblib.page import AlignedPage

db_path = Path(sys.argv[1])
report_path = Path(sys.argv[2])
volume_root = Path(sys.argv[3])
data = db_path.read_bytes()

if len(data) < 4096 or len(data) % 4096:
    raise ValueError(f'Unexpected database size: {len(data)} bytes')

page_size = struct.unpack_from('<I', data, 4)[0]
header_table_count = struct.unpack_from('<I', data, 8)[0]
next_unused_page = struct.unpack_from('<I', data, 12)[0]
sequence = struct.unpack_from('<I', data, 20)[0]

type_targets = {
    'block_tracks': 'tracks',
    'block_artists': 'artists',
    'block_albums': 'albums',
    'block_playlists': 'playlists',
    'block_playlist_map': 'playlist_map',
    'block_artwork': 'artwork',
    'block_colors': 'colors',
    'block_genres': 'genres',
    'block_keys': 'keys',
    'block_labels': 'labels',
}
salvaged = {target: [] for target in type_targets.values()}
page_failures = []
page_types = {}

for page_number in range(1, len(data) // page_size):
    offset = page_number * page_size
    block = data[offset:offset + page_size]
    raw_index = struct.unpack_from('<I', block, 4)[0]
    raw_type = struct.unpack_from('<I', block, 8)[0]
    try:
        page = AlignedPage.parse(block)
        page_type = str(page.page_type)
        page_types[page_type] = page_types.get(page_type, 0) + 1
        target = type_targets.get(page_type)
        if target:
            for entry_block in page.entry_list:
                for entry, enabled in zip(reversed(entry_block.entries), reversed(entry_block.entry_enabled)):
                    if enabled and not isinstance(entry, str):
                        salvaged[target].append(entry)
    except Exception as exc:
        page_failures.append({
            'page_number': page_number,
            'raw_index': raw_index,
            'raw_type': raw_type,
            'error_type': type(exc).__name__,
            'error': str(exc),
        })

def resolve_device_path(raw):
    text = (raw or '').replace('\\', '/').strip()
    parts = [part for part in PurePosixPath(text).parts if part not in ('/', '\\')]
    if parts and parts[0].endswith(':'):
        parts = parts[1:]
    return volume_root.joinpath(*parts)

tracks = salvaged['tracks']
playlists = salvaged['playlists']
playlist_map = salvaged['playlist_map']
track_ids = {int(item.id) for item in tracks}
playlist_ids = {int(item.id) for item in playlists}
playlist_by_id = {int(item.id): item for item in playlists}

def playlist_path(item):
    names = [str(item.name)]
    parent_id = int(item.folder_id)
    seen = {int(item.id)}
    while parent_id and parent_id in playlist_by_id and parent_id not in seen:
        seen.add(parent_id)
        parent = playlist_by_id[parent_id]
        names.append(str(parent.name))
        parent_id = int(parent.folder_id)
    return ' / '.join(reversed(names))

entry_counts = {}
broken_references = []
for item in playlist_map:
    playlist_id = int(item.playlist_id)
    track_id = int(item.track_id)
    entry_counts[playlist_id] = entry_counts.get(playlist_id, 0) + 1
    if playlist_id not in playlist_ids or track_id not in track_ids:
        broken_references.append({
            'playlist_id': playlist_id,
            'track_id': track_id,
            'entry_index': int(item.entry_index),
            'playlist_salvaged': playlist_id in playlist_ids,
            'track_salvaged': track_id in track_ids,
        })

missing_paths = []
track_rows = []
for item in tracks:
    raw_path = str(item.path)
    physical = resolve_device_path(raw_path)
    exists = physical.exists()
    if not exists:
        missing_paths.append({
            'track_id': int(item.id),
            'title': str(item.title),
            'path': raw_path,
            'resolved_path': str(physical),
        })
    track_rows.append({
        'track_id': int(item.id),
        'title': str(item.title),
        'path': raw_path,
        'physical_exists': exists,
    })

playlist_rows = [{
    'playlist_id': int(item.id),
    'parent_id': int(item.folder_id),
    'name': str(item.name),
    'path': playlist_path(item),
    'is_folder': bool(item.is_folder),
    'entry_count': entry_counts.get(int(item.id), 0),
} for item in playlists]

report = {
    'database': str(db_path),
    'file_size': len(data),
    'page_size': page_size,
    'physical_page_count': len(data) // page_size,
    'header_table_count': header_table_count,
    'header_next_unused_page': next_unused_page,
    'header_sequence': sequence,
    'parsed_page_count': len(data) // page_size - 1 - len(page_failures),
    'failed_page_count': len(page_failures),
    'page_types': page_types,
    'salvaged_counts': {key: len(value) for key, value in salvaged.items()},
    'broken_reference_count': len(broken_references),
    'missing_physical_path_count': len(missing_paths),
    'page_failures': page_failures,
    'playlists': playlist_rows,
    'broken_references': broken_references,
    'missing_physical_paths': missing_paths,
    'tracks': track_rows,
}

report_path.parent.mkdir(parents=True, exist_ok=True)
report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
print(json.dumps({key: report[key] for key in (
    'physical_page_count', 'parsed_page_count', 'failed_page_count',
    'salvaged_counts', 'broken_reference_count', 'missing_physical_path_count'
)}, ensure_ascii=False))
'@

$env:PYTHONPATH = $parserRoot
$script | & $python - $DatabasePath $ReportPath $VolumeRoot
if ($LASTEXITCODE -ne 0) {
    throw "Falha ao recuperar estruturas legadas (código $LASTEXITCODE)."
}

