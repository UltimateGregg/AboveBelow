#!/usr/bin/env python3
"""Query the s&box API schema for type signatures.

Usage:
  query_schema.py <type_name>          # full dump of a type
  query_schema.py <type_name> <member> # just one member
  query_schema.py --list <pattern>     # find types matching pattern
"""
import json
import sys

SCHEMA = "/sessions/brave-upbeat-pasteur/mnt/S&Box/api schema.json"

def load():
    with open(SCHEMA) as f:
        return json.load(f)

def find_type(types, name):
    # exact match by FullName or Name
    for t in types:
        if t.get("FullName") == name or t.get("Name") == name:
            return t
    return None

def fmt_method(m):
    params = ", ".join(f"{p['Type']} {p['Name']}" for p in m.get("Parameters", []))
    return f"{m.get('ReturnType', 'void')} {m['Name']}({params})"

def fmt_property(p):
    return f"{p.get('PropertyType', '?')} {p['Name']}"

def dump_type(t, member=None):
    print(f"=== {t['FullName']}  (assembly: {t.get('Assembly', '?')}) ===")
    if t.get("BaseType"):
        print(f"BaseType: {t['BaseType']}")
    if t.get("Documentation", {}).get("Summary"):
        print(f"Doc: {t['Documentation']['Summary'].strip()[:300]}")
    print()
    if member:
        member_lower = member.lower()
        # check properties
        for p in t.get("Properties", []) or []:
            if p["Name"].lower() == member_lower:
                print(f"PROPERTY: {fmt_property(p)}")
                if p.get("Documentation", {}).get("Summary"):
                    print(f"  Doc: {p['Documentation']['Summary'].strip()}")
                return
        # check methods
        hits = [m for m in (t.get("Methods") or []) if m["Name"].lower() == member_lower]
        for m in hits:
            print(f"METHOD: {fmt_method(m)}")
            if m.get("Documentation", {}).get("Summary"):
                print(f"  Doc: {m['Documentation']['Summary'].strip()}")
        if not hits:
            print(f"No member named {member!r} on {t['FullName']}")
        return
    # full dump
    if t.get("Properties"):
        print(f"-- Properties ({len(t['Properties'])}) --")
        for p in t["Properties"]:
            print(f"  {fmt_property(p)}")
    if t.get("Methods"):
        print(f"-- Methods ({len(t['Methods'])}) --")
        for m in t["Methods"][:50]:
            print(f"  {fmt_method(m)}")
        if len(t["Methods"]) > 50:
            print(f"  ... ({len(t['Methods']) - 50} more)")

def main():
    args = sys.argv[1:]
    if not args:
        print(__doc__)
        return
    data = load()
    types = data["Types"]

    if args[0] == "--list":
        pat = args[1].lower()
        for t in types:
            if pat in t.get("FullName", "").lower() or pat in t.get("Name", "").lower():
                print(t["FullName"])
        return

    name = args[0]
    member = args[1] if len(args) > 1 else None
    t = find_type(types, name)
    if not t:
        print(f"Type {name!r} not found. Try --list with a substring.")
        return
    dump_type(t, member)

if __name__ == "__main__":
    main()
