

#!/bin/bash -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[0;1m'
NC='\033[0m' # No Color

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
    git commit -m "uaa-release version v${1}"
}

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

echo "Creating bosh UAA-release $1 using `bosh -v`"

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

git checkout $branch_to_release_from

# initalize submodule uaa
sub_update

# restore private.yml in case it got deleted
mv /tmp/private.yml config/

# create a release tar ball
bosh create release --name uaa --version $1 --with-tarball

# we will finalize the release on master branch
git checkout master
git reset --hard origin/master
sub_update

if [ "$branch_to_release_from" = "develop" ]; then
    # if we are releasing from develop
    # create a merge commit with the changes
    git merge --no-ff develop -m "Merge of branch develop for release $1"
    sub_update
fi

finalize_and_commit $1
git push origin master
git checkout develop
git reset --hard origin/develop
git merge master -m "Merge of branch master for release $1"
sub_update
git push origin develop

# tag the release
if [ "$branch_to_release_from" = "develop" ]; then
    git checkout master
    sub_update
    git tag -a v${1} -m "$1 release"
    git push origin master --tags
else
    git checkout $branch_to_release_from
    sub_update
    git tag -a v${1} -m "$1 release"
    git push origin $branch_to_release_from --tags
fi


