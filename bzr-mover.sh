#!/bin/bash
#
#

project="$1"

if [ -z "$project" ]; then
  echo "Provide project name to move"
  echo "  $(basename $0) <project>"
  exit 1
fi

source "$(dirname $0)/projects-mapping.source"


function cleanup_dirs()
{
  if [ -n "$ubuntu_bzr_repo" ] && [ -d "$ubuntu_bzr_repo" ]; then
    rm -rf "$ubuntu_bzr_repo"
  fi
}

trap cleanup_dirs ERR EXIT SIGQUIT SIGTERM SIGINT

source="$project"
bzr_repo=$project
launchpad_owner="ubuntu-desktop"

if [ -n "${ubuntu_aliases[$project]}" ]; then
  source="${ubuntu_aliases[$project]}"
fi

if [ -n "${ubuntu_bzr_aliases[$project]}" ]; then
  bzr_repo="${ubuntu_bzr_aliases[$project]}"
fi

if [ -n "$LAUNCHPAD_OWNER" ]; then
  launchpad_owner="$LAUNCHPAD_OWNER"
fi

set -xe

bzr_project_repo="$bzr_repo/ubuntu${ubuntu_bzr_sufix_aliases[$project]}"
bzr_uri="lp:~ubuntu-desktop/$bzr_project_repo"
bzr_push_uri="lp:~$launchpad_owner/$bzr_project_repo"

bzr branch "$bzr_uri" "$source.bzr"
cd "$source.bzr" || exit 1

rm -rf ./*
touch THIS_REPOSITORY_HAS_BEEN_MOVED_TO_GIT
echo "https://git.launchpad.net/~ubuntu-desktop/ubuntu/+source/$source" >> THIS_REPOSITORY_HAS_BEEN_MOVED_TO_GIT
bzr add THIS_REPOSITORY_HAS_BEEN_MOVED_TO_GIT

bzr commit -m "Moved to git: lp:~ubuntu-desktop/ubuntu/+source/$source"
bzr push "$bzr_push_uri"
