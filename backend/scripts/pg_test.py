"""Run the test suite against a throwaway PostgreSQL.

    python scripts/pg_test.py [pytest arguments...]

It finds initdb/pg_ctl (in "C:/Program Files/PostgreSQL/<highest version>/bin" or on PATH), creates a brand-new
cluster in a temporary folder (trust auth, listening only on 127.0.0.1, on a free port), starts it, creates a
database, runs pytest with OPENLUCID_TEST_DATABASE_URL pointing at it, then stops the cluster and deletes the folder,
also when the tests fail or you press Ctrl-C. It never touches an existing PostgreSQL service or data directory.
The exit code is pytest's.
"""

import os
import re
import shutil
import socket
import subprocess
import sys
import tempfile
import time
from pathlib import Path

import psycopg

BACKEND_DIR = Path(__file__).resolve().parent.parent
WINDOWS_INSTALL_ROOT = Path("C:/Program Files/PostgreSQL")
DATABASE_NAME = "openlucid_test"
SUPERUSER = "postgres"
EXE = ".exe" if os.name == "nt" else ""


def find_pg_bin() -> Path:
    """The bin folder of the newest local PostgreSQL that has both initdb and pg_ctl."""

    def has_tools(folder: Path) -> bool:
        return (folder / f"initdb{EXE}").is_file() and (folder / f"pg_ctl{EXE}").is_file()

    if WINDOWS_INSTALL_ROOT.is_dir():
        versions = [p for p in WINDOWS_INSTALL_ROOT.iterdir() if p.is_dir() and re.fullmatch(r"\d+(\.\d+)?", p.name)]
        for version in sorted(versions, key=lambda p: [int(part) for part in p.name.split(".")], reverse=True):
            if has_tools(version / "bin"):
                return version / "bin"
    initdb = shutil.which("initdb")
    if initdb and has_tools(Path(initdb).parent):
        return Path(initdb).parent
    sys.exit("Could not find initdb and pg_ctl. Install PostgreSQL 15+ or put its bin folder on PATH.")


def free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def run(command: list[str], **kwargs) -> None:
    subprocess.run(command, check=True, stdout=subprocess.DEVNULL, **kwargs)


def init_cluster(pg_bin: Path, data_dir: Path, port: int) -> None:
    run([str(pg_bin / f"initdb{EXE}"), "-D", str(data_dir), "-U", SUPERUSER, "-A", "trust", "-E", "UTF8",
         "--locale=C", "--no-instructions"])
    settings = (
        "\n# throwaway test cluster (scripts/pg_test.py)\n"
        f"port = {port}\n"
        "listen_addresses = '127.0.0.1'\n"
        "unix_socket_directories = ''\n"
        # Durability is pointless for a cluster that is deleted afterwards; this makes tests faster.
        "fsync = off\nsynchronous_commit = off\nfull_page_writes = off\n"
    )
    with open(data_dir / "postgresql.conf", "a", encoding="utf-8") as conf:
        conf.write(settings)


def start_cluster(pg_bin: Path, data_dir: Path, log_file: Path) -> None:
    # A separate process group on Windows, so Ctrl-C reaches us (and we stop the server cleanly) instead of it.
    flags = subprocess.CREATE_NEW_PROCESS_GROUP if os.name == "nt" else 0
    run([str(pg_bin / f"pg_ctl{EXE}"), "-D", str(data_dir), "-l", str(log_file), "-w", "-t", "60", "start"],
        creationflags=flags)


def stop_cluster(pg_bin: Path, data_dir: Path) -> None:
    subprocess.run(
        [str(pg_bin / f"pg_ctl{EXE}"), "-D", str(data_dir), "-m", "immediate", "-w", "-t", "60", "stop"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def remove_folder(folder: Path) -> None:
    """Delete the temp folder; Windows can hold files a moment after the server stops, so retry briefly."""
    for _ in range(20):
        shutil.rmtree(folder, ignore_errors=True)
        if not folder.exists():
            return
        time.sleep(0.5)
    print(f"pg_test: could not fully remove {folder}; please delete it by hand.", file=sys.stderr)


def create_database(port: int) -> None:
    with psycopg.connect(host="127.0.0.1", port=port, user=SUPERUSER, dbname="postgres", autocommit=True) as conn:
        conn.execute(f"CREATE DATABASE {DATABASE_NAME}")


def main(pytest_args: list[str]) -> int:
    pg_bin = find_pg_bin()
    temp_dir = Path(tempfile.mkdtemp(prefix="openlucid-pg-"))
    data_dir = temp_dir / "data"
    started = False
    try:
        port = free_port()
        print(f"pg_test: PostgreSQL from {pg_bin}, temporary cluster on 127.0.0.1:{port}", flush=True)
        init_cluster(pg_bin, data_dir, port)
        start_cluster(pg_bin, data_dir, temp_dir / "postgres.log")
        started = True
        create_database(port)
        env = dict(os.environ)
        env["OPENLUCID_TEST_DATABASE_URL"] = f"postgresql+psycopg://{SUPERUSER}@127.0.0.1:{port}/{DATABASE_NAME}"
        return subprocess.run([sys.executable, "-m", "pytest", *pytest_args], cwd=BACKEND_DIR, env=env).returncode
    except KeyboardInterrupt:
        print("pg_test: interrupted, cleaning up.", file=sys.stderr)
        return 130
    except subprocess.CalledProcessError as error:
        print(f"pg_test: setting up PostgreSQL failed: {error}", file=sys.stderr)
        log = temp_dir / "postgres.log"
        if log.exists():
            print(log.read_text(encoding="utf-8", errors="replace")[-3000:], file=sys.stderr)
        return 1
    finally:
        if started or data_dir.exists():
            stop_cluster(pg_bin, data_dir)
        remove_folder(temp_dir)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
