#!/usr/bin/env bash
# buddy.sh — region producer for buddy companion
# Outputs region JSON to ~/.claude/buddy/regions/buddy.json
# Ported from buddy-status.sh (lines 38-106). Same logic, different output.

set -u

REGION_FILE="$HOME/.claude/buddy/regions/buddy.json"
BUDDY_FILE="$HOME/.claude/buddy.json"

# Self-cache: skip work if region was updated <5s ago
if [[ -f "$REGION_FILE" ]]; then
  prev=$(jq -r '.updated_at // 0' "$REGION_FILE" 2>/dev/null)
  age=$(( $(date +%s) - prev ))
  if (( age < 5 )); then
    exit 0
  fi
fi

mkdir -p "$(dirname "$REGION_FILE")"

# No buddy yet → egg prompt
if [[ ! -f "$BUDDY_FILE" ]]; then
  now=$(date +%s)
  jq -n --argjson now "$now" '{
    id: "buddy", text: "🥚 /buddy", color: "dim",
    priority: 90, row: 0, ttl_sec: 30, updated_at: $now
  }' > "$REGION_FILE"
  exit 0
fi

buddy=$(cat "$BUDDY_FILE" 2>/dev/null)
if [[ -z "$buddy" ]]; then
  now=$(date +%s)
  jq -n --argjson now "$now" '{
    id: "buddy", text: "🥚 /buddy", color: "dim",
    priority: 90, row: 0, ttl_sec: 30, updated_at: $now
  }' > "$REGION_FILE"
  exit 0
fi

# Parse fields
name=$(echo "$buddy" | jq -r '.name // "Buddy"')
species=$(echo "$buddy" | jq -r '.species // "capybara"')
affection=$(echo "$buddy" | jq -r '.affection // 50')
hunger=$(echo "$buddy" | jq -r '.hunger // 60')
napping=$(echo "$buddy" | jq -r '.napping // false')
rarity=$(echo "$buddy" | jq -r '.rarity // "Common"')
shiny=$(echo "$buddy" | jq -r '.shiny // false')
current_event=$(echo "$buddy" | jq -r '.current_event // ""')
event_ts=$(echo "$buddy" | jq -r '.event_ts // 0')

# Time of day
hour=$(date +%H)
hour=$((10#$hour))

# Species face
face_for_species() {
  local sp="$1" hr="$2"
  case "$sp" in
    goose)    echo "(ò_ó)>" ;;
    cat)      echo "( •ω•)" ;;
    rabbit)   echo "(•ᴗ•)" ;;
    owl)      echo "(◉‿◉)" ;;
    penguin)  echo "(•◡•)" ;;
    snail)    echo "(@‿@)" ;;
    dragon)   echo "(>ᴗ<)" ;;
    octopus)  echo "(✿◠‿◠)" ;;
    ghost)    echo "(◌ᵒ◌)" ;;
    robot)    echo "[•_•]" ;;
    cactus)   echo "(♥‿♥)" ;;
    mushroom) echo "(◕‿◕)" ;;
    chonk)    echo "(ꖘ ꖘ)" ;;
    capybara) echo "(ᵒᴗᵒ)" ;;
    bat)
      if (( hr >= 23 || hr <= 4 )); then
        echo "(ò_ó)"
      elif (( hr >= 5 && hr <= 11 )); then
        echo "(–_–)"
      else
        echo "(._. )"
      fi
      ;;
    tardigrade) echo "(>°w°<)" ;;
    moth)     echo "(•‿•)" ;;
    ferret)   echo "(•ω•)>" ;;
    *)        echo "(•‿•)" ;;
  esac
}

now=$(date +%s)

# Nap branch — short-circuit, no hearts/hunger
if [[ "$napping" == "true" ]]; then
  case "$species" in
    bat) face="(–_–)💤" ;;
    *)   face="(-_-)💤" ;;
  esac
  text="${face} ${name} 💤"
  color="dim"
  jq -n --arg t "$text" --arg c "$color" --argjson now "$now" '{
    id: "buddy", text: $t, color: $c, row: 0,
    priority: 90, ttl_sec: 30, updated_at: $now
  }' > "$REGION_FILE"
  exit 0
fi

# Event face override (10s window)
event_face=""
event_active=false
event_kind=""
if [[ -n "$current_event" && "$event_ts" != "0" ]]; then
  age=$(( now - event_ts ))
  if (( age < 10 )); then
    case "$current_event" in
      git_commit)   event_face="(•‿•)✓" ;;
      test_fail)    event_face="(×_×)"  ;;
      force_push)   event_face="(ò_ó)!" ;;
      new_file)     event_face="(•ω•)"  ;;
      big_edit)     event_face="(•_•)"  ;;
      error_loop)   event_face="(>_<)"  ;;
    esac
    if [[ -n "$event_face" ]]; then
      event_active=true
      event_kind="$current_event"
    fi
  fi
fi

# Pick face
if [[ -n "$event_face" ]]; then
  face="$event_face"
else
  face=$(face_for_species "$species" "$hour")
fi

# Hearts (3 tiers)
if (( affection >= 70 )); then
  hearts="❤❤❤"
elif (( affection >= 40 )); then
  hearts="❤❤♡"
else
  hearts="❤♡♡"
fi

# Hunger icon
if (( hunger < 30 )); then
  hunger_icon="🍖?"
else
  hunger_icon=""
fi

# Rarity prefix
rarity_prefix=""
case "$rarity" in
  Uncommon)  rarity_prefix="✦ " ;;
  Rare)      rarity_prefix="★ " ;;
  Epic)      rarity_prefix="✦★ " ;;
  Legendary) rarity_prefix="✦★✦ " ;;
esac

# Shiny tag
shiny_tag=""
if [[ "$shiny" == "true" ]]; then
  shiny_tag="✨"
fi

# Compose text (no ANSI — renderer applies color)
text="${face} ${rarity_prefix}${name}${shiny_tag} ${hearts}${hunger_icon}"

# Color logic
if $event_active; then
  case "$event_kind" in
    error_loop|test_fail|force_push) color="red" ;;
    *) color="cyan" ;;
  esac
elif (( affection < 30 )); then
  color="dim"
elif (( hunger < 30 )); then
  color="yellow"
else
  color="default"
fi

jq -n --arg t "$text" --arg c "$color" --argjson now "$now" '{
  id: "buddy", text: $t, color: $c, row: 0,
  priority: 90, ttl_sec: 30, updated_at: $now
}' > "$REGION_FILE"
