from __future__ import annotations

import sys
import traceback
from pathlib import Path
from typing import Callable

from PySide6.QtCore import QObject, QRunnable, Qt, QThreadPool, Signal
from PySide6.QtGui import QAction
from PySide6.QtWidgets import (
    QApplication,
    QCheckBox,
    QFileDialog,
    QHBoxLayout,
    QHeaderView,
    QLabel,
    QLineEdit,
    QMainWindow,
    QMessageBox,
    QPushButton,
    QStatusBar,
    QTabWidget,
    QTableWidget,
    QTableWidgetItem,
    QVBoxLayout,
    QWidget,
)

from .downloads import download_track, resolve_url
from .metadata import missing_fields, read_track, scan_audio
from .models import Track
from .organizer import organize_tracks
from .paths import find_rekordbox_database
from .rekordbox import audit_database, write_playlist


STYLE = """
QWidget { background: #d8d5cc; color: #151515; font-family: -apple-system, Helvetica Neue; font-size: 13px; }
QMainWindow { background: #bcb9b1; }
QTabWidget::pane { border: 1px solid #77736b; }
QTabBar::tab { background: #aaa79f; padding: 12px 24px; border: 1px solid #77736b; }
QTabBar::tab:selected { background: #171717; color: white; }
QPushButton { min-height: 34px; padding: 0 16px; border: 1px solid #77736b; background: #ebe9e3; font-weight: 600; }
QPushButton:hover { background: #ffffff; }
QPushButton#primary { background: #171717; color: white; border-color: #171717; }
QLineEdit { min-height: 34px; background: #f4f2ed; border: 1px solid #88847b; padding: 0 8px; }
QTableWidget { background: #eeecc6; alternate-background-color: #dfddd5; gridline-color: #aaa69d; }
QHeaderView::section { background: #aaa79f; padding: 7px; border: 0; font-weight: 700; }
QLabel#title { font-size: 22px; font-weight: 800; }
QLabel#hint { color: #56534d; }
"""


class WorkerSignals(QObject):
    success = Signal(object)
    failure = Signal(str)


class Worker(QRunnable):
    def __init__(self, fn: Callable, *args):
        super().__init__()
        self.fn = fn
        self.args = args
        self.signals = WorkerSignals()

    def run(self):
        try:
            self.signals.success.emit(self.fn(*self.args))
        except Exception as exc:
            traceback.print_exc()
            self.signals.failure.emit(str(exc))


class Page(QWidget):
    def __init__(self, title: str, hint: str):
        super().__init__()
        self.layout = QVBoxLayout(self)
        title_label = QLabel(title)
        title_label.setObjectName("title")
        self.layout.addWidget(title_label)
        hint_label = QLabel(hint)
        hint_label.setObjectName("hint")
        hint_label.setWordWrap(True)
        self.layout.addWidget(hint_label)


class MainWindow(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("CRIVO DJ por MANELZ0RD")
        self.resize(1240, 780)
        self.pool = QThreadPool.globalInstance()
        self.download_tracks: list[Track] = []
        self.organize_tracks: list[Track] = []
        self.setStatusBar(QStatusBar())
        self.tabs = QTabWidget()
        self.setCentralWidget(self.tabs)
        self._build_download_page()
        self._build_organize_page()
        self._build_audit_page()
        quit_action = QAction("Sair", self)
        quit_action.triggered.connect(self.close)
        self.menuBar().addMenu("CRIVO DJ").addAction(quit_action)
        self._detect_database()

    def error(self, message: str):
        self.statusBar().showMessage("A operação encontrou um erro.")
        QMessageBox.critical(self, "CRIVO DJ", message)

    def info(self, message: str):
        QMessageBox.information(self, "CRIVO DJ", message)

    def run(self, fn: Callable, args: tuple, success: Callable, busy: str):
        self.statusBar().showMessage(busy)
        worker = Worker(fn, *args)
        worker.signals.success.connect(success)
        worker.signals.failure.connect(self.error)
        self.pool.start(worker)

    @staticmethod
    def button(text: str, primary: bool = False) -> QPushButton:
        button = QPushButton(text)
        if primary:
            button.setObjectName("primary")
        return button

    def _build_download_page(self):
        page = Page("BAIXAR TRACKS", "Cole ou arraste links do YouTube, SoundCloud ou Spotify. Tracks individuais e playlists são aceitas.")
        row = QHBoxLayout()
        self.url_input = QLineEdit()
        self.url_input.setPlaceholderText("Cole o link aqui")
        add = self.button("ADICIONAR", True)
        add.clicked.connect(self._resolve_link)
        self.url_input.returnPressed.connect(self._resolve_link)
        row.addWidget(self.url_input, 1)
        row.addWidget(add)
        page.layout.addLayout(row)
        target_row = QHBoxLayout()
        self.download_folder = QLineEdit(str(Path.home() / "Music" / "CRIVO DJ"))
        choose = self.button("ESCOLHER PASTA")
        choose.clicked.connect(lambda: self._choose_directory(self.download_folder))
        target_row.addWidget(QLabel("SALVAR EM"))
        target_row.addWidget(self.download_folder, 1)
        target_row.addWidget(choose)
        page.layout.addLayout(target_row)
        self.download_table = QTableWidget(0, 5)
        self.download_table.setHorizontalHeaderLabels(["FAIXA", "ARTISTA", "FONTE", "DURAÇÃO", "STATUS"])
        self.download_table.horizontalHeader().setSectionResizeMode(0, QHeaderView.Stretch)
        self.download_table.setAlternatingRowColors(True)
        page.layout.addWidget(self.download_table, 1)
        actions = QHBoxLayout()
        remove = self.button("REMOVER SELECIONADAS")
        remove.clicked.connect(self._remove_download_rows)
        start = self.button("INICIAR DOWNLOAD", True)
        start.clicked.connect(self._start_downloads)
        actions.addWidget(remove)
        actions.addStretch()
        actions.addWidget(start)
        page.layout.addLayout(actions)
        page.setAcceptDrops(True)
        page.dragEnterEvent = lambda event: event.acceptProposedAction() if event.mimeData().hasUrls() or event.mimeData().hasText() else None
        page.dropEvent = self._drop_links
        self.tabs.addTab(page, "BAIXAR")

    def _build_organize_page(self):
        page = Page("ORGANIZAR", "Organize downloads ou escolha uma pasta que já contenha sua pesquisa musical.")
        for label, attribute in (("ORIGEM", "organize_source"), ("DESTINO", "organize_destination")):
            row = QHBoxLayout()
            edit = QLineEdit()
            setattr(self, attribute, edit)
            choose = self.button("ESCOLHER PASTA")
            choose.clicked.connect(lambda checked=False, target=edit: self._choose_directory(target))
            row.addWidget(QLabel(label))
            row.addWidget(edit, 1)
            row.addWidget(choose)
            page.layout.addLayout(row)
        scan = self.button("LER TRACKS")
        scan.clicked.connect(self._scan_organize)
        page.layout.addWidget(scan, alignment=Qt.AlignLeft)
        self.organize_table = QTableWidget(0, 7)
        self.organize_table.setHorizontalHeaderLabels(["FAIXA", "ARTISTA", "ÁLBUM", "GÊNERO", "ANO", "DADOS FALTANTES", "ARQUIVO"])
        self.organize_table.horizontalHeader().setSectionResizeMode(0, QHeaderView.Stretch)
        self.organize_table.setAlternatingRowColors(True)
        page.layout.addWidget(self.organize_table, 1)
        rb_row = QHBoxLayout()
        self.send_rekordbox = QCheckBox("Gravar playlist diretamente no Rekordbox")
        self.playlist_name = QLineEdit("CRIVO DJ — Organizado")
        self.copy_files = QCheckBox("Copiar e preservar os originais")
        self.copy_files.setChecked(True)
        rb_row.addWidget(self.copy_files)
        rb_row.addWidget(self.send_rekordbox)
        rb_row.addWidget(QLabel("PLAYLIST"))
        rb_row.addWidget(self.playlist_name, 1)
        page.layout.addLayout(rb_row)
        execute = self.button("ORGANIZAR", True)
        execute.clicked.connect(self._execute_organize)
        page.layout.addWidget(execute, alignment=Qt.AlignRight)
        self.tabs.addTab(page, "ORGANIZAR")

    def _build_audit_page(self):
        page = Page("SAÚDE DO REKORDBOX", "Escaneie sem alterar nada. Revise arquivos ausentes, dados incompletos, análises e playlists.")
        row = QHBoxLayout()
        self.database_path = QLineEdit()
        choose = self.button("ESCOLHER BASE")
        choose.clicked.connect(self._choose_database)
        scan = self.button("ESCANEAR BIBLIOTECA", True)
        scan.clicked.connect(self._scan_database)
        row.addWidget(QLabel("MASTER.DB"))
        row.addWidget(self.database_path, 1)
        row.addWidget(choose)
        row.addWidget(scan)
        page.layout.addLayout(row)
        self.audit_summary = QLabel("Base ainda não escaneada.")
        page.layout.addWidget(self.audit_summary)
        self.audit_filter = QLineEdit()
        self.audit_filter.setPlaceholderText("Pesquisar track, artista, problema, playlist ou local")
        self.audit_filter.textChanged.connect(self._filter_audit)
        page.layout.addWidget(self.audit_filter)
        self.audit_table = QTableWidget(0, 6)
        self.audit_table.setHorizontalHeaderLabels(["TRACK", "ARTISTA", "PROBLEMA", "PLAYLISTS", "ANÁLISE", "LOCAL"])
        self.audit_table.horizontalHeader().setSectionResizeMode(0, QHeaderView.Stretch)
        self.audit_table.setAlternatingRowColors(True)
        page.layout.addWidget(self.audit_table, 1)
        self.tabs.addTab(page, "AUDITORIA")

    def _choose_directory(self, target: QLineEdit):
        selected = QFileDialog.getExistingDirectory(self, "Escolher pasta", target.text() or str(Path.home()))
        if selected:
            target.setText(selected)

    def _choose_database(self):
        selected, _ = QFileDialog.getOpenFileName(self, "Escolher master.db", str(Path.home()), "Banco do Rekordbox (master.db)")
        if selected:
            self.database_path.setText(selected)

    def _detect_database(self):
        try:
            self.database_path.setText(str(find_rekordbox_database()))
            self.statusBar().showMessage("Base do Rekordbox detectada.")
        except FileNotFoundError:
            self.database_path.setPlaceholderText("master.db não localizado — escolha manualmente")

    def _drop_links(self, event):
        urls = [url.toString() for url in event.mimeData().urls()]
        text = event.mimeData().text()
        candidates = urls or [part for part in text.split() if part.startswith(("http://", "https://"))]
        if candidates:
            self.url_input.setText(candidates[0])
            self._resolve_link()
            event.acceptProposedAction()

    def _resolve_link(self):
        url = self.url_input.text().strip()
        if not url:
            return
        self.run(resolve_url, (url,), self._links_resolved, "Lendo dados da track ou playlist…")

    def _links_resolved(self, tracks: list[Track]):
        self.download_tracks.extend(tracks)
        self.url_input.clear()
        self._refresh_download_table()
        self.statusBar().showMessage(f"{len(tracks)} track(s) adicionada(s) à lista.")

    def _refresh_download_table(self):
        self.download_table.setRowCount(len(self.download_tracks))
        for row, track in enumerate(self.download_tracks):
            values = [track.title, track.artist, track.source, f"{int(track.duration // 60)}:{int(track.duration % 60):02d}" if track.duration else "", track.status]
            for column, value in enumerate(values):
                self.download_table.setItem(row, column, QTableWidgetItem(str(value)))

    def _remove_download_rows(self):
        rows = sorted({index.row() for index in self.download_table.selectedIndexes()}, reverse=True)
        for row in rows:
            self.download_tracks.pop(row)
        self._refresh_download_table()

    def _start_downloads(self):
        if not self.download_tracks:
            self.error("Adicione pelo menos uma track ou playlist.")
            return
        destination = Path(self.download_folder.text()).expanduser()

        def task():
            downloaded: list[Path] = []
            for track in self.download_tracks:
                track.status = "Baixando"
                downloaded.extend(download_track(track, destination))
                track.status = "Concluído"
            return downloaded

        self.run(task, (), self._downloads_finished, "Baixando tracks…")

    def _downloads_finished(self, files: list[Path]):
        self._refresh_download_table()
        self.organize_source.setText(self.download_folder.text())
        self.statusBar().showMessage(f"Download concluído: {len(files)} arquivo(s).")

    def _scan_organize(self):
        source = Path(self.organize_source.text()).expanduser()
        self.run(scan_audio, (source,), self._organize_scanned, "Lendo arquivos e metadados…")

    def _organize_scanned(self, tracks: list[Track]):
        self.organize_tracks = tracks
        self.organize_table.setRowCount(len(tracks))
        for row, track in enumerate(tracks):
            values = [track.title, track.artist, track.album, track.genre, track.year or "", ", ".join(missing_fields(track)), str(track.path or "")]
            for column, value in enumerate(values):
                item = QTableWidgetItem(str(value))
                if column < 5:
                    item.setFlags(item.flags() | Qt.ItemIsEditable)
                else:
                    item.setFlags(item.flags() & ~Qt.ItemIsEditable)
                self.organize_table.setItem(row, column, item)
        self.statusBar().showMessage(f"{len(tracks)} track(s) prontas para organização.")

    def _tracks_from_organize_table(self) -> list[Track]:
        for row, track in enumerate(self.organize_tracks):
            track.title = self.organize_table.item(row, 0).text().strip()
            track.artist = self.organize_table.item(row, 1).text().strip()
            track.album = self.organize_table.item(row, 2).text().strip()
            track.genre = self.organize_table.item(row, 3).text().strip()
            year = self.organize_table.item(row, 4).text().strip()
            track.year = int(year) if year.isdigit() else None
        return self.organize_tracks

    def _execute_organize(self):
        if not self.organize_tracks:
            self.error("Leia uma pasta com tracks antes de organizar.")
            return
        destination_text = self.organize_destination.text().strip()
        if not destination_text:
            self.error("Escolha a pasta de destino.")
            return
        destination = Path(destination_text).expanduser()
        tracks = self._tracks_from_organize_table()
        database = Path(self.database_path.text()).expanduser() if self.database_path.text() else None
        send = self.send_rekordbox.isChecked()
        name = self.playlist_name.text()
        copy_files = self.copy_files.isChecked()

        def task():
            organized = organize_tracks(tracks, destination, copy_files)
            result = None
            if send:
                if database is None:
                    raise FileNotFoundError("Escolha o master.db do Rekordbox.")
                result = write_playlist(database, name, organized)
            return organized, result

        self.run(task, (), self._organize_finished, "Organizando e validando…")

    def _organize_finished(self, result):
        tracks, rekordbox_result = result
        message = f"{len(tracks)} track(s) organizadas."
        if rekordbox_result:
            message += f"\n\nPlaylist '{rekordbox_result['playlistName']}' confirmada com {rekordbox_result['tracksInPlaylist']} track(s).\nBackup: {rekordbox_result['backup']}"
        self.statusBar().showMessage("Organização concluída.")
        self.info(message)

    def _scan_database(self):
        path = Path(self.database_path.text()).expanduser()
        self.run(audit_database, (path,), self._audit_finished, "Pyrekordbox está lendo o master.db…")

    def _audit_finished(self, result: dict):
        summary = result["summary"]
        self.audit_summary.setText(
            f"{summary['total']} tracks  •  {summary['healthy']} saudáveis  •  {summary['attention']} precisam de atenção  •  {summary['missingFiles']} sem arquivo físico"
        )
        tracks = result["tracks"]
        self.audit_table.setRowCount(len(tracks))
        for row, track in enumerate(tracks):
            values = [track["title"], track["artist"], ", ".join(track["problems"]) or "Saudável", ", ".join(track["playlists"]), track["analysis"], track["location"]]
            for column, value in enumerate(values):
                item = QTableWidgetItem(value)
                item.setFlags(item.flags() & ~Qt.ItemIsEditable)
                self.audit_table.setItem(row, column, item)
        self.statusBar().showMessage("Auditoria concluída sem alterar a biblioteca.")

    def _filter_audit(self, text: str):
        query = text.casefold().strip()
        for row in range(self.audit_table.rowCount()):
            haystack = " ".join(self.audit_table.item(row, column).text() for column in range(self.audit_table.columnCount()) if self.audit_table.item(row, column)).casefold()
            self.audit_table.setRowHidden(row, bool(query and query not in haystack))


def main() -> int:
    application = QApplication(sys.argv)
    application.setApplicationName("CRIVO DJ")
    application.setOrganizationName("MANELZ0RD")
    application.setStyleSheet(STYLE)
    window = MainWindow()
    window.show()
    return application.exec()

