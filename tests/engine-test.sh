#!/usr/bin/env bash
# Runs a copy of wakey.sh against fake pmset/sudo/agent-deck, so no real setting changes.
# The copy only sees caffeinate runs started by this test, so live sessions cannot skew it.
set -u
SRC="$(cd "$(dirname "$0")/.." && pwd)/wakey.sh"
T=$(mktemp -d)
mkdir -p "$T/bin" "$T/p"
export XDG_STATE_HOME=$T/state
S=$XDG_STATE_HOME/wakey
echo 0 > "$T/sd"
echo $$ > "$T/parents"
printf "Now drawing from 'AC Power'\n -InternalBattery-0 96%%; charging\n" > "$T/batt"
echo '[{"status":"running"},{"status":"waiting"}]' > "$T/agents.json"

cat > "$T/bin/pmset" <<EOF
#!/bin/bash
case "\$*" in
  "-g batt") cat "$T/batt" ;;
  "-g") echo " SleepDisabled		\$(cat "$T/sd")" ;;
  "-a disablesleep "*) echo "\$3" > "$T/sd" ;;
esac
EOF
cat > "$T/bin/sudo" <<'EOF'
#!/bin/bash
[[ $1 == -n ]] && shift
[[ $1 == -l ]] && exit 0
exec "$@"
EOF
cat > "$T/bin/agent-deck" <<EOF
#!/bin/bash
[[ -f "$T/agents_fail" ]] && exit 1
cat "$T/agents.json"
EOF
chmod +x "$T/bin/"*
export PATH="$T/bin:$PATH"
P=$T/p/wakey.sh
sed -e "s#^PMSET=.*#PMSET=$T/bin/pmset#" -e "s#^AGENT_DECK=.*#AGENT_DECK=$T/bin/agent-deck#" \
    -e 's#^AGENT_POLL_SECONDS=.*#AGENT_POLL_SECONDS=1#' -e 's#^AGENT_GRACE_SECONDS=.*#AGENT_GRACE_SECONDS=4#' \
    -e 's#^RELEASE_POLL_SECONDS=.*#RELEASE_POLL_SECONDS=1#' \
    -e "s#pgrep -x -U \"\$(id -u)\" caffeinate#pgrep -x -P \"\$(cat $T/parents)\" caffeinate#" "$SRC" > "$P"
chmod +x "$P"
fail() { echo "FAIL: $*"; "$P" stop; exit 1; }
alive() { kill -0 "$1" 2>/dev/null; }
title() { "$P" | head -1; }

echo "== idle"
[[ "$(title)" == " | sfimage=eye.slash" ]] || fail "idle title: $(title)"

echo "== start, stop, timer"
"$P" start 60; read -r p0 _ < "$S/state"
ps -p "$p0" -o args= | grep -q "caffeinate -dis -t 60" || fail "caffeinate not started"
[[ "$(title)" == "0:01 | sfimage=eye.fill" ]] || fail "timed title: $(title)"
"$P" stop; sleep 1; alive "$p0" && fail "stop left $p0 running"
"$P" start 2; read -r p0 _ < "$S/state"; sleep 4
alive "$p0" && fail "timer did not expire"
[[ "$(title)" == " | sfimage=eye.slash" ]] || fail "expired title: $(title)"

echo "== until"
"$P" until 0; read -r _ e _ < "$S/state"
[[ "$(date -r "$e" +%H:%M:%S)" == 00:00:00 ]] || fail "until 0 ends $(date -r "$e")"
"$P" stop

echo "== +1h"
"$P" start 600; read -r p1 e1 _ < "$S/state"
"$P" | grep -q '^+1h' || fail "+1h not offered"
"$P" extend; read -r p2 e2 _ < "$S/state"
d=$(( e2 - e1 )); (( d >= 3598 && d <= 3602 )) || fail "extend moved end by $d"
alive "$p1" && fail "old pid survived extend"
"$P" stop

echo "== terminal caffeinate runs"
/usr/bin/caffeinate -dis -t 7777 & fp=$!
sleep 1
"$P" | grep -q "Terminal caffeinate $fp: 2:10" || fail "terminal run not listed"
"$P" kill "$fp"; sleep 1; alive "$fp" && fail "kill did not stop $fp"
"$P" kill $$ && fail "kill accepted a non-caffeinate pid"
# Given a command, caffeinate forks: the run to list is a child of $fp.
/usr/bin/caffeinate -i /bin/sh -c 'sleep 30' ' | bash=/usr/bin/false param1=x' & fp=$!
echo "$$,$fp" > "$T/parents"
sleep 1
"$P" | grep -q 'false param1=x | font=Menlo size=11$' || fail "args line not listed"
"$P" | grep -q '[^¦] bash=/usr/bin/false' && fail "caffeinate args injected a menu action"
pkill -P "$fp"; kill "$fp"; echo $$ > "$T/parents"

echo "== lid ticked, no session"
"$P" lid
[[ "$(title)" == "·:laptopcomputer: | sfimage=eye.slash" ]] || fail "armed title: $(title)"

echo "== lid with a session"
"$P" start 2; read -r pl _ < "$S/state"
[[ "$(cat "$T/sd")" == 1 ]] || fail "disablesleep not set"
[[ "$(title)" == *":laptopcomputer: | sfimage=eye.fill" ]] || fail "lid title: $(title)"
sleep 5
[[ "$(cat "$T/sd")" == 0 ]] || fail "watcher did not reset lid after expiry"
"$P" start 60; "$P" start 60; sleep 3
[[ "$(cat "$T/sd")" == 1 ]] || fail "old watcher cleared lid for the new session"
"$P" stop; [[ "$(cat "$T/sd")" == 0 ]] || fail "stop did not reset lid"

echo "== agents mode"
"$P" agents; read -r pa _ m < "$S/state"
[[ "$m" == agents ]] || fail "mode=$m"
sleep 1
[[ "$(title)" == ":sparkles: :laptopcomputer: | sfimage=eye.fill" ]] || fail "agents title: $(title)"
"$P" | grep -q "1 running" || fail "running count missing"
"$P" | grep -q '^+1h' && fail "+1h offered in agents mode"
touch "$T/agents_fail"; echo '[]' > "$T/agents.json"
sleep 7; alive "$pa" || fail "session ended on failed agent-deck read"
"$P" | grep -q "? running" || fail "failed read not shown as ?"
rm "$T/agents_fail"; sleep 2
alive "$pa" || fail "ended without full grace after failures"
sleep 6
alive "$pa" && fail "not stopped after grace with 0 running"
sleep 2; [[ "$(cat "$T/sd")" == 0 ]] || fail "lid not released after agents end"

echo "== battery cutoff"
"$P" start 600; read -r pb _ < "$S/state"
printf "Now drawing from 'Battery Power'\n -InternalBattery-0 50%%; discharging\n" > "$T/batt"
"$P" >/dev/null; alive "$pb" || fail "stopped at 50%"
printf "Now drawing from 'AC Power'\n -InternalBattery-0 10%%; charging\n" > "$T/batt"
"$P" >/dev/null; alive "$pb" || fail "stopped on AC at 10%"
printf "Now drawing from 'Battery Power'\n -InternalBattery-0 15%%; discharging\n" > "$T/batt"
"$P" >/dev/null; sleep 1
alive "$pb" && fail "not stopped at 15% on battery"
[[ "$(cat "$T/sd")" == 0 ]] || fail "lid not reset on battery stop"
"$P" battery 0; "$P" start 600; read -r pc _ < "$S/state"
"$P" >/dev/null; alive "$pc" || fail "cutoff Off still stopped at 15%"
"$P" | grep -q "Battery cutoff: off" || fail "off label"
printf "Now drawing from 'Battery Power'\n -InternalBattery-0 25%%; discharging\n" > "$T/batt"
"$P" battery 30; "$P" >/dev/null; sleep 1
alive "$pc" && fail "30% cutoff did not stop at 25%"
"$P" | grep -q "Battery cutoff: below 30%" || fail "30 label"

echo "ALL PASS"
