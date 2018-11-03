#!/bin/bash -e
[ -z "$BBB_ADDRESS" ] && BBB_ADDRESS=root@192.168.7.2

case "$1" in
--help)
	cat <<END
Tool to download and install debian packages on Bela when the board has no internet access. Run this on the host computer (which needs internet access).

Usage:
  run this on the host passing as parameters the packages you would want to install. For instance, if you would like to run on the board:
  $ apt-get install libjson-c-dev libcurl4-openssl-dev liboauth-dev
  you should run on the host:
  $ $0 libjson-c-dev libcurl4-openssl-dev liboauth-dev
  This assumes that the board will be accessible at $BBB_ADDRESS. If this is not the case, set the environment variable BBB_ADDRESS before running the script, e.g.:
  $ BBB_ADDRESS=root@192.168.6.2 $0 libjson-c-dev libcurl4-openssl-dev liboauth-dev
END
exit
;;
esac

PACKAGES=$@
TMP_DIR=/tmp/pkgs/ # FFS, keep the trailing /, or rsync will create a subfolder /tmp/pkgs/pkgs
rm -rf $TMP_DIR
mkdir -p $TMP_DIR
cd $TMP_DIR
# run apt-get install --print-uris on the board. This will return a list of URLs. We then get them with `curl`, copy them to the board and install them.
ssh $BBB_ADDRESS "rm -rf $TMP_DIR && apt-get install --print-uris $PACKAGES" | { grep -o "'.*'" || { echo "No packages to install" >&2; exit 0; }; }  | xargs -I___ curl -LO ___
ls $TMP_DIR/* 2>/dev/null || exit 0
rsync -a $TMP_DIR $BBB_ADDRESS:$TMP_DIR
ssh $BBB_ADDRESS "dpkg -i $TMP_DIR/*"
