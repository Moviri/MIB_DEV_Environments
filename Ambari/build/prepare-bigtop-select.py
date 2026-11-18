#!/usr/bin/env python3
"""Port the pinned Bigtop 3.3.0 distro-select to Python 3, preserving behavior."""

import argparse
import hashlib
import os
from pathlib import Path
import shutil
import tempfile


# Exclude only the interpreter line, which RPM packaging may rewrite.
ORIGINAL = "813d2f4fe2286cb3a42d16ef607ae228590bd4dce902531d0e359358c724bfbe"
PATCHED = "e8f64012d35213c26848e735fde920ee66c897705dda4798071ffd60ce961273"


def prepare(path, build_root=None, backup=False):
    path = path.resolve(strict=True)
    header, body = path.read_text().split("\n", 1)
    digest = hashlib.sha256(body.encode()).hexdigest()
    if digest == PATCHED:
        print("Bigtop selector is already Python 3 compatible.")
        return
    if digest != ORIGINAL or header not in (
        "#!/usr/bin/env python2", "#!/usr/bin/python2", "#!/usr/bin/python2.7"
    ):
        raise ValueError("Unexpected distro-select contents; refusing to modify it.")

    body = body.replace("0755", "0o755")
    # Python 3 dict views cannot be sorted in place or shallow-copied as lists.
    for name in ("leaves", "aliases", "result"):
        body = body.replace(name + ".keys()", "list(" + name + ".keys())")
    if hashlib.sha256(body.encode()).hexdigest() != PATCHED:
        raise ValueError("Selector conversion did not match the expected result.")
    result = "#!/usr/bin/python3\n" + body
    compile(result, str(path), "exec")

    # Invalidate before writing, including when an earlier source RPM was built.
    if build_root is not None:
        for name in (".srpm", ".rpm"):
            marker = build_root / "build/bigtop-select" / name
            if marker.exists():
                marker.unlink()
    if backup:
        original = path.with_name(path.name + ".before-python3-fix")
        if not original.exists():
            shutil.copy2(str(path), str(original))

    descriptor, temporary = tempfile.mkstemp(prefix=".distro-select-", dir=str(path.parent))
    try:
        with os.fdopen(descriptor, "w") as stream:
            stream.write(result)
        shutil.copymode(str(path), temporary)
        os.replace(temporary, str(path))
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    print("Updated Bigtop 3.3.0 distro-select for Python 3.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("selector", type=Path)
    parser.add_argument("--build-root", type=Path)
    parser.add_argument("--backup", action="store_true")
    args = parser.parse_args()
    prepare(args.selector, args.build_root, args.backup)
