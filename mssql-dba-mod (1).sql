-- DBA Notes --
--
-- Started by Viet H.  2014
-- 
-- These notes are broken out into two parts.    This file contains scripts that can do severe damage to a SQL Instance.   Test it out.



-- Shrinking a Log File
USE [OAuthSession]
DBCC SHRINKFILE ('OAuthSession_log', TRUNCATEONLY);
GO
-- Wait for backup so current vlf resets to 1, and repeat as needed
-- Resize to projected max + 20%.
ALTER DATABASE [OAuthSession] MODIFY FILE ( NAME = N'OAuthSession_log', SIZE = 2GB )

-- Increase max size of a file.    Remember to check that autogrowth is on.
ALTER DATABASE SDE MODIFY FILE ( NAME = 'SDE_Data', MAXSIZE = 3GB )

-- Changes recovery Model for a database.
ALTER DATABASE PrimeAlliance SET RECOVERY SIMPLE;

--generate job disable
SELECT 'exec msdb..sp_update_job @job_name = '''+NAME+''', @enabled = 0' FROM msdb..sysjobs where enabled = 1 order by len(name)

-- Create Script to Change all to Simple in TEST Databases
select 'ALTER DATABASE [' + name + '] SET RECOVERY SIMPLE;' from sys.databases where recovery_model_desc != 'SIMPLE' and state = 0;


select 'ALTER DATABASE [' + name + '] SET RECOVERY FULL; BACKUP DATABASE [' + name + '] TO DISK = ''NUL:'' WITH STATS = 10' from sys.databases where replica_id is null and database_id > 4;

-- Generic Copy Backup
DECLARE @dbname nvarchar(max), @bklocation nvarchar(max), @sql nvarchar(max)

SET @dbname = '';

SET @bklocation = N'\\RK-CBARESTORE01\G_Backups\' + replace(@@SERVERNAME,'\','_') + '_' + @dbname + '_' + replace(replace(CONVERT(nvarchar(30), GETDATE(), 120),':',''),' ','_') + '.bak';
SET @sql = 'BACKUP DATABASE [' + @dbname + '] TO  DISK = ''' + @bklocation + ''' WITH  COPY_ONLY, NOFORMAT, COMPRESSION, NOINIT,  NAME = N''' + @dbname + '-Full Database Backup'', SKIP, NOREWIND, NOUNLOAD,  STATS = 10';

select @bklocation;
select @sql;

exec sp_executesql @sql;

-- Good Windows Disk IO Tester

SQLIO -kW -s10 -o8 -b8 -t4 f:\testfile.dat
del f:\testfile.dat

-- Temp Install Telnet
Add-WindowsFeature Telnet-Client
Remove-WindowsFeature Telnet-Client

-- Install .NET 3.5 on Azure Datacenter 2012 R2
Get-WindowsFeature NET-Framework-Core
Install-WindowsFeature NET-Framework-Core -source \\roc-itutil01\Apps\sxs
Remove-WindowsFeature NET-Framework-Core


-- Backup Details:
RESTORE HEADERONLY
FROM DISK = N'\\RK-CBARESTORE01\G_Backups\Digital\040115\SQLTIER1C_TIER1_03\Eflow\f-0.stream0'
GO

-- Vaporize Logs (and any chance of point in time recovery)
DECLARE @droplog_sql NVARCHAR(MAX);

SET @droplog_sql = '';
SELECT @droplog_sql = @droplog_sql + 
'USE [' + d.name + ']; DBCC SHRINKFILE (''' + f.name + ''', TRUNCATEONLY); BACKUP LOG [' + d.name + '] TO DISK = ''NUL:'' WITH STATS = 10; DBCC SHRINKFILE (''' + f.name + ''', TRUNCATEONLY);' + char(13)
FROM sys.databases d
	INNER JOIN sys.master_files f ON d.database_id = f.database_id
	INNER JOIN sys.dm_hadr_availability_replica_states ars ON d.replica_id = ars.replica_id
WHERE f.type_desc = 'LOG' and f.state = 0 and ars.role_desc = 'PRIMARY' and size > (128 * 50)
ORDER BY size DESC;
PRINT @droplog_sql;
EXEC sp_executesql @droplog_sql;

-- Basic restore with stats.
USE [master]
ALTER DATABASE [AkcelerantPF] SET SINGLE_USER WITH ROLLBACK IMMEDIATE
RESTORE DATABASE [AkcelerantPF] FROM  DISK = N'K:\backups\AkcelerantPF_041515.Bak' WITH  FILE = 1, NOUNLOAD,  REPLACE,  STATS = 2
GO

-- Create Script to Move from Percentage Growth

SELECT 
	'ALTER DATABASE [' + d.name + '] MODIFY FILE ( NAME = N''' + f.name + ''', FILEGROWTH = ' + 
		CASE f.type WHEN 0 THEN '512MB' ELSE '256MB' END + ' )',
f.name, f.*, d.*
FROM sys.databases d WITH (NOLOCK)
  INNER JOIN sys.master_files f WITH (NOLOCK) ON d.database_id = f.database_id
WHERE is_percent_growth = 1 AND (d.database_id > 4 OR d.database_id = 3) and d.state = 0
ORDER BY 1;

SELECT 
	'ALTER DATABASE [' + d.name + '] MODIFY FILE ( NAME = N''' + f.name + ''', FILEGROWTH = ' + 
		CASE f.type WHEN 0 THEN '256MB' ELSE '128MB' END + ' )',
f.name, f.*, d.*
FROM sys.databases d WITH (NOLOCK)
  INNER JOIN sys.master_files f WITH (NOLOCK) ON d.database_id = f.database_id
WHERE (d.database_id > 4 OR d.database_id = 3) and d.state = 0 and f.is_percent_growth = 0 and f.growth <= 64 * 128
ORDER BY 1;

-- Change owner of a database - May need a sp_dropuser first if it complains.
USE [OAuthSession]
sp_changedbowner 'sa'


USE [AccessManagement]
DBCC SHRINKFILE ('AccessManagement_log', TRUNCATEONLY);
GO
ALTER DATABASE [AccessManagement_log] MODIFY FILE ( NAME = N'E:\SQLLogs\AccessManagement_log.ldf', FILEGROWTH = 256MB, SIZE = 512MB);
GO

--recover sysadmin (creates user if not exist - works up to 2008R2)
psexec -s \\ROC-BADGE02 sqlcmd -W -S .\ -Q "select @@SERVERNAME, @@SERVICENAME, isnull(max(SYSTEM_USER),SYSTEM_USER), MAX(sysadmin) from master.dbo.syslogins where loginname = system_user" 

psexec -s \\ROC-BADGE02 sqlcmd -S .\ -Q "exec sp_addsrvrolemember 'FTFCU\SG-sqldba','sysadmin'"

--system details:
psexec -s \\WEST-AKCELCMC01 sqlcmd -W -S .\SQLEXPRESS -Q "select @@SERVERNAME, @@SERVICENAME, isnull(max(SYSTEM_USER),SYSTEM_USER), MAX(sysadmin), SERVERPROPERTY('productversion'), SERVERPROPERTY ('productlevel'), SERVERPROPERTY ('edition') from master.dbo.syslogins where loginname = system_user"

psexec -s \\BVTN-CALLREX02 sqlcmd -W -S .\SQLEXPRESS -Q "select @@SERVERNAME, @@SERVICENAME, isnull(max(SYSTEM_USER),SYSTEM_USER), MAX(sysadmin), SERVERPROPERTY('productversion'), SERVERPROPERTY ('productlevel'), SERVERPROPERTY ('edition') from master.dbo.syslogins where loginname = system_user"

psexec -s \\BVTN-CALLREX02 sqlcmd -S .\SQLEXPRESS -Q "exec sp_addsrvrolemember 'FTFCU\SG-sqldba','sysadmin'"

psexec -s \\WEST-AKCELCMC01 sqlcmd -S .\SQLEXPRESS -Q "exec sp_addsrvrolemember 'FTFCU\SG-sqldba','sysadmin'"

exec sp_addsrvrolemember N'NT AUTHORITY\SYSTEM','sysadmin'

--Configuration Manager : Remote
SQLServerManager10.msc /32 /COMPUTER:rk-sql2008-lab1
SQLServerManager11.msc /32 /COMPUTER:lab-csql2012a


--splunk 2012+
--USE [model]
--CREATE USER [NT AUTHORITY\SYSTEM] FOR LOGIN [NT AUTHORITY\SYSTEM]
--EXEC sp_addrolemember N'db_datareader', N'NT AUTHORITY\SYSTEM'
--USE [master]
--GRANT VIEW ANY DEFINITION TO [NT AUTHORITY\SYSTEM];
--GO

-- sample detach / attach

use [master];
go
alter database [avail] set single_user with rollback immediate;
go
alter database [avail] set read_only;
go
alter database [avail] set multi_user;
go

exec master.dbo.sp_detach_db @dbname=N'avail';

create database avail
on (filename = 'E:\MSSQL10_50.TIER8_01\MSSQL\DATA\avail.mdf'),(filename = 'E:\MSSQL10_50.TIER8_01\MSSQL\DATA\avail_1.ldf')
 for attach;
 
-- scripted detach cmd generator
SELECT 'ALTER DATABASE [' + DB_NAME(p1.database_id) + '] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; ' + 
       'EXEC sp_detach_db @dbname = ''' + DB_NAME(p1.database_id) + ''', @skipchecks = ''true''; ' as db_detach,
       'CREATE DATABASE [' + DB_NAME(p1.database_id) + '] ON ' +
        stuff( (SELECT ',' + '(FILENAME = ''' + physical_name + ''')' 
                FROM sys.master_files p2
                WHERE p2.database_id = p1.database_id
                ORDER BY physical_name
                FOR XML PATH(''), TYPE).value('.', 'varchar(max)')
             ,1,1,'') + ' FOR ATTACH;'
       AS db_attach
FROM sys.master_files p1
WHERE database_id > 4
GROUP BY database_id;

-- test script.

SELECT 
'BACKUP DATABASE ' + quotename(d.name) + ' TO DISK = ''I:\WorkSpace\' + d.name + '.bak'' WITH INIT, COPY_ONLY, STATS = 5'
FROM sys.databases d
	INNER JOIN sys.dm_hadr_availability_replica_states ars ON d.replica_id = ars.replica_id
 
 
 -- Not fully tested
alter database [dba_admin_mirror01] set partner off;
restore database [dba_admin_mirror01] with recovery;
alter database [dba_admin_mirror01] set offline with rollback immediate;

alter database rtcshared set partner resume

alter DATABASE rtcshared set partner failover

--Remove Auto_Close
declare @sql nvarchar(max);
set @sql = '';

select @sql = @sql + 'alter database [' + name + '] set auto_close off;' + char(13) FROM sys.databases where state = 0 and is_auto_close_on = 1;
select @sql

exec sp_executesql @sql;


-- Move the location of the TEMPDB
use master
go
Alter database tempdb modify file (name = tempdev, filename = 'L:\TempDB\tempdb.mdf')
go
Alter database tempdb modify file (name = templog, filename = 'M:\TempDBLog\templog.ldf')
go

EXEC sys.sp_configure N'show advanced options', N'1'
GO
RECONFIGURE WITH OVERRIDE
GO
EXEC sys.sp_configure N'max degree of parallelism', N'2'
GO
RECONFIGURE WITH OVERRIDE
GO
EXEC sp_configure 'cost threshold for parallelism', 10;
GO
RECONFIGURE WITH OVERRIDE
GO

DBCC SQLPERF ('sys.dm_os_wait_stats', CLEAR);

select 
  'exec msdb.dbo.sp_help_jobstep @job_name = ''' + name + '''',
  sj.* 
from msdb.dbo.sysjobs sj
order by LEN(name);


--

--Move System DB:

USE master;
GO
ALTER DATABASE tempdb 
MODIFY FILE (NAME = tempdev, FILENAME = 'C:\SQLData\tempdb.mdf');
GO
ALTER DATABASE tempdb 
MODIFY FILE (NAME = templog, FILENAME = 'C:\SQLData\templog.ldf');
GO
ALTER DATABASE model 
MODIFY FILE (NAME = modeldev, FILENAME = 'C:\SQLData\model.mdf');
GO
ALTER DATABASE model 
MODIFY FILE (NAME = modellog, FILENAME = 'C:\SQLData\modellog.ldf');
GO
ALTER DATABASE msdb 
MODIFY FILE (NAME = MSDBData, FILENAME = 'C:\SQLData\MSDBData.mdf');
GO
ALTER DATABASE msdb 
MODIFY FILE (NAME = MSDBLog, FILENAME = 'C:\SQLData\MSDBLog.ldf');
GO

alter database tempdb modify file (name = templog, filename = 'E:\TempDBLog\templog.ldf')
go
alter database tempdb modify file (name = tempdev1, filename = 'E:\TempDB\tempdb1.mdf')
go
alter database tempdb modify file (name = tempdev2, filename = 'E:\TempDB\tempdb2.mdf')
go
alter database tempdb modify file (name = tempdev3, filename = 'E:\TempDB\tempdb3.mdf')
go
alter database tempdb modify file (name = tempdev4, filename = 'E:\TempDB\tempdb4.mdf')
go

use master
go
alter database tempdb modify file (name = templog, filename = 'M:\TempDBLog\templog.ldf')
go
alter database tempdb modify file (name = tempdev1, filename = 'L:\TempDB\tempdb1.mdf')
go
alter database tempdb modify file (name = tempdev2, filename = 'L:\TempDB\tempdb2.mdf')
go
alter database tempdb modify file (name = tempdev3, filename = 'L:\TempDB\tempdb3.mdf')
go
alter database tempdb modify file (name = tempdev4, filename = 'L:\TempDB\tempdb4.mdf')
go



-- Split TempDB (assumes not changed before)

select 'ALTER DATABASE ' + QUOTENAME(db_name(database_id)) + ' MODIFY FILE (NAME=N''' + name + ''', NEWNAME= N''' + name + '1'')' from sys.master_files where database_id = 2 and name = 'tempdev' union all
select 'ALTER DATABASE ' + QUOTENAME(db_name(database_id)) + ' MODIFY FILE (NAME=N''' + name + '1'', FILENAME= N''' + replace(physical_name,'.mdf','1.mdf') + ''', SIZE = 512MB , FILEGROWTH = 1024MB)' from sys.master_files where database_id = 2 and name = 'tempdev' union all
select 'ALTER DATABASE ' + QUOTENAME(db_name(database_id)) + ' ADD FILE (NAME=N''' + name + '2'', FILENAME= N''' + replace(physical_name,'.mdf','2.mdf') + ''', SIZE = 512MB , FILEGROWTH = 1024MB)' from sys.master_files where database_id = 2 and name = 'tempdev' union all
select 'ALTER DATABASE ' + QUOTENAME(db_name(database_id)) + ' ADD FILE (NAME=N''' + name + '3'', FILENAME= N''' + replace(physical_name,'.mdf','3.mdf') + ''', SIZE = 512MB , FILEGROWTH = 1024MB)' from sys.master_files where database_id = 2 and name = 'tempdev' union all
select 'ALTER DATABASE ' + QUOTENAME(db_name(database_id)) + ' ADD FILE (NAME=N''' + name + '4'', FILENAME= N''' +replace(physical_name,'.mdf','4.mdf') + ''', SIZE = 512MB , FILEGROWTH = 1024MB)' from sys.master_files where database_id = 2 and name = 'tempdev'

-- Remove file

USE tempdb
GO
DBCC SHRINKFILE (tempdev_Data02, EMPTYFILE);
DBCC SHRINKFILE (tempdev_Data03, EMPTYFILE);
DBCC SHRINKFILE (tempdev_Data04, EMPTYFILE);
GO 
ALTER DATABASE tempdb REMOVE FILE tempdev_Data02 
ALTER DATABASE tempdb REMOVE FILE tempdev_Data03 
ALTER DATABASE tempdb REMOVE FILE tempdev_Data04 

-- clone login
select 'create login [' + name + '] with password = ' 
      + master.dbo.fn_varbintohexstr(password_hash) + ' hashed, sid = '
      + master.dbo.fn_varbintohexstr(sid) + ', default_database = [' 
      + default_database_name + ']'
      + case is_policy_checked when 0 then ', check_policy = off' when 1 then ', check_policy = on' else '' end
      + case is_expiration_checked when 0 then ', check_expiration = off' when 1 then ', check_expiration = on' else '' end
      , *
from sys.sql_logins where is_disabled = 0 and name not in ('sa');

select 'create login ' + QUOTENAME(name) + ' from windows with default_database = [' + dbname + ']'
, * from sys.syslogins where 1 in (isntgroup, isntname) and denylogin = 0 and name not like 'NT %\%';

select 'EXEC master..sp_addsrvrolemember @loginame = N''' + name + ''', @rolename = N''sysadmin'''
from sys.syslogins where sysadmin = 1 and denylogin = 0 and name not in ('sa') and name not like 'NT %\%';

-- Broken Logins / Orphaned Users (use next block :: login analysis)
declare @sp_change_users_login table (dbname sysname null, UserName sysname, UserSID varbinary(85))

declare @databases table (itr int identity, dbname sysname);
declare @itr int, @total int, @dbname sysname, @sql nvarchar(1024), @uptime int;

select @uptime = datediff(minute,create_date,getdate()) from sys.databases where NAME='tempdb'

insert into @databases (dbname) select name from sys.databases where state = 0 and database_id > 4;
select @itr = min(itr), @total = count(*) from @databases;

while @itr <= @total
begin
	select @itr = itr + 1, @dbname = dbname from @databases where itr = @itr;
	set @sql = 'use [' + @dbname + ']; EXEC sp_change_users_login ''Report'';'
	insert into @sp_change_users_login (UserName, UserSID)
		exec sp_executesql @sql;
	update @sp_change_users_login set dbname = @dbname where dbname is null;
end

select UserName, UserSID, isnull(replace(upper(master.dbo.fn_varbintohexstr(sl.sid)),'0X','0x'), 'Missing Login') as LoginSID, cul.dbname,
	case when sl.sid is not null then
		'use [' + cul.dbname + ']; EXEC sp_change_users_login ''update_one'', ''' + UserName + ''', ''' + UserName + ''';' 
	end as FixSidDiffSql
from @sp_change_users_login cul left join sys.syslogins sl on cul.UserName = sl.name;

--- login vs db user analysis

declare @logins table (dbname sysname, name sysname, utype char(1), schema_id int, schema_name sysname null, object_ct int, dbsid varchar(85), loginsid varchar(85))
declare @dblist table (dbname sysname);
declare @dbsql nvarchar(max), @sql nvarchar(max);

select @dbsql = case when db_name() != 'master' then 'select ''' + db_name() + '''' when SERVERPROPERTY('IsHadrEnabled') is null then 'select name from sys.databases where database_id > 4 and state = 0 and is_read_only = 0' else 'select name from sys.databases d LEFT JOIN sys.dm_hadr_availability_replica_states ars ON d.replica_id = ars.replica_id where database_id > 4 and state = 0 and isnull(ars.role,1) = 1 and is_read_only = 0' end
insert into @dblist
   exec sp_executesql @dbsql

set @sql = ''
select @sql = @sql + 'select ''' + dbname + ''' as dbname, db.name, db.type, s.schema_id, s.name, (select count(*) from ' + QUOTENAME(dbname) + '.sys.objects where schema_id = s.schema_id), replace(upper(master.dbo.fn_varbintohexstr(db.sid)),''0X'',''0x''), replace(upper(master.dbo.fn_varbintohexstr(sl.sid)),''0X'',''0x'') from ' + QUOTENAME(dbname) + '.sys.database_principals db left join sys.syslogins sl on db.name COLLATE Latin1_General_CI_AI = sl.name COLLATE Latin1_General_CI_AI left join sys.sql_logins slo on db.name COLLATE Latin1_General_CI_AI = slo.name COLLATE Latin1_General_CI_AI left join ' + QUOTENAME(dbname) + '.sys.schemas s on s.principal_id = db.principal_id where db.type in (''S'',''U'') and db.principal_id > 4;' from @dblist;
	insert into @logins
		exec sp_executesql @sql

select l.*, 
	case 
	when loginsid is null and utype = 'U' then 'use master; create login ' + QUOTENAME(name) + ' from windows with default_database = [' + dbname + '];' 
	when loginsid is null and utype = 'S' then '--Build out user with correct password.' 
	when loginsid != dbsid then 'use [' + dbname + ']; EXEC sp_change_users_login ''update_one'', ''' + name + ''', ''' + name + ''';' 
	else '' end as fix1,
	case 
	when (loginsid != dbsid or loginsid is null) and schema_id is null then 'use [' + dbname + ']; drop user ' + quotename(name) + ';' 
	when (loginsid != dbsid or loginsid is null) and schema_id is not null and object_ct = 0 then 'use [' + dbname + ']; drop schema ' + quotename(schema_name) + '; drop user ' + quotename(name) + ';' 
	else '' end as fix2
from @logins l
order by dbname, name


-- db roles :: useful to run before restoring from production
select 
	roles.name Role_Name,
	members.name Member_Name,
	'exec sp_addrolemember ['+
	roles.name+
	'], ['+
	members.name+
	']' Grant_Permission
from sys.database_principals members
inner join sys.database_role_members drm
	on members.principal_id = drm.member_principal_id
inner join sys.database_principals roles
	on drm.role_principal_id = roles.principal_id
where members.name <> 'dbo'

-- Remove Foreign Keys for Truncate :

sp_fkeys 'Tokens'

set nocount on
declare @table sysname
declare @schema sysname

select @table = 'Sessions',  @schema = 'dbo'

print '/*Drop Foreign Key Statements for ['+@schema+'].['+@table+']*/'

select 'ALTER TABLE ['+SCHEMA_NAME(o.schema_id)+'].['+ o.name+'] DROP CONSTRAINT ['+fk.name+']'
from sys.foreign_keys fk
inner join sys.objects o on fk.parent_object_id = o.object_id
where o.name = @table and SCHEMA_NAME(o.schema_id)  = @schema
          
print '/*Create Foreign Key Statements for ['+@schema+'].['+@table+']*/'
select 'ALTER TABLE ['+SCHEMA_NAME(o.schema_id)+'].['+o.name+'] ADD CONSTRAINT ['+fk.name+'] FOREIGN KEY (['+c.name+']) 
REFERENCES ['+SCHEMA_NAME(refob.schema_id)+'].['+refob.name+'](['+refcol.name+'])'
from sys.foreign_key_columns fkc
inner join sys.foreign_keys fk on fkc.constraint_object_id = fk.object_id
inner join sys.objects o on fk.parent_object_id = o.object_id
inner join sys.columns c on fkc.parent_column_id = c.column_id and o.object_id = c.object_id
inner join sys.objects refob on fkc.referenced_object_id = refob.object_id 
inner join sys.columns refcol on fkc.referenced_column_id = refcol.column_id and fkc.referenced_object_id = refcol.object_id
where o.name = @table and SCHEMA_NAME(o.schema_id)  = @schema

-- Network Backup/Restore, Assign a temp drive letter for SSMS to use

select name, value, value_in_use from sys.configurations where name in ('show advanced options', 'xp_cmdshell');
GO
-- Set to 1 where 0
sp_configure 'show advanced options', 1
reconfigure with override
GO
sp_configure 'xp_cmdshell' , 1 
reconfigure with override
GO
-- confirm we're FTFCU\svc-sqldbeng and map restore server to R:  << infosec will knock at your door here.
exec xp_cmdshell 'whoami'
GO
exec xp_cmdshell 'net use R: \\rk-cbarestore01\backups'
GO
-- Go back to the way they were
sp_configure 'xp_cmdshell' , 0 
reconfigure with override
GO
sp_configure 'show advanced options', 0
reconfigure with override
GO
exec xp_fixeddrives 1
GO
-- cleanup
exec xp_cmdshell 'net use R: /delete'
GO

-- Test Compression benefit
EXEC sp_estimate_data_compression_savings 'dbo', 'ASSOCIATION', NULL, NULL, 'ROW';
EXEC sp_estimate_data_compression_savings 'dbo', 'RESUL_TRANSACTIONS', NULL, NULL, 'PAGE';

-- Compress Table, set maxdop = CPU/2.
ALTER TABLE dbo.TRANSACTION0 REBUILD WITH (DATA_COMPRESSION = PAGE, ONLINE = ON, SORT_IN_TEMPDB = ON, MAXDOP = 2); 

-- Compress scripting
SELECT s.Name AS SchemaName, t.NAME AS TableName, i.name as IndexName, p.rows AS RowCounts,
    SUM(a.total_pages) / 128 AS TotalSpaceMB, SUM(a.used_pages) / 128 AS UsedSpaceMB, (SUM(a.total_pages) - SUM(a.used_pages)) / 128 AS UnusedSpaceMB,
    REPLACE(p.data_compression_desc,'NONE','') [Compression],
    CASE WHEN p.data_compression_desc = 'NONE' and SERVERPROPERTY('EngineEdition') = 3 THEN
		CASE WHEN i.name IS NULL THEN 'ALTER TABLE ' ELSE 'ALTER INDEX ' + QUOTENAME(i.name) + ' ON ' END
		+ QUOTENAME(s.Name) + '.' + QUOTENAME(t.Name) + ' REBUILD PARTITION = ALL WITH (DATA_COMPRESSION = PAGE, ONLINE = ON, SORT_IN_TEMPDB = ON, MAXDOP = 2);'
    END Compress_SQL, t.create_date
FROM sys.tables t
INNER JOIN sys.indexes i ON t.OBJECT_ID = i.object_id
INNER JOIN sys.partitions p ON i.object_id = p.OBJECT_ID AND i.index_id = p.index_id
INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
LEFT OUTER JOIN sys.schemas s ON t.schema_id = s.schema_id
WHERE t.NAME NOT LIKE 'dt%' 
    AND t.is_ms_shipped = 0
    AND i.OBJECT_ID > 255 
GROUP BY s.Name, t.Name, i.name, p.Rows, p.data_compression_desc, t.create_date
ORDER BY TotalSpaceMB desc;

-- Tail log backup
alter database cw set online;
backup log cw to disk = 'e:\backups\cw_log_tail.bck' with init, no_truncate;

-- Fix @@ServerName - Occurs when system is cloned.
SELECT ServerProperty('machinename') as [machinename]
    ,ServerProperty('ServerName') as [ServerName]
    ,@@ServerName as [@@ServerName];
    
EXEC sp_dropserver 'ROC-HELPDESK';
GO
EXEC sp_addserver 'ROC-HDTEST01', 'local';
GO    

-- Snapshot and restore
--CREATE DATABASE HB_OnlineBanking_SS ON (Name ='HB_OnlineBanking_Data', FileName='G:\Restore\HB_OnlineBanking_Data.ss1') AS SNAPSHOT OF HB_OnlineBanking; 
--GO

--USE master
--GO
--RESTORE DATABASE HB_OnlineBanking FROM DATABASE_SNAPSHOT = 'HB_OnlineBanking_SS';
--GO

--USE master
--GO
--DROP DATABASE SNAPSHOT HB_OnlineBanking_SS



-- Reconfigure Memory - When not SQL Only - Necessary to not starve out other applications or instances.
USE master
EXEC sp_configure 'show advanced options', 1
RECONFIGURE WITH OVERRIDE

EXEC sp_configure 'min server memory', '0'
EXEC sp_configure 'max server memory', '6144' -- 16384
RECONFIGURE WITH OVERRIDE 

EXEC sp_configure 'show advanced options', 0
RECONFIGURE WITH OVERRIDE

-- Unlock Account without Password
ALTER LOGIN [Webreader] WITH CHECK_POLICY = OFF;
ALTER LOGIN [Webreader] WITH CHECK_POLICY = ON;

-- Unlock Account with password
ALTER LOGIN test WITH PASSWORD = 'asdfjkl;' UNLOCK ;

-- hasaccess flag is missing - for some reason sysadmin overrides this, but missing play button in SSMS.  (rare)
USE master;
GRANT CONNECT SQL TO [FTFCU\SG-sqldba];
GO

-- Wednesday Snapshots
DECLARE @dayofweek varchar(255), @dbname sysname, @path varchar(512), @filename varchar(512), @ssname nvarchar(512)
DECLARE @dropcmd varchar(max)
DECLARE @createcmd varchar(max)

--Read-Only Routing

ALTER AVAILABILITY GROUP [SQL-SP15]
 MODIFY REPLICA ON N'LAB-CSQL2012A\SP15A' WITH (SECONDARY_ROLE(READ_ONLY_ROUTING_URL=N'tcp://LAB-CSQL2012A:52907'))
 
ALTER AVAILABILITY GROUP [SQL-SP15]
 MODIFY REPLICA ON N'LAB-CSQL2012B\SP15B' WITH (SECONDARY_ROLE(READ_ONLY_ROUTING_URL=N'tcp://LAB-CSQL2012B:60129'))
 
ALTER AVAILABILITY GROUP [SQL-SP15]
 MODIFY REPLICA ON N'LAB-CSQL2012A\SP15A' WITH (PRIMARY_ROLE(READ_ONLY_ROUTING_LIST = (N'LAB-CSQL2012B\SP15B', N'LAB-CSQL2012A\SP15A'))) 
 
ALTER AVAILABILITY GROUP [SQL-SP15]
 MODIFY REPLICA ON N'LAB-CSQL2012B\SP15B' WITH (PRIMARY_ROLE(READ_ONLY_ROUTING_LIST = (N'LAB-CSQL2012A\SP15A', N'LAB-CSQL2012B\SP15B'))) 
 
 

/*
-- Snapshot
SET @path = 'K:\backups\'
SET @dbname = 'AkcelerantPF'

SET @dayofweek = datename(dw,getdate())

IF @dayofweek in ('Sunday','Wednesday','Friday')
BEGIN
	SET @ssname = @dbname + '_' + @dayofweek
	SET @filename = @path + @ssname + '.ss'
	IF EXISTS (SELECT name FROM master.dbo.sysdatabases WHERE name = @ssname)
	BEGIN 
		SET @dropcmd = '';
		SELECT @dropcmd = @dropcmd + 'kill ' + CONVERT(varchar(5), spid) + '; ' FROM master..sysprocesses WHERE dbid = db_id(@ssname)
		SET @dropcmd = @dropcmd + 'DROP DATABASE [{SSNAME}];'
		SET @dropcmd = REPLACE(@dropcmd,'{SSNAME}', @ssname);
		--EXEC(@dropcmd)
		print @dropcmd
	END
	IF NOT EXISTS (SELECT name FROM master.dbo.sysdatabases WHERE name = @ssname)
	BEGIN
		SET @createcmd = 'CREATE DATABASE [{SSNAME}] ON ( NAME = ''{DBNAME}'', FILENAME = ''{FILENAME}'' ) AS SNAPSHOT OF [{DBNAME}];'
		SET @createcmd = REPLACE(@createcmd,'{DBNAME}', @dbname);
		SET @createcmd = REPLACE(@createcmd,'{SSNAME}', @ssname);
		SET @createcmd = REPLACE(@createcmd,'{FILENAME}', @filename);
		EXEC(@createcmd)
		print @createcmd
	END
END

-- Backup

DECLARE @dayofweek varchar(255), @dbname sysname, @path varchar(512)
DECLARE @backupcmd varchar(max)

SET @path = 'K:\backups\'
SET @dbname = 'AkcelerantPF'

SET @dayofweek = datename(dw,getdate())

IF @dayofweek in ('Sunday','Tuesday','Wednesday')
BEGIN
	SET @backupcmd = 'USE {DBNAME}; BACKUP DATABASE {DBNAME} TO DISK = ''{PATH}{DBNAME}_{DAYOFWEEK}.Bak'' WITH FORMAT, MEDIANAME = ''BK_{DBNAME}_{DAYOFWEEK}'',  NAME = ''Full Backup of {DBNAME}'';'
	SET @backupcmd = REPLACE(@backupcmd,'{PATH}', @path);
	SET @backupcmd = REPLACE(@backupcmd,'{DBNAME}', @dbname);
	SET @backupcmd = REPLACE(@backupcmd,'{DAYOFWEEK}', @dayofweek);
	EXEC(@backupcmd)
END
*/

-- copy files
robocopy J:\ /"\rk-cbarestore01\g$\Backups\/" TEAASP-020915.bak /IPG:20 /L 
robocopy J:\ /"\rk-cbarestore01\g$\Backups\/" TEAASP-020915.bak /E /L 

robocopy /"\identifi-app1\f$\/" /"\rk-cbarestore01\h$\/" /MIR /COPY:DAT /DCOPY:T /Z /W:5 /R:5 /MT:16


-- Update Splunk Forwarder
robocopy /"\roc-itutil01\apps\InfoSec\Splunk\Splunk_Forwarders\ftfcu_mssql_forwarder_inputs\/" /"\roc-reporter\c$\Program Files\SplunkUniversalForwarder\etc\apps\ftfcu_mssql_forwarder_inputs\/" /E /L
psservice \\roc-reporter restart SplunkForwarder

-- ReadOnly Routing
ALTER AVAILABILITY GROUP [SQL-SP15]
 MODIFY REPLICA ON N'LAB-CSQL2012A\SP15A' WITH (SECONDARY_ROLE(READ_ONLY_ROUTING_URL=N'tcp://LAB-CSQL2012A:52907'))
 
ALTER AVAILABILITY GROUP [SQL-SP15]
 MODIFY REPLICA ON N'LAB-CSQL2012B\SP15B' WITH (SECONDARY_ROLE(READ_ONLY_ROUTING_URL=N'tcp://LAB-CSQL2012B:60129'))
 
ALTER AVAILABILITY GROUP [SQL-SP15]
 MODIFY REPLICA ON N'LAB-CSQL2012A\SP15A' WITH (PRIMARY_ROLE(READ_ONLY_ROUTING_LIST = (N'LAB-CSQL2012B\SP15B', N'LAB-CSQL2012A\SP15A'))) 
 
ALTER AVAILABILITY GROUP [SQL-SP15]
 MODIFY REPLICA ON N'LAB-CSQL2012B\SP15B' WITH (PRIMARY_ROLE(READ_ONLY_ROUTING_LIST = (N'LAB-CSQL2012A\SP15A', N'LAB-CSQL2012B\SP15B'))) 

-- 
ALTER AVAILABILITY GROUP [SQLTIER102]
 MODIFY REPLICA ON N'STG-CSQL2012A\TIER1_02A' WITH (SECONDARY_ROLE(READ_ONLY_ROUTING_URL=N'tcp://STG-CSQL2012A:52965'))
 
ALTER AVAILABILITY GROUP [SQLTIER102]
 MODIFY REPLICA ON N'STG-CSQL2012B\TIER1_02B' WITH (SECONDARY_ROLE(READ_ONLY_ROUTING_URL=N'tcp://STG-CSQL2012B:58625'))
 
ALTER AVAILABILITY GROUP [SQLTIER102]
 MODIFY REPLICA ON N'STG-CSQL2012A\TIER1_02A' WITH (PRIMARY_ROLE(READ_ONLY_ROUTING_LIST = (N'STG-CSQL2012B\TIER1_02B', N'STG-CSQL2012A\TIER1_02A'))) 
 
ALTER AVAILABILITY GROUP [SQLTIER102]
 MODIFY REPLICA ON N'STG-CSQL2012B\TIER1_02B' WITH (PRIMARY_ROLE(READ_ONLY_ROUTING_LIST = (N'STG-CSQL2012A\TIER1_02A', N'STG-CSQL2012B\TIER1_02B'))) 

 
-- Backup for Mirroring 
 
--TCP://ROC-SQLWITNESS:7022

BACKUP DATABASE [GoodControl] TO  DISK = N'H:\bak\ROC-SQL01A_GoodControl_05-07-2015.bak' WITH INIT
GO
BACKUP LOG [GoodControl] TO  DISK = N'H:\bak\ROC-SQL01A_GoodControl_05-07-2015.trn' WITH INIT
GO

-- Relaxed Cluster Monitor
(get-cluster).SameSubnetDelay = 2000
(get-cluster).SameSubnetThreshold = 15

get-cluster | fl *subnet*  

(get-cluster).CrossSubnetDelay = 2000
(get-cluster).CrossSubnetThreshold = 15

-- Multi-Subnet Consideration

Get-ClusterResource "DOCUWAREDB_PROD-DOCUWAREDB" | Get-ClusterParameter

$GroupName = "DOCUWAREDB"
$NetworkName = "DOCUWAREDB_PROD-DOCUWAREDB"
Get-ClusterResource $NetworkName | Get-ClusterParameter

Get-ClusterResource $NetworkName | Set-ClusterParameter RegisterAllProvidersIP 0
Get-ClusterResource $NetworkName | Set-ClusterParameter HostRecordTTL 300

Stop-ClusterResource $NetworkName
Start-ClusterResource $NetworkName
Start-ClusterResource $GroupName


$GroupName = "SQLTIER103"
$NetworkName = "SQLTIER103_PROD-SQLTIER103"

Get-ClusterResource $NetworkName | Get-ClusterParameter

Remove-ClusterResourceDependency -Resource $GroupName -Provider $NetworkName

Get-ClusterResource $NetworkName | Set-ClusterParameter RegisterAllProvidersIP 0
Get-ClusterResource $NetworkName | Set-ClusterParameter HostRecordTTL 300

Stop-ClusterResource $NetworkName
Start-ClusterResource $NetworkName
Start-ClusterResource $GroupName

Get-ClusterResource $NetworkName | Update-ClusterNetworkNameResource

Add-ClusterResourceDependency -Resource $GroupName -Provider $NetworkName

Get-ClusterResource $NetworkName | Get-ClusterParameter


$GroupName = "IDENTIFIDB"
$NetworkName = "IDENTIFIDB_PROD-IDENTIFIDB"

Get-ClusterResource $NetworkName | Get-ClusterParameter

Remove-ClusterResourceDependency -Resource $GroupName -Provider $NetworkName

Get-ClusterResource $NetworkName | Set-ClusterParameter RegisterAllProvidersIP 0
Get-ClusterResource $NetworkName | Set-ClusterParameter HostRecordTTL 300

Stop-ClusterResource $NetworkName
Start-ClusterResource $NetworkName
Start-ClusterResource $GroupName

Get-ClusterResource $NetworkName | Update-ClusterNetworkNameResource

Add-ClusterResourceDependency -Resource $GroupName -Provider $NetworkName

Get-ClusterResource $NetworkName | Get-ClusterParameter


--

ALTER AVAILABILITY GROUP SQLEDW MODIFY LISTENER 'LAB-SQLEDW' (PORT = 1433);

-- CIS Benchmarking SQL 2012 - 

REVOKE EXECUTE ON xp_regread TO PUBLIC;
REVOKE EXECUTE ON xp_fixeddrives TO PUBLIC;
REVOKE EXECUTE ON xp_dirtree TO PUBLIC;

EXECUTE sp_configure 'show advanced options', 1;
RECONFIGURE;
GO
EXECUTE sp_configure 'Remote access', 0;
RECONFIGURE;
GO
EXECUTE sp_configure 'Ole Automation Procedures', 0;
RECONFIGURE;
GO
EXECUTE sp_configure 'show advanced options', 0;
RECONFIGURE;
GO

DECLARE @donotuse NVARCHAR(MAX);
SET @donotuse = '';

SELECT @donotuse = @donotuse + 'ALTER LOGIN ' + name + ' WITH NAME = sa_do_not_use;' FROM sys.server_principals WHERE sid = 0x01 and name != 'sa_do_not_use';
SELECT @donotuse = @donotuse + 'ALTER LOGIN sa_do_not_use DISABLE;' FROM sys.server_principals WHERE sid = 0x01 and is_disabled = 0;

SELECT @donotuse
EXEC sp_executesql @donotuse;

ALTER LOGIN [sa_do_not_use] WITH CHECK_EXPIRATION=ON
GO
ALTER LOGIN [##MS_PolicyTsqlExecutionLogin##] WITH CHECK_EXPIRATION=ON
GO
ALTER LOGIN [##MS_PolicyEventProcessingLogin##] WITH CHECK_EXPIRATION=ON
GO

-- switch non-sa to sa (fixes against who leave, but loses signature on which IT user knows about the db)
SELECT name, SUSER_SNAME(owner_sid) object_owner, 'USE [' + name + ']; EXEC sp_changedbowner ''sa_do_not_use'';' as fix_cmd 
FROM sys.databases WHERE owner_sid != 0x01
union all
SELECT name, SUSER_NAME(principal_id), 'USE master; ALTER AUTHORIZATION ON ENDPOINT::' + name + ' TO ' + SUSER_SNAME(0x01) as cmd
FROM (
  SELECT principal_id, name FROM sys.database_mirroring_endpoints union all
  SELECT principal_id, name FROM sys.service_broker_endpoints
) ep WHERE principal_id != 0x01;
--
SELECT 'GRANT CONNECT ON ENDPOINT::Hadr_endpoint TO [ftfcu\svc-sqldbeng];'

GRANT CONNECT ON ENDPOINT::mirroring_endpoint TO [ftfcu\svc-sqldbeng];
GRANT CONNECT ON ENDPOINT::mirroring_endpoint TO [ftfcu\roc-sql01a_sqlsvc];

alter endpoint [mirroring_endpoint] state = stopped
alter endpoint [mirroring_endpoint] state = started

-- Missing Owners
select suser_sname(owner_sid), d.* from sys.databases d;
select 'use [' + d.name + ']; exec sp_changedbowner ''' +  suser_sname(0x01) + ''';' from sys.databases d where suser_sname(owner_sid) is null or suser_sname(owner_sid) = 'FTFCU\vieth-admin';

--- cis hardening v2

declare @hardening nvarchar(max), @donotuse nvarchar(max), @configuration nvarchar(max), @public nvarchar(max), @haslink bit;

set @configuration = '';
set @hardening = '';
set @public = '';

select @haslink = count(*) from sys.servers where is_remote_login_enabled = 1 and is_linked = 1;

select @public = @public + 'revoke execute on ' + ao.name + ' to public;' + char(13)
from    
    sys.database_principals dp
	join sys.database_permissions dpm ON dp.principal_id = dpm.grantee_principal_id
	join sys.all_objects AS ao on dpm.major_id=ao.object_id AND dpm.minor_id=0 AND dpm.class=1
where
    dp.name = 'public' and ao.name in ('xp_regread','xp_fixeddrives','xp_dirtree','xp_fileexist','xp_grantlogin')

set @hardening = @public;

select @configuration = @configuration + 'execute sp_configure ''' + name + ''', 0;' + char(13) + 'reconfigure;' + char(13) 
from sys.configurations
where (name in ('Ole Automation Procedures','SQL Mail XPs','Ad Hoc Distributed Queries','Cross DB Ownership Chaining','Remote Admin Connections','Scan For Startup Procs','CLR Enabled') 
   or (name = 'Remote Access' and @haslink = 0)
   or (name like 'xp_c_ds_ell')
   ) and value = 1;

set @hardening = @hardening + case when @configuration <> '' then 'execute sp_configure ''show advanced options'', 1;' + char(13) + 'reconfigure;' + char(13) + @configuration + 'execute sp_configure ''show advanced options'', 0;' + char(13) + 'reconfigure;' + char(13) else '' end;

set @donotuse = '';

select @donotuse = @donotuse + 'alter login ' + name + ' with name = sa_do_not_use;' FROM sys.server_principals WHERE sid = 0x01 and name != 'sa_do_not_use';
select @donotuse = @donotuse + 'alter login sa_do_not_use disable;' FROM sys.server_principals WHERE sid = 0x01 and is_disabled = 0;

set @hardening = @hardening + @donotuse;

select @hardening

--exec sp_executesql @hardening;

---

declare @password_policy nvarchar(max);

set @password_policy = '';

select @password_policy = @password_policy + 'alter login ' + QuoteName(name) + ' with check_policy = on' +
   case is_expiration_checked when 0 then ', check_expiration = off' when 1 then ', check_expiration = on' else '' end + '; '
from sys.sql_logins where is_policy_checked = 0 and is_disabled = 0;

select @password_policy

--exec sp_executesql @password_policy;
---

CREATE DATABASE HomeBanking_SS ON (Name ='HomeBanking', FileName='G:\Restore\HomeBanking.ss1') AS SNAPSHOT OF HomeBanking; 
CREATE DATABASE HB_OnlineBanking_SS ON (Name ='HB_OnlineBanking_Data', FileName='G:\Restore\HB_OnlineBanking_Data.ss1') AS SNAPSHOT OF HB_OnlineBanking;

RESTORE DATABASE HomeBanking FROM DATABASE_SNAPSHOT = 'HomeBanking_SS';
RESTORE DATABASE HB_OnlineBanking FROM DATABASE_SNAPSHOT = 'HB_OnlineBanking_SS';

DROP DATABASE HomeBanking_SS
DROP DATABASE HB_OnlineBanking_SS

-- AAG TDE Example
-- Primary Replica

CREATE MASTER KEY ENCRYPTION BY Password = '1ALqeAh1Ri40B5bd';

BACKUP MASTER KEY
  TO FILE='\\RK-CBARESTORE01\G_Backups\lab-csql2012a_mk'
  ENCRYPTION BY PASSWORD = 'mk$P@ssword';

CREATE CERTIFICATE FTFCU_SQL_Certificate
  WITH SUBJECT = 'FTFCU SQL Certificate';

BACKUP CERTIFICATE FTFCU_SQL_Certificate
  TO FILE='\\RK-CBARESTORE01\G_Backups\lab-csql2012_cer'
  WITH Private KEY (
    FILE='\\RK-CBARESTORE01\G_Backups\lab-csql2012_pk',
    ENCRYPTION BY PASSWORD = 'pk$P@ssword'
  );

-- encrypting a "seed" database
use seed;

create database encryption key with algorithm = aes_256 encryption by server certificate FTFCU_SQL_Certificate;

use master;

alter database seed set encryption on;

backup database [seed] to disk = '\\RK-CBARESTORE01\G_Backups\seed_db.bak' with init
backup log [seed] to disk = '\\RK-CBARESTORE01\G_Backups\seed_tl.bak' with init

alter availability group [SQLEDW] add database [seed];

-- untested: EKM
user master

create cryptographic provider Vormetric

create asymmetric key vormetric_tde from provider Vormetric
with provider_key_name 'sqltest', creation_disposition = open_existing;

create database encryption key with algorithm = aes_256 encryption by server asymmetric key vormetric_tde

-- default compression on for backup
EXEC sp_configure 'backup compression default', 1 ;
RECONFIGURE WITH OVERRIDE ;
GO


-- Secondary Replicas
CREATE MASTER KEY ENCRYPTION BY Password = '1ALqeAh1Ri40B5bd';

BACKUP MASTER KEY
  TO FILE='\\RK-CBARESTORE01\G_Backups\lab-csql2012b_mk'
  ENCRYPTION BY PASSWORD = 'mk$P@ssword';

CREATE CERTIFICATE FTFCU_SQL_Certificate
  FROM FILE = '\\RK-CBARESTORE01\G_Backups\lab-csql2012_cer'
  WITH PRIVATE KEY (
    FILE = '\\RK-CBARESTORE01\G_Backups\lab-csql2012_pk',
    DECRYPTION BY PASSWORD = 'pk$P@ssword'
  )

-- joining an encrypted "seed" database
restore database [seed] from disk = '\\RK-CBARESTORE01\G_Backups\seed_db.bak' with norecovery
restore log [seed] from disk = '\\RK-CBARESTORE01\G_Backups\seed_tl.bak' with norecovery

alter database [seed] set hadr availability group = [SQLEDW];

alter database [seed] set hadr off;

-- Connect probe to internal load balancer:

Get-ClusterResource "SQLEDW_10.7.61.133" | Set-ClusterParameter -Multiple @{"ProbePort"="59999";"SubnetMask"="255.255.255.255";"OverrideAddressMatch"=1;"EnableDhcp"=0}

-- synonym builder
select case when ss.name is not null then 'drop synonym [dbo].[' + ss.name + ']; ' else '' end +
     'create synonym [' + s.name + '].[' + t.name + '] for [seed].[' + s.name + '].[' + t.name + '];' 
from seed.sys.tables t
    inner join seed.sys.schemas s
        on t.schema_id = s.schema_id
	left join sys.synonyms ss on ss.base_object_name = '[seed].[' + s.name + '].[' + t.name + ']' 
where t.type = 'U';

-- Resolving after forced quorum and cluster recovery:

ALTER AVAILABILITY GROUP [SQLEDW] FORCE_FAILOVER_ALLOW_DATA_LOSS

-- CPU Affinity: Set to suppress a runaway instance.   Don't set it otherwise.
sp_configure 'show advanced options', 1;
RECONFIGURE;
GO
sp_configure 'affinity mask', 3;
RECONFIGURE;
GO
EXECUTE sp_configure 'show advanced options', 0;
RECONFIGURE;

-------

sp_configure 'show advanced options', 1;
GO
RECONFIGURE;
GO
sp_configure 'EKM provider enabled', 1;
GO
RECONFIGURE;
GO

CREATE CRYPTOGRAPHIC PROVIDER VormetricEKM
FROM FILE = 'C:\Program Files\Vormetric\DataSecurityExpert\agent\pkcs11\bin\vorekm.dll';
GO

SELECT * FROM [model].[sys].[cryptographic_providers]

CREATE CREDENTIAL sa_ekm_tde_credential
WITH IDENTITY ='Identity1',
SECRET = '3WPknU@KZFfB@S2JvQ5LVYL@qSFx6Z7m'
FOR CRYPTOGRAPHIC PROVIDER VormetricEKM
GO

ALTER LOGIN [FTFCU\svc-sqldbeng] ADD CREDENTIAL sa_ekm_tde_credential;
GO

CREATE ASYMMETRIC KEY vormetric_tde
FROM PROVIDER VormetricEKM
WITH PROVIDER_KEY_NAME = 'sqltest',
CREATION_DISPOSITION=OPEN_EXISTING
GO

SELECT * FROM [master].[sys].[asymmetric_keys]

CREATE CREDENTIAL ekm_tde_credential
WITH IDENTITY ='Identity2',
SECRET = '3WPknU@KZFfB@S2JvQ5LVYL@qSFx6Z7m'
FOR CRYPTOGRAPHIC PROVIDER VormetricEKM

CREATE LOGIN EKM_login
FROM ASYMMETRIC KEY vormetric_tde;

ALTER LOGIN EKM_login
ADD CREDENTIAL ekm_tde_credential;

use db1;

create database encryption key with algorithm = aes_128 encryption by server asymmetric key vormetric_tde

alter database db1 set encryption on


SELECT DB_NAME(e.database_id) AS DatabaseName, e.database_id, e.encryption_state, c.name, e.percent_complete,
	CASE e.encryption_state
		WHEN 0 THEN 'No database encryption key present, no encryption'
		WHEN 1 THEN 'Unencrypted'
		WHEN 2 THEN 'Encryption in progress'
		WHEN 3 THEN 'Encrypted'
		WHEN 4 THEN 'Key change in progress'
		WHEN 5 THEN 'Decryption in progress'
	END AS encryption_state_desc
FROM sys.dm_database_encryption_keys AS e
	LEFT JOIN master.sys.asymmetric_keys AS c
ON e.encryptor_thumbprint = c.thumbprint

-- Reset Schema(s) to default owner
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

declare @dblist table (dbname sysname);
declare @schemafix table (cmd varchar(255));
declare @dbsql nvarchar(max), @sql nvarchar(max), @fixsql nvarchar(max);

select @dbsql = case when db_name() != 'master' then 'select ''' + db_name() + '''' when SERVERPROPERTY('IsHadrEnabled') is null then 'select name from sys.databases where database_id > 4 and state = 0 and is_read_only = 0' else 'select name from sys.databases d LEFT JOIN sys.dm_hadr_availability_replica_states ars ON d.replica_id = ars.replica_id where database_id > 4 and state = 0 and isnull(ars.role,1) = 1 and is_read_only = 0' end
insert into @dblist
   exec sp_executesql @dbsql

set @sql = ''
select @sql = @sql + 
'select ''USE ' + quotename(dbname) + '; ALTER AUTHORIZATION ON SCHEMA::'' + quotename(s.name) + '' TO '' + quotename(isnull(dpp.name,''dbo'')) + ''   -- was '' + quotename(dp.name)
from ' + QUOTENAME(dbname) + '.sys.database_principals dp 
    join ' + QUOTENAME(dbname) + '.sys.schemas s on dp.principal_id = s.principal_id
    left join ' + QUOTENAME(dbname) + '.sys.database_principals dpp on s.name = dpp.name
where s.name != dp.name and dp.name != ''dbo'' and s.name not like ''%\%'';'
from @dblist

insert into @schemafix
	exec sp_executesql @sql

set @fixsql = ''

select @fixsql = @fixsql + cmd + char(13) from @schemafix

select @fixsql

--exec sp_executesql @fixsql;

-- Cluster up but main sync replica is MIA.
ALTER AVAILABILITY GROUP SQLEDW FORCE_FAILOVER_ALLOW_DATA_LOSS;