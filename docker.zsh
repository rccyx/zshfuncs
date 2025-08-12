# ================================================================
#   DOCKER QUICK‑STRIKE FUNCTIONS
#   deps: docker ≥20, fzf
# ================================================================
_pick_ct(){ docker ps --format '{{.ID}}  {{.Image}}  {{.Names}}' \
            | fzf --prompt="🐳 pick container ⇢ " --height 60% --border --reverse \
            | awk '{print $1}'; }

# jump into a running container (falls back to sh if bash missing)
dinto(){
  local id=$(_pick_ct) || { _err "no container"; return 1; }
  docker exec -it "$id" bash 2>/dev/null || docker exec -it "$id" sh
}

# live top inside selected container
dtop(){
  local id=$(_pick_ct) || return 1
  docker top "$id"
}

# restart chosen container cleanly
drestart(){
  local id=$(_pick_ct) || return 1
  docker restart "$id" && _ok "restarted $id"
}

# follow logs on multiple containers (multi‑select)
dlogs(){
  local ids=($(docker ps --format '{{.ID}}  {{.Image}}' | \
              fzf --multi --prompt="📜 logs ⇢ " --height 60% --border --reverse | awk '{print $1}'))
  [[ ${#ids[@]} -eq 0 ]] && { _err "none selected"; return 1; }
  docker logs -f "${ids[@]}"
}

# list images by size and optionally delete picked ones
dimgls(){
  local selection
  selection=$(docker image ls --format '{{.Repository}}:{{.Tag}}  {{.ID}}  {{.Size}}' \
             | sort -h -k3 | column -t \
             | fzf --multi --prompt="🗑 images ⇢ " --height 60% --border --reverse)
  [[ -z $selection ]] && return
  echo "$selection" | awk '{print $2}' | xargs -r docker image rm
}

# prune everything older than 24h (images, stopped containers, volumes)
ddeepclean(){
  docker container prune -f
  docker image prune -a --filter "until=24h" -f
  docker volume prune -f
  _ok "deep cleaned docker resources >24h old"
}

# pick dangling volumes interactively and remove
dvolrm(){
  local vols
  vols=$(docker volume ls -qf dangling=true | \
         fzf --multi --prompt="🧹 volumes ⇢ " --height 60% --border --reverse)
  [[ -z $vols ]] && return
  echo "$vols" | xargs -r docker volume rm && _ok "removed selected volumes"
}

# copy files out of a container
dcp(){
  local id=$(_pick_ct) || return 1
  echo -n "path inside container ⇢ "; read -r src
  echo -n "destination dir ⇢ "; read -r dst
  [[ -z $src || -z $dst ]] && { _err "missing path"; return 1; }
  docker cp "$id:$src" "$dst" && _ok "copied"
}

# pull updates and roll the current compose stack
dupdate(){
  docker compose pull && docker compose up -d && _ok "stack updated"
}

# quick network overview
dnet(){
  docker network ls
  for n in $(docker network ls -q); do
    printf "\n%s\n" "$(docker network inspect -f '{{ .Name }}' "$n")"
    docker network inspect -f '{{ range $k,$v := .Containers }}• {{ $v.Name }}{{ "\n" }}{{ end }}' "$n"
  done
}

# terminate all containers
tercon() {
	for c in $(docker ps -a | tail -n+2 | awk '{print $1}'); do
  		docker stop "${c}" || :
  		docker rm "${c}"
	done
}

# remove all volumes
tervol() {
   docker volume rm $(docker volume ls -q)
}

# remove all images
terimg() {
   for img in $(docker images -q); do
        docker rmi "${img}" || :
    done
}


dprune() {
	 tercon && terimg && tervol
   docker container prune -f
   docker system prune -f
   docker image prune -f
   docker volume prune -f
}
