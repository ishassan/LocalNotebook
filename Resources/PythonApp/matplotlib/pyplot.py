from __future__ import annotations

from dataclasses import dataclass, field
from html import escape
from typing import Iterable

_pending_outputs: list[dict] = []
_current_figure = None


@dataclass
class _Series:
    kind: str
    x: list[float]
    y: list[float]
    color: str
    label: str | None = None
    width: float = 2.0


@dataclass
class _Figure:
    title: str = ""
    xlabel: str = ""
    ylabel: str = ""
    series: list[_Series] = field(default_factory=list)


def figure():
    global _current_figure
    _current_figure = _Figure()
    return _current_figure


def gcf():
    global _current_figure
    if _current_figure is None:
        _current_figure = _Figure()
    return _current_figure


def clf():
    global _current_figure
    _current_figure = _Figure()


def close(_fig=None):
    global _current_figure
    _current_figure = None


def title(value: str):
    gcf().title = str(value)


def xlabel(value: str):
    gcf().xlabel = str(value)


def ylabel(value: str):
    gcf().ylabel = str(value)


def plot(x: Iterable[float], y: Iterable[float], color: str = "#0f6bb7", label: str | None = None, linewidth: float = 2.0):
    fig = gcf()
    fig.series.append(_Series("line", _float_list(x), _float_list(y), color=color, label=label, width=linewidth))


def scatter(x: Iterable[float], y: Iterable[float], color: str = "#d65232", label: str | None = None):
    fig = gcf()
    fig.series.append(_Series("scatter", _float_list(x), _float_list(y), color=color, label=label, width=4.0))


def bar(x: Iterable[float], height: Iterable[float], color: str = "#4a8f5d", label: str | None = None):
    fig = gcf()
    fig.series.append(_Series("bar", _float_list(x), _float_list(height), color=color, label=label, width=16.0))


def show():
    fig = gcf()
    _pending_outputs.append(
        {
            "output_type": "display_data",
            "data": {
                "image/svg+xml": _render_svg(fig),
                "text/plain": f"<Figure series={len(fig.series)}>",
            },
            "metadata": {},
        }
    )
    close(fig)


def _consume_rendered_outputs():
    outputs = list(_pending_outputs)
    _pending_outputs.clear()
    return outputs


def _float_list(values: Iterable[float]) -> list[float]:
    return [float(value) for value in values]


def _render_svg(fig: _Figure) -> str:
    width = 360
    height = 220
    pad_left = 48
    pad_right = 20
    pad_top = 24
    pad_bottom = 42
    plot_width = width - pad_left - pad_right
    plot_height = height - pad_top - pad_bottom

    xs = [x for series in fig.series for x in series.x] or [0.0, 1.0]
    ys = [y for series in fig.series for y in series.y] or [0.0, 1.0]
    min_x, max_x = min(xs), max(xs)
    min_y, max_y = min(ys), max(ys)
    if min_x == max_x:
        max_x += 1.0
    if min_y == max_y:
        max_y += 1.0

    def tx(value: float) -> float:
        return pad_left + ((value - min_x) / (max_x - min_x)) * plot_width

    def ty(value: float) -> float:
        return pad_top + plot_height - ((value - min_y) / (max_y - min_y)) * plot_height

    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
        '<rect width="100%" height="100%" rx="18" fill="#fbfbf7"/>',
        f'<line x1="{pad_left}" y1="{pad_top + plot_height}" x2="{width - pad_right}" y2="{pad_top + plot_height}" stroke="#6c6f73" stroke-width="1"/>',
        f'<line x1="{pad_left}" y1="{pad_top}" x2="{pad_left}" y2="{pad_top + plot_height}" stroke="#6c6f73" stroke-width="1"/>',
    ]

    if fig.title:
        parts.append(f'<text x="{width / 2}" y="16" text-anchor="middle" font-size="14" font-family="-apple-system, BlinkMacSystemFont, sans-serif" fill="#16202a">{escape(fig.title)}</text>')
    if fig.xlabel:
        parts.append(f'<text x="{width / 2}" y="{height - 10}" text-anchor="middle" font-size="12" font-family="-apple-system, BlinkMacSystemFont, sans-serif" fill="#55606d">{escape(fig.xlabel)}</text>')
    if fig.ylabel:
        parts.append(f'<text x="14" y="{height / 2}" text-anchor="middle" font-size="12" transform="rotate(-90 14 {height / 2})" font-family="-apple-system, BlinkMacSystemFont, sans-serif" fill="#55606d">{escape(fig.ylabel)}</text>')

    for series in fig.series:
        if series.kind == "line":
            points = " ".join(f"{tx(x):.2f},{ty(y):.2f}" for x, y in zip(series.x, series.y))
            parts.append(f'<polyline fill="none" stroke="{series.color}" stroke-width="{series.width}" points="{points}" />')
        elif series.kind == "scatter":
            for x, y in zip(series.x, series.y):
                parts.append(f'<circle cx="{tx(x):.2f}" cy="{ty(y):.2f}" r="{series.width}" fill="{series.color}" />')
        elif series.kind == "bar":
            for x, y in zip(series.x, series.y):
                x_pos = tx(x) - series.width / 2
                y_pos = ty(y)
                bar_height = pad_top + plot_height - y_pos
                parts.append(f'<rect x="{x_pos:.2f}" y="{y_pos:.2f}" width="{series.width}" height="{bar_height:.2f}" rx="4" fill="{series.color}" />')

    parts.append("</svg>")
    return "".join(parts)
