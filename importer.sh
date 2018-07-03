#!/bin/bash
#
# sudo apt install devscripts ubuntu-dev-tools git-remote-bzr
#

project="$1"
merge_version="$2"

if [ -z "$project" ]; then
  echo "Provide project name to import"
  echo "  $(basename $0) <project> [debian_merge_version]"
  exit 1
fi

source "$(dirname $0)/projects-mapping.source"

function version_to_tag()
{
  perl -p -e 'y/:~/%_/;s/\.(?=\.|$|lock$)/.#/g;'
}

function cleanup_dirs()
{
  if [ -n "$ubuntu_bzr_repo" ] && [ -d "$ubuntu_bzr_repo" ]; then
    rm -rf "$ubuntu_bzr_repo"
  fi

  if [ -n "$dsc_dir" ] && [ -d "$dsc_dir" ]; then
    rm -rf "$dsc_dir"
  fi
}

trap cleanup_dirs ERR EXIT SIGQUIT SIGTERM SIGINT

source="$project"
upstream="$project"
debsource="$project"
debteam="gnome-team"
bzr_repo=$project
launchpad_owner="ubuntu-desktop"
use_local_bzr_repo=true

if [ -n "${ubuntu_aliases[$project]}" ]; then
  source="${ubuntu_aliases[$project]}"
fi

if [ -n "${debian_aliases[$project]}" ]; then
  debsource="${debian_aliases[$project]}"
fi

if [ -n "${debian_team[$project]}" ]; then
  debteam="${debian_team[$project]}"
fi

if [ -n "${ubuntu_bzr_aliases[$project]}" ]; then
  bzr_repo="${ubuntu_bzr_aliases[$project]}"
fi

if [ -n "${upstream_project[$project]}" ]; then
  upstream="${upstream_project[$project]}"
fi

if [ -n "$LAUNCHPAD_OWNER" ]; then
  launchpad_owner="$LAUNCHPAD_OWNER"
fi

set -xe
export GIT_PAGER=''

if [ ! -d $source/.git ]; then
  gbp clone "https://salsa.debian.org/$debteam/$debsource.git" "$source" \
            --postclone="git remote rename origin salsa"
fi

cd $source

git remote add -f gnome "https://gitlab.gnome.org/GNOME/$upstream.git"
git remote add origin "lp:~$launchpad_owner/ubuntu/+source/$source"
git config push.followTags true

last_distro=$(ubuntu-distro-info --latest)
for suite in "$last_distro"{-{backports,proposed,security,updates},}; do
  IFS=" | " project_db=($(rmadison -s "$suite" "$source"))
  unset IFS

  if [ "${#project_db[@]}" -gt 2 ]; then
    version="${project_db[1]}"
    if dpkg --compare-versions "$version" gt "$last_version"; then
      last_version="$version"
      component=$(echo "${project_db[2]}" | cut -d/ -f2)
      if [ "$component" == "$last_distro" ]; then
        component="main"
      fi
    fi
  fi
done

if [ -z "$last_version" ]; then
  echo "Impossible to find last package version for $source"
  exit 1
fi

if [[ "$last_version" =~ ^[0-9]+: ]]; then
  last_version="$(echo "$last_version" | cut -d: -f2)"
  use_local_bzr_repo=true
fi

if [ -z "$merge_version" ]; then
  if [[ "$debsource" == lib* ]]; then
    intial=${project:0:4}
  else
    intial=${project:0:1}
  fi

  project_changelog=$(wget -o /dev/null -qO - \
    http://changelogs.ubuntu.com/changelogs/pool/$component/$intial/$source/${source}_${last_version}/changelog);

  if [ -n "$project_changelog" ]; then
    for ((i = 0; ; i += 1)); do
      version="$(echo "$project_changelog" | dpkg-parsechangelog -l - -S Version -o $i -c 1)";

      if [[ "$version" =~ -[0-9]+ubuntu[0-9]+ ]]; then
        continue
      elif [[ "$version" =~ -[0-9]+$ ]]; then
        merge_version=$version
        echo "Last debian version found at $version (salsa tag is debian/$(echo "$version" | version_to_tag)"
        break
      elif [ -z "$version" ]; then
        break;
      fi
    done
  fi

  if [ -z "$merge_version" ]; then
    echo "Impossible to find debian fork, please provide it as script parameter"
    exit 1
  fi
fi

# checkout to the latest debian merge and move as ubuntu/master
merge_tag=${merge_version/:/%}
git checkout -b ubuntu/master "debian/$merge_tag"

bzr_uri="lp:~ubuntu-desktop/$bzr_repo/ubuntu${ubuntu_bzr_sufix_aliases[$project]}"
bzr_repo_uri="bzr::$bzr_uri"

if [ "$use_local_bzr_repo" == true ]; then
  # while read -r line; do
  #   tag="$(echo "${line/:/%}" | sed -n "s,\([a-f0-9]\+\) releasing package $source version \(.*[0-9]\+ubuntu[0-9]\+.*\),\2 \1,p")"
  #   [ -n "$tag" ] && ! git show-ref $tag &> /dev/null && git tag $tag
  # done < <(git log ubuntu-bzr/master --oneline)

  ubuntu_bzr_repo=$(mktemp --suffix="-$source-ubuntu-bzr-repo" --dry-run)
  bzr branch "$bzr_uri" "$ubuntu_bzr_repo"
  bzr_repo_uri="$ubuntu_bzr_repo"

  (
    cd "$bzr_repo_uri"

    while read -r line; do
      if [[ "$line" =~ (.+)\ +([0-9]+) ]]; then
        tag="${BASH_REMATCH[1]}"
        revision="${BASH_REMATCH[2]}"
        rewritten_tag="$(echo "$tag" | version_to_tag)"

        if [ -n "$rewritten_tag" ] && [ "$rewritten_tag" != "$tag" ]; then
          if bzr tag $rewritten_tag -r $revision; then
            bzr tag --delete $tag
          fi
        fi
      fi
    done < <(bzr tags)

    git init
    bzr fast-export --plain . | git fast-import

    # # For --rewrite-tags-names
    # for t in $(git tag); do
    #   if [[ "$t" =~ ^[0-9]+_ ]]; then
    #     if git tag "$(echo "$t" | sed "s,^\([0-9]\+\)_,\1%,")" "$t"; then
    #       git tag -d "$t"
    #     fi
    #   fi
    # done
  )
fi

git remote add ubuntu-bzr "$bzr_repo_uri"
git fetch ubuntu-bzr
# for t in $(git tag -l '[0-9]*[0-9]ubuntu[0-9]*'); do git tag "ubuntu/$t" "$t"; git tag -d "$t"; done

for t in $(git tag --merged ubuntu-bzr/master); do
  if git tag "ubuntu/$t" "$t"; then
    git tag -d "$t"
  fi
done

git merge -s ours --no-commit ubuntu-bzr/master --allow-unrelated-histories
git rm -rf --ignore-unmatch debian
git read-tree --prefix=/ -u ubuntu-bzr/master
git rm -rf --ignore-unmatch .bzr*
git commit -m "Importing $bzr_uri"

# Since we want to import a dsc now, we need to remove the tag it already provides or gbp will complain
last_tag="ubuntu/$(echo "$last_version" | version_to_tag)"
# last_version="$(echo "${last_tag//%/:}" | cut -f2 -d/)"

if ! git show-ref -q $last_tag; then
  last_tag=$(git describe --tags --abbrev=0 ubuntu-bzr/master)
fi
# git tag ubuntu/bzr-last-release "$last_tag"
bzr_last_release="$last_tag-bzr"
git tag "$bzr_last_release" "$last_tag"
git tag -d "$last_tag"

dsc_dir="$(mktemp -d --suffix="-$source-lp-source")"
dsc_file="$dsc_dir/${source}_$(echo "$last_version" | sed "s,^[0-9]\+:,,").dsc"
(cd "$dsc_dir" && pull-lp-source -d --no-conf "$source" "$last_version")

if ! [ -e "$dsc_file" ]; then
  echo "No $dsc_file found, please download it for $source $last_version"
  exit 1
fi

if [ "$(git branch --remote --list 'salsa/upstream' | wc -l)" -gt 0 ]; then
  upstream_branch="upstream"
else
  upstream_branch="upstream/latest"
  last_packaged_version=$(echo "$last_version" | cut -d'-' -f1)
  last_packaged_major_version=$(echo "$last_packaged_version" | cut -d. -f-2)
  last_upstream_version=$(git describe --tags --abbrev=0 upstream/latest | cut -d'/' -f2)
  last_upstream_major_version=$(echo "$last_upstream_version" | cut -d. -f-2)

  if dpkg --compare-versions "$last_packaged_major_version" lt "$last_upstream_major_version"; then
    upstream_branch="upstream/${last_packaged_major_version}.x"
  fi

  if ! git branch --remote --list 'salsa/*' | grep -qs "$upstream_branch"; then
    echo "$project expects to use $upstream_branch as branch, but that can't be found."
    echo "Please, make sure that salsa has it, or import the orig to generate that."
    exit 1
  fi
fi

gbp import-dsc --debian-branch=ubuntu/master --debian-tag='ubuntu/%(version)s' --upstream-branch="$upstream_branch" "$dsc_file"

after_release_commits="$(git log "$bzr_last_release"..ubuntu-bzr/master --reverse --format=format:%H)"

if [ -n "$after_release_commits" ]; then
  echo "Found commits after release, readding them..."
  for commit in $after_release_commits; do
    if ! git format-patch -1 --stdout $commit | git am -3; then
      echo "Failed to re-apply bzr-change"
      git show $commit --shortstat
      git am --abort
      continue
    fi
    # if ! git show $commit | git apply -3; then
    #   echo "Failed to re-apply bzr-change"
    #   git show $commit --shortstat
    #   continue
    # fi
    # if [ -n "$(git diff --cached)" ]; then
    #   git commit -C $commit
    # fi
  done
fi

cat << EOF > debian/gbp.conf
[DEFAULT]
debian-branch=ubuntu/master
upstream-branch=$upstream_branch
debian-tag=ubuntu/%(version)s
upstream-vcs-tag=%(version)s
pristine-tar=True
EOF

git add debian/gbp.conf

if [ -n "$(git diff --cached debian/gbp.conf)" ]; then
  git commit debian/gbp.conf -m "Add debian/gbp.conf with ubuntu settings"
fi

read -r -d '' VCS <<EOF || true
XS-Debian-Vcs-Browser: https://salsa.debian.org/$debteam/$debsource
XS-Debian-Vcs-Git: https://salsa.debian.org/$debteam/$debsource
Vcs-Browser: https://git.launchpad.net/~ubuntu-desktop/ubuntu/+source/$source
Vcs-Git: https://git.launchpad.net/~ubuntu-desktop/ubuntu/+source/$source
EOF

for ctrl in debian/control*; do
  awk -v r="$VCS" '{gsub(/^Vcs-Bzr:.*/,r)}1' $ctrl > $ctrl.tmp
  mv $ctrl.tmp $ctrl
done

if [ -n "$(git --no-pager diff)" ]; then
  git commit debian/control* -m "debian/control*: update VCS informations"
fi

git remote prune ubuntu-bzr
git remote remove ubuntu-bzr

git gc --prune=now --aggressive

(cd .. && touch $source.DONE)
