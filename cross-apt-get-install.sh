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
TMP_LOG=$TMP_DIR/log
ONE_LINE_LOG=$TMP_DIR/one_line
#the expected values in ...+deb9u1_armhf.deb
ARCH=armhf
DEB=9
MAX_DEBU_ATTEMPTS=10
rm -rf $TMP_DIR
mkdir -p $TMP_DIR
cd $TMP_DIR
# run apt-get install --print-uris on the board. This will return a list of URLs. We then get them with `curl`, copy them to the board and install them.
ssh $BBB_ADDRESS "rm -rf $TMP_DIR && apt-get install --print-uris $PACKAGES" | { grep -o "'.*'" || { echo "No packages to install" >&2; exit 0; }; }  | xargs -t -I___ curl -s -w '%{filename_effective} %{url_effective} %{http_code}\n' -LO ___ | tee $TMP_LOG
grep -q 404 $TMP_LOG || :
if [ "$?" -eq 0 ]
then
	echo
	echo 'Some packages failed to download, trying to guess a more recent URL'
	while read line
	do
		line=`echo $line | grep " 404" || :`
		if [ "" != "$line" ]
		then
			oldurl=`echo $line | cut -d" " -f 2`
			echo This failed: $oldurl
			oldfile=`echo $line | cut -d" " -f 1`
			rm -rf $oldfile
			grepped=`echo $oldurl | grep ".*+deb[0-9]\{1,2\}u\([0-9]\{1,\}\)_$ARCH.deb" || :`
			if [ "$grepped" == "" ]
			then
				# no debu : we need to add a fictious one
				oldurl=`echo $oldurl | sed "s/_$ARCH\.deb/+deb${DEB}u0_$ARCH.deb/"`
			fi
			debu=`echo $oldurl | sed "s/.*+deb[0-9]\{1,2\}u\([0-9]\{1,\}\)_$ARCH.deb/\1/"`
			if [ "$debu" == "" ]
			then
				echo "Unable to parse URL $oldurl to attempt automated guessing"
				exit 1
			else
				ATTEMPTS=1
				while [ $ATTEMPTS -lt $MAX_DEBU_ATTEMPTS ]
				do
					newdebu=$((debu + ATTEMPTS))
					# try and replace the last revision number of the debXuY
					newurl=`echo $oldurl | sed "s/u${debu}_$ARCH.deb.*/u${newdebu}_$ARCH.deb/"`
					echo Retrying: $newurl
					curl -s -w '%{filename_effective} %{url_effective} %{http_code}\n' -LO $newurl > $ONE_LINE_LOG
					cat $ONE_LINE_LOG | grep " 404" || { echo SUCCESS; break; }
					oldfile=`echo $line | cut -d" " -f 1`
					rm -rf $oldfile
					ATTEMPTS=$(( ATTEMPTS + 1 ))
				done
			fi
			echo
		fi
	done < $TMP_LOG
fi
rm -rf $TMP_LOG $ONE_LINE_LOG
ls $TMP_DIR/* 2>/dev/null || exit 0
rsync -a $TMP_DIR $BBB_ADDRESS:$TMP_DIR
ssh $BBB_ADDRESS "dpkg -i $TMP_DIR/*"
