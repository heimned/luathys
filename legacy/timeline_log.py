"""
Dynamic Timeline Log UI Component for Luathys Extractor
Built with PyQt6 using a Sui Dark Palette theme
"""
from PyQt6.QtWidgets import (
    QWidget, QVBoxLayout, QHBoxLayout, QLabel, QPushButton,
    QFrame, QScrollArea, QSizePolicy, QSpacerItem
)
from PyQt6.QtGui import QFont, QPainter, QColor, QPen, QBrush, QPalette
from PyQt6.QtCore import Qt, QTimer, QPropertyAnimation, QEasingCurve, Property, pyqtProperty

# Color Constants (Sui Dark Palette)
COLORS = {
    'background_main': '#131826',
    'card_bg': '#1A1F31',
    'border': '#23293D',
    'rail': '#2F3752',
    'muted_text': '#6C728F',
    'info': '#3B82F6',
    'success': '#22C55E',
    'warning': '#F59E0B',
    'error': '#EF4444',
    'pill_bg': '#1F243A',
    'scrollbar_bg': '#2D3344',
    'scrollbar_thumb': '#4A5568',
}

STATUS_CONFIG = {
    'info': {'color': COLORS['info'], 'icon': '[i]', 'glow': True},
    'success': {'color': COLORS['success'], 'icon': '[OK]', 'glow': False},
    'warning': {'color': COLORS['warning'], 'icon': '[!]', 'glow': True},
    'error': {'color': COLORS['error'], 'icon': '[X]', 'glow': True},
}

class StatusNode(QWidget):
    def __init__(self, entry_type, parent=None):
        super().__init__(parent)
        self.config = STATUS_CONFIG.get(entry_type, STATUS_CONFIG['info'])
        self.setFixedSize(16, 16)

    def paintEvent(self, event):
        painter = QPainter(self)
        painter.setRenderHint(QPainter.RenderHint.Antialiasing)
        color = QColor(self.config['color'])
        rect = self.rect().adjusted(2, 2, -2, -2)
        if self.config['glow']:
            painter.setPen(QPen(color.lighter(150), 4))
            painter.setBrush(QBrush(color))
            painter.drawEllipse(rect)
        painter.setPen(Qt.PenStyle.NoPen)
        painter.setBrush(QBrush(color))
        painter.drawEllipse(rect)

class TimelinePillCard(QFrame):
    def __init__(self, message, entry_type):
        super().__init__()
        layout = QHBoxLayout(self)
        layout.setContentsMargins(10, 6, 10, 6)
        layout.setSpacing(8)

        badge = QLabel(STATUS_CONFIG.get(entry_type, STATUS_CONFIG['info'])['icon'])
        badge.setStyleSheet(f"color: {STATUS_CONFIG.get(entry_type, STATUS_CONFIG['info'])['color']}; font-weight: bold;")
        msg = QLabel(message)
        msg.setWordWrap(True)
        layout.addWidget(badge)
        layout.addWidget(msg)

        self.setStyleSheet(f"""
            QFrame {{
                background-color: {COLORS['pill_bg']};
                border-radius: 12px;
                padding: 4px 8px;
            }}
        """)

class AnimatedLogItem(QFrame):
    def __init__(self, message, entry_type, timestamp, parent=None):
        super().__init__(parent)
        self.alpha = 0.0
        self.init_ui(message, entry_type, timestamp)

    def init_ui(self, message, entry_type, timestamp):
        layout = QHBoxLayout(self)
        layout.setContentsMargins(0, 8, 0, 8)
        layout.setSpacing(12)

        timestamp_lbl = QLabel(timestamp)
        timestamp_lbl.setStyleSheet(f"color: {COLORS['muted_text']}; font-size: 12px; font-family: 'Courier New';")
        timestamp_lbl.setFixedWidth(70)
        timestamp_lbl.setAlignment(Qt.AlignmentFlag.AlignRight | Qt.AlignmentFlag.AlignTop)

        rail_container = QFrame()
        rail_layout = QVBoxLayout(rail_container)
        rail_layout.setContentsMargins(0, 0, 0, 0)
        rail_layout.setSpacing(0)
        rail_container.setFixedWidth(20)

        self.status_node = StatusNode(entry_type)
        self.rail = QFrame()
        self.rail.setFrameShape(QFrame.Shape.VLine)
        self.rail.setStyleSheet(f"background-color: {COLORS['rail']};")
        self.rail.setFixedWidth(2)
        self.rail.setSizePolicy(QSizePolicy.Policy.Fixed, QSizePolicy.Policy.Expanding)

        rail_layout.addWidget(self.status_node, alignment=Qt.AlignmentFlag.AlignHCenter)
        rail_layout.addWidget(self.rail)

        self.card = TimelinePillCard(message, entry_type)
        layout.addWidget(timestamp_lbl)
        layout.addWidget(rail_container)
        layout.addWidget(self.card, stretch=1)

        self.opacity_effect = QPropertyAnimation(self, b"opacity")
        self.opacity_effect.setDuration(300)
        self.opacity_effect.setStartValue(0.0)
        self.opacity_effect.setEndValue(1.0)
        self.opacity_effect.setEasingCurve(QEasingCurve.Type.OutQuad)

    def animate_in(self):
        self.opacity_effect.start()

    @pyqtProperty(float)
    def opacity(self):
        return self.alpha

    @opacity.setter
    def opacity(self, value):
        self.alpha = value
        self.setWindowOpacity(value)
        self.update()

class TimelineLog(QWidget):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.is_collapsed = False
        self.init_ui()

    def init_ui(self):
        main_layout = QVBoxLayout(self)
        main_layout.setContentsMargins(0, 0, 0, 0)
        main_layout.setSpacing(0)

        # Header Bar
        header = QFrame()
        header.setFixedHeight(40)
        header.setStyleSheet(f"""
            QFrame {{
                background-color: {COLORS['card_bg']};
                border-bottom: 1px solid {COLORS['border']};
                border-top-left-radius: 8px;
                border-top-right-radius: 8px;
                padding: 0 12px;
            }}
        """)
        h_layout = QHBoxLayout(header)
        title = QLabel("Dynamic Timeline Log")
        title.setStyleSheet(f"color: {COLORS['info']}; font-weight: bold; font-size: 14px; font-family: 'Consolas';")
        toggle_btn = QPushButton("▼")
        toggle_btn.setFixedSize(24, 24)
        toggle_btn.setStyleSheet(f"""
            QPushButton {{
                background-color: transparent;
                color: {COLORS['muted_text']};
                border: none;
                font-size: 12px;
            }}
            QPushButton:hover {{
                color: {COLORS['info']};
            }}
        """)
        toggle_btn.clicked.connect(self.toggle_collapse)
        h_layout.addWidget(title)
        h_layout.addStretch()
        h_layout.addWidget(toggle_btn)
        main_layout.addWidget(header)

        # Scrollable Content Area
        self.scroll_area = QScrollArea()
        self.scroll_area.setWidgetResizable(True)
        self.scroll_area.setStyleSheet(f"""
            QScrollArea {{
                background-color: {COLORS['background_main']};
                border: none;
                border-bottom-left-radius: 8px;
                border-bottom-right-radius: 8px;
            }}
            QScrollBar:vertical {{
                background-color: {COLORS['scrollbar_bg']};
                width: 8px;
                margin: 0px;
            }}
            QScrollBar::handle:vertical {{
                background-color: {COLORS['scrollbar_thumb']};
                border-radius: 4px;
            }}
            QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical {{
                height: 0px;
            }}
        """)

        self.content_widget = QWidget()
        self.content_layout = QVBoxLayout(self.content_widget)
        self.content_layout.setContentsMargins(16, 0, 16, 16)
        self.content_layout.setSpacing(0)
        self.content_layout.addStretch()
        self.scroll_area.setWidget(self.content_widget)
        main_layout.addWidget(self.scroll_area, stretch=1)

        self.setStyleSheet(f"""
            TimelineLog {{
                background-color: {COLORS['background_main']};
                border: 1px solid {COLORS['border']};
                border-radius: 8px;
            }}
        """)

    def toggle_collapse(self):
        self.is_collapsed = not self.is_collapsed
        self.scroll_area.setVisible(not self.is_collapsed)
        # Update button text (handled in C
