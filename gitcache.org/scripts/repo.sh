#!/bin/bash

# This script clones or updates a git repo. It is extremely simple. 

# global vars
base_dir=/cache/repos/pub
lock_dir=/tmp
valid_domains="git.ganeti.org|git.macports.org|git.macruby.org|gcc.gnu.org|github.com|code.google.com"
valid_protos="file|git|https?"
proto=https
clone_url=
local_repo=
command=$1
repository=$2

PATH=$PATH:/usr/local/bin

errexit() {
  log_error "$@"
  exit 1
}

log_info() {
  echo "[REPO][INFO][$(date)]: $@"
}

log_error() {
  echo 1>&2 "[REPO][ERROR][$(date)]: $@"
}

lockdo() {
  # create a lock file for a repo
  if [ ! -d "$lock_dir" ]; then
    mkdir -p "$lock_dir"
  fi

  local lock=$lock_dir/gitcache.${local_repo//\//.}.lock

  if [ "$1" == "create" ];then
    if [ -f "$lock" ]; then
      errexit "lock already exists for $local_repo"
    else
      touch "$lock"
    fi
  elif [ "$1" == "remove" ]; then
    [ -f "$lock" ] && rm -f "$lock"
  fi 
}

clone() {
  # clone a git repository
  if [ -d "$local_repo/objects" ]; then
    errexit "$local_repo has already been cloned"
  fi

  log_info "cloning $local_repo"
  mkdir -p "$local_repo" && \
  git clone --mirror "$clone_url" "$local_repo" && \
  update
}

update() {
  # update a git repository
  if [ ! -d "$local_repo" ]; then
    errexit "$local_repo does not exist or is not a git repo"
  fi

  log_info "updating $local_repo"
  pushd "$local_repo" >/dev/null && fupdate && \
  popd >/dev/null
}

clupdate() {
  if [ ! -d "$local_repo/objects" ]; then
    clone
  else
    update
  fi
}

fupdate() {
  git fetch &
  local pid=$!
  local tm=$(date +%s)

  while [ -d /proc/$pid ]; do
    local tmn=$(date +%s)
    local df=$(($tmn-$tm))

    if [ $df -ge 600 ]; then
      echo "killing $pid during update of $local_repo"|mail -s "update error: $local_repo" errors@gitcache.org
      kill $pid
    fi

    sleep 5
  done

  git update-server-info
}

mdinfo() {
  echo "${local_repo%.git}" "$base_dir/$local_repo"
}

path() {
  echo "$base_dir/$local_repo"
}

usage() {
  # print usage to stdout and exit
  echo -e "
    Info: Clone or update a git repository

    usage: $0 {clone|update|clupdate|path} [repo url]

    example:

    $0 clone github.com/apache/httpd
    $0 update github.com/apache/httpd
  "

  exit 1
}

parse_repo() {
  # Sets:
  #  domain e.g github.com
  #  repo e.g apache/httpd
  #  clone_url e.g. https://github.com/apache/httpd.git
  local re=${repository%.git}
  re=${re%\/}

  if [[ $re =~ ^($valid_protos):///?($valid_domains)\/+(.+)$ ]]; then
    local_repo=${BASH_REMATCH[2]}/${BASH_REMATCH[3]}.git
    clone_url=$re.git
  elif [[ $re =~ ^($valid_domains)\/+(.+)$ ]]; then
    local_repo=${BASH_REMATCH[1]}/${BASH_REMATCH[2]}.git
    clone_url=$proto://$re.git
  elif [[ $re =~ ^(\w+@)?($valid_domains):(.+)$ ]]; then
    local_repo=${BASH_REMATCH[2]}/${BASH_REMATCH[3]}.git
    clone_url=$re.git
  else
    errexit "could not parse repo url $repository"
  fi

  if ! [ "$local_repo" ] && [ "$clone_url" ]; then
    errexit "repo: $local_repo or clone_url: $clone_url is empty"
  fi

  if [[ $local_repo =~ (\.\.|:) ]]; then
    errexit "path in repo url cannot contain ../ or :"
  fi

  if [[ $clone_url =~ "code.google.com" ]]; then
    clone_url=${clone_url/%.git/\/}
  fi
}

main () {
  if [ ! -d "$base_dir" ]; then
    mkdir -p "$base_dir"
  fi

  pushd "$base_dir" >/dev/null

  parse_repo
  lockdo "create"
  $command
  lockdo "remove"

  popd "$base_dir" >/dev/null
}

if [ $# -lt 2 ]; then
  usage
fi

case "$command" in
    clone|update|clupdate|mdinfo|path)
    main
    ;;
    *)
    usage
    ;;
esac

exit $?
