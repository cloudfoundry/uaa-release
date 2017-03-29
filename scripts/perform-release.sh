#!/bin/bash -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[0;1m'
NC='\033[0m' # No Color

TMPDIR=/tmp
SAVEDIR=$TMPDIR/uaa-release-save
RELEASES=$SAVEDIR/releases
FINAL_BUILDS=$SAVEDIR/.final_builds

# update submodules
function sub_update {
    git submodule sync
    git submodule foreach --recursive 'git submodule sync; git clean -d --force --force'
    git submodule update --init --recursive --force
    git clean -ffd
}

function usage {
    echo -e "Usage: ${GREEN}$(basename $0) bosh_release_version [branch_to_release_from/develop] [/path/to/private.yml]${NC}"
    echo -e "Usage: ${GREEN}$(basename $0) 11.4 v11.4-branch${NC}"
    echo -e "\n${GREEN}$(basename $0)${NC} requires a completely pristine clone of ${CYAN}uaa-release${NC}, containing no uncommitted changes or untracked or ignored files."
    echo -e "Before performing the release, it is strongly recommended that you update blobs with ${GREEN}bosh sync blobs${NC}"
    echo -e "The ${CYAN}uaa${NC} submodule should be bumped by checking out the appropriate version ${BOLD}tag (not the branch)${NC} and committing the submodule update before running ${GREEN}$(basename $0)${NC}"
    echo -e "Specify the new ${YELLOW}bosh_release_version${NC}. The script will update the relevant branches and tags."
    echo -e "For a usual release, the ${YELLOW}branch_to_release_from${NC} should be develop. For patch releases, it should be a previous release."
    echo -e "The ${YELLOW}private.yml${NC} file serves as the private key for updating the blobstore."
    echo -e "If successful, the release should appear at ${CYAN}http://bosh.io/releases/github.com/cloudfoundry/uaa-release${NC} in a short time."
}

function invalid_version {
  echo -e "${NC}Invalid version:${RED} ${1} ${NC}"
  echo -e "${GREEN}Correct version must start with a digit and only contain digits and dots.${NC}"
}

function finalize_and_commit {
    tarball=dev_releases/uaa/uaa-$1.tgz
    #dryrun
    bosh finalize release $tarball --dry-run --name uaa --version $1
    #actual
    bosh finalize release $tarball --name uaa --version $1
    #bosh generated files
    git add .
    git commit --no-verify -m "uaa-release version v${1}"
}

function copy_master_release_metadata {
    # make a copy of releases files, we will use these
    rm -rf $SAVEDIR
    mkdir -p $SAVEDIR
    git checkout master
    cp -r releases $SAVEDIR/
    cp -r .final_builds $SAVEDIR/
}

function paste_master_release_metadata {
    # update metadata in preparation of release
    echo -e "Merging release metadata"
    cp -r $RELEASES/* releases/
    cp -r $FINAL_BUILDS/* .final_builds/
    git add releases .final_builds
    if git commit -m "Update bosh release metadata information for version ${1}"; then
        git push origin $1
        echo -e "Release metadata merged"
    else
       echo -e "No merge required. No changes detected"
    fi
}

# =============================================================================
#                               SCRIPT START
# =============================================================================

# check our command line arguments
if [ "$#" -lt 1 ]; then
    usage
    exit 1
fi

#validate the version number
if [[ "$1" =~ ^[0-9]+.?[0-9]*$ ]]; then
  echo -e "Creating release with version ${GREEN}${1}${NC} and tag with ${GREEN}v${1}${NC}"
else
  invalid_version $1
  exit 1
fi

# what branch do we release from
branch_to_release_from=develop
if [ "$#" -ge 2 ]; then
    branch_to_release_from=$2
fi

# navigate to the correct release directory
cd `dirname $0`/..
echo -e "${NC}Performing release from directory:${GREEN} `pwd` ${NC}"

# initialize sub modules if needed
sub_update

# ensure we have a clean repo - to avoid unwanted files making it into a release
if [[ -n $(git status -s) ]]; then
    git status -s
    echo
    echo -e "${RED}ERROR:${NC} Release must be performed from a fresh clone of the repository."
    exit 1
fi

echo "Updating all branches"
git fetch --all --prune > /dev/null

# save the metadata files from master
copy_master_release_metadata

echo "Creating bosh UAA-release ${GREEN} ${1} ${NC} using `bosh -v`"

# just in case it gets deleted during branch switch
if [ "$#" -ge 3 ]; then
    cp $3 /tmp/private.yml
elif [ -f config/private.yml ]; then
    cp config/private.yml /tmp/private.yml
else
    echo -e "${RED}ERROR:${NC} Missing private.yml file" >&2
    usage
    exit 1
fi

# jump to the branch that contains our code and sync submodule
git checkout $branch_to_release_from
sub_update

# paste in our metadata from master and commit it
paste_master_release_metadata $branch_to_release_from

# restore private.yml in case it got deleted
mv /tmp/private.yml config/

echo -e "Building tarball ${GREEN}${1}${NC} and tag with ${GREEN}v${1}${NC}"
# create a release tar ball
bosh create release --name uaa --version $1 --with-tarball
metadata_commit=''
# finalize release, get commit SHA so that we can cherry pick it later
finalize_and_commit $1 metadata_commit

# tag the release
git tag -a v${1} -m "$1 release"
git push origin $branch_to_release_from --tags

# jump to master branch
git checkout master
git reset --hard origin/master
sub_update


if [ "$branch_to_release_from" = "develop" ]; then
    # merge metadata files -
    echo -e "Merging develop to master"
    git merge --no-ff origin/develop -m "Merge of branch develop for release ${1}"
else
    # cherry pick the metadata files - we can't merge. different code paths
    echo -e "Cherry picking metadata commit to master for release ${1} and sha ${metadata_commit}"
    git cherry-pick ${metadata_commit}
fi

# update develop (merge master to develop so that the next release won't have a conflict
git push origin master --tags
git checkout develop
git merge --no-ff master -m "Bumping develop with master contents in preparation of next release"
git push origin develop


