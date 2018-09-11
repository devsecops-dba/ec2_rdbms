connect / as sysdba
set pages 1000 line 150
spool /tmp/dbsetup.log
alter system set db_recovery_file_dest_size='2G' scope=both;
alter system set db_recovery_file_dest='+RECO' scope=both;
ALTER DATABASE FORCE LOGGING;
ALTER DATABASE ADD LOGFILE MEMBER   '+RECO' TO GROUP 1;
ALTER DATABASE ADD LOGFILE MEMBER   '+RECO' TO GROUP 2;
ALTER DATABASE ADD LOGFILE MEMBER   '+RECO' TO GROUP 3;
alter system set db_recovery_file_dest='+RECO' scope = both;
ALTER SYSTEM SET LOG_ARCHIVE_FORMAT='TESTDB_%t_%s_%r.arc' SCOPE=SPFILE;
alter system set LOG_ARCHIVE_DEST_1='LOCATION=USE_DB_RECOVERY_FILE_DEST VALID_FOR=(ALL_LOGFILES,ALL_ROLES) DB_UNIQUE_NAME=TESTDB';
SHUTDOWN IMMEDIATE;
STARTUP MOUNT;
ALTER DATABASE ARCHIVELOG;
ALTER DATABASE OPEN;
select status from v$database d where d.LOG_MODE='ARCHIVELOG' and 'OPEN' = (select status from v$instance);
spool off
exit