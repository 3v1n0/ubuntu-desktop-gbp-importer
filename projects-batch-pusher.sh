#!/bin/bash

this_dir=$(dirname $0)
projects=()

for i in *.DONE; do
  projects+=($(basename "$i" .DONE))
done

export IMPORTER_PROJECTS="${projects[@]}"
"$this_dir/projects-batch-runner.sh" pusher.sh
