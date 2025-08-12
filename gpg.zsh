# encrypt a file with a passphrase
passenc() {
    local input_file=$1
    local output_file="${input_file}.gpg"
    if gpg --symmetric --cipher-algo AES256 --quiet --batch --yes --output "$output_file" "$input_file"; then
        shred -u "$input_file"
        echo -e "\e[1;32mEncrypted $input_file and saved as: $output_file\e[0m"
    else
        echo -e "\e[1;31mEncryption failed for $input_file\e[0m"
    fi
}

passdec() {
    local input_file=$1
    local output_file="${input_file%.gpg}"

    if gpg --use-agent --quiet --batch --yes --decrypt --cipher-algo AES256 --output "$output_file" "$input_file" 2>/dev/null; then
        shred -u "$input_file"
        echo -e "\e[1;32mDecrypted $input_file and saved as: $output_file\e[0m"
    else
        echo -e "\e[1;31mDecryption failed for $input_file\e[0m"
    fi
}

# gpg dameon  starts acting up, reload it
loadpg() {
   pkill -9 gpg-agent
   export GPG_TTY=$(tty)
}
