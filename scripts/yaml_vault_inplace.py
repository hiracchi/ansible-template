#!/usr/bin/env python3
"""encrypt-string.sh から呼ばれる補助スクリプト(単体で使うものではない)。

YAML を行単位で扱い、コメントや他の行を壊さずに特定キーの値だけを読み書きする。

  get     <キーパス> <YAMLファイル>   現在の値(平文)を標準出力に出す
  replace <キーパス> <YAMLファイル>   標準入力の "name: !vault |" ブロックで値を置き換える

キーパスは "." 区切り。リストの要素は、その要素のいずれかのキーの値が一致する
セグメントで指定する(例: my_users.toshi.password は "user: toshi" の要素の password)。
"""
import json
import os
import re
import sys
import tempfile


def indent_of(line):
    return len(line) - len(line.lstrip(" "))


def skippable(line):
    s = line.strip()
    return s == "" or s.startswith("#") or s == "---"


def unquote(v):
    v = v.strip()
    if len(v) >= 2 and v[0] == v[-1] == '"':
        try:
            return json.loads(v)
        except ValueError:
            return v[1:-1]
    if len(v) >= 2 and v[0] == v[-1] == "'":
        return v[1:-1].replace("''", "'")
    return v


def scalar_of(view_line):
    m = re.match(r"^\s*[^\s#:][^:]*:\s+(.*?)\s*$", view_line)
    return unquote(m.group(1)) if m else None


def first_content(view, start, end):
    for i in range(start, end):
        if not skippable(view[i]):
            return i
    return None


def find(orig, keys):
    # リスト要素の先頭行 "- k: v" を "  k: v" に見立てた表示用の行
    view = [re.sub(r"^(\s*)- ", lambda m: m.group(1) + "  ", l) for l in orig]
    start, end = 0, len(orig)
    idx = None
    last = key_indent = 0
    in_item = False  # リスト要素の中にいる間は、先頭行の "- " をキー行として扱う
    for seg in keys:
        fc = first_content(view, start, end)
        if fc is None:
            sys.exit(f"キーが見つかりません: {seg}")
        child = indent_of(view[fc])
        if not in_item and orig[fc].lstrip().startswith("- "):
            # リスト: 要素の先頭行(元の行が "- " で始まる)を集める
            item_indent = indent_of(orig[fc])
            starts = [
                i for i in range(start, end)
                if orig[i].lstrip().startswith("- ") and indent_of(orig[i]) == item_indent
            ]
            hit = None
            for n, s in enumerate(starts):
                e = starts[n + 1] if n + 1 < len(starts) else end
                for i in range(s, e):
                    if skippable(view[i]) or indent_of(view[i]) != child:
                        continue
                    if scalar_of(view[i]) == seg:
                        hit = (s, e)
                        break
                if hit:
                    break
            if not hit:
                sys.exit(f"リストの要素が見つかりません: {seg}")
            start, end = hit
            idx = None  # 要素の中でさらにキーをたどる
            in_item = True
        else:
            pat = re.compile(r"^" + " " * child + re.escape(seg) + r"\s*:(\s|$)")
            hit = None
            for i in range(start, end):
                if skippable(view[i]):
                    continue
                if indent_of(view[i]) < child:
                    break
                if pat.match(view[i]):
                    hit = i
                    break
            if hit is None:
                sys.exit(f"キーが見つかりません: {seg}")
            idx = hit
            in_item = False
            key_indent = indent_of(view[idx])
            last = idx
            for j in range(idx + 1, len(view)):
                if view[j].strip() == "":
                    # 空行を挟んでもブロック内の可能性があるが、安全のためここで止める
                    break
                if indent_of(view[j]) > key_indent:
                    last = j
                else:
                    break
            start, end = idx + 1, last + 1
    if idx is None:
        sys.exit("最後のセグメントはキー名で指定してください")
    return view, idx, last, key_indent


def current_value(view, idx, last, key_indent):
    first = view[idx]
    rest = first.split(":", 1)[1].strip()
    if rest.startswith("!vault"):
        sys.exit("すでに暗号化されています(!vault)。")
    if re.match(r"^[|>][+-]?\d*$", rest):
        body = view[idx + 1:last + 1]
        base = min(indent_of(l) for l in body if l.strip()) if body else 0
        text = "\n".join(l[base:] if l.strip() else "" for l in body)
        if rest.startswith("|"):
            return text if rest.endswith("-") else text + "\n"
        sys.exit("折りたたみ形式(>)の値には対応していません。")
    return unquote(rest)


def main():
    if len(sys.argv) != 4 or sys.argv[1] not in ("get", "replace"):
        sys.exit(__doc__)
    mode, key_path, target = sys.argv[1:]
    with open(target, encoding="utf-8") as f:
        orig = f.read().split("\n")
    view, idx, last, key_indent = find(orig, key_path.split("."))

    if mode == "get":
        sys.stdout.write(current_value(view, idx, last, key_indent))
        return

    encrypted = [l for l in sys.stdin.read().splitlines() if l.strip()]
    prefix = orig[idx][:key_indent]  # リスト要素の先頭行なら "  - " を保つ
    head = prefix + encrypted[0].strip()
    body = [" " * (key_indent + 2) + l.strip() for l in encrypted[1:]]
    new_lines = orig[:idx] + [head] + body + orig[last + 1:]
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(os.path.abspath(target)))
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write("\n".join(new_lines))
    os.chmod(tmp, os.stat(target).st_mode)
    os.replace(tmp, target)
    print(f"{target}: {key_path} を暗号化値で置き換えました(行 {idx + 1}-{last + 1})。")


if __name__ == "__main__":
    main()
