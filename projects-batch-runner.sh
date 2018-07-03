#!/bin/bash

N=5
tool=$1
this_dir=$(dirname $0)
CHILD_PIDS=()

function kill_children()
{
  kill ${CHILD_PIDS[@]}
  exit 1
}

if [ -z "$tool" ]; then
  echo "No tool valid tool provided"
  echo "  $0 [tool-to-run]"
  exit 1
fi

if ! [ -x "$this_dir/$tool" ]; then
  echo "'$this_dir/$tool' does not exist or is not executable"
  echo "  $0 [tool-to-run]"
  exit 1
fi

if ! [ -x "$this_dir/importer.sh" ]; then
  echo "Can't find a valid $this_dir/importer.sh"
  exit 1
fi

if [ -z "$IMPORTER_PROJECTS" ]; then
  if [ -f "$this_dir/projects.source" ]; then
    source "$this_dir/projects.source"
  fi
fi

if [ -z "$IMPORTER_PROJECTS" ]; then
  echo "Impossible to find a '\$IMPORTER_PROJECT' var defined or '$this_dir/projects.source'"
  exit 1
fi

if [[ "$BATCH_JOBS" =~ [0-9]+ ]]; then
  N=$BATCH_JOBS
fi

trap kill_children SIGHUP SIGINT SIGTERM

for p in $IMPORTER_PROJECTS; do
  ((i=i%N)); ((i++==0)) && wait
  "$this_dir/$tool" $p 2>&1 | tee "$p.$(basename "${tool/\//_}" .sh)".log &
  CHILD_PIDS+=($!)
done
