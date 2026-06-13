"""Minimal TOML writer shared by capture and split.

stdlib has tomllib (read) but no writer; the Quicksilver specs are flat enough
to emit by hand. Output is validated with `taplo lint` after generation.
"""


def esc(s):
    return s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")


def val(v, indent=0):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(v)
    if isinstance(v, str):
        return f'"{esc(v)}"'
    if isinstance(v, list):
        if not v:
            return "[]"
        # TOML arrays may span lines; wrap long ones (or arrays of inline
        # tables) one element per line with a trailing comma for clean diffs.
        if len(v) <= 3 and not any(isinstance(x, (dict, list)) for x in v):
            return "[" + ", ".join(val(x) for x in v) + "]"
        pad = "  " * (indent + 1)
        body = ",\n".join(pad + val(x, indent + 1) for x in v)
        return "[\n" + body + ",\n" + "  " * indent + "]"
    raise TypeError(type(v))


def emit(rows, header):
    """rows: list of (table_name, ordered-field-dict). None values are skipped.

    A field whose value is a list of dicts is emitted as a nested
    `[[table.field]]` array-of-tables (every object expanded to key = value
    lines) rather than an inline-table array.
    """
    out = [header, ""]
    for table, fields in rows:
        out.append(f"[[{table}]]")
        nested = []
        for k, v in fields.items():
            if v is None:
                continue
            if isinstance(v, list) and v and all(isinstance(x, dict) for x in v):
                nested.append((k, v))
            else:
                out.append(f"{k} = {val(v)}")
        for k, items in nested:
            for item in items:
                out.append(f"\n[[{table}.{k}]]")
                out += [f"{ik} = {val(iv)}" for ik, iv in item.items() if iv is not None]
        out.append("")
    return "\n".join(out)


def catalog_tail(presets, omitted):
    """Catalog-wide settings, appended after the array-of-tables body.

    Both are emitted as their own `[table]` sections: a bare root key after a
    table header would be silently nested under it, so `omitted_items` lives
    under a dedicated `[catalog]` table.
    """
    out = []
    if presets:
        out.append("\n[enabled_presets]")
        out += [f"{k} = {val(v)}" for k, v in presets.items()]
    if omitted:
        out.append("\n[catalog]")
        out.append(f"omitted_items = {val(list(omitted))}")
    return ("\n".join(out) + "\n") if out else ""
