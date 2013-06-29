#!/bin/bash

url=https://github.com
trending=explore
forked=popular/forked
starred=popular/starred

get() {
  URL=""

  case "$1" in
    all)
      for j in trending forked starred; do
        get $j
      done | sort | uniq
    ;;
    trending|featured)
    URL=$url/$trending
    ;;
    forked)
    URL=$url/$forked
    ;;
    starred)
    URL=$url/$starred
    ;;
    user)
    if [ -z "$2" ]; then
      usage
    fi
    URL=$url/$2?tab=repositories
    ;;
    *)
    usage
    ;;
  esac

  if [ -n "$URL" ]; then
    wget -q -O - /tmp/.rget.$$ $URL | parse
  fi
}

parse() {
  grep title | grep network  | sed 's@.*<a href="@github.com@g' | sed 's@/network".*@@g' |sort | uniq
}

usage() {
  echo "$0 get (trending|featured|forked|starred|all|user [username])"
  exit 1
}

case "$1" in
  get)
  shift
  get "$@"
  ;;
  *)
  usage
  ;;
esac
