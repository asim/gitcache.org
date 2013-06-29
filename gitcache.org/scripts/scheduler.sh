#!/bin/bash

# The scheduler runs the cloneorupdate.sh script.

# sub-shells are used for concurrency
concurrency=5

# global vars
base_dir=/app/gitcache.org
tmp_dir=/tmp/gitcache_scheduler.$RANDOM
lock_dir=/tmp
urls=$base_dir/data/repo.db
updater=$base_dir/scripts/repo.sh
mdupdater=$base_dir/app/bin/repo.rb

PATH=$PATH:/usr/local/bin

log_info() {
  echo "[SCHEDULER][INFO][$(date)]: $@"
}

log_error() {
  echo 1>&2 "[SCHEDULER][ERROR][$(date)]: $@"
}

lockdo() {
  if [ ! -d "$lock_dir" ]; then
    mkdir -p "$lock_dir"
  fi

  local lock=$lock_dir/gitcache.scheduler.lock

  if [ "$1" == "create" ];then
    if [ -f "$lock" ]; then
      log_error "lock already exists"
      exit 1
    else
      touch "$lock"
    fi
  elif [ "$1" == "remove" ]; then
    [ -f "$lock" ] && rm -f "$lock"
  fi 
}

set_ruby() {
  . $rvm_path/scripts/rvm &>/dev/null
  rvm use 2.0.0 &>/dev/null
}

run_clupdate() {
  local repo_file=$1

  for repo in $(cat "$repo_file"); do
    local sleep_time=$(($RANDOM % 30))
    log_info "sleep $sleep_time before updating $repo"
    sleep $(($RANDOM % 30))
    $updater clupdate "$repo"
#    ruby $mdupdater update $($updater mdinfo $repo)
  done
}

# main
#lockdo create
#set_ruby
mkdir -p "$tmp_dir"
pushd "$tmp_dir" >/dev/null

lines_per_file=$(($(wc -l $urls|awk '{print $1}')/$concurrency))

if [ $lines_per_file -ge 1 ]; then
  echo "running $concurrency concurrent updates"
  split -l $lines_per_file $urls $tmp_dir/repo_urls.

  for file in $tmp_dir/repo_urls.*; do
    (run_clupdate "$file") &
  done
else
  run_clupdate "$urls"
fi

wait
rm -rf "$tmp_dir"
#lockdo remove

exit $?
