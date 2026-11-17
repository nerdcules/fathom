#!/bin/bash
# The real-ufw check for Fathom issue #1, in the disposable VM. Prints PASS/FAIL per check.
A=/usr/local/lib/fathom-sentinel/admin
IF=$(ip -j link | jq -r '.[].ifname' | grep -m1 -E '^(en|eth|wl)')
rules() { sudo cat /etc/ufw/user.rules /etc/ufw/user6.rules | grep '^### tuple'; }
count() { rules | grep -c -- "$1"; }
hexc() { printf %s "$1" | od -An -tx1 | tr -d ' \n'; }
FB=$(hexc fathom-block); FL=$(hexc fathom-lockdown)
pass=0; fail=0
check() { if eval "$2"; then echo "PASS $1"; pass=$((pass+1)); else echo "FAIL $1"; fail=$((fail+1)); fi; }
echo "interface: $IF; IPv6: $(grep ^IPV6= /etc/default/ufw)"
before=$(rules)

# 1. Your own block of an address, identical to Fathom's but without its comment.
sudo ufw prepend deny from 192.0.2.77 >/dev/null
sudo $A block 192.0.2.77 2>/tmp/e; code=$?
check "block refuses beside your identical rule (exit 3)" '[ $code = 3 ]'
check "  ...and adds nothing" '[ $(count "deny any any 0.0.0.0/0 any 192.0.2.77 in") = 1 ]'
sudo $A unblock 192.0.2.77 2>/tmp/e; code=$?
check "unblock leaves your rule (exit 3, rule still there)" '[ $code = 3 ] && [ $(count "192.0.2.77 in\$") = 1 ]'
sudo ufw delete deny from 192.0.2.77 >/dev/null

# 2. Fathom's own block, pressed twice, then unblocked; IPv4 and IPv6.
for ip in 192.0.2.88 2001:db8::5; do
  sudo $A block $ip; sudo $A block $ip
  check "block $ip twice gives one rule with Fathom's comment" '[ $(rules | grep -- " $ip in comment=$FB" | wc -l) = 1 ]'
  sudo $A unblock $ip
  check "unblock $ip removes it" '[ $(rules | grep -c -- " $ip in") = 0 ]'
done

# 3. Unblock before block changes nothing.
sudo $A unblock 192.0.2.99; code=$?
check "unblock of an address never blocked changes nothing" '[ "$(rules)" = "$before" ]'

# 4. Lockdown beside your own identical interface rule.
sudo ufw deny in on $IF >/dev/null
sudo $A lockdown on 2>/tmp/e; code=$?
check "lockdown on refuses beside your rule (exit 3)" '[ $code = 3 ] && [ $(rules | grep -c "comment=$FL") = 0 ]'
sudo $A lockdown off 2>/tmp/e
check "lockdown off keeps your interface rule (IPv4 and IPv6)" '[ $(rules | grep -c " in_$IF\$") = 2 ]'
sudo ufw delete deny in on $IF >/dev/null

# 5. Lockdown on twice, off; off before on.
sudo $A lockdown off
check "lockdown off before on changes nothing" '[ "$(rules)" = "$before" ]'
sudo $A lockdown on; sudo $A lockdown on
check "lockdown on twice gives Fathom's rule once per family" '[ $(rules | grep -c " in_$IF comment=$FL") -ge 1 ] && [ $(rules | grep " in_$IF comment=$FL" | sort | uniq -d | wc -l) = 0 ]'
sudo $A lockdown off
check "lockdown off returns to the original rules" '[ "$(rules)" = "$before" ]'

# 6. Uninstall's remove-all beside your identical rule.
sudo $A block 192.0.2.88
sudo $A lockdown on
sudo $A remove-all; code=$?
check "remove-all takes out Fathom's rules" '[ $(rules | grep -cE "comment=($FB|$FL)") = 0 ]'
check "  ...and the ruleset is back to the original" '[ "$(rules)" = "$before" ]'
echo "passed $pass, failed $fail"
