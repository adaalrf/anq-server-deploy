"""Validate snapshots; extract only into a NEW directory outside live game state."""
import hashlib
from pathlib import Path, PurePosixPath
import sys
import tarfile


def checked_members(source):
    members = source.getmembers()
    if not members:
        raise ValueError("Archive is empty.")
    for member in members:
        path = PurePosixPath(member.name)
        if path.is_absolute() or ".." in path.parts or not (member.isfile() or member.isdir()):
            raise ValueError("Archive contains an unsafe path, link or special file.")
    return members


def validate(archive: Path) -> None:
    with tarfile.open(archive, "r:gz") as source:
        checked_members(source)


def restore(archive: Path, target: Path, live: Path) -> None:
    archive = archive.resolve(strict=True)
    target = target.resolve()
    live = live.resolve()
    if target == live or live in target.parents:
        raise ValueError("Restore checks cannot write into live game state.")
    if target.exists():
        raise ValueError("Choose a new, nonexistent restore directory.")
    checksum = Path(str(archive) + ".sha256").read_text().split()[0]
    with archive.open("rb") as stream:
        actual = hashlib.file_digest(stream, "sha256").hexdigest()
    if actual != checksum:
        raise ValueError("Archive checksum mismatch; nothing extracted.")
    with tarfile.open(archive, "r:gz") as source:
        members = checked_members(source)
        target.mkdir(mode=0o700)
        source.extractall(target, members=members, filter="data")
    print(f"Extracted into {target}. Inspect saves/settings before any manual recovery.")


if __name__ == "__main__":
    try:
        if len(sys.argv) == 3 and sys.argv[1] == "--validate":
            validate(Path(sys.argv[2]))
        elif len(sys.argv) == 4:
            restore(*(Path(value) for value in sys.argv[1:]))
        else:
            raise ValueError("Expected ARCHIVE NEW_DIRECTORY LIVE_DIRECTORY")
    except (OSError, ValueError, IndexError, tarfile.TarError) as error:
        print(f"Restore check failed: {error}", file=sys.stderr)
        sys.exit(1)
