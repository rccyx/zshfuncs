mkdir -p ~/Pictures/Screenshots

# mac-style capture: save to file, copy to clipboard, then open in swappy
cat > ~/.local/bin/shot-mac <<'EOF'
#!/bin/sh
set -e
out="$HOME/Pictures/Screenshots/$(date +'%Y-%m-%d_%H-%M-%S').png"
geom="$(slurp -b '#00000066' -c '#ffffffff' -s '#ffffffff' -w 2)"
grim -g "$geom" "$out"
wl-copy < "$out"
notify-send "📸 Saved + copied" "$out"
# open the same file in swappy so Save overwrites in place
swappy -f "$out" || true
EOF
chmod +x ~/.local/bin/shot-mac

