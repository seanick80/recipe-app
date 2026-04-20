"""Logging configuration for the Recipe App server.

Two log streams:
- server.log: all INFO+ messages (requests, queries, general operations)
- audit.log: auth and security events only (login, logout, denied, rate limit)

Uses a dictConfig-compatible format so uvicorn doesn't clobber our handlers.
Pass LOGGING_CONFIG to uvicorn or call setup_logging() post-startup.
"""
from __future__ import annotations

import logging
from pathlib import Path

LOGS_DIR = Path(__file__).parent / "logs"
LOGS_DIR.mkdir(exist_ok=True)

_FORMAT = "%(asctime)s %(levelname)-8s [%(name)s] %(message)s"
_DATE_FORMAT = "%Y-%m-%d %H:%M:%S"

# dictConfig passed to uvicorn so it merges with (not replaces) our config
LOGGING_CONFIG: dict = {
    "version": 1,
    "disable_existing_loggers": False,
    "formatters": {
        "default": {
            "format": _FORMAT,
            "datefmt": _DATE_FORMAT,
        },
        "access": {
            "format": "%(asctime)s %(levelname)-8s [%(name)s] %(message)s",
            "datefmt": _DATE_FORMAT,
        },
    },
    "handlers": {
        "server_file": {
            "class": "logging.handlers.RotatingFileHandler",
            "filename": str(LOGS_DIR / "server.log"),
            "maxBytes": 5 * 1024 * 1024,
            "backupCount": 3,
            "formatter": "default",
            "level": "INFO",
        },
        "audit_file": {
            "class": "logging.handlers.RotatingFileHandler",
            "filename": str(LOGS_DIR / "audit.log"),
            "maxBytes": 5 * 1024 * 1024,
            "backupCount": 5,
            "formatter": "default",
            "level": "INFO",
        },
        "console": {
            "class": "logging.StreamHandler",
            "formatter": "default",
            "stream": "ext://sys.stderr",
        },
    },
    "loggers": {
        "uvicorn": {
            "handlers": ["console", "server_file"],
            "level": "INFO",
            "propagate": False,
        },
        "uvicorn.error": {
            "handlers": ["console", "server_file"],
            "level": "INFO",
            "propagate": False,
        },
        "uvicorn.access": {
            "handlers": ["console", "server_file"],
            "level": "INFO",
            "propagate": False,
        },
        "audit": {
            "handlers": ["audit_file", "server_file"],
            "level": "INFO",
            "propagate": False,
        },
    },
    "root": {
        "handlers": ["console", "server_file"],
        "level": "INFO",
    },
}


def setup_logging() -> None:
    """Apply LOGGING_CONFIG via dictConfig.

    Called from main.py at import time.  When running under ``uvicorn
    main:app``, uvicorn applies its own dictConfig *before* importing
    main.py, so calling this again simply re-applies our config.
    """
    import logging.config

    logging.config.dictConfig(LOGGING_CONFIG)


def get_audit_logger() -> logging.Logger:
    """Return the audit logger."""
    return logging.getLogger("audit")
