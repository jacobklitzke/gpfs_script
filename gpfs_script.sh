#!/bin/bash
# paths to binaries
MMLSCONFIG="/usr/lpp/mmfs/bin/mmlsconfig"
MMCHCLUSTER="/usr/lpp/mmfs/bin/mmchcluster"
MMGETSTATE="/usr/lpp/mmfs/bin/mmgetstate"
MMLSNSD="/usr/lpp/mmfs/bin/mmlsnsd"
MMCRNSD="/usr/lpp/mmfs/bin/mmcrnsd"
MMDELNSD="/usr/lpp/mmfs/bin/mmdelnsd"
MMLSFS="/usr/lpp/mmfs/bin/mmlsfs"
MMCRFS="/usr/lpp/mmfs/bin/mmcrfs"
MMDELFS="/usr/lpp/mmfs/bin/mmdelfs"
MMFSADM="/usr/lpp/mmfs/bin/mmfsadm"
MMMOUNT="/usr/lpp/mmfs/bin/mmmount"
MMUMOUNT="/usr/lpp/mmfs/bin/mmumount"
MMLSMOUTN="/usr/lpp/mmfs/bin/mmlsmount"
BENCH="/root/benchmark"
IOR="/gpfs1/benchmark/IOR"
IOZONE="/gpfs1/benchmark/iozone"
TEE="/usr/bin/tee"
SMCLI="/opt/SMgr/client/SMcli"
PERL="/usr/bin/perl"
LS="/usr/bin/ls"
WC="/usr/bin/wc"

# filesystem constants
FSMOUNT="/gpfs1"
FSNAME="gpfs1"
AUTOMOUNT="yes"
FSBLOCKSIZE="4M"
VERIFYNSD="no"
NUMNODES="8"
BLOCKALLOC="cluster"

# mpirun constants
ALLOWROOT="--allow-run-as-root"
NUMPROC="48"
HOSTFILE="$FSMOUNT/benchmark/hostsfile"

# IOR constants
FLAGS="-w -r -Z"
XFERSIZE="4M"
BLKSIZE="20G"
POSTFLAGS="-F -eg"

#Storage constants
$CONTROLLER_A_IPS=(192.168.210.30 192.168.210.32 192.168.210.34 192.168.210.36 192.168.210.38 192.168.210.40)
$CONTROLLER_B_IPS=(192.168.210.31 192.168.210.33 192.168.210.35 192.168.210.37 192.168.210.39 192.168.210.41)
$LUNS_PER_BOX=6

#functions
#verify_prereqs - Make the user verify all prerequsites have been met. If the prerequsites isn't met, the program exits.
verify_prereqs() {
  read -p "Is the benchmark folder in the /gpfs1/ directory? (y/n) " -n 1 -r
  echo
  check_response $REPLY

  read -p "Is the gpfs filesystem mounted? (y/n) " -n 1 -r
  echo
  check_response $REPLY

  read -p "Is the cache script and e-mail script in the /root/bin directory? (y/n) " -n 1 -r
  echo
  check_response $REPLY

  read -p "Are all of the NSD stanza files in the /root/nsd directory (y/n)? " -n 1 -r
  echo
  check_response $REPLY

  echo -e "Alright, I suppose i'll start running now. I'll let you know when I finish.\n "
}

#check_response - Checks the input of the user for the verify_prereqs function. If there user answers no, the program exits.
#$1 - This parameter is the input of the user.
check_response() {
  if [[ ! $1 =~ ^[Yy]$ ]]
  then
    echo "Becuase you have answered no to one of the prerequsites, the program will exit. Please correct the issue and try again."
    exit 1
  fi
}
#create_nsds - This function creates the NSDs from a given file.
#$1 - This parameter is the nsd_stanza file path
create_nsds() {
  $MMCRNSD -F $1 -v no
  verify_nsd_creation $1
}

#verify_nsd_creation - This function verifies that all nsds were successfully created.
#$1 - This parameter is the nsd_stanza file path.
verify_nsd_creation() {
  count=$(get_nsd_count $1)
  actual_nsd_count=$($MMLSNSD | grep gpfs | wc -l)
  if ! [ count == actual_nsd_count ]; then
    echo "There was an error creating the NSDs. Please verify the NSD file $1 "
    exit
  fi
}

#create_fs - This function creates the filesystem for use with GPFS. Uses global constants defined above
#$1 - This parameter is the nsd stanze file path.
function create_fs() {
	# create filesysem using stanza file passed in
	$MMCRFS $FSMOUNT $FSNAME -F $1 -A $AUTOMOUNT -B $FSBLOCKSIZE -v $VERIFYNSD -n $NUMNODES -j $BLOCKALLOC
  verify_fs_creation
}

#verify_fs_creation - This function verifies that the filesystem was actually created. Uses global constants defined above.
function verify_fs_creation() {
  if ![ $MMLSFS all -T | grep $FSMOUNT ]; then
    echo "There was an error mounting the filesystem. Check the logs."
    exit
  fi
}

#mount_fs - This function mounts the filesystem.
#$1 - This parameter is the $FSNAME global constant. The name of the filesystem.
function mount_fs {
  $MMMOUNT $1 -a
  verify_mount
}

#verify_mount - This function verifies that the filesystem was mounted on all nodes. Uses global constants.
function verify_mount {
  if ![ $($MMLSMOUNT | grep -c $NUMNODES) == 1 ]; then
    echo "There was a problem mounting the filesystem on all nodes. Please check the problem."
    exit
  fi
}

#change_cache_setup - This function changes the cahce settings for the LUNs attached to the filesystem.
#$1 - This parameter is the nsd stanza file path.
function change_cache_setup () {
  count=$(get_nsd_count $1)
  box_count=$count/6
  if ! [$count % 6 == 0]; then
    $box_count=$box_count+1
  fi

  for i in `seq 1 $box_count`;
  do
    change_cache $CONTROLLER_A_IPS[$i-1] $CONTROLLER_B_IPS[$i-1] $2[0] $2[1] $2[2] $2[3]
  done
  $cacheSettings = "1011"
  echo "cacheSettings"
}

#copy_benchmark_folder - This function copies the benchmark folder to the /gpfs1 directory.
function copy_benchmark_folder() {
  cp -r /root/benchmark /gpfs1
}

# change_cache - This function changes cache settings through SMCLI calls.
#$1 - This parameter is the IP Address of controller A.
#$2 - This parameter is the IP Address of controller B
#$3 - This parameter is the cache setting for readCache (TRUE/FALSE)
#$4 - This parameter is the cache setting for readPrefetch (TRUE/FALSE)
#$5 - This parameter is the cache setting for writeCache (TRUE/FALSE)
#$6 - This parameter is the cache setting for writeCacheMirroring (TRUE/FALSE)
function change_cache()
{
  $SMCLI $1 $2 -c "set allVolumes readCacheEnabled=$3;" > /dev/null 2>&1
  $SMCLI $1 $2 -c "set allVolumes cacheReadPrefetch=$4;" > /dev/null 2>&1
  $SMCLI $1 $2 -c "set allVolumes writeCacheEnabled=$5;" > /dev/null 2>&1
  $SMCLI $1 $2 -c "set allVolumes mirrorCacheEnabled=$6;" > /dev/null 2>&1
  $SMCLI $1 $2 -c "set allVolumes cacheWithoutBatteryEnabled=FALSE;" > /dev/null 2>&1
}

#run_IOR_test - This functions runs the IOR program for benchmarking
#$1 - This parameter is the nsd stanza file path
#$2 - This parameter is the binary representation of the cache settings of the test. (e.g. 1011, 1010, 0000, etc.)
function run_IOR_test() {
  TIME=$(date +"%H-%M")
  DATE=$(date +"%d-%m-%Y")
  count=$(get_nsd_count $1)
  filename=$count"LUNS_"$2"_"$DATE"_"$TIME".log"

  for i in power8a power8b; do
    ssh $i "/var/mmfs/etc/blockio.ksh"
  done

  mpirun $ALLOWROOT -n $NUMPROC --hostfile $HOSTFILE /gpfs1/benchmark/IOR $FLAGS -t $XFERSIZE -b $BLKSIZE $POSTFLAGS | tee ~/bench_results/$filename; perl /root/bin/email.pl
}

#unmount_fs - This function unmounts the filesystem from all nodes
function unmount_fs {
  $MMUMOUNT $1 -a
  verify_unmount
}

#verify_unmount - This function verifies the filesystem was unmounted on all nodes.
function verify_unmount {
  if ![ $($MMLSMOUNT | grep -c 0) == 1 ]; then
    echo "There was a problem unmount the filesystem. Please fix the issue."
  fi
}

#delete_fs - This function deletes the filesystem.
function delete_fs {
  $MMDELFS $FSNAME
  verify_fs_deletion
}

#verify_fs_deletion - This function verifies the filesystem was actuall deleted.
function verify_fs_deletion {
  if [ $MMLSFS all -T | grep $FSMOUNT ]; then
    echo "There was a problem unmounting the filesystem. Please fix the issue"
  fi
}

#delete_nsds - This function deletes the NSDs
#$1 - This parameter is the nsd staza file path
function delete_nsds {
  $MMDELNSD -F $1
  verify_nsd_deletion
}

#verify_nsd_deletion - This function verifies all NSDs were successfully deleted.
function verify_nsd_deletion {
  nsd_count=$($MMLSNSD | grep gpfs | wc -l)
  if ![$nsd_count == 0]; then
    echo "There was a problem deleting the nsds with nsd stanza $1 . Please check the stanza file."
}

#get_nsd_count - This function is a utility function. Used to get number of NSDs from a nsd stanza file.
#$1 - The nsd stanza file path
function get_nsd_count() {
  count=$(grep -o -c '%nsd:' $1)
  echo="$count"
}
#ACTUAL SCRIPT STARTS HERE!
verify_prereqs
for i in `seq 1 $(ls -1 ~/ | wc -l)`;
do
  nsd_stanza=$(ls -1 ~/ | sed -n "$i"p)
  create_nsds $nsd_stanza
  create_fs $nsd_stanza
  mount_fs $FSNAME
  copy_benchmark_folder

  cache_parameters=(TRUE FALSE TRUE TRUE)
  cache_settings=$(change_cache_setup $nsd_stanza $cache_parameters)
  run_IOR_test $nsd_stanza $cache_settings
  unmount_fs $FSNAME

  cache_settings=$(change_cache_setup $nsd_stanza $cache_parameters)
  mount_fs $FS_NAME
  run_IOR_test $nsd_stanza $cache_settings
  unmount_fs $FSNAME

  cache_settings=$(change_cache_setup $nsd_stanza $cache_parameters)
  mount_fs $FS_NAME
  run_IOR_test $nsd_stanza $cache_settings
  unmount_fs $FSNAME

  delete_fs $FSNAME
  delete_nsds $nsd_stanza

done
