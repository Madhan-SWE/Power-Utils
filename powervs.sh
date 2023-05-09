APIKEY=""
diskname="$(cat /dev/urandom | tr -dc 'a-z' | fold -w 5 | head -n 1)-disk"
disktype=tier1
disksize=1
CRN=""
diskIds=()
wwns=()
mpaths=()
dm_devices=()
bastion_ip=""

ssh root@$bastion_ip ibmcloud pi service-target $CRN
noOfDisks=5
instanceId=""
ut=$(date +%s)
log1="log1-$ut.txt"
log2="log2-$ut.txt"
log3="log3-$ut.txt"
log4="log4-$ut.txt"

traceLogs(){

logFileName=$1

echo "$(date) ================================ dmsetup table ================================" >> $logFileName
dmsetup table >> $logFileName
echo "$(date) ================================ multipath -ll  ================================" >> $logFileName
multipath -ll >> $logFileName
echo "$(date) ================================ multipathd show paths format \"%w %d %t %i %o %T %z %s %m\"   ================================" >> $logFileName
multipathd show paths format "%w %d %t %i %o %T %z %s %m" >> $logFileName
echo "$(date) ================================ multipathd show maps format \"%w %d %n %s\"   ================================" >> $logFileName
multipathd show maps format "%w %d %n %s" >> $logFileName
echo "$(date) ================================ ls -ll /dev/disk/by-id/  ================================" >> $logFileName
ls -ll /dev/disk/by-id >> $logFileName
echo "$(date) ================================ ls -ll /dev/mapper  ================================" >> $logFileName
ls -ll /dev/mapper >> $logFileName
echo "$(date) ================================ ls -ll /sys/block  ================================" >> $logFileName
ls -ll /sys/block  >> $logFileName
}



traceLogs $log1

for(( i=0; i<noOfDisks; i++ ))
  do
    echo "$(date) Creating disk : $diskname-$i" >> $log1
    diskDetails=$(ssh root@$bastion_ip ibmcloud pi volume-create "$diskname-$i" --type $disktype --size $disksize --json)
    echo "$(date)  Disk details: $diskDetails" >> $log1
    diskId=$(echo $diskDetails | jq  '.volumeID')
    echo "$(date) disk id: $diskId"
    diskIds+=($diskId)
done

echo "$(date) created disk ids: $diskIds" >> $log1

for i in "${diskIds[@]}"
do
  for(( j=1; j<=10; j++ ))
  do
    state=$(ssh root@$bastion_ip ibmcloud pi vol $i --json | jq '.state'| xargs)
    if [[ $state = "available" ]]
    then
        echo "Volume $i created" >> $log1
        echo "Volume $i created"
        break
    else
        echo "Volume $i not yet created, state : $state" >> $log1
        echo "Volume $i not yet created, state : $state"
        sleep 10
    fi
  done
done


for(( i=0; i<noOfDisks; i++ ))
  do
    wwn=$(ssh root@$bastion_ip ibmcloud pi vol ${diskIds[$i]}  --json | jq '.wwn' | xargs)
    echo "wwn: $wwn"
    wwns+=($wwn)
    echo "$(date) Attaching disk id: $diskId  wwn: $wwn to the instance: $instanceId" >> $log1
    ssh root@$bastion_ip ibmcloud pi volume-attach ${diskIds[$i]} --instance $instanceId >> $log1
    mpaths+=("")
    dm_devices+=("")
done

for i in "${diskIds[@]}"
do
  for(( j=1; j<=10; j++ ))
  do
    state=$(ssh root@$bastion_ip ibmcloud pi vol $i --json | jq '.state'| xargs)
    if [[ $state = "in-use" ]]
    then
        echo "Volume $i is attached" >> $log1
        echo "Volume $i attached"
        break
    else
        echo "Volume $i not yet attached, state : $state" >> $log1
        echo "Volume $i not yet attached, state : $state"
        sleep 10
    fi
  done
done

echo "############  After volumes are attached : ############" >> $log1
traceLogs $log1


idx=0
for i in "${wwns[@]}"
do
   traceLogs $log2
   echo "$(date) WWN: $i"
   echo "- - -" > /sys/class/scsi_host/host0/scan
   echo "- - -" > /sys/class/scsi_host/host1/scan
   echo "- - -" > /sys/class/scsi_host/host2/scan
   echo "- - -" > /sys/class/scsi_host/host3/scan
   echo "- - -" > /sys/class/scsi_host/host4/scan

   for(( j=1; j<=10; j++ ))
   do
      found=false
      for dm_device in `dmsetup ls --target multipath | cut -f 2 | cut -d "," -f 2 | sed 's/)*$//g'`; 
      do
        echo "dm-$dm_device";
        uuid=$(cat "/sys/block/dm-$dm_device/dm/uuid")
        sstr=$(echo $i|  tr '[:upper:]' '[:lower:]')
        if [[ $uuid = *"$sstr"* ]];
        then
          echo "$(date) Device found for wwn: $i"
          echo "$(date) disk id: ${diskIds[$idx]} Device found for wwn: $i" >> $log2
          found=true
          dm_devices[$idx]="dm-$dm_device"
          name=$(cat "/sys/block/dm-$dm_device/dm/name")
          echo "Adding mpath: $name to mpaths" >> $log2
          mpaths[$idx]=$name
          echo "Mpaths[$idx]: ${mpaths[$idx]}" >> $log2
          idx=$((idx+1))
          break
        fi
      done
      
      if [ "$found" = false ] ; then
        echo "$(date) disk id: ${diskIds[$idx]} Device not found for wwn: $wwn"
        echo "$(date) disk id: ${diskIds[$idx]} Device not found for wwn: $wwn" >> $log2
      sleep 10
      else
        break
      fi

   done
   echo "############  After volume Scanning : ############" >> $log2
   traceLogs $log2
done

echo "Mpaths: $mpaths" >> $log3
for(( i=0; i<noOfDisks; i++ ))
  do
    if [[ ! -z ${mpaths[$i]} ]] ;
    then
      echo "Mpaths[$i]: ${mpaths[$i]}" >> $log3
      echo "$(date) disk id: ${diskIds[$i]} Making directory ${mpaths[$i]}-mnt for mpath ${mpaths[$i]}" >> $log3
      echo "$(date) disk id: ${diskIds[$i]} Making directory ${mpaths[$i]}-mnt for mpath ${mpaths[$i]}"
      mkdir "${mpaths[$i]}-mnt"
      echo "$(date) disk id: ${diskIds[$i]} mkfs.xfs /dev/mapper/${mpaths[$i]}" >> $log3
      echo "$(date) disk id: ${diskIds[$i]} mkfs.xfs /dev/mapper/${mpaths[$i]}" 
      mkfs.xfs "/dev/mapper/${mpaths[$i]}" >> $log3
      echo "$(date) disk id: ${diskIds[$i]} mount /dev/mapper/${mpaths[$i]} ${mpaths[$i]}-mnt" >> $log3
      echo "$(date) disk id: ${diskIds[$i]} mount /dev/mapper/${mpaths[$i]} ${mpaths[$i]}-mnt"
      mount  "/dev/mapper/${mpaths[$i]}" "${mpaths[$i]}-mnt" >> $log3
    fi
done


for(( i=0; i<noOfDisks; i++ ))
  do
    if [[ ! -z ${mpaths[$i]} ]]
    then
        
        echo "$(date) disk id: ${diskIds[$i]} umount /dev/mapper/${mpaths[$i]}" >> $log3
        echo "$(date) disk id: ${diskIds[$i]} umount /dev/mapper/${mpaths[$i]}"
        umount "/dev/mapper/${mpaths[$i]}" >> $log3

        echo "$(date) disk id: ${diskIds[$i]} Deleting directory ${mpaths[$i]}-mnt for mpath ${mpaths[$i]}" >> $log3
        echo "$(date) disk id: ${diskIds[$i]} Deleting directory ${mpaths[$i]}-mnt for mpath ${mpaths[$i]}"
        rm -rf "${mpaths[$i]}-mnt" >> $log3

        traceLogs $log3

        #echo "$(date) disk id: ${diskIds[$i]} dmsetup message /dev/mapper/${mpaths[$i]} 0 fail_if_no_path " >> $log3
        #echo "$(date) disk id: ${diskIds[$i]} dmsetup message /dev/mapper/${mpaths[$i]} 0 fail_if_no_path "
        #dmsetup message "/dev/mapper/${mpaths[$i]}" 0 fail_if_no_path >> $log3

        slaves=$(ls /sys/block/${dm_devices[$i]}/slaves)
        echo "$(date) disk id: ${diskIds[$i]}  ${dm_devices[$i]} : slaves: $slaves"


        #echo "$(date) disk id: ${diskIds[$i]} dmsetup remove --force /dev/mapper/${mpaths[$i]}" >> $log3
        #echo "$(date) disk id: ${diskIds[$i]} dmsetup remove --force /dev/mapper/${mpaths[$i]}"
        #dmsetup remove --force "/dev/mapper/${mpaths[$i]}" >> $log3
 
        #echo "$(date) disk id: ${diskIds[$i]} multipath -f  /dev/mapper/${mpaths[$i]}" >> $log3
        #echo "$(date) disk id: ${diskIds[$i]} multipath -f  /dev/mapper/${mpaths[$i]}"
        #multipath -f "/dev/mapper/${mpaths[$i]}" >> $log3
        
        for slave in $slaves
        do
          echo "$(date) disk id: ${diskIds[$i]} echo 1 > /sys/block/$slave/device/delete" >> $log3
          echo 1 > /sys/block/$slave/device/delete >> $log3
        done

        #echo "$(date) disk id: ${diskIds[$i]} echo 1 > /sys/block/${dm_devices[$i]}/device/delete" >> $log3
        #echo "$(date) disk id: ${diskIds[$i]} echo 1 > /sys/block/${dm_devices[$i]}/device/delete"
        #echo 1 > "/sys/block/${dm_devices[$i]}/device/delete" >> $log3

        traceLogs $log3
    
    fi
done


traceLogs $log4

for(( i=0; i<noOfDisks; i++ ))
  do
    echo "ibmcloud pi volume-detach ${diskIds[$i]} --instance $instanceId" >> $log4
    echo "ibmcloud pi volume-detach ${diskIds[$i]} --instance $instanceId"
    ssh root@$bastion_ip ibmcloud pi volume-detach ${diskIds[$i]} --instance $instanceId >> $log4
    # sleep 5
done

for i in "${diskIds[@]}"
do
  for(( j=1; j<=10; j++ ))
  do
    state=$(ssh root@$bastion_ip ibmcloud pi vol $i --json | jq '.state'| xargs)
    if [[ $state = "available" ]] 
    then
        echo "Volume $i is detached" >> $log4
        echo "Volume $i detached"
        break
    else
        echo "Volume $i not yet detached, state : $state" >> $log4
        echo "Volume $i not yet detached, state : $state"
        sleep 10
    fi
  done
done


traceLogs $log4

for(( i=0; i<noOfDisks; i++ ))
  do
    echo "$(date) ibmcloud pi volume-delete ${diskIds[$i]}" >> $log4
    echo "$(date) ibmcloud pi volume-delete ${diskIds[$i]}"
    ssh root@$bastion_ip ibmcloud pi volume-delete ${diskIds[$i]} >> $log4
done

