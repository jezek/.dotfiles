#!/usr/bin/env bash
# Interaktívne premigrovanie systémových Flatpak balíkov do používateľských.
# Prompt: [Y/n/a/q]
#   Y / Enter  – migrovať aktuálny balík
#   n          – preskočiť aktuálny balík
#   a          – migrovať aktuálny + všetky ďalšie bez otázok
#   q          – ukončiť interaktívnu časť a prejsť rovno na cleanup
# Po interakcii sa vždy spustí odstránenie nepoužívaných systémových balíkov.
# Kroky migrácie (pri Y/a):
#   1) pridá chýbajúci remote do používateľského prostredia (import .flatpakrepo & GPG kľúč)
#   2) nainštaluje balík pre používateľa
#   3) odinštaluje balík zo systému
# Všetky príkazy sa logujú funkciou run(). Skript pokračuje aj pri chybách.

set -uo pipefail   # bez -e – chceme pokračovať pri chybách

log() { printf '[%(%H:%M:%S)T] %s\n' -1 "$*"; }
run() { log "$ $*"; "$@"; }

# vráti URL .flatpakrepo alebo prázdny reťazec
get_flatpakrepo() {
  local remote="$1" url=""
  url=$(flatpak remotes --system --columns=name,url | awk -v r="$remote" '$1==r {print $2"/"r".flatpakrepo"; exit}')
  [[ -z "$url" && "$remote" == "flathub" ]] && url="https://dl.flathub.org/repo/flathub.flatpakrepo"
  printf '%s' "$url"
}

# pridá remote do používateľskej inštalácie (ak chýba)
ensure_user_remote() {
  local remote="$1"
  if flatpak remotes --user | awk '{print $1}' | grep -qx "$remote"; then
    return 0
  fi
  local repo_url; repo_url=$(get_flatpakrepo "$remote")
  if [[ -z "$repo_url" ]]; then
    log "⚠️  .flatpakrepo pre remote '$remote' sa nenašlo – migrácia sa preskočí."
    return 1
  fi
  log "➕  Pridávam remote '$remote' z $repo_url"
  run flatpak remote-add --user --if-not-exists "$remote" --from "$repo_url"
}

################################ 1. Zoznam balíkov ################################
log "📋 Získavam zoznam systémových balíkov…"
mapfile -t refs < <(flatpak list --system --columns=ref,origin)
log "🔍 Nájdených refs: ${#refs[@]}"
if (( ${#refs[@]} == 0 )); then
  log "ℹ️  Žiadne systémové Flatpak balíky na migráciu – končím."
  exit 0
fi

AUTO_ALL=0   # od tejto chvíle všetko Áno
QUIT_NOW=0   # q → ukončí loop

############################### 2. Interaktívna migrácia ############################
for entry in "${refs[@]}"; do
  if (( QUIT_NOW == 1 )); then break; fi
  IFS=$'\t' read -r ref origin <<< "$entry"

  if (( AUTO_ALL == 0 )); then
    printf "\nPremigrovať balík %s (remote: %s)? [Y/n/a/q] " "$ref" "$origin"
    if ! read -r answer; then
      printf '\n'
      log "❌  Vstup bol ukončený – migráciu ruším."
      exit 1
    fi
    answer=${answer,,}
    [[ -z "$answer" ]] && answer="y"
    case "$answer" in
      a)
        AUTO_ALL=1; answer="y";;
      q)
        QUIT_NOW=1; continue;;
    esac
  else
    answer="y"
  fi

  if [[ "$answer" =~ ^y ]]; then
    log "➡️  Migrujem $ref…"
    if [[ -n "$origin" && "$origin" != "(none)" ]]; then
      ensure_user_remote "$origin" || { log "⏭️  Preskakujem $ref."; continue; }
    fi
    if ! run flatpak install --user -y "$origin" "$ref"; then
      log "❌  Inštalácia zlyhala – preskakujem $ref."
      continue
    fi
    log "✅  Inštalácia úspešná."
    run sudo flatpak uninstall --system -y "$ref" || \
      log "⚠️  Nepodarilo sa odinštalovať zo systému (možno už odstránené)."
  else
    log "⏭️  Preskakujem $ref."
  fi
  # optional sleep
  # sleep 0.05
done

################################ 3. Cleanup systému ################################
log "🧹 Odstraňujem nepoužívané systémové balíky (--unused)…"
run sudo flatpak uninstall --system -y --unused || true

log '🎉 Migrácia dokončená.'
