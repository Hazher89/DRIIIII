"""Ensure OpenAI CLIP is importable for YOLO-World (Windows-friendly)."""

from __future__ import annotations

import logging
import subprocess
import sys

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger("ensure_clip")


def main() -> int:
    try:
        import clip  # noqa: F401

        logger.info("CLIP OK (%s)", getattr(clip, "__file__", "unknown"))
        return 0
    except Exception as exc:
        logger.warning("CLIP mangler (%s) — installerer openai-clip fra PyPI…", exc)

    cmds = [
        [sys.executable, "-m", "pip", "install", "--upgrade", "openai-clip", "ftfy", "regex"],
        # Fallback zip uten permanent git-klon
        [
            sys.executable,
            "-m",
            "pip",
            "install",
            "https://github.com/openai/CLIP/archive/refs/heads/main.zip",
        ],
    ]
    for cmd in cmds:
        try:
            logger.info("Kjorer: %s", " ".join(cmd))
            subprocess.check_call(cmd)
            import clip  # noqa: F401

            logger.info("CLIP installert OK")
            return 0
        except Exception as exc:
            logger.warning("Install feilet: %s", exc)

    logger.error(
        "Kunne ikke installere CLIP. Kjør manuelt i .venv:\n"
        "  .\\.venv\\Scripts\\pip install openai-clip ftfy regex"
    )
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
