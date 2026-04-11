import ast
import base64
import contextlib
import io
import json
import os
import traceback

_SESSIONS = {}
_EXECUTION_COUNTS = {}


def _ensure_session(session_id: str) -> dict:
    if session_id not in _SESSIONS:
        _SESSIONS[session_id] = {"__name__": "__main__"}
        _EXECUTION_COUNTS[session_id] = 0
    return _SESSIONS[session_id]


def _capture_rich_result(value):
    if value is None:
        return None

    data = {"text/plain": repr(value)}
    if hasattr(value, "_repr_markdown_"):
        try:
            markdown = value._repr_markdown_()
            if markdown:
                data["text/markdown"] = markdown
        except Exception:
            pass
    if hasattr(value, "_repr_html_"):
        try:
            html = value._repr_html_()
            if html:
                data["text/html"] = html
        except Exception:
            pass
    return {"output_type": "display_data", "data": data, "metadata": {}}


def _capture_matplotlib_outputs():
    outputs = []
    try:
        import matplotlib

        matplotlib.use("Agg")
        import matplotlib.pyplot as plt

        for fig_number in list(plt.get_fignums()):
            fig = plt.figure(fig_number)
            png_buffer = io.BytesIO()
            svg_buffer = io.StringIO()
            fig.savefig(png_buffer, format="png", bbox_inches="tight")
            fig.savefig(svg_buffer, format="svg", bbox_inches="tight")
            outputs.append(
                {
                    "output_type": "display_data",
                    "data": {
                        "image/png": base64.b64encode(png_buffer.getvalue()).decode("utf-8"),
                        "image/svg+xml": svg_buffer.getvalue(),
                    },
                    "metadata": {},
                }
            )
            plt.close(fig)
    except Exception:
        try:
            from matplotlib import pyplot as plt

            shim_outputs = getattr(plt, "_consume_rendered_outputs", lambda: [])()
            outputs.extend(shim_outputs)
        except Exception:
            pass
    return outputs


@contextlib.contextmanager
def _temporary_cwd(path):
    if not path:
        yield
        return
    previous = os.getcwd()
    os.chdir(path)
    try:
        yield
    finally:
        os.chdir(previous)


def execute_code(session_id: str, code: str, working_directory: str | None = None) -> str:
    namespace = _ensure_session(session_id)
    _EXECUTION_COUNTS[session_id] += 1
    execution_count = _EXECUTION_COUNTS[session_id]
    stdout_buffer = io.StringIO()
    stderr_buffer = io.StringIO()
    outputs = []

    try:
        parsed = ast.parse(code, mode="exec")
        expression = None
        body = parsed.body
        if body and isinstance(body[-1], ast.Expr):
            expression = ast.Expression(body.pop().value)
            ast.fix_missing_locations(expression)

        module = ast.Module(body=body, type_ignores=[])
        ast.fix_missing_locations(module)

        with _temporary_cwd(working_directory), contextlib.redirect_stdout(stdout_buffer), contextlib.redirect_stderr(stderr_buffer):
            exec(compile(module, "<cell>", "exec"), namespace, namespace)
            if expression is not None:
                result = eval(compile(expression, "<cell>", "eval"), namespace, namespace)
                display = _capture_rich_result(result)
                if display:
                    outputs.append(display)
    except Exception as exc:
        outputs.append(
            {
                "output_type": "error",
                "ename": type(exc).__name__,
                "evalue": str(exc),
                "traceback": traceback.format_exception(type(exc), exc, exc.__traceback__),
            }
        )

    stdout_text = stdout_buffer.getvalue()
    stderr_text = stderr_buffer.getvalue()
    if stdout_text:
        outputs.insert(0, {"output_type": "stream", "name": "stdout", "text": stdout_text})
    if stderr_text:
        outputs.append({"output_type": "stream", "name": "stderr", "text": stderr_text})

    outputs.extend(_capture_matplotlib_outputs())
    return json.dumps({"execution_count": execution_count, "outputs": outputs})


def reset_session(session_id: str) -> str:
    _SESSIONS.pop(session_id, None)
    _EXECUTION_COUNTS.pop(session_id, None)
    _ensure_session(session_id)
    return json.dumps({"ok": True})
