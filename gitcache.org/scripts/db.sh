#!/bin/bash

# URL db accessor

# global vars
base_dir=/app/gitcache.org
urls=$base_dir/data/repo.db

add_url() {
  if [ -z "$1" ]; then
    echo "no url provided"
    return
  fi

  if (grep -q "$1" $urls)>/dev/null; then
    echo "url $1 already exists"
  else
    echo "adding url $1"
    echo "$1" >> $urls
  fi
}

add() {
  if [ "$1" ]; then
    add_url "$1"    
  else
    while read line; do
      add_url "$line"
    done
  fi
}

case "$1" in
  add)
  shift
  add $@
  ;;
  *)
  echo "$0 add url OR cat urls | $0 add"
  ;;
esac
