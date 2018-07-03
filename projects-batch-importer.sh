#!/bin/bash

set -x

this_dir=$(dirname $0)

"$this_dir/projects-batch-runner.sh" importer.sh
