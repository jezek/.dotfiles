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

# vráti lokálny .flatpakrepo deskriptor, ak je nainštalovaný
get_flatpakrepo() {
  local remote="$1" directory descriptor
  for directory in "${FLATPAK_CONFIG_DIR:-/etc/flatpak}/remotes.d" \
                   "${FLATPAK_DATA_DIR:-/usr/share/flatpak}/remotes.d"; do
    descriptor="$directory/$remote.flatpakrepo"
    if [[ -r "$descriptor" ]]; then
      printf '%s' "$descriptor"
      return 0
    fi
  done
  return 1
}

# vráti URL a možnosti existujúceho systémového remote
get_system_remote() {
  local remote="$1"
  flatpak remotes --system --show-disabled --columns=name,url,options |
    awk -F '\t' -v r="$remote" '$1 == r { print; found=1; exit } END { exit !found }'
}

# vráti keyring systémového remote, ak existuje
get_system_remote_keyring() {
  local remote="$1" installation keyring
  while IFS= read -r installation; do
    [[ -n "$installation" ]] || continue
    keyring="${installation%/}/repo/$remote.trustedkeys.gpg"
    if [[ -r "$keyring" ]]; then
      printf '%s' "$keyring"
      return 0
    fi
  done < <(flatpak --installations)
  return 1
}

remote_has_option() {
  local options="${1// /}"
  [[ ",$options," == *",$2,"* ]]
}

# pridá remote do používateľskej inštalácie (ak chýba)
ensure_user_remote() {
  local remote="$1" descriptor config configured_name repo_url options keyring
  local -a command=(flatpak remote-add --user --if-not-exists)
  if flatpak remotes --user --columns=name | grep -Fxq "$remote"; then
    return 0
  fi

  if descriptor=$(get_flatpakrepo "$remote"); then
    log "➕  Pridávam remote '$remote' z $descriptor"
    run "${command[@]}" --from "$remote" "$descriptor"
    return
  fi

  if ! config=$(get_system_remote "$remote"); then
    log "⚠️  Konfigurácia remote '$remote' sa nenašla – migrácia sa preskočí."
    return 1
  fi
  IFS=$'\t' read -r configured_name repo_url options <<< "$config"
  if [[ "$configured_name" != "$remote" || -z "$repo_url" ]]; then
    log "⚠️  Konfigurácia remote '$remote' je neplatná – migrácia sa preskočí."
    return 1
  fi

  if remote_has_option "$options" no-gpg-verify; then
    command+=(--no-gpg-verify)
  elif keyring=$(get_system_remote_keyring "$remote"); then
    command+=(--gpg-import="$keyring")
  else
    log "⚠️  Podpisový kľúč remote '$remote' sa nenašiel – migrácia sa preskočí."
    return 1
  fi
  remote_has_option "$options" no-enumerate && command+=(--no-enumerate)
  remote_has_option "$options" no-use-for-deps && command+=(--no-use-for-deps)

  log "➕  Kopírujem systémový remote '$remote' ($repo_url)"
  run "${command[@]}" "$remote" "$repo_url"
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
