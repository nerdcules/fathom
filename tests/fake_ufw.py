#!/usr/bin/env python3
"""A stand-in for ufw for the tests: never the real firewall.

It keeps its rules in $FATHOM_SENTINEL_ETC/ufw/user.rules and user6.rules in
ufw's own '### tuple ###' format, reads IPV6= from
$FATHOM_SENTINEL_ETC/default/ufw, and follows ufw 0.36.2's rules for
adding, prepending and deleting, as read from its source
(backend_iptables.py set_rule, common.py UFWRule.match, frontend.py
set_rule for prepend). It takes only the commands Fathom uses:

  ufw [--force] [prepend|delete] allow|deny [in on <iface>] [proto <p>]
      [from <addr>] [to <addr>] [port <ports>] [comment <text>]

FAKE_UFW_LOG: append each command line to this file.
FAKE_UFW_DELETE_IGNORES_COMMENT=1: act like a ufw that deletes the first
rule matching apart from its comment, to show the helper notices.
FAKE_UFW_FAIL=1: fail every command.
"""

import ipaddress
import os
import sys

ETC = os.environ["FATHOM_SENTINEL_ETC"]
FILES = {4: os.path.join(ETC, "ufw/user.rules"), 6: os.path.join(ETC, "ufw/user6.rules")}
ANY = {4: "0.0.0.0/0", 6: "::/0"}
HEAD = "*filter\n### RULES ###\n"
TAIL = "\n### END RULES ###\nCOMMIT\n"


def ipv6_on():
    try:
        with open(os.path.join(ETC, "default/ufw")) as f:
            return any(line.strip() == "IPV6=yes" for line in f)
    except OSError:
        return False


def read(family):
    try:
        with open(FILES[family]) as f:
            lines = [line.rstrip("\n") for line in f if line.startswith("### tuple ###")]
    except FileNotFoundError:
        return []
    rules = []
    for line in lines:
        body, _, hexed = line[len("### tuple ###"):].strip().partition(" comment=")
        rules.append((body.split(), hexed.strip()))
    return rules


def write(family, rules):
    with open(FILES[family], "w") as f:
        f.write(HEAD)
        for fields, hexed in rules:
            f.write("\n### tuple ### " + " ".join(fields) + (f" comment={hexed}" if hexed else "") + "\n")
            f.write("-A ufw-user-input -j FAKE\n")
        f.write(TAIL)


def match(x, y):
    """common.py UFWRule.match: 0 match, 1 no match, -1 all but action,
    -2 all but comment."""
    (xf, xc), (yf, yc) = x, y
    if xf[1:] != yf[1:]:
        return 1
    if xf[0] == yf[0] and xc == yc:
        return 0
    if xf[0] == yf[0]:
        return -2
    return -1


def set_rule(rules, rule, position, remove):
    """backend_iptables.py set_rule, for one address family."""
    newrules, found, inserted, matches, modified = [], False, False, 0, False
    loose = remove and os.environ.get("FAKE_UFW_DELETE_IGNORES_COMMENT") == "1"
    for count, r in enumerate(rules, 1):
        if count == position:
            inserted = True
            newrules.append(rule)
        ret = match(r, rule)
        if ret < 1:
            matches += 1
        if loose and ret in (0, -2) and not found:
            found = True
        elif ret == 0 and not found and not inserted:
            found = True
            if not remove:
                newrules.append(rule)
        elif ret == -2 and remove and rule[1] == "":
            found = True
        elif ret < 0 and not remove and not inserted:
            found = modified = True
            newrules.append(rule)
        else:
            newrules.append(r)
    if inserted:
        if matches > 0:
            return None, "Skipping inserting existing rule"
    elif not found and not remove:
        newrules.append(rule)
    elif not found and remove:
        return None, "Could not delete non-existent rule"
    elif found and not remove and not modified:
        return None, "Skipping adding existing rule"
    return newrules, "Rules updated"


def address(text):
    net = ipaddress.ip_network(text, strict=False)
    return net.version, (str(net.network_address) if net.num_addresses == 1 else str(net))


def main(argv):
    if os.environ.get("FAKE_UFW_LOG"):
        with open(os.environ["FAKE_UFW_LOG"], "a") as f:
            f.write(" ".join(argv) + "\n")
    if os.environ.get("FAKE_UFW_FAIL") == "1":
        sys.exit("ERROR: fake ufw told to fail")
    argv = [a for a in argv if a != "--force"]
    position, remove = 0, False
    if argv and argv[0] == "prepend":
        position, argv = -1, argv[1:]
    elif argv and argv[0] == "delete":
        remove, argv = True, argv[1:]
    if not argv or argv[0] not in ("allow", "deny"):
        sys.exit(f"ERROR: fake ufw doesn't know: {' '.join(argv)}")
    action, rest = argv[0], argv[1:]
    proto, dport, ifaces, comment, src, dst = "any", "any", "in", "", None, None
    i = 0
    while i < len(rest):
        word = rest[i]
        if word == "in" and rest[i + 1:i + 2] == ["on"]:
            ifaces = "in_" + rest[i + 2]
            i += 3
            continue
        value = rest[i + 1]
        if word == "proto":
            proto = value
        elif word == "from":
            src = address(value)
        elif word == "to":
            dst = address(value)
        elif word == "port":
            dport = value
        elif word == "comment":
            comment = value.encode().hex()
        else:
            sys.exit(f"ERROR: fake ufw doesn't know '{word}'")
        i += 2
    versions = {a[0] for a in (src, dst) if a}
    if len(versions) > 1:
        sys.exit("ERROR: Invalid address mix")
    families = sorted(versions) if versions else ([4, 6] if ipv6_on() else [4])
    if 6 in families and not ipv6_on():
        sys.exit("ERROR: IPv6 support not enabled")
    out = []
    for family in families:
        fields = [action, proto, dport, dst[1] if dst else ANY[family], "any",
                  src[1] if src else ANY[family], ifaces]
        rules = read(family)
        # frontend.py: prepend goes in at position 1, or appends to an empty list.
        pos = (1 if rules else 0) if position == -1 else 0
        new, said = set_rule(rules, (fields, comment), pos, remove)
        if new is not None:
            write(family, new)
        out.append(said + (" (v6)" if family == 6 else ""))
    print("\n".join(out))


if __name__ == "__main__":
    main(sys.argv[1:])
