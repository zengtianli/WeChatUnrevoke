"""公开边界扫描：公开仓、引擎仓、公开 ZIP、官网与产品卡里不得出现本机私有工具的字样。

关键词表只放本机、不进公开仓：scripts/accept/boundary.local.txt（已被 .gitignore 忽略，一行一个正则片段，
区分大小写）。没有这张表时整项报告 BLOCKED（78），不当作零命中。只报命中计数与所在范围/文件名，
绝不打印命中行正文。只读：不 fetch、不改任何仓。由 privacy.py 调用，也可单独运行。
"""
from __future__ import annotations

import ast
import hashlib
import json
import re
import subprocess
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
UNREVOKE = ROOT
TWEAK = ROOT.parent / "vendor/WeChatTweak"
PRODUCTS = Path.home() / "Dev/tools/configs/menus/entities/products.yaml"
PRODUCT_ID = "unrevoke-mac"
PATTERNS = Path(__file__).with_name("boundary.local.txt")
MAX_LISTED = 8
KEYWORDS = ""
PATTERN = re.compile(b"(?!)")


class Unavailable(Exception):
    pass


def load_patterns() -> None:
    global KEYWORDS, PATTERN
    try:
        parts = [line.strip() for line in PATTERNS.read_text(encoding="utf-8").splitlines()
                 if line.strip() and not line.lstrip().startswith("#")]
    except OSError:
        parts = []
    if not parts:
        raise Unavailable("本机没有公开边界关键词表 scripts/accept/boundary.local.txt")
    KEYWORDS = "|".join(parts)
    PATTERN = re.compile(KEYWORDS.encode())


class Checks:
    def __init__(self):
        self.rows = []

    def ok(self, label: str, cond: bool, note: str = ""):
        self.rows.append({"check": label, "passed": bool(cond), "note": note})
        print(("✓ " if cond else "✗ ") + label + (f" — {note}" if note else ""), flush=True)


def count(data: bytes) -> int:
    return len(PATTERN.findall(data))


def git(repo: Path, *args: str, ok=(0,)) -> subprocess.CompletedProcess:
    result = subprocess.run(["git", "-C", str(repo), *args], capture_output=True, timeout=120)
    if result.returncode not in ok:
        raise RuntimeError(f"git {args[0]} 退出码 {result.returncode}")
    return result


def describe(total_items: int, unit: str, hits: dict[str, int]) -> str:
    if not hits:
        return f"扫描 {total_items} 个{unit}，零命中"
    listed = sorted(hits.items(), key=lambda kv: (-kv[1], kv[0]))[:MAX_LISTED]
    more = f" 等共 {len(hits)} 个" if len(hits) > MAX_LISTED else ""
    return (f"扫描 {total_items} 个{unit}，命中 {sum(hits.values())} 处，位于："
            + "、".join(f"{name}({n})" for name, n in listed) + more)


def scan_tree(repo: Path, rev: str) -> tuple[str, dict[str, int], int]:
    """git 树里的路径名 + 全部 blob 内容（-a 连二进制一起扫）。"""
    sha = git(repo, "rev-parse", "--verify", "--quiet", rev + "^{commit}").stdout.decode().strip()
    names = [n for n in git(repo, "ls-tree", "-r", "-z", "--name-only", sha).stdout.decode("utf-8", "replace").split("\0") if n]
    hits: dict[str, int] = {}
    for name in names:
        n = count(name.encode())
        if n:
            hits[f"{name}[路径名]"] = n
    grep = git(repo, "grep", "-a", "-c", "-E", "-z", "-e", KEYWORDS, sha, "--", ok=(0, 1))
    # -z 输出形如 "<sha>:<path>\0<count>\n"；只取文件名与计数，不取正文。
    for record in grep.stdout.decode("utf-8", "replace").splitlines():
        path, _, n = record.rpartition("\0")
        if path:
            name = path.split(":", 1)[1] if path.startswith(sha + ":") else path
            hits[name] = hits.get(name, 0) + int(n or 0)
    return sha[:12], hits, len(names)


def scan_worktree_changes(repo: Path) -> tuple[dict[str, int], int]:
    """git status 里未跟踪（未忽略）与已修改/新增的工作区文件：路径名 + 字节。"""
    raw = git(repo, "status", "--porcelain=v1", "-z", "--untracked-files=all").stdout.decode("utf-8", "replace")
    fields = raw.split("\0")
    paths, i = [], 0
    while i < len(fields):
        entry = fields[i]
        i += 1
        if len(entry) < 4:
            continue
        status, path = entry[:2], entry[3:]
        if "R" in status or "C" in status:
            i += 1  # -z 模式下重命名/复制的原路径紧随其后
        if "D" in status and not (repo / path).exists():
            continue
        paths.append(path)
    hits: dict[str, int] = {}
    for path in paths:
        target = repo / path
        data = path.encode()
        if target.is_symlink():
            data += b"\n" + str(target.readlink()).encode()
        elif target.is_file():
            data += b"\n" + target.read_bytes()
        n = count(data)
        if n:
            hits[path] = n
    return hits, len(paths)


def scan_zip_bytes(archive: zipfile.ZipFile, label: str, hits: dict[str, int]) -> int:
    names = archive.namelist()
    for name in names:
        n = count(name.encode())
        if not name.endswith("/"):
            n += count(archive.read(name))
        if n:
            hits[f"{label}!{name}"] = hits.get(f"{label}!{name}", 0) + n
    return len(names)


def approved_manifest() -> set[str]:
    """与 tests/test_release_manifest.py 同法解析 release.sh 的 PY_MANIFEST.allowed，唯一来源。"""
    shell = (UNREVOKE / "release.sh").read_text()
    gate = shell.split("<<'PY_MANIFEST'\n", 1)[1].split("\nPY_MANIFEST", 1)[0]
    declaration = next(node for node in ast.parse(gate).body
                       if isinstance(node, ast.Assign) and node.targets[0].id == "allowed")
    return set(ast.literal_eval(declaration.value))


def public_zip() -> tuple[Path, str]:
    release = json.loads((UNREVOKE / "dist/site/release.json").read_text())
    return UNREVOKE / f"dist/WeChatUnrevoke-{release['version']}.zip", release["sha256"]


def products_entry() -> tuple[bytes, int]:
    """products.yaml 中 unrevoke-mac 的产品条目原文块（含其中注释）+ 各集合里提到它的行。"""
    import yaml

    text = PRODUCTS.read_text(encoding="utf-8")
    entries = [e for e in (yaml.safe_load(text).get("products") or []) if isinstance(e, dict) and e.get("id") == PRODUCT_ID]
    if len(entries) != 1:
        raise RuntimeError(f"products.yaml 中 {PRODUCT_ID} 条目数为 {len(entries)}")
    lines = text.splitlines()
    start = next(i for i, line in enumerate(lines) if re.match(rf"^\s*-\s+id:\s*{re.escape(PRODUCT_ID)}\s*$", line))
    indent = len(lines[start]) - len(lines[start].lstrip())
    end = start + 1
    while end < len(lines):
        line = lines[end]
        stripped = line.lstrip()
        if stripped and (len(line) - len(stripped)) <= indent:
            break
        end += 1
    block = lines[start:end] + [line for i, line in enumerate(lines)
                                if not (start <= i < end) and re.search(rf"\b{re.escape(PRODUCT_ID)}\b", line)]
    # 结构化值也扫一遍，防止 YAML 锚点/多行标量让原文块漏掉内容。
    payload = "\n".join(block).encode() + b"\n" + json.dumps(entries[0], ensure_ascii=False, default=str).encode()
    return payload, len(block)


def guarded(c, label: str, fn):
    try:
        fn()
    except Exception as exc:  # noqa: BLE001 —— 扫不到就是失败，不能当作零命中
        c.ok(label, False, f"扫描失败：{type(exc).__name__}")


def check_public_boundary(c) -> None:
    def trees():
        for repo, rev, label in ((UNREVOKE, "HEAD", "unrevoke HEAD"),
                                 (UNREVOKE, "refs/remotes/origin/main", "unrevoke origin/main（本地引用，未 fetch）"),
                                 (TWEAK, "HEAD", "WeChatTweak HEAD")):
            guarded(c, f"公开边界零命中：{label}", lambda repo=repo, rev=rev, label=label: _tree(repo, rev, label))

    def _tree(repo, rev, label):
        sha, hits, total = scan_tree(repo, rev)
        c.ok(f"公开边界零命中：{label}", not hits, f"{sha}；" + describe(total, "文件", hits))

    def worktree():
        hits, total = scan_worktree_changes(UNREVOKE)
        c.ok("公开边界零命中：unrevoke 工作区未跟踪与已修改文件", not hits, describe(total, "文件", hits))

    def release_zip():
        path, expected = public_zip()
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        c.ok("公开 ZIP sha256 与 release.json 一致", digest == expected, f"{path.name} {digest[:8]}")
        if digest != expected:
            return
        hits: dict[str, int] = {}
        with zipfile.ZipFile(path) as archive:
            total = scan_zip_bytes(archive, path.name, hits)
            names = archive.namelist()
        c.ok("公开边界零命中：公开 ZIP 条目名与全部条目字节", not hits, describe(total, "条目", hits))
        allowed = approved_manifest()
        extra, missing = set(names) - allowed, allowed - set(names)
        # 泄露只看多出来的文件；白名单比已发的 ZIP 多（例如下一版新增的命令行）不算泄露，记在备注里。
        c.ok("公开 ZIP 文件清单不超出 release.sh 白名单",
             not extra and len(names) == len(set(names)),
             f"条目 {len(names)}，白名单 {len(allowed)}，多出 {len(extra)}，缺少 {len(missing)}，重复 {len(names) - len(set(names))}")

    def site():
        root = UNREVOKE / "dist/site"
        files = sorted(p for p in root.rglob("*") if p.is_file())
        if not files:
            raise RuntimeError("dist/site 为空")
        hits: dict[str, int] = {}
        for p in files:
            rel = p.relative_to(root).as_posix()
            n = count(rel.encode()) + count(p.read_bytes())
            if n:
                hits[rel] = n
            if p.suffix.lower() == ".zip" and zipfile.is_zipfile(p):
                with zipfile.ZipFile(p) as archive:
                    scan_zip_bytes(archive, rel, hits)
        c.ok("公开边界零命中：dist/site 全部文件（ZIP 另展开扫描）", not hits, describe(len(files), "文件", hits))

    def products():
        payload, lines = products_entry()
        n = count(payload)
        c.ok(f"公开边界零命中：products.yaml 的 {PRODUCT_ID} 条目", n == 0,
             f"扫描 {lines} 行，" + ("零命中" if n == 0 else f"命中 {n} 处"))

    trees()
    guarded(c, "公开边界零命中：unrevoke 工作区未跟踪与已修改文件", worktree)
    guarded(c, "公开 ZIP 校验与扫描", release_zip)
    guarded(c, "公开边界零命中：dist/site 全部文件", site)
    guarded(c, f"公开边界零命中：products.yaml 的 {PRODUCT_ID} 条目", products)


def scan() -> list[dict]:
    """返回检查行；缺关键词表抛 Unavailable。"""
    load_patterns()
    c = Checks()
    check_public_boundary(c)
    return c.rows


if __name__ == "__main__":
    try:
        rows = scan()
    except Unavailable as error:
        print(f"BLOCKED: {error}")
        sys.exit(78)
    failed = [r for r in rows if not r["passed"]]
    print(f"公开边界：{len(rows)} 项，{len(failed)} 项未通过")
    sys.exit(1 if failed else 0)
