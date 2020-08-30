#!/bin/bash

set -ex

# Use nim stable if NIM_VERSION/BRANCH not set
if [[ -z "$NIM_VERSION" ]]
then
  if [[ -z "$BRANCH" ]]
  then
    export NIM_VERSION=stable
  else
    export NIM_VERSION="$BRANCH"
  fi
fi

# Detect if Travis, Github Workflows, etc
if [[ ! -z "$TRAVIS_CPU_ARCH" ]]
then
  export CPU_ARCH="$TRAVIS_CPU_ARCH" # amd64, arm64, ppc64le
  export OS_NAME="$TRAVIS_OS_NAME" # windows, macosx, linux
elif [[ ! -z "$GITHUB_WORKFLOW" ]]
then
  export CPU_ARCH="$GH_CPU_ARCH"
  export OS_NAME="$GH_OS_NAME"
fi

echo "CPU_ARCH=$CPU_ARCH"
echo "OS_NAME=$OS_NAME"

download_nightly() {
  if [[ "$OS_NAME" == "linux" ]]
  then
    if [[ "$CPU_ARCH" == "amd64" ]]
    then
      local SUFFIX="linux_x64\.tar\.xz"
    else
      # linux_arm64, etc
      local SUFFIX="linux_${CPU_ARCH}\.tar\.xz"
    fi
  elif [[ "$OS_NAME" == "osx" ]]
  then
    if [[ "$CPU_ARCH" == "amd64" ]]
    then
      # Used to be osx.tar.xz, now is macosx_x64.tar.xz
      local SUFFIX="macosx_x64\.tar\.xz"
    else
      # macosx_arm64, perhaps someday
      local SUFFIX="macosx_${CPU_ARCH}\.tar\.xz"
    fi
  elif [[ "$OS_NAME" == "windows" ]]
  then
    local SUFFIX="windows_x64\.zip"
  fi

  if [[ ! -z "$SUFFIX" ]]
  then
    # Fetch nightly download url. This is subject to API rate limiting, so may fail
    # intermittently, in which case the script will fallback to building nim.
    local NIGHTLY_API_URL=https://api.github.com/repos/nim-lang/nightlies/releases

    local NIGHTLY_DOWNLOAD_URL=$(curl $NIGHTLY_API_URL -SsLf \
      | grep "\"browser_download_url\": \".*${SUFFIX}\"" \
      | head -n 1 \
      | sed -n 's/".*\(https:.*\)".*/\1/p')
  fi

  if [[ ! -z "$NIGHTLY_DOWNLOAD_URL" ]]
  then
    local NIGHTLY_ARCHIVE=$(basename $NIGHTLY_DOWNLOAD_URL)
    curl $NIGHTLY_DOWNLOAD_URL -SsLf > $NIGHTLY_ARCHIVE
  else
    echo "No nightly build available for $OS_NAME $CPU_ARCH"
  fi

  if [[ ! -z "$NIGHTLY_ARCHIVE" && -f "$NIGHTLY_ARCHIVE" ]]
  then
    rm -Rf $HOME/Nim-devel
    mkdir -p $HOME/Nim-devel
    tar -xf $NIGHTLY_ARCHIVE -C $HOME/Nim-devel --strip-components=1
    rm $NIGHTLY_ARCHIVE
    export PATH="$HOME/Nim-devel/bin:$PATH"
    echo "Installed nightly build $NIGHTLY_DOWNLOAD_URL"
    return 1
  fi

  return 0
}


build_nim () {
  if [[ "$NIM_VERSION" == "devel" ]]
  then
    if [[ "$BUILD_NIM" != 1 ]]
    then
      # If not forcing build, download nightly build
      download_nightly
      local DOWNLOADED=$?
      if [[ "$DOWNLOADED" == "1" ]]
      then
        # Nightly build was downloaded
        return
      fi
    fi
    # Note: don't cache $HOME/Nim-devel in your .travis.yml
    local NIMREPO=$HOME/Nim-devel
  else
    # Not actually using choosenim, but cache in same location.
    local NIMREPO=$HOME/.choosenim/toolchains/nim-$NIM_VERSION-$CPU_ARCH
  fi

  export PATH=$NIMREPO/bin:$PATH

  if [[ -f "$NIMREPO/bin/nim" ]]
  then
    echo "Using cached nim $NIMREPO"
  else
    echo "Building nim $NIM_VERSION"
    if [[ "$NIM_VERSION" =~ [0-9] ]]
    then
      local GITREF="v$NIM_VERSION" # version tag
    else
      local GITREF=$NIM_VERSION
    fi
    git clone -b $GITREF --single-branch https://github.com/nim-lang/Nim.git $NIMREPO
    cd $NIMREPO
    sh build_all.sh
    cd -
  fi
}


use_choosenim () {
  local GITBIN=$HOME/.choosenim/git/bin
  export CHOOSENIM_CHOOSE_VERSION="$NIM_VERSION --latest"
  export CHOOSENIM_NO_ANALYTICS=1
  export PATH=$HOME/.nimble/bin:$GITBIN:$PATH
  if ! type -P choosenim &> /dev/null
  then
    echo "Installing choosenim"

    mkdir -p $GITBIN
    if [[ "$OS_NAME" == "windows" ]]
    then
      export EXT=.exe
      # Setup git outside "Program Files", space breaks cmake sh.exe
      cd $GITBIN/..
      curl -L -s "https://github.com/git-for-windows/git/releases/download/v2.23.0.windows.1/PortableGit-2.23.0-64-bit.7z.exe" -o portablegit.exe
      7z x -y -bd portablegit.exe
      cd -
    fi

    curl https://nim-lang.org/choosenim/init.sh -sSf > init.sh
    sh init.sh -y
    cp $HOME/.nimble/bin/choosenim$EXT $GITBIN/.

    # Copy DLLs for choosenim
    if [[ "$OS_NAME" == "windows" ]]
    then
      cp $HOME/.nimble/bin/*.dll $GITBIN/.
    fi
  else
    echo "choosenim already installed"
    rm -rf $HOME/.choosenim/current
    choosenim update $NIM_VERSION --latest
    choosenim $NIM_VERSION
  fi
}

if [[ "$OS_NAME" == "osx" ]]
then
  # Work around https://github.com/nim-lang/Nim/issues/12337 fixed in 1.0+
  ulimit -n 8192
fi

# Autodetect whether to build nim or use choosenim, based on architecture.
# Force nim build with BUILD_NIM=1
# Force choosenim with USE_CHOOSENIM=1
if [[ ( "$CPU_ARCH" != "amd64" || "$BUILD_NIM" == "1" ) && "$USE_CHOOSENIM" != "1" ]]
then
  build_nim
else
  use_choosenim
fi
