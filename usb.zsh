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