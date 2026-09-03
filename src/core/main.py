"""
Luathys Extractor - Desktop Application
Extracts Roblox Luau bytecode from memory.

Usage:
1. Launch Roblox and join the game
2. Run Luathys Extractor
3. Click "Scan Now"
4. Scripts are extracted to output directory
"""

import os
import sys
import time
import subprocess
import threading

try:
    from PyQt6.QtWidgets import (
        QApplication, QMainWindow, QWidget, QVBoxLayout, QHBoxLayout,
        QPushButton, QLabel, QProgressBar, QTextEdit, QFileDialog,
        QFrame, QMessageBox, QSystemTrayIcon, QMenu
    )
    from PyQt6.QtGui import QFont, QPalette, QColor, QTextCursor
    from PyQt6.QtCore import Qt, QTimer
except ImportError:
    subprocess.check_call([sys.executable, "-m", "pip", "install", "pyqt6"])
    from PyQt6.QtWidgets import (
        QApplication, QMainWindow, QWidget, QVBoxLayout, QHBoxLayout,
        QPushButton, QLabel, QProgressBar, QTextEdit, QFileDialog,
        QFrame, QMessageBox, QSystemTrayIcon, QMenu
    )
    from PyQt6.QtGui import QFont, QPalette, QColor, QTextCursor
    from PyQt6.QtCore import Qt, QTimer

try:
    import pymem
    import pymem.process
    import pymem.exception
except ImportError:
    subprocess.check_call([sys.executable, "-m", "pip", "install", "pymem"])
    import pymem
    import pymem.process
    import pymem.exception

VERSION = "1.1.1"
DEFAULT_OUTPUT_DIR = os.path.expanduser("~/HUKI")

SIGNATURES = {
    "luau": [b"\x03\x30\x00\x00", b"\x19\x00\x00\x00"],
}

# SUNC API Documentation reference: https://docs.sunc.sh/
class MemoryScanner:
    def __init__(self, parent):
        self.parent = parent
        self.pm = None

    def find_roblox(self):
        try:
            self.pm = pymem.Pymem("RobloxPlayerBeta.exe")
            return True, self.pm.process_handle
        except Exception as e:
            return False, str(e)

    def scan_memory(self, on_found=None):
        if not self.pm:
            ok, res = self.find_roblox()
            if not ok:
                return []

        found = []
        try:
            handle = self.pm.process_handle
            chunk = 0x500000
            addr = 0x100000
            max_addr = 0x7FFFFFFFFFFF

            while addr < max_addr:
                try:
                    data = pymem.read_bytes(handle, addr, min(chunk, max_addr - addr))
                    for _p in SIGNATURES.get("luau", []):
                        pos = data.find(_p)
                        while pos != -1:
                            bc = data[max(0, pos-0x100):min(len(data), pos+0x2000)]
                            if len(bc) > 100:
                                found.append({"address": hex(addr+pos), "data": bc, "size": len(bc)})
                                if on_found: on_found(len(found))
                            pos = data.find(_p, pos+1)
                except:
                    pass
                addr += chunk
        except Exception as e:
            self.parent.log(f"Scan error: {e}")
        return found

    def scan_services(self):
        services = []
        try:
            targets = [b"ServerScriptService", b"ReplicatedStorage", b"ServerStorage", b"Workspace", b"StarterPlayer"]
            chunk = 0x500000
            addr = 0x100000
            max_addr = 0x7FFFFFFFFFFF
            while addr < max_addr:
                try:
                    data = pymem.read_bytes(self.pm.process_handle, addr, min(chunk, max_addr - addr))
                    for t in targets:
                        p = data.find(t)
                        if p != -1:
                            services.append({"service": t.decode(), "address": hex(addr + p)})
                except: pass
                addr += chunk
        except Exception as e:
            self.parent.log(f"Service scan error: {e}")
        return services


class LuathysApp(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle(f"Luathys Extractor v{VERSION}")
        self.resize(800, 600)
        self.apply_style()

        self.scanner = MemoryScanner(self)
        self.output_dir = DEFAULT_OUTPUT_DIR
        self.results = []
        self.scanning = False

        self.build_ui()
        self.setup_tray()

    def apply_style(self):
        pal = QPalette()
        pal.setColor(QPalette.ColorRole.Window, QColor("#1e1e2e"))
        pal.setColor(QPalette.ColorRole.WindowText, QColor("#cdd6f4"))
        pal.setColor(QPalette.ColorRole.Base, QColor("#303446"))
        pal.setColor(QPalette.ColorRole.Text, QColor("#cdd6f4"))
        pal.setColor(QPalette.ColorRole.Highlight, QColor("#89b4fa"))
        QApplication.instance().setPalette(pal)
        QApplication.instance().setFont(QFont("Consolas", 9))
        QApplication.instance().setStyleSheet("""
            QMainWindow { background-color: #1e1e2e; }
            QTextEdit { background-color: #303446; border: 1px solid #45475a; color: #cdd6f4; font-family: 'Consolas', monospace; }
            QPushButton { background-color: #89b4fa; border: none; padding: 8px 16px; border-radius: 4px; color: #1e1e2e; font-weight: bold; }
            QPushButton:hover { background-color: #89b8fa; }
            QPushButton:disabled { background-color: #585b70; color: #6c7086; }
            QProgressBar { border: 1px solid #45475a; border-radius: 4px; background-color: #303446; height: 20px; }
            QProgressBar::chunk { background-color: #89b4fa; border-radius: 3px; }
            QFrame { background-color: #303446; border: 1px solid #45475a; border-radius: 6px; }
            QLabel { color: #cdd6f4; }
        """)

    def build_ui(self):
        w = QWidget()
        layout = QVBoxLayout(w)
        layout.setSpacing(12)
        layout.setContentsMargins(20, 20, 20, 20)

        # Header
        h = QFrame()
        hl = QHBoxLayout(h)
        t = QLabel("Luathys Extractor")
        t.setFont(QFont("Consolas", 20, QFont.Weight.Bold))
        t.setStyleSheet("color: #89b4fa;")
        v = QLabel(f"v{VERSION}")
        v.setStyleSheet("color: #6c7086;")
        hl.addWidget(t)
        hl.addStretch()
        hl.addWidget(v)
        layout.addWidget(h)

        # Process status
        pf = QFrame()
        pl = QHBoxLayout(pf)
        self.proc_status = QLabel("Roblox Process: Not detected")
        self.proc_status.setStyleSheet("color: #f38ba8;")
        self.indicator = QLabel("●")
        self.indicator.setStyleSheet("color: #f38ba8;")
        pl.addWidget(self.indicator)
        pl.addWidget(self.proc_status)
        pl.addStretch()
        cb = QPushButton("Check Process")
        cb.clicked.connect(self.check_process)
        pl.addWidget(cb)

        self.dir_label = QLabel(f"Output: ~/HUKI/")
        bb = QPushButton("Browse")
        bb.clicked.connect(self.select_dir)
        pl.addWidget(bb)
        pl.addWidget(self.dir_label)
        layout.addWidget(pf)

        # Controls
        cf = QFrame()
        cf.setFixedHeight(80)
        cl = QHBoxLayout(cf)
        self.scan_btn = QPushButton("Scan Now")
        self.scan_btn.setFixedHeight(40)
        self.scan_btn.clicked.connect(self.start_scan)
        self.stop_btn = QPushButton("Stop")
        self.stop_btn.setFixedHeight(40)
        self.stop_btn.setEnabled(False)
        self.stop_btn.clicked.connect(self.stop_scan)
        self.export_btn = QPushButton("Export Results")
        self.export_btn.setFixedHeight(40)
        self.export_btn.setEnabled(False)
        self.export_btn.clicked.connect(self.export)
        cl.addWidget(self.scan_btn)
        cl.addWidget(self.stop_btn)
        cl.addWidget(self.export_btn)
        cl.addStretch()
        inst = QLabel("1. Launch Roblox\n2. Click Scan\n3. Export")
        inst.setStyleSheet("color: #6c7086;")
        cl.addWidget(inst)
        layout.addWidget(cf)

        # Progress
        prf = QFrame()
        prl = QVBoxLayout(prf)
        self.prog_label = QLabel("Ready")
        self.prog_label.setStyleSheet("color: #cdd6f4;")
        self.prog_bar = QProgressBar()
        self.prog_bar.setVisible(False)
        self.found_label = QLabel("Scripts found: 0")
        self.found_label.setStyleSheet("color: #6c7086;")
        prl.addWidget(self.prog_label)
        prl.addWidget(self.prog_bar)
        prl.addWidget(self.found_label)
        layout.addWidget(prf)

        # Log
        lf = QFrame()
        ll = QVBoxLayout(lf)
        lt = QLabel("Log")
        lt.setStyleSheet("color: #89b4fa;")
        ll.addWidget(lt)
        self.log_out = QTextEdit()
        self.log_out.setReadOnly(True)
        self.log_out.setLineWrapMode(QTextEdit.LineWrapMode.NoWrap)
        ll.addWidget(self.log_out)
        layout.addWidget(lf)

        self.setCentralWidget(w)

    def setup_tray(self):
        self.tray = QSystemTrayIcon()
        menu = QMenu()
        sa = menu.addAction("Show")
        sa.triggered.connect(self.show)
        qa = menu.addAction("Quit")
        qa.triggered.connect(self.close)
        self.tray.setContextMenu(menu)
        self.tray.show()

    def log(self, msg):
        ts = time.strftime("%H:%M:%S")
        self.log_out.append(f"[{ts}] {msg}")
        self.log_out.moveCursor(QTextCursor.MoveOperation.End)
        self.log_out.ensureCursorVisible()
        QApplication.processEvents()

    def check_process(self):
        self.log("Checking for Roblox...")
        self.proc_status.setText("Checking...")
        self.indicator.setStyleSheet("color: #f9e79f;")
        QApplication.processEvents()
        time.sleep(0.3)
        ok, res = self.scanner.find_roblox()
        if ok:
            self.proc_status.setText(f"Detected (PID: {res})")
            self.indicator.setStyleSheet("color: #a6e3a1;")
            self.log(f"Roblox found, PID: {res}")
        else:
            self.proc_status.setText(f"Not found ({res})")
            self.indicator.setStyleSheet("color: #f38ba8;")
            self.log(f"Roblox not found: {res}")

    def select_dir(self):
        d = QFileDialog.getExistingDirectory(self, "Output Directory", self.output_dir)
        if d:
            self.output_dir = d
            self.dir_label.setText(f"Output: {os.path.basename(d)}/")

    def start_scan(self):
        self.scanning = True
        self.scan_btn.setEnabled(False)
        self.stop_btn.setEnabled(True)
        self.prog_bar.setVisible(True)
        self.prog_bar.setValue(0)
        self.results = []
        threading.Thread(target=self._scan_worker, daemon=True).start()

    def stop_scan(self):
        self.scanning = False
        self.log("Scan stopped")
        self.scan_btn.setEnabled(True)
        self.stop_btn.setEnabled(False)

    def _scan_worker(self):
        self.log("Starting memory scan...")
        def on_found(c):
            if not self.scanning: return
            self.found_label.setText(f"Scripts found: {c}")
        scripts = self.scanner.scan_memory(on_found)
        self.log(f"Found {len(scripts)} potential scripts")
        svcs = self.scanner.scan_services()
        self.log(f"Found {len(svcs)} service markers")
        if self.scanning:
            self.results = scripts
            self.export_btn.setEnabled(True)
            self.prog_label.setText("Done!")
            self.prog_bar.setValue(100)
            self.log("Scan complete. Click Export.")
        self.scanning = False
        self.scan_btn.setEnabled(True)
        self.stop_btn.setEnabled(False)

    def export(self):
        if not self.results:
            self.log("No results to export")
            return
        self.log(f"Exporting {len(self.results)} to {self.output_dir}...")
        os.makedirs(self.output_dir, exist_ok=True)
        ok = 0
        for i, s in enumerate(self.results):
            try:
                bc = os.path.join(self.output_dir, f"script_{i+1}.bin")
                with open(bc, "wb") as f:
                    f.write(s["data"])
                ok += 1
            except Exception as e:
                self.log(f"Error {i}: {e}")
        self.log(f"Exported {ok}/{len(self.results)} scripts")
        QMessageBox.information(self, "Done", f"Exported {ok} scripts to {self.output_dir}")

def main():
    app = QApplication.instance() or QApplication(sys.argv)
    w = LuathysApp()
    w.show()
    w.log("Luathys Extractor ready")
    w.log("Launch Roblox, then click 'Check Process'")
    sys.exit(app.exec())

if __name__ == "__main__":
    main()
