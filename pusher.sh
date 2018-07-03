#!/bin/bash

set -ex
project="$1"

if ! [ -d "$1/.git" ]; then
  echo "'$1' is not a valid project dir"
  echo "  $1 [project-folder]"
  exit 1
fi

cd "$project" || exit 1

upstream_branch=$(grep upstream-branch debian/gbp.conf | cut -f2 -d=)

if [ -z "$upstream_branch" ]; then
  echo "No valid upstream-branch found"
  exit 1
fi

git push -f -u origin ubuntu/master
git push -f -u origin "$upstream_branch"
git push -f -u origin pristine-tar
git tag | grep -E '^ubuntu/|^debian/|^upstream/' | xargs --no-run-if-empty git push -f origin
