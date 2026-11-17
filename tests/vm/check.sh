#!/usr/bin/env bash
# The full VM check of this checkout (uncommitted changes included):
#   FATHOM_VM_USER=<vm user> check.sh [older-ref]
# In the running test VM, with Fathom not installed: an older Fathom
# (default e132146, before issues #1-#3), then this one over it (upgrade),
# uninstall, a fresh install, the opt-in parts, the real-ufw checks
# (fwtest.sh), and a full uninstall beside a ufw rule of the user's. Each
# uninstall is compared with a capture taken before the first install.
# Prints PASS/FAIL per check; logs go to $FATHOM_VM/logs/<time>-<commit>.
# Every command runs in the VM; the host only copies files in.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo=$(git -C "$here" rev-parse --show-toplevel)
vm_dir=${FATHOM_VM:-$HOME/VMs/omarchy-test}
old=${1:-e132146}
tree=$(git -C "$repo" stash create)
tree=${tree:-HEAD}
label="$(git -C "$repo" rev-parse --short HEAD)$([[ $tree != HEAD ]] && echo -dirty)"
logs="$vm_dir/logs/$(date +%Y%m%d-%H%M%S)-$label"
mkdir -p "$logs"
pass=0 fail=0

vm() { "$here/vm.sh" "$@"; }
check() { if [[ $2 == 0 ]]; then echo "PASS $1"; pass=$((pass + 1)); else echo "FAIL $1"; fail=$((fail + 1)); fi; }
# Run a Fathom script in the VM with a terminal; log it; exit code back.
step() {
  local name=$1 cmd=$2
  # A step that hangs (Hyprland once froze on uninstall's `hyprctl reload`
  # in the VM) fails after 5 minutes instead of stopping the check.
  timeout 300 "$here/vm.sh" -t "$cmd 2>&1; echo \"EXIT=\$?\"" | tr -d '\r' | sed 's/\x1b\][^\\]*\\//g' >"$logs/$name.log" 2>&1
  grep -q '^EXIT=0$' "$logs/$name.log" || { echo "  ($name: no EXIT=0 within 5 minutes; see $logs/$name.log)"; return 1; }
}
# Compare a capture with the baseline. Allowed: the hyprland.lua backups
# install.sh makes (README: uninstall leaves them), and Omarchy's own
# rewrite of the bar setting in shell.json; $2 is extra ufw lines expected.
same_as_baseline() {
  local cap=$1 extra_ufw=${2:-}
  vm "cd ~/captures && for f in theme bar fathom-dirs hyprland.md5 hyprland-fathom user-units system-units system-files; do
        diff -q baseline/\$f $cap/\$f >/dev/null || { echo \"differs: \$f\"; exit 1; }; done
      diff <(grep -v '^hyprland.lua.bak.' baseline/files) <(grep -v '^hyprland.lua.bak.' $cap/files) >/dev/null || { echo 'differs: files'; exit 1; }
      norm() { jq -S 'del(.bar.transparent, .bar.background)' \"\$1\"; }
      diff <(norm baseline/shell.json) <(norm $cap/shell.json) >/dev/null || { echo 'differs: shell.json'; exit 1; }
      diff <( (cat baseline/ufw-tuples; printf '%s' '$extra_ufw' | sed '/^\$/d') | sort) <(sort $cap/ufw-tuples) >/dev/null || { echo 'differs: ufw rules'; exit 1; }" \
    >>"$logs/compare-$cap.log" 2>&1
}

echo "Checking $label (older: $old) in $vm_dir; logs in $logs"
vm 'true' 2>/dev/null; check "the VM answers over SSH" $?
[[ $fail == 0 ]] || { echo "Start it with tests/vm/run.sh and run setup.sh in it (README.md)."; exit 1; }

vm 'rm -rf ~/fathom-old ~/fathom-new'
git -C "$repo" archive --prefix=fathom-old/ "$old" | vm 'tar -x -C ~'
git -C "$repo" archive --prefix=fathom-new/ "$tree" | vm 'tar -x -C ~'
# Rules a run that stopped early may have left: only this check's own test
# addresses (192.0.2.0/24 is for documentation, so nobody else's).
vm 'for ip in 192.0.2.66 192.0.2.88; do sudo ufw delete deny from $ip >/dev/null 2>&1; sudo ufw delete deny from $ip comment fathom-block >/dev/null 2>&1; done; true'
vm 'cat > ~/capture.sh && chmod +x ~/capture.sh' <"$here/capture.sh"
vm 'cat > ~/fwtest.sh' <"$here/fwtest.sh"
vm '! test -e ~/.local/state/fathom/installed && ! test -e ~/.config/omarchy/themes/fathom && ! grep -q "\"fathom\." ~/.config/omarchy/shell.json'
check "Fathom is not installed in the VM to start with" $?
[[ $fail == 0 ]] || { echo "Run ~/fathom-new/uninstall.sh in the VM first."; exit 1; }
vm '~/capture.sh baseline' >/dev/null

# Upgrade: the older Fathom, then this one over it.
step old-install 'cd ~/fathom-old && ./install.sh'; check "older Fathom ($old) installs" $?
step upgrade 'cd ~/fathom-new && ./install.sh'; check "this Fathom installs over it (upgrade)" $?
vm '[ $(omarchy plugin list | grep -cE "^fathom\.(deck|desk|player) +enabled") = 3 ]'
check "  ...deck, desk and player plugins enabled" $?
vm 'for p in deck desk player; do diff -rq ~/fathom-new/$p/plugin/fathom.$p ~/.config/omarchy/plugins/fathom.$p >/dev/null || exit 1; done'
check "  ...and they are this checkout's" $?
vm 'test -f ~/.config/omarchy/themes/fathom/.fathom-install && [ "$(omarchy theme current)" = Fathom ]'
check "  ...theme built by fathom-look and switched on" $?
vm '[ "$(tr "\n" " " < ~/.local/state/fathom/installed)" = "skin player deck desk mail " ]'
check "  ...parts recorded: skin player deck desk mail" $?

step uninstall-1 'cd ~/fathom-new && ./uninstall.sh'; check "uninstall" $?
vm '~/capture.sh after-uninstall' >/dev/null
same_as_baseline after-uninstall; check "  ...back to the state before Fathom" $?

step fresh 'cd ~/fathom-new && ./install.sh'; check "fresh install (default parts)" $?
vm 'sleep 2; journalctl --user -u fathom-mail.service -n 5 --no-pager -o cat | grep -q "No mail accounts; nothing to watch."'
check "  ...Mail with no account says so and stops" $?

vm -t 'python3 -I -c "import grpc, google.protobuf, opentelemetry.proto" 2>/dev/null || omarchy pkg add python-opentelemetry-proto python-grpcio python-protobuf' >"$logs/pulse-deps.log" 2>&1
step optional 'cd ~/fathom-new && ./install.sh --sentinel --pulse --crumbs --signin'
check "opt-in parts: --sentinel --pulse --crumbs --signin" $?
if vm 'cat /etc/sddm.conf /etc/sddm.conf.d/*.conf 2>/dev/null | grep -q "^User=$USER$"'; then
  grep -q "signs you in" "$logs/optional.log"
else
  grep -q "next time you start up or sign out" "$logs/optional.log"
fi
check "  ...the sign-in message matches the VM's autologin" $?

vm 'bash ~/fwtest.sh' >"$logs/fwtest.log" 2>&1
grep -q "^passed [0-9]*, failed 0$" "$logs/fwtest.log"; check "real-ufw checks: $(tail -1 "$logs/fwtest.log")" $?

# Full uninstall beside a rule of the user's and an active Fathom block.
user_rule='### tuple ### deny any any 0.0.0.0/0 any 192.0.2.66 in'
vm 'sudo ufw prepend deny from 192.0.2.66 >/dev/null && sudo /usr/local/lib/fathom-sentinel/admin block 192.0.2.88'
step uninstall-2 'cd ~/fathom-new && ./uninstall.sh'; check "full uninstall with root parts" $?
vm '~/capture.sh final' >/dev/null
same_as_baseline final "$user_rule"; check "  ...back to the state before Fathom, the user's own ufw rule kept" $?
vm 'sudo ufw delete deny from 192.0.2.66 >/dev/null'

echo "passed $pass, failed $fail (logs: $logs)"
[[ $fail == 0 ]]
