#!/bin/bash -e
# Oracle Database Bootstrapping OL73HVM
#
#
#

function install_packages() {
    echo "[INFO] Calling: yum install -y $$@"
    yum install -y $$@ > /dev/null
}
#
function attach_volume () {
  fs_device=$1
  instance_id=$2
  volume_id=$3
  region=$4
  cmd_output=$$(aws ec2 attach-volume \
        --device $${fs_device} \
        --instance-id $${instance_id} \
        --volume-id $${volume_id} \
        --region ${region} \
         2>&1)
   return_code=$?
   echo "$${return_code}:$${cmd_output}"
}

#
function get_volume_status() {
  volume_id=$1
  region=$2
  cmd_output=$$(aws ec2 describe-volumes \
        --region ${region} \
        --volume-ids $${volume_id} \
        --query Volumes[].State \
        --output text \
         2>&1)
   return_code=$?
   echo "$${return_code}:$${cmd_output}"
}

#
function create_volume() {
  region=$1
  avail_zone=$2
  size=$3
  fs_device=$4
  pratice_area=$5
  cmd_output=$$(aws ec2 create-volume \
        --availability-zone ${avail_zone} \
        --size $${size} \
        --volume-type gp2 \
        --region ${region} \
        --tag-specifications "ResourceType=volume,Tags=[{Key=PracticeArea,Value=$$practice_area},{Key=Name,Value=sanjeevk_rdbms_ebs_vol},{Key=DeviceName,Value=$$fs_device}]" \
        2>&1 )
   return_code=$?
   sleep 30
   echo "$${return_code}:$${cmd_output}"
}
#
function get_volume_id() {
  region=$1
  avail_zone=$2
  fs_device=$3
  practice_area=$4
  cmd_output=$$(aws ec2 describe-volumes \
        --region ${region} \
        --filters \
            Name=availability-zone,Values=${avail_zone} \
            Name=tag:DeviceName,Values=$${fs_device} \
            Name=tag:PracticeArea,Values=$${practice_area} \
        --query "Volumes[*].{ID:VolumeId}" \
        --output text \
         2>&1)
   return_code=$?
   echo "$${return_code}:$${cmd_output}"
}

function get_instance_id() {
   instance_id=`curl -s -m 30 'http://169.254.169.254/latest/meta-data/instance-id'`
   if [[ $${instance_id} == *"Not Found"* ]] ; then
      echo "instance id is not found.exiting script."
      exit 1
   fi
   echo $${instance_id}
}
#
# main
# variables
echo "MAIN program from bootstrap.sh script"
# print region variable passed from tf script
echo "value of variable region is : ${region}"
# print region variable passed from tf script
echo "value of variable availability-zone is : ${avail_zone}"
# print rdbms_bucket variable passed from tf script
echo "value of variable rdbms_bucket is : ${rdbms_bucket}"
# print asm_pass variable passed from tf script
echo "value of variable asm_pass is : ${asmpass}"
# print dbport variable passed from tf script
echo "value of variable dbport is : ${dbport}"
practice_area=fss

# yum update
cd /tmp
export PATH=$PATH:/usr/local/bin
cd /etc/yum.repos.d
echo "installing [un]zip"
sudo yum install zip -y
sudo yum install unzip -y
#
# install awscli
echo "installing awscli"
curl "https://s3.amazonaws.com/aws-cli/awscli-bundle.zip" -o "awscli-bundle.zip"
unzip awscli-bundle.zip
sudo ./awscli-bundle/install -i /usr/local/aws -b /usr/local/bin/aws
# 
# create and attach ebs volumes
device_list=("/dev/xvdb|20|/u01" "/dev/xvdc|20|none" "/dev/xvdd|20|none" "/dev/xvde|20|none" "/dev/xvdf|20|none" "/dev/xvdg|20|none" "/dev/xvdh|20|none" "/dev/xvdi|20|none" "/dev/xvdj|20|none" "/dev/xvdk|20|none" "/dev/xvdx|20|none" "/dev/xvdt|40|/stage")
instance_id=`echo $(get_instance_id)`
#
for device in "$${device_list[@]}"
do
  #
  fs_device=`echo $$device | awk -F"|" '{print $1}'`
  size=`echo $$device | awk -F"|" '{print $2}'`
  fs_mount=`echo $$device | awk -F"|" '{print $3}'`
  echo "fs_device:$${fs_device}"
  echo "size:$${size}"
  echo "fs_mount:$${fs_mount}"

  # get volume_id for fs_device
  result=$$(get_volume_id "$region" "$avail_zone" "$$fs_device" "$$practice_area")
  echo "result is :$$result"
  echo "-------------------"
  return_code=`echo $$result |awk  -F":" '{print $1}'`
  ebs_volume_id=`echo $$result |awk -F":" '{print $2}'`

  # if aws cmd succeeds and volid does not exist create it
  if [[ ($$return_code -eq 0) && ( -z "$$ebs_volume_id" ) ]]; then
    result=$$(create_volume "$region" "$avail_zone" "$$size" "$$fs_device" "$$practice_area")
    echo "result for create_volume is: $$result"
    return_code=`echo $$result |awk  -F":" '{print $1}'`
    # call get_volume_id
    result=$$(get_volume_id "$region" "$avail_zone" "$$fs_device" "$$practice_area")
    ebs_volume_id=`echo $$result |awk -F":" '{print $2}'`
    # done with call
    ebs_volume_id=`echo $$result |awk -F":" '{print $2}'`
    if [[ ($$return_code -eq 0) && ( -n "$$ebs_volume_id" )]]; then
      echo "Volume for $${fs_device} was newly created with volume_id:$${ebs_volume_id}"
    fi
  elif [[ ($$return_code -eq 0) && ( -n "$$ebs_volume_id" ) ]]; then
    echo "Volume for $${fs_device}  already exists  with volume_id:$${ebs_volume_id}"
  else
    echo "Issue with aws cmd. Please check. exiting"
    exit 1
  fi

  # get volume status for given vol_id
  result=$$(get_volume_status "$$ebs_volume_id" "$region")
  echo "result:$$result"
  return_code=`echo $$result |awk  -F":" '{print $1}'`
  ebs_volume_state=`echo $$result |awk -F":" '{print $2}'`

  # if aws cmd succeeds and volstatus is not attached
  if [[ ($$return_code -eq 0) && ( $${ebs_volume_state} == "available" ) ]]; then
    echo "Volume for $${fs_device} has status: $${ebs_volume_state}"
    result=$$(attach_volume "$$fs_device" "$$instance_id" "$$ebs_volume_id" "$region")
    echo "result:$$result"
    return_code=`echo $$result |awk  -F":" '{print $1}'`
    output=`echo $$result |awk -F":" '{print $2}'`

    if [[ ($$return_code -eq 0)]]; then
       echo "Volume "$$ebs_volume_id" with device "$$fs_device" has been attached to instance "$$instance_id" successfully"
    else
    echo "Issue with aws cmd. Please check. exiting"
    fi
  else
    echo "Volume for $${fs_device} has status: $${ebs_volume_state}"
  fi

  #
  # sleep for /dev/xvd to attach fully to instance
  echo "Sleeping 30 secs.."
  sleep 30 
  # Format /dev/nnn> if it does not contain a partition yet
  if [[ $${fs_mount} != "none" ]]; then
  echo "sudo file -b -s $${fs_device}"
  has_partition=`sudo file -b -s $${fs_device}`
  echo "has_partition:$${has_partition}"
    if [ "$${has_partition}" == "data" ]; then
      sudo mkfs -t ext4 $${fs_device}
    fi
  echo "mounting file system"
      sudo mkdir -p $${fs_mount}
      sudo mount $${fs_device} $${fs_mount}
      # Persist the volume in /etc/fstab so it gets mounted again
      echo "$${fs_device} $${fs_mount} ext4 defaults,nofail 0 2" | sudo tee -a /etc/fstab
  fi
done

# sync software files from s3 to host under /stage
echo "syncing software from s3"
aws s3 sync s3://${rdbms_bucket}/ /stage --exclude "*" --include "*.rpm" --include "*zip" --include "*.rsp"

#unzip binaries
echo "unzipping binaries"
unzip -qo /stage/linuxamd64_12102_database_1of2.zip -d /stage
unzip -qo /stage/linuxamd64_12102_database_2of2.zip -d /stage
unzip -qo /stage/linuxamd64_12102_grid_1of2.zip -d /stage
unzip -qo /stage/linuxamd64_12102_grid_2of2.zip -d /stage

# update security limits
echo "updating security limits"
sed -i 's/4096/16384/g' /etc/security/limits.d/20-nproc.conf
sed -i 's/SELINUX=enforcing/SELINUX=permissive/g' /etc/selinux/config
service iptables stop
systemctl disable iptables.service

# Update Kernel parameters to Oracle Documentation recommended values
echo "updating kernel parameters"
cp /etc/sysctl.conf /etc/sysctl.conf_backup
cat /etc/sysctl.conf | grep -v shmall | grep -v shmmax >/etc/sysctl.conf_txt
mv -f /etc/sysctl.conf_txt /etc/sysctl.conf
echo '#input parameters ' >>/etc/sysctl.conf
echo 'fs.file-max = 6815744' >>/etc/sysctl.conf
echo 'kernel.sem = 250 32000 100 128' >>/etc/sysctl.conf
echo 'kernel.shmmni = 4096' >>/etc/sysctl.conf
echo kernel.shmall = ${shmall} >>/etc/sysctl.conf
echo kernel.shmmax = ${shmmax} >>/etc/sysctl.conf
echo 'net.core.rmem_default = 262144' >>/etc/sysctl.conf
echo 'net.core.rmem_max = 4194304' >>/etc/sysctl.conf
echo 'net.core.wmem_default = 262144' >>/etc/sysctl.conf
echo 'net.core.wmem_max = 1048576' >>/etc/sysctl.conf
echo 'fs.aio-max-nr = 1048576' >>/etc/sysctl.conf
echo 'net.ipv4.ip_local_port_range = 9000 65500' >>/etc/sysctl.conf
# Activate Kernel parameter updated
/sbin/sysctl -p

# Update user limit for Oracle limits recommended values
echo "updating user limits"
cp /etc/security/limits.conf /etc/security/limits.conf_backup
cat /etc/security/limits.conf | grep -v End >/etc/security/limits.conf_txt
mv -f /etc/security/limits.conf_txt /etc/security/limits.conf
echo '#input parameters added from bootstrap script' >>/etc/security/limits.conf
echo 'oracle   soft   nofile    1024' >>/etc/security/limits.conf
echo 'oracle   hard   nofile    65536' >>/etc/security/limits.conf
echo 'oracle   soft   nproc    16384' >>/etc/security/limits.conf
echo 'oracle   hard   nproc    16384' >>/etc/security/limits.conf
echo 'oracle   soft   stack    10240' >>/etc/security/limits.conf
echo 'oracle   hard   stack    32768' >>/etc/security/limits.conf
echo '# End of file' >>/etc/security/limits.conf

# Create Oracle user
echo "create oracle user"
groupadd -g 54321 oinstall
groupadd -g 54322 dba
groupadd -g 54323 oper
useradd -u 54321 -g oinstall -G dba,oper oracle

# create grid and rdbms home directories
echo "create grid and rdbms home directories"
mkdir -p /u01/app/oracle/product/12c/db_1
mkdir -p /u01/app/oracle/product/12c/grid

# install asm modules
echo "installing asm modules"
install_packages kmod-oracleasm
install_packages oracleasm-support
rpm -Uvh /stage/oracleasmlib-2.0.12-1.el7.x86_64.rpm

# change permissions to oracle:oinstall on /u01 and /stage
chown -R oracle:oinstall /u01 /stage
chmod -R 775 /u01 /stage

#Configure oracleasm module and initialize it
echo "configure oracleasm module"
oracleasm configure -u oracle -g dba -b -s y -e
oracleasm init

# Make partitions to the ASM RECO and DATA disks
echo "making partitions for ASM RECO and DATA disks"
echo -e 'o\nn\np\n1\n\n\nw' | fdisk /dev/xvdc
echo -e 'o\nn\np\n1\n\n\nw' | fdisk /dev/xvdd
echo -e 'o\nn\np\n1\n\n\nw' | fdisk /dev/xvde
echo -e 'o\nn\np\n1\n\n\nw' | fdisk /dev/xvdf
echo -e 'o\nn\np\n1\n\n\nw' | fdisk /dev/xvdg
echo -e 'o\nn\np\n1\n\n\nw' | fdisk /dev/xvdh
echo -e 'o\nn\np\n1\n\n\nw' | fdisk /dev/xvdi
echo -e 'o\nn\np\n1\n\n\nw' | fdisk /dev/xvdj
echo -e 'o\nn\np\n1\n\n\nw' | fdisk /dev/xvdk
sync
# Updated DISK headers to assign an ASM DISKGROUP
echo "oracleasm creating disks..."
oracleasm createdisk RECO1 /dev/xvdc1  || echo "success"
oracleasm createdisk RECO2 /dev/xvdd1  || echo "success"
oracleasm createdisk RECO3 /dev/xvde1  || echo "success"
oracleasm createdisk DATA1 /dev/xvdf1  || echo "success"
oracleasm createdisk DATA2 /dev/xvdg1  || echo "success"
oracleasm createdisk DATA3 /dev/xvdh1  || echo "success"
oracleasm createdisk DATA4 /dev/xvdi1  || echo "success"
oracleasm createdisk DATA5 /dev/xvdj1  || echo "success"
oracleasm createdisk DATA6 /dev/xvdk1  || echo "success"
# Restart oracleasm
oracleasm init
# install kernel packages
YUM_PACKAGES=(
    xorg-x11-xauth.x86_64
    xorg-x11-server-utils.x86_64
    dbus-x11.x86_64
    binutils
    compat-libcap1
    gcc
    gcc-c++
    glibc
    glibc.i686
    glibc-devel
    glibc-devel.i686
    ksh
    libgcc
    libgcc.i686
    libstdc++
    libstdc++.i686
    libstdc++-devel
    libstdc++-devel.i686
    libaio
    libaio.i686
    libaio-devel
    libaio-devel.i686
    libXext
    libXext.i686
    libXtst
    libXtst.i686
    libX11
    libX11.i686
    libXau
    libXau.i686
    libxcb
    libxcb.i686
    libXi
    libXi.i686
    make
    sysstat
    unixODBC
    unixODBC-devel
    java
    compat-libstdc++-33
)
echo "installing yum packages"
install_packages $${YUM_PACKAGES[@]}
# Update Oracle user profile
echo "export TMP=/tmp" >>/home/oracle/.bash_profile
echo "export TMPDIR=/tmp" >>/home/oracle/.bash_profile
echo "export ORACLE_BASE=/u01/app/oracle" >>/home/oracle/.bash_profile
echo "export ORACLE_HOME=/u01/app/oracle/product/12c/db_1" >>/home/oracle/.bash_profile
echo "export ORACLE_SID=TESTDB" >>/home/oracle/.bash_profile
echo "export PATH=/usr/sbin:$$PATH" >>/home/oracle/.bash_profile
echo "export PATH=/u01/app/oracle/product/12c/db_1/bin:$$PATH" >>/home/oracle/.bash_profile
echo "export LD_LIBRARY_PATH=/u01/app/oracle/product/12c/db_1/lib:/lib:/usr/lib" >>/home/oracle/.bash_profile
echo "export CLASSPATH=/u01/app/oracle/product/12c/db_1/jlib:/u01/app/oracle/product/12c/db_1/rdbms/jlib" >>/home/oracle/.bash_profile
# Make a SWAP space available and update fsta
mkswap /dev/xvdx
swapon /dev/xvdx
echo "/dev/xvdx    swap      swap    defaults       0 0">>/etc/fstab
# Update permission for Oracle user to sudo and to ssh
echo "updating oracle user sudo access"
mkdir -p /home/oracle/.ssh
cp /home/ec2-user/.ssh/authorized_keys /home/oracle/.ssh/.
chown oracle:dba /home/oracle/.ssh /home/oracle/.ssh/authorized_keys
chmod 600 /home/oracle/.ssh/authorized_keys
echo "oracle ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
REQ_TTY=0
if [ $$(cat /etc/sudoers | grep '^Defaults' | grep -c '!requiretty') -eq 0 ] ; then
    sed -i 's/requiretty/!requiretty/g' /etc/sudoers
    REQ_TTY=1
fi

#Install Oracle Grid infrastructure using grid-setup.rsp parameter file, to /u01/app/oracle/product/12c/grid home
echo "silent install grid infrahome"
HOSTN=`curl -s -m 30 'http://169.254.169.254/latest/meta-data/hostname'`
sed -i s/changehostname/$${HOSTN}/g /stage/*.rsp 
sed -i s/ASM_PASS/${asmpass}/g /stage/*.rsp 
sed -i s/DATABASE_PORT/${dbport}/g /stage/*.rsp 
/stage/grid/runInstaller -silent -ignorePrereq -responsefile /stage/grid-setup.rsp &>> /tmp/oracleexec.log
# Wait until the installer asks for root.sh running scripts as this is asynchronous from shell execution
timeout 900 grep -q '1. /u01/app/oraInventory/orainstRoot.sh' <(tail -f /tmp/oracleexec.log)
echo runInstaller_end &>> /tmp/oracleexec.log


echo "end of bootstrap.sh script"
