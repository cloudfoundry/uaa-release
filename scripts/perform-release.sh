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
    echo -e "Usage: ${GREEN}$(basename $0) ${RED}11.4 v11.4-branch /path/to/private.yml${NC}"
    echo -e "\n\n${GREEN}$(basename $0)${NC} requires a completely pristine clone of ${CYAN}uaa-release${NC}, containing no uncommitted changes or untracked or ignored files."
    echo -e "\nBefore performing the release, it is strongly recommended that you update blobs with ${GREEN}bosh sync blobs${NC}"
    echo -e "\nThe ${CYAN}uaa${NC} submodule should be bumped by checking out the appropriate version ${BOLD}tag (not the branch)${NC} and committing the submodule update before running ${GREEN}$(basename $0)${NC}"
    echo -e "Specify the new ${YELLOW}bosh_release_version${NC}. The script will update the relevant branches and tags."
    echo -e "\nFor a usual release, the ${YELLOW}branch_to_release_from${NC} should be develop. For patch releases, it should be a previous release."
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
    local result=$2
    eval $result="`git rev-parse HEAD`"
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
    echo -e "${CYAN}Merging release metadata${NC}"
    cp -r $RELEASES/* releases/
    cp -r $FINAL_BUILDS/* .final_builds/
    git add releases .final_builds
    if git commit -m "Update bosh release metadata information for version ${1}"; then
        git push origin $1
        echo -e "${CYAN}Release metadata merged${NC}"
    else
       echo -e "${CYAN}No merge required. No changes detected${NC}"
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
  echo -e "${CYAN}Creating release with version ${GREEN}${1}${NC} and tag with ${GREEN}v${1}${NC}"
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
# this ensures that we are in the correct place
cd `dirname $0`/..
echo -e "${CYAN}Performing release from directory:${GREEN} `pwd` ${NC}"

# initialize sub modules if needed
sub_update

# ensure we have a clean repo - to avoid unwanted files making it into a release
if [[ -n $(git status -s) ]]; then
    git status -s
    echo
    echo -e "${RED}ERROR:${NC} Release must be performed from a fresh clone of the repository."
    exit 1
fi

# fetch all branches so that we have the latest data
echo -e "${CYAN}Updating all branches${NC}"
git fetch --all --prune > /dev/null

# save the metadata files from master
# this saves all metadata from master
# into a temporary directory
copy_master_release_metadata

echo -e "${CYAN}Creating bosh UAA-release ${GREEN} ${1} ${NC} using `bosh -v`"

# we save private.yml to a temp directory
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

# perform chronological release on branch `releases/version`
git checkout -b releases/$1
# restore private.yml in case it got deleted
cp /tmp/private.yml config/

echo -e "${CYAN}Building tarball ${GREEN}${1}${NC} and tag with ${GREEN}v${1}${NC}"
# create a release tar ball - and a dev release
bosh create release --name uaa --version $1 --with-tarball
metadata_commit=''
# finalize release, get commit SHA so that we can cherry pick it later
finalize_and_commit $1 metadata_commit
echo -e "${CYAN}Finalized metadata with commit SHA ${metadata_commit}${NC}"

# tag the release and individual metadata
echo -e "${CYAN}Tagging and pushing the release branch${NC}"
git tag -a v${1} -m "$1 release"
git push origin $branch_to_release_from --tags

# go back to our original release branch
# so that we can merge back ALL metadata to master
git checkout $branch_to_release_from
sub_update

# clean out the old release
rm releases/uaa/uaa-${1}.tgz

# paste in our metadata from master and commit it
paste_master_release_metadata $branch_to_release_from
# restore private.yml in case it got deleted
mv /tmp/private.yml config/

echo -e "${CYAN}Generating metadata for master ${GREEN}${1}${NC} with tag ${GREEN}v${1}${NC}"
metadata_commit=''
# finalize release, get commit SHA so that we can cherry pick it later
finalize_and_commit $1 metadata_commit
echo -e "${CYAN}Finalized merge metadata with commit SHA ${metadata_commit}${NC}"

# jump to master branch
echo -e "${CYAN}Switching to master branch to prep for metadata migration${NC}"
git checkout master
git reset --hard origin/master
sub_update

# merge release branch, with all metadata, to master
# a patch release has a dot in it
if [[ ${1} == *.* ]]; then
    #patch releases, that contain dots, we cherry pick the commit metadata only
    echo -e "${CYAN}Cherry picking metadata commit to master for release ${1} and sha ${metadata_commit}${NC}"
    git cherry-pick ${metadata_commit}
else
    echo -e "${CYAN}Merging $branch_to_release_from to master${NC}"
    # merge to master - accept the dev branch as resolutions for conflicts
    git merge --no-ff ${branch_to_release_from} -m "Merge of branch ${branch_to_release_from} for release ${1}${NC}" -X theirs
fi

# update develop (merge master to develop so that the next release won't have a conflict
echo -e "${CYAN}Pushing master branch and release tags${NC}"
git push origin master --tags
echo -e "${CYAN}Merging master to develop to avoid conflicts in the future${NC}"
git checkout develop
git merge --no-ff master -m "Bumping develop with master contents in preparation of next release"
git push origin develop

# place the release on a branch, because rel-eng doesn't do git fetch --tags
echo -e "${CYAN}Creating release branch to store tag on${NC}"
git checkout -b releases/v${1} v${1}
git push origin releases/v${1}
git checkout develop

# finally done!
echo -e "${CYAN}Release ${1} completed with tag v${1} and SHA: ${metadata_commit}{NC}"


