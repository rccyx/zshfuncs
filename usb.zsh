# USB utilities

_pick_usb(){
  local dev line
  line=$(lsblk -o NAME,MODEL,TRAN,SIZE,MOUNTPOINT -nr | awk '$3=="usb"{printf "/dev/%s  %s  %s  %s  %s\n",$1,$2,$3,$4,$5}' \
        | fzf --prompt="🔌 select usb ⇢ " --border --height 60% --reverse)
  [[ -z $line ]] && return 1
  dev=${line%% *}
  printf "%s" "$dev"
}

_confirm(){
  local msg=$1; echo -ne "$(clr 33)$msg [y/N] ⇢ $(clr 0)"; read -r c; [[ $c =~ ^[Yy]$ ]]
}

# ISO → USB flasher with picker, progress, and strong verification (zsh)
flash() {
  emulate -L zsh
  setopt err_return pipefail
  setopt extendedglob

  local N=$'\033[0m' R=$'\033[31m' G=$'\033[32m' Y=$'\033[33m' C=$'\033[36m'
  _ts(){ date +%H:%M:%S; }
  _log(){ print -r -- "${C}[$(_ts)] $*${N}"; }
  _ok(){  print -r -- "${G}[$(_ts)] $*${N}"; }
  _warn(){print -r -- "${Y}[$(_ts)] $*${N}"; }
  _err(){ print -ru2 -- "${R}[$(_ts)] $*${N}"; }
  _have(){ command -v "$1" >/dev/null 2>&1; }

  _pick_iso() {
    local iso list
    if [[ -n "$1" && -f "$1" ]]; then print -r -- "$1"; return 0; fi
    if _have fd; then
      list=$(fd -HI -t f -e iso -e img . "$HOME/Downloads" 2>/dev/null)
    else
      list=$(find . "$HOME/Downloads" -maxdepth 3 -type f \( -iname '*.iso' -o -iname '*.img' \) 2>/dev/null)
    fi
    [[ -z "$list" ]] && { _err "no ISO files under . or ~/Downloads"; return 1; }
    if _have fzf; then
      print -r -- "$list" \
      | awk '{cmd="stat -c%s \""$0"\" 2>/dev/null || stat -f%z \""$0"\"" ; cmd|getline s; close(cmd); printf "%s\t%9.2f MB  %s\n",$0,s/1048576,$0 }' \
      | fzf --with-nth=2.. --prompt="pick ISO ⇢ " --height 60% --border --reverse \
      | cut -f1
    else
      print -r -- "${${(f)list}[1]}"
    fi
  }

  _pick_usb_disk() {
    local US=$'\x1f' line sel
    local -a rows; rows=()
    while IFS= read -r line; do
      eval "$line"  # NAME= MODEL= TRAN= SIZE= RM= TYPE=
      [[ "$TYPE" == "disk" ]] || continue
      [[ "$TRAN" == "usb" || "$RM" == "1" ]] || continue
      rows+=("/dev/${NAME}${US}${NAME}  ${MODEL:-?}  ${SIZE}  ${TRAN:-?}  RM=${RM}")
    done < <(lsblk -dn -o NAME,MODEL,TRAN,SIZE,RM,TYPE -P)

    [[ ${#rows[@]} -gt 0 ]] || { _err "no USB or removable disks detected"; return 1; }

    if _have fzf; then
      sel=$(printf "%s\n" "${rows[@]}" | sed "s/${US}/\t/" \
            | fzf --with-nth=2.. --prompt="pick target disk ⇢ " --height 60% --border --reverse) || return 1
      print -r -- "${sel%%	*}"
    else
      print -r -- "${rows[1]%%$US*}"
    fi
  }

  local iso dev isosz devsz dtype rootdisk parent
  iso=$(_pick_iso "$1") || return 1
  [[ -r "$iso" ]] || { _err "cannot read ISO: $iso"; return 1; }
  isosz=$(stat -c%s "$iso" 2>/dev/null || stat -f%z "$iso")

  if [[ -n "$2" ]]; then
    dev="$2"
  else
    dev=$(_pick_usb_disk) || return 1
  fi

  # sanitize
  dev=$(printf '%s' "$dev" | tr -d '\r' | awk '{$1=$1;print}')

  # get type for this node only
  dtype=$(lsblk -dn -o TYPE "$dev" 2>/dev/null | head -n1)
  if [[ "$dtype" != "disk" ]]; then
    parent=$(lsblk -no PKNAME "$dev" 2>/dev/null | head -n1 | tr -d '[:space:]')
    [[ -n "$parent" ]] || { _err "target must be a disk node, not a partition"; return 1; }
    _warn "you picked a partition ($dev); using its parent /dev/$parent"
    dev="/dev/$parent"
    dtype=$(lsblk -dn -o TYPE "$dev" 2>/dev/null | head -n1)
  fi
  [[ "$dtype" == "disk" ]] || { _err "target must be a disk node, not a partition"; return 1; }

  rootdisk=$(lsblk -no PKNAME "$(findmnt -no SOURCE /)" 2>/dev/null | head -n1 | tr -d '[:space:]')
  [[ -n "$rootdisk" && "/dev/$rootdisk" == "$dev" ]] && { _err "refusing to write to your root disk $dev"; return 1; }

  devsz=$(lsblk -bn -o SIZE "$dev" | head -n1)
  (( devsz >= isosz )) || { _err "device smaller than ISO"; return 1; }

  _log "ISO: $iso ($(numfmt --to=iec --suffix=B "$isosz" 2>/dev/null || echo "$isosz bytes"))"
  _log "USB: $dev  MODEL=$(lsblk -no MODEL "$dev")  SIZE=$(lsblk -no SIZE "$dev")  TRAN=$(lsblk -no TRAN "$dev")"
  printf "%sType %sFLASH%s to erase %s and write the image ⇢ %s" "$Y" "$Y" "$N" "$dev" "$N"
  local ans; read -r ans; [[ "$ans" == "FLASH" ]] || { _err "aborted"; return 1; }

  _log "unmounting any mounted partitions"
  lsblk -nrpo NAME,MOUNTPOINT "$dev" | awk '$2!=""{print $1}' | while read -r p; do sudo umount "$p" >/dev/null 2>&1 || :; done
  _have udevadm && sudo udevadm settle || :

  _log "clearing first MiB"
  sudo dd if=/dev/zero of="$dev" bs=1M count=1 conv=fsync status=none

  _log "writing image with progress"
  if _have pv; then
    pv "$iso" | sudo dd iflag=fullblock oflag=direct conv=fsync bs=4M of="$dev" status=progress
  else
    sudo dd if="$iso" of="$dev" iflag=fullblock oflag=direct conv=fsync bs=4M status=progress
  fi
  sync
  sudo blockdev --flushbufs "$dev" 2>/dev/null || :

  _warn "you may see: driver descriptor 2048 vs Linux 512. This is normal for hybrid ISOs."

  _log "refreshing partition table"
  sudo partprobe "$dev" >/dev/null 2>&1 || sudo blockdev --rereadpt "$dev" >/dev/null 2>&1 || :
  _log "layout:"
  lsblk -o NAME,FSTYPE,SIZE,TYPE,MOUNTPOINT,MODEL "$dev"

  _log "verify 1/2: hashing first 64 MiB (or full size if smaller)"
  local quick=$((64*1024*1024))
  local read_n=$(( isosz < quick ? isosz : quick ))
  local iso_q dev_q
  if _have pv; then
    iso_q=$(head -c "$read_n" "$iso" | pv -s "$read_n" | sha256sum | awk '{print $1}')
    dev_q=$(sudo dd if="$dev" bs=1M count=$(( (read_n+1048575)/1048576 )) status=none | head -c "$read_n" | pv -s "$read_n" | sha256sum | awk '{print $1}')
  else
    iso_q=$(head -c "$read_n" "$iso" | sha256sum | awk '{print $1}')
    dev_q=$(sudo dd if="$dev" bs=1M count=$(( (read_n+1048575)/1048576 )) status=none | head -c "$read_n" | sha256sum | awk '{print $1}')
  fi
  if [[ "$iso_q" != "$dev_q" ]]; then
    _err "verify failed on first $read_n bytes"
    return 2
  fi
  _ok "partial hash OK"

  _log "verify 2/2: full ISO length hash"
  local iso_h dev_h
  if _have pv; then
    iso_h=$(pv -s "$isosz" "$iso" | sha256sum | awk '{print $1}')
    dev_h=$(sudo dd if="$dev" bs=4M count=$(( (isosz+4194303)/4194304 )) status=none | head -c "$isosz" | pv -s "$isosz" | sha256sum | awk '{print $1}')
  else
    iso_h=$(sha256sum "$iso" | awk '{print $1}')
    dev_h=$(sudo dd if="$dev" bs=4M count=$(( (isosz+4194303)/4194304 )) status=none | head -c "$isosz" | sha256sum | awk '{print $1}')
  fi
  if [[ "$iso_h" == "$dev_h" ]]; then
    _ok "verify OK  sha256=$iso_h"
  else
    _err "verify failed  iso=$iso_h  dev=$dev_h"
    return 2
  fi

  if _have udisksctl; then
    _log "powering device off"
    sudo udisksctl power-off -b "$dev" >/dev/null 2>&1 || :
  fi

  _ok "done. boot from the USB."
}



usbinfo(){
  _note "scanning usb buses…"
  lsusb | awk '{printf "• %s %s %s\n",$6,$7,$0}' | sed 's/^[^ ]* [^ ]* //'
}

usbls(){
  local dev=$(_pick_usb) || { _err "nothing picked"; return 1; }
  _note "partition table for $dev"
  sudo lsblk "$dev" -o NAME,FSTYPE,SIZE,MOUNTPOINT,LABEL -f
}

usbmount(){
  local part dest
  part=$(_pick_usb) || return 1
  [[ -b $part ]] || { _err "bad device"; return 1; }
  dest="/mnt/usb-$(basename "$part")"
  sudo mkdir -p "$dest"
  sudo mount "$part" "$dest" && _ok "mounted at $dest"
}

usbumount(){
  local part
  part=$(_pick_usb) || return 1
  sudo umount "$part" && sudo udisksctl power-off -b "$part" && _ok "safely ejected $part"
}

usbformat(){
  local dev fs
  dev=$(_pick_usb) || return 1
  _confirm "erase and format $dev ?" || { _err "aborted"; return 1; }
  echo -n "$(clr 33)filesystem (fat32/exfat/ntfs/ext4) ⇢ $(clr 0)"; read -r fs
  case $fs in
    fat32) sudo mkfs.vfat -F 32 "$dev" ;;
    exfat) sudo mkfs.exfat "$dev"      ;;
    ntfs)  sudo mkfs.ntfs -Q "$dev"    ;;
    ext4)  sudo mkfs.ext4 -F "$dev"    ;;
    *) _err "unknown fs"; return 1 ;;
  esac
  _ok "$dev formatted as $fs"
}

usbwipe(){
  local dev=$(_pick_usb) || return 1
  _confirm "DESTROY all data on $dev with dd if=/dev/zero bs=4M ?" || { _err "aborted"; return 1; }
  sudo dd if=/dev/zero of="$dev" bs=4M status=progress && sync && _ok "wiped $dev"
}

usbburn(){
  local iso dev
  iso=$(fd . -e iso -e img | fzf --prompt="🖼  pick iso ⇢ " --border) || { _err "no iso chosen"; return 1; }
  dev=$(_pick_usb) || return 1
  _confirm "flash $iso to $dev ?" || { _err "aborted"; return 1; }
  sudo dd if="$iso" of="$dev" bs=4M status=progress conv=fsync && sync && _ok "image written"
}

usbclone(){
  local src dst img
  echo -n "$(clr 33)clone [device→img | img→device] ? (d/i) ⇢ $(clr 0)"; read -r dir
  if [[ $dir == d* ]]; then
    src=$(_pick_usb) || return 1
    img="$HOME/$(basename "$src").img"
    _confirm "create image $img from $src ?" || return 1
    sudo dd if="$src" of="$img" bs=4M status=progress conv=fsync && _ok "image saved to $img"
  else
    img=$(fd . -e img | fzf --prompt="🖼  pick img ⇢ " --border) || return 1
    dst=$(_pick_usb) || return 1
    _confirm "write $img to $dst ?" || return 1
    sudo dd if="$img" of="$dst" bs=4M status=progress conv=fsync && _ok "clone complete"
  fi
}

usbperf(){
  local dev=$(_pick_usb) || return 1
  _confirm "run quick write speed test on $dev ?" || return 1
  sudo dd if=/dev/zero of="$dev" bs=1M count=512 conv=fdatasync status=progress
}

compdef _usbdev usbmount usbumount usbformat usbwipe usbperf usbburn usbls
_usbdev(){
  local -a devs; devs=(${(f)"$(lsblk -nr -o NAME,TRAN | awk '$2==\"usb\"{print \"/dev/\"$1}')"})
  _describe 'usb' devs
}

usb() {
  emulate -L zsh
  setopt err_return pipefail
  local N=$'\033[0m' Y=$'\033[33m' C=$'\033[36m' R=$'\033[31m'
  local TAB=$'\t'

  local -A desc; desc=(
    flash       "ISO to USB flasher with verify"
    usbinfo     "List USB devices"
    usbls       "Show partitions and mountpoints"
    usbmount    "Mount a USB partition"
    usbumount   "Unmount and power off"
    usbformat   "Format device fat32/exfat/ntfs/ext4"
    usbwipe     "Wipe device with zeros"
    usbburn     "Quick write ISO to device"
    usbclone    "Device image create or write"
    usbperf     "Write speed test"
    usb_copy    "USB → directory clone"
    usb_put     "Copy local folder → USB"
  )

  local -a names available lines
  names=(flash usbinfo usbls usbmount usbumount usbformat usbwipe usbburn usbclone usbperf usb_copy usb_put)
  for f in $names; do
    (( $+functions[$f] )) && available+="$f"
  done
  (( ${#available} )) || { print -ru2 -- "${R}No USB funcs found in this shell${N}"; return 1; }

  if command -v fzf >/dev/null; then
    lines=()
    for f in $available; do
      lines+=("${f}${TAB}${desc[$f]:-$f}")
    done
    local pick fn
    pick=$(printf "%s\n" "${lines[@]}" \
      | fzf --delimiter=$'\t' --with-nth=2.. --prompt="USB menu ⇢ " --height 60% --border --reverse) || return 1
    fn=${pick%%$TAB*}
    print -r -- "${C}→ $fn${N}"
    if (( $+functions[$fn] )); then
      "$fn"
    else
      print -ru2 -- "${R}$fn not defined${N}"
      return 127
    fi
  else
    print -r -- "${Y}fzf not found. Using numbered menu.${N}"
    local i=1 choice
    for f in $available; do print -r -- "[$i] $f - ${desc[$f]:-$f}"; ((i++)); done
    print -n -- "${C}Pick number ⇢ ${N}"
    read -r choice
    if [[ "$choice" =~ '^[0-9]+$' ]] && (( choice>=1 && choice<=${#available} )); then
      local fn=${available[$choice]}
      print -r -- "${C}→ $fn${N}"
      "$fn"
    else
      print -ru2 -- "${R}invalid selection${N}"
      return 1
    fi
  fi
}

# ===============  COMPLETIONS  ==================
compdef _usbdev usbmount usbumount usbformat usbwipe usbperf usbburn usbls
_usbdev(){
  local -a devs; devs=(${(f)"$(lsblk -nr -o NAME,TRAN | awk '$2=="usb"{print "/dev/"$1}')"})
  _describe 'usb' devs
}
