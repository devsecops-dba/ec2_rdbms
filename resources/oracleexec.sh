#!/bin/bash -e
#silent install grid-infra
/stage/grid/runInstaller -silent -ignorePrereq -responsefile /stage/grid-setup.rsp &>> /tmp/oracleexec.log
# Wait until the installer asks for root.sh running scripts as this is asynchronous from shell execution
timeout 900 grep -q '1. /u01/app/oraInventory/orainstRoot.sh' <(tail -f /tmp/oracleexec.log)
echo runInstaller_end &>> /tmp/oracleexec.log
echo "execute:-> oraInstRoot.sh" &>> /tmp/oracleexec.log
echo "----------------------------" &>> /tmp/oracleexec.log
sudo /u01/app/oraInventory/orainstRoot.sh &>> /tmp/oracleexec.log
echo "execute:-> run grid root.sh" &>> /tmp/oracleexec.log
echo "----------------------------" &>> /tmp/oracleexec.log
sudo /u01/app/oracle/product/12c/grid/root.sh &>> /tmp/oracleexec.log
echo "execute:-> configTollAllCommands" &>> /tmp/oracleexec.log
echo "----------------------------" &>> /tmp/oracleexec.log
/u01/app/oracle/product/12c/grid/cfgtoollogs/configToolAllCommands RESPONSE_FILE=/stage/asm-config.rsp || echo "success" &>> /tmp/oracleexec.log
echo "create diskgroups.." &>> /tmp/oracleexec.log
echo "----------------------------" &>> /tmp/oracleexec.log
/u01/app/oracle/product/12c/grid/bin/asmca -silent -createDiskGroup -sysAsmPassword ${asmpass} -asmsnmpPassword ${asmpass} -diskGroupName RECO -diskList ORCL:RECO1,ORCL:RECO2,ORCL:RECO3 -redundancy EXTERNAL &>> /tmp/oracleexec.log
#silent install rdbms home
/stage/database/runInstaller -silent -ignorePrereq -responsefile /stage/db-config.rsp &>> /tmp/oracleexec.log
# Wait until the installer asks for root.sh running scripts as this is asynchronous from shell execution
timeout 900 grep -q '1. /u01/app/oracle/product/12c/db_1/root.sh' <(tail -f /tmp/oracleexec.log)
# Execute the root.sh to configure and give correct oratab and permissions
sudo /u01/app/oracle/product/12c/db_1/root.sh &>> /tmp/oracleexec.log
# Run configToolAllCommands to configure database using db-post-rsp
/u01/app/oracle/product/12c/db_1/cfgtoollogs/configToolAllCommands RESPONSE_FILE=/stage/db-post.rsp &>> /tmp/oracleexec.log
# Setup oracle Database variables
export ORACLE_SID=TESTDB
export ORACLE_HOME=/u01/app/oracle/product/12c/db_1
export PATH=/u01/app/oracle/product/12c/db_1/bin:${PATH}
# Run SQLPLUS to update parameter files, setup ARCHIVELOG mode and LOGFILES
sqlplus /nolog @/stage/dbsetup.sql &>> /tmp/oracleexec.log