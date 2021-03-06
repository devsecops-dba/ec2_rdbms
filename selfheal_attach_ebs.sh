#!/bin/bash
#set -xv
#
function attach_volume () {
  fs_device=$1
  instance_id=$2
  volume_id=$3
  cmd_output=$(aws ec2 attach-volume \
        --device ${fs_device} \
        --instance-id ${instance_id} \
        --volume-id ${volume_id} \
         2>&1) 
   return_code=$?
   echo "${return_code}:${cmd_output}"
}

#
function get_volume_status() { 
  volume_id=$1
  cmd_output=$(aws ec2 describe-volumes \
        --volume-ids ${volume_id} \
        --query Volumes[].State \
        --output text \
         2>&1)
   return_code=$?
   echo "${return_code}:${cmd_output}"
}

#
function create_volume() { 
  region=$1
  avail_zone=$2
  size=$3
  fs_device=$4
  pratice_area=$5
  cmd_output=$(aws ec2 create-volume \
        --availability-zone ${avail_zone} \
        --size ${size} \
        --volume-type gp2 \
        --region ${region} \
        --tag-specifications "ResourceType=volume,Tags=[{Key=PracticeArea,Value=$practice_area},{Key=Name,Value=sanjeevk_rdbms_ebs_vol},{Key=DeviceName,Value=$fs_device}]")
   return_code=$?
   sleep 30
   echo "${return_code}:${cmd_output}"
}
#
function get_volume_id() { 
  region=$1
  avail_zone=$2
  fs_device=$3
  practice_area=$4
  cmd_output=$(aws ec2 describe-volumes \
        --region ${region} \
        --filters \
            Name=availability-zone,Values=${avail_zone} \
            Name=tag:DeviceName,Values=${fs_device} \
            Name=tag:PracticeArea,Values=${practice_area} \
        --query "Volumes[*].{ID:VolumeId}" \
        --output text \
         2>&1)
   return_code=$?
   echo "${return_code}:${cmd_output}"
}

function get_instance_id() {
   instance_id=`curl -s -m 30 'http://169.254.169.254/latest/meta-data/instance-id'`
   if [[ ${instance_id} == *"Not Found"* ]] ; then
      echo "instance id is not found.exiting script."
      exit 1
   fi
   echo ${instance_id}
}    
#
#main
region=us-west-2
avail_zone=us-west-2a
device_list=("/dev/xvdb|20|/u01" "/dev/xvdc|20|none")
practice_area=fss
#
instance_id=`echo $(get_instance_id)`
#
for device in "${device_list[@]}"
do
  #
  fs_device=`echo $device | awk -F"|" '{print $1}'`
  size=`echo $device | awk -F"|" '{print $2}'`
  fs_mount=`echo $device | awk -F"|" '{print $3}'`
  echo "fs_device:${fs_device}"
  echo "size:${size}"
  echo "fs_mount:${fs_mount}"

  # get volume_id for fs_device
  result=$(get_volume_id "$region" "$avail_zone" "$fs_device" "$practice_area")
  return_code=`echo $result |awk  -F":" '{print $1}'`
  ebs_volume_id=`echo $result |awk -F":" '{print $2}'`

  # if aws cmd succeeds and volid does not exist create it
  if [[ ($return_code -eq 0) && ( -z "$ebs_volume_id" ) ]]; then
    result=$(create_volume "$region" "$avail_zone" "$size" "$fs_device" "$practice_area")
    return_code=`echo $result |awk  -F":" '{print $1}'`
    ebs_volume_id=`echo $result |awk -F":" '{print $2}'`
    if [[ ($return_code -eq 0) && ( -n "$ebs_volume_id" )]]; then
      echo "Volume for ${fs_device} was newly created with volume_id:${ebs_volume_id}"
    fi
  elif [[ ($return_code -eq 0) && ( -n "$ebs_volume_id" ) ]]; then
    echo "Volume for ${fs_device}  already exists  with volume_id:${ebs_volume_id}"
  else
    echo "Issue with aws cmd. Please check. exiting"
    exit 1
  fi

  # get volume status for given vol_id
  result=$(get_volume_status "$ebs_volume_id") 
  return_code=`echo $result |awk  -F":" '{print $1}'`
  ebs_volume_state=`echo $result |awk -F":" '{print $2}'`

  # if aws cmd succeeds and volstatus is not attached
  if [[ ($return_code -eq 0) && ( ${ebs_volume_state} == "available" ) ]]; then
    echo "Volume for ${fs_device} has status: ${ebs_volume_state}"
    result=$(attach_volume "$fs_device" "$instance_id" "$ebs_volume_id")
    return_code=`echo $result |awk  -F":" '{print $1}'`
    output=`echo $result |awk -F":" '{print $2}'`

    if [[ ($return_code -eq 0)]]; then
       echo "Volume "$ebs_volume_id" with device "$fs_device" has been attached to instance "$instance_id" successfully"
    else
    echo "Issue with aws cmd. Please check. exiting"
    fi
  else
    echo "Volume for ${fs_device} has status: ${ebs_volume_state}"
  fi

  #
  # Format /dev/nnn> if it does not contain a partition yet
  if [[ ${fs_mount} != "none" ]]; then
  has_partition=`sudo file -b -s ${fs_device}`
  echo "has_partition:${has_partition}"
    if [ "${has_partition}" == "data" ]; then
      sudo mkfs -t ext4 ${fs_device}
      sudo mkdir -p ${fs_mount}
      sudo mount ${fs_device} ${fs_mount}
      # Persist the volume in /etc/fstab so it gets mounted again
      echo "${fs_device} ${fs_mount} ext4 defaults,nofail 0 2" | sudo tee -a /etc/fstab
    fi
  fi
  
done
