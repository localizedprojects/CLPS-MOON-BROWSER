"""Deterministic output helpers shared by every pipeline writer.

* :func:`write_json` writes UTF-8 with LF line endings on every platform
  (``Path.write_text`` turns ``\n`` into CRLF on Windows, so a regenerated
  file was never byte-identical to the committed LF file).
* :func:`utc_stamp` is the ``generatedUtc`` stamp. It honours the
  reproducible-builds ``SOURCE_DATE_EPOCH`` variable, so a no-op
  regeneration can leave the tree byte-identical.
"""

from __future__ import annotations

import datetime as dt
import json
import os
from pathlib import Path


def write_json(path, obj, **dumps_kwargs) -> None:
    Path(path).write_bytes(json.dumps(obj, **dumps_kwargs).encode("utf-8"))


def utc_stamp() -> str:
    sde = os.environ.get("SOURCE_DATE_EPOCH", "").strip()
    if sde:
        t = dt.datetime.fromtimestamp(int(sde), dt.timezone.utc)
    else:
        t = dt.datetime.now(dt.timezone.utc)
    return t.strftime("%Y-%m-%dT%H:%M:%SZ")
