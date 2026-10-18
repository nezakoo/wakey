#!/usr/bin/env bash
# Wakey's engine. Prints its menu in the SwiftBar/xbar text format; Wakey.app renders it.
set -euo pipefail

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/wakey"
STATE="$STATE_DIR/state"
LID_PREF="$STATE_DIR/lid"
LID_SET="$STATE_DIR/lid-set"
UNTIL_HOURS=(7 8 9 10 12 18 22 0)
# Claude Code holds `caffeinate -i -t 300` while it works; those are not runs to show.
IGNORE_PARENT=claude
GUARD_POLL_SECONDS=15
EXTEND_SECONDS=3600
BATTERY_PREF="$STATE_DIR/battery-cutoff"
BATTERY_CUTOFF_DEFAULT=20
BATTERY_CUTOFF_CHOICES=(0 10 20 30 50)
AGENT_POLL_SECONDS=30
AGENT_GRACE_SECONDS=600
PROCESS_CHOICES=5
# Absolute: apps launched from the Dock or at login get launchd's PATH, which lacks these directories.
TOOL_DIRS=("$HOME/.local/bin" /opt/homebrew/bin /usr/local/bin)
find_tool() {
  local d
  for d in "${TOOL_DIRS[@]}"; do [[ -x "$d/$1" ]] && { echo "$d/$1"; return; }; done
  echo "/opt/homebrew/bin/$1"
}
AGENT_DECK=$(find_tool agent-deck)
JQ=$(find_tool jq)
PMSET=/usr/bin/pmset
ACT="terminal=false refresh=true bash='$0'"

# Text goes in as an argument, never into the AppleScript source.
notify() { osascript -e 'on run argv' -e 'display notification (item 1 of argv) with title "Wakey"' -e 'end run' "$1" || true; }
alert() { osascript -e 'on run argv' -e 'display alert (item 1 of argv)' -e 'end run' "$1" || true; }
ask() { osascript -e 'on run argv' -e 'text returned of (display dialog (item 1 of argv) default answer (item 2 of argv))' -e 'end run' "$1" "$2"; }

is_caffeinate() { [[ "$(ps -p "$1" -o comm= 2>/dev/null)" == *caffeinate ]]; }

our_pid() {
  [[ -f "$STATE" ]] || return 1
  local pid
  read -r pid _ < "$STATE"
  is_caffeinate "$pid" || return 1
  echo "$pid"
}

setup_lid() {
  local f
  f=$(mktemp)
  echo "$USER ALL=(root) NOPASSWD: $PMSET -a disablesleep 1, $PMSET -a disablesleep 0" > "$f"
  # Validate the root-owned copy, not $f: $f stays user-writable until it is installed. sudo skips names with a dot.
  local tmp=/etc/sudoers.d/.wakey.tmp
  osascript -e "do shell script \"install -m 0440 -o root -g wheel $f $tmp && visudo -cf $tmp && mv $tmp /etc/sudoers.d/wakey || { rm -f $tmp; exit 1; }\" with administrator privileges"
  rm -f "$f"
}

lid_allowed() { sudo -n -l "$PMSET" -a disablesleep 1 >/dev/null 2>&1; }

lid_on() { sudo -n "$PMSET" -a disablesleep 1 && touch "$LID_SET"; }

lid_off() {
  [[ -f "$LID_SET" ]] || return 0
  sudo -n "$PMSET" -a disablesleep 0 && rm -f "$LID_SET"
}

# Runs beside every session, so the battery cutoff and the lid reset hold after Wakey.app quits or crashes,
# and when a session ends by timer while nothing else is running.
guard() {
  while kill -0 "$1" 2>/dev/null; do
    if battery_low; then
      if [[ "$(our_pid || true)" == "$1" ]]; then
        stop
        notify "Stopped keeping awake: battery below $(battery_cutoff)%"
      fi
      return
    fi
    sleep "$GUARD_POLL_SECONDS"
  done
  our_pid >/dev/null || lid_off
}

stop() {
  local pid
  if pid=$(our_pid); then kill "$pid"; fi
  rm -f "$STATE"
  lid_off
}

# State: "<caffeinate pid> <end epoch or 0> <mode> [watched pid]".
start() {
  local seconds=$1 mode=${2:-timed} target=${3:-} args=(-dis) end=0 pid
  stop
  mkdir -p "$STATE_DIR"
  if [[ "$seconds" != 0 ]]; then
    args+=(-t "$seconds")
    end=$(( $(date +%s) + seconds ))
  fi
  if [[ -n "$target" ]]; then args+=(-w "$target"); fi
  nohup /usr/bin/caffeinate "${args[@]}" >/dev/null 2>&1 &
  pid=$!
  echo "$pid $end $mode $target" > "$STATE"
  if [[ -f "$LID_PREF" ]]; then lid_on || true; fi
  nohup "$0" guard "$pid" >/dev/null 2>&1 &
  if [[ "$mode" == agents ]]; then nohup "$0" agents-watch "$pid" >/dev/null 2>&1 & fi
}

extend() {
  local end
  read -r _ end _ < "$STATE"
  start $(( end - $(date +%s) + EXTEND_SECONDS ))
}

agents_running() {
  local json
  json=$("$AGENT_DECK" list --json) || return 1
  "$JQ" '[.[] | select(.status == "running")] | length' <<< "$json"
}

# A failed agent-deck read counts as busy: an unreadable state must never end the session.
agents_watch() {
  local busy_at n
  busy_at=$(date +%s)
  while kill -0 "$1" 2>/dev/null; do
    if ! n=$(agents_running) || (( n > 0 )); then
      busy_at=$(date +%s)
    elif (( $(date +%s) - busy_at >= AGENT_GRACE_SECONDS )); then
      kill "$1"
      return
    fi
    sleep "$AGENT_POLL_SECONDS"
  done
}

battery_cutoff() {
  if [[ -f "$BATTERY_PREF" ]]; then cat "$BATTERY_PREF"; else echo "$BATTERY_CUTOFF_DEFAULT"; fi
}

battery_low() {
  local batt cutoff re='([0-9]+)%'
  cutoff=$(battery_cutoff)
  batt=$("$PMSET" -g batt)
  [[ "$batt" == *"'Battery Power'"* && "$batt" =~ $re ]] && (( BASH_REMATCH[1] < cutoff ))
}

seconds_until() {
  local now target
  now=$(date +%s)
  target=$(date -v"$1"H -v"$2"M -v0S +%s)
  (( target > now )) || target=$(date -v+1d -v"$1"H -v"$2"M -v0S +%s)
  echo $(( target - now ))
}

custom() {
  local hhmm re='^([01]?[0-9]|2[0-3]):([0-5][0-9])$'
  hhmm=$(ask "Keep awake until (HH:MM)" "09:00") || return 0
  if [[ ! "$hhmm" =~ $re ]]; then
    alert "Expected HH:MM, got: $hhmm"
    return 1
  fi
  start "$(seconds_until "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}")"
}

# Menu text: a "|" would start the line's params, turning them into a clickable command.
safe() { local s=${1//|/¦}; echo "${s//$'\n'/ }"; }

process_name() { local c; c=$(ps -p "$1" -o comm=) && safe "${c##*/}"; }

# "<pid> <cpu%> <name>" for this user's busiest processes, Wakey's own excluded.
busy_processes() {
  local pid cpu comm name n=0
  while read -r pid cpu comm; do
    name=${comm##*/}
    [[ "$pid" == "$$" || "$pid" == "$PPID" || "$name" == ps || "$name" == caffeinate ]] && continue
    echo "$pid $cpu $(safe "$name")"
    (( ++n < PROCESS_CHOICES )) || break
  done < <(ps -U "$(id -u)" -r -o pid=,pcpu=,comm=)
}

watch_process() {
  if [[ ! "$1" =~ ^[0-9]+$ ]] || ! kill -0 "$1" 2>/dev/null; then
    alert "No process of yours with PID $1"
    return 1
  fi
  start 0 process "$1"
}

process_custom() {
  local answer pid
  answer=$(ask "Keep awake while this process runs (name or PID)" "") || return 0
  if [[ "$answer" =~ ^[0-9]+$ ]]; then
    pid=$answer
  elif ! pid=$(pgrep -n -x -U "$(id -u)" -- "$answer"); then
    alert "No running process of yours named: $answer"
    return 1
  fi
  watch_process "$pid"
}

toggle_lid() {
  local pid
  mkdir -p "$STATE_DIR"
  if [[ -f "$LID_PREF" ]]; then
    rm "$LID_PREF"
    lid_off
  else
    touch "$LID_PREF"
    if our_pid >/dev/null; then lid_on || true; fi
  fi
}

etime_seconds() {
  local t=$1 d=0 h=0 m s
  if [[ "$t" == *-* ]]; then d=${t%%-*}; t=${t#*-}; fi
  IFS=: read -r -a p <<< "$t"
  if (( ${#p[@]} == 3 )); then h=${p[0]}; m=${p[1]}; s=${p[2]}; else m=${p[0]}; s=${p[1]}; fi
  echo $(( 10#$d * 86400 + 10#$h * 3600 + 10#$m * 60 + 10#$s ))
}

# "<pid> <end epoch or 0>" for this user's caffeinate runs this plugin did not start.
foreign() {
  local ours pid args re='-t ?([0-9]+)'
  ours=$(our_pid || true)
  for pid in $(pgrep -x -U "$(id -u)" caffeinate || true); do
    [[ "$pid" == "$ours" ]] && continue
    [[ "$(ps -p "$(ps -p "$pid" -o ppid=)" -o comm= 2>/dev/null)" == *"$IGNORE_PARENT"* ]] && continue
    args=$(ps -p "$pid" -o args=) || continue
    if [[ "$args" =~ $re ]]; then
      echo "$pid $(( $(date +%s) - $(etime_seconds "$(ps -p "$pid" -o etime= | tr -d ' ')") + BASH_REMATCH[1] ))"
    else
      echo "$pid 0"
    fi
  done
}

left() {
  if [[ "$1" == 0 ]]; then echo "∞"; return; fi
  local m=$(( ($1 - $(date +%s) + 59) / 60 ))
  printf '%d:%02d' $(( m / 60 )) $(( m % 60 ))
}

case "${1:-}" in
  start) start "$2"; exit ;;
  until) start "$(seconds_until "$2" 0)"; exit ;;
  custom) custom; exit ;;
  stop) stop; exit ;;
  kill) is_caffeinate "$2" && kill "$2"; exit ;;
  lid) toggle_lid; exit ;;
  setup-lid) setup_lid; exit ;;
  battery) mkdir -p "$STATE_DIR"; echo "$2" > "$BATTERY_PREF"; exit ;;
  guard) guard "$2"; exit ;;
  process) watch_process "$2"; exit ;;
  process-custom) process_custom; exit ;;
  extend) extend; exit ;;
  agents) start 0 agents; exit ;;
  agents-watch) agents_watch "$2"; exit ;;
esac

ours=""
if ours=$(our_pid) && battery_low; then
  stop
  ours=""
  notify "Stopped keeping awake: battery below $(battery_cutoff)%"
fi
if [[ -n "$ours" ]]; then read -r _ end mode target < "$STATE"; else rm -f "$STATE"; lid_off; fi
others=$(foreign)
lid=""
[[ "$("$PMSET" -g | awk '/SleepDisabled/ {print $2}')" == 1 ]] && lid=":laptopcomputer:"

if [[ -n "$ours" ]]; then
  title_end=$end
elif [[ -n "$others" ]]; then
  title_end=$(awk '{ if ($2 == 0) z = 1; else if ($2 > m) m = $2 } END { print z ? 0 : m }' <<< "$others")
fi
# end= lets Wakey.app warn before a timed session of its own runs out.
if [[ "${mode:-}" == agents ]]; then
  echo ":sparkles:${lid:+ $lid} | sfimage=eye.fill"
elif [[ "${mode:-}" == process ]]; then
  echo ":hourglass:${lid:+ $lid} | sfimage=eye.fill"
elif [[ -n "${title_end:-}" ]]; then
  echo "$(left "$title_end")${lid:+ $lid} | sfimage=eye.fill${ours:+ end=$end}"
elif [[ -z "$lid" && -f "$LID_PREF" ]]; then
  echo "·:laptopcomputer: | sfimage=eye.slash"
else
  echo "$lid | sfimage=eye.slash"
fi
echo "---"
[[ -n "$lid" ]] && echo ":laptopcomputer: Stays awake with the lid closed"

if [[ -n "$ours" ]]; then
  if [[ "$mode" == agents ]]; then
    echo "Awake while agents run: $(agents_running || echo '?') running"
  elif [[ "$mode" == process ]]; then
    echo "Awake while $(process_name "$target" || echo "process $target") runs (PID $target)"
  elif [[ "$end" == 0 ]]; then
    echo "Awake indefinitely"
  else
    echo "Awake until $(date -r "$end" '+%a %H:%M')"
    echo "+1h | $ACT param1=extend"
  fi
  echo "Stop | $ACT param1=stop"
fi
while read -r pid oend; do
  [[ -n "$pid" ]] || continue
  echo "Terminal caffeinate $pid: $(left "$oend") | color=gray"
  # A "|" in the args would start this line's params, turning them into a clickable command.
  args=$(ps -p "$pid" -o args=) || args=""
  echo "--$(safe "$args") | font=Menlo size=11"
  echo "--Stop it | $ACT param1=kill param2=$pid"
done <<< "$others"
echo "---"
echo "Sleep displays now | bash=$PMSET param1=displaysleepnow terminal=false sfimage=display"
echo "---"
echo "Start for 1h | $ACT param1=start param2=3600"
echo "Start for 3h | $ACT param1=start param2=10800"
echo "Start for 8h | $ACT param1=start param2=28800"
echo "Until"
for h in "${UNTIL_HOURS[@]}"; do printf -- '--%02d:00 | %s param1=until param2=%d\n' "$h" "$ACT" "$h"; done
echo "--Custom… | $ACT param1=custom"
echo "Indefinitely | $ACT param1=start param2=0"
# Without agent-deck every read fails, which counts as busy: the session would never end.
[[ -x "$AGENT_DECK" && -x "$JQ" ]] && echo "While agents run | $ACT param1=agents"
echo "While a process runs"
while read -r pid cpu name; do
  echo "--$name ($pid) · ${cpu%.*}% CPU | $ACT param1=process param2=$pid"
done < <(busy_processes)
echo "--Other… | $ACT param1=process-custom"
echo "---"
if lid_allowed; then
  echo "Also with lid closed | $ACT param1=lid checked=$([[ -f "$LID_PREF" ]] && echo true || echo false)"
else
  echo "Also with lid closed: set up… | $ACT param1=setup-lid"
fi
cutoff=$(battery_cutoff)
[[ "$cutoff" == 0 ]] && echo "Battery cutoff: off" || echo "Battery cutoff: below $cutoff%"
for c in "${BATTERY_CUTOFF_CHOICES[@]}"; do
  [[ "$c" == 0 ]] && label=Off || label="$c%"
  echo "--$label | $ACT param1=battery param2=$c checked=$([[ "$c" == "$cutoff" ]] && echo true || echo false)"
done
