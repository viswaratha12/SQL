-- DBA Notes --
--
-- Started by Viet H.  2014
-- 
-- These notes are broken out into two parts.    This file contains query only scripts.




-- Base Instance info.   Useful later

SELECT @@SERVERNAME as name, @@SERVICENAME as instance_name
	, (SELECT max(local_tcp_port) FROM sys.dm_exec_connections WHERE session_id = @@SPID) port
    , SERVERPROPERTY('ComputerNamePhysicalNetBIOS') server_name, SERVERPROPERTY('productversion') sql_version
	, SERVERPROPERTY('productlevel') sql_level, SERVERPROPERTY('edition') sql_edition
    , cpu_count
FROM sys.dm_os_sys_info



-- Initial Catalog=seed;ApplicationIntent=ReadOnly


-- runas /user:FTFCU\<user>-admin cmd

-- dsquery user -samid vieth | dsget user -memberof
-- dsquery group -samid SG-sqldba | dsget group -members -expand
-- net group /domain "SG-sqldba"

-- dsquery user -samid availagentSVC | dsget user -memberof


-- compmgmt /computer:rk-sqltst8

-- powershell
-- gwmi win32_operatingsystem -computername ROC-SQLTST8 | % caption


--Log file Location
xp_readerrorlog 0, 1, N'Logging SQL Server messages in file', NULL, NULL, N'asc' 
GO

-- Connection Pooling
select host_name, program_name, count(*) as sessions 
from sys.dm_exec_sessions group by host_name, program_name, security_id
order by sessions desc;

-- Base OS
-- SQL Server (MSSQLSERVER) - Started - Manual - FTFCU\svc-sqldbeng
-- SQL Server Agent (MSSQLSERVER) - Started - Automatic (Delayed Start) - FTFCU\svc-sqlagent
-- SQL Server Browser - Started - Automatic - Local Service
-- SQL Server VSS Writer - Started - Automatic - Local System

-- Host Instance is running on - Useful to detect cluster
SELECT SERVERPROPERTY('ComputerNamePhysicalNetBIOS') AS [CurrentNodeName] 

-- CPU Pressure
SELECT scheduler_id, current_tasks_count, runnable_tasks_count, work_queue_count, pending_disk_io_count
FROM sys.dm_os_schedulers
WHERE scheduler_id < 255


    -- Memory Info
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
    SELECT object_name, replace(counter_name,'KB','MB') as name, cntr_value/1024 as value FROM sys.dm_os_performance_counters WHERE counter_name IN ('Total Server Memory (KB)', 'Target Server Memory (KB)')
    --UNION ALL  --2005
    --SELECT 'Windows','Total System Memory (MB)', physical_memory_in_bytes/1048576 as system_memory FROM sys.dm_os_sys_info
    UNION ALL
    SELECT 'Configuration', [description], value_in_use FROM sys.configurations WHERE name like '%server memory%' 
    ORDER BY 3 OPTION (RECOMPILE)

    -- Memory OS --2008+
    SELECT total_mb          = cast(total_physical_memory_kb / 1024.0 as numeric(10,1)),
           avail_mb          = cast(available_physical_memory_kb / 1024.0 as numeric(10,1)),
           avail_pct         = cast(100.0 * available_physical_memory_kb / total_physical_memory_kb as numeric(10,1)),
           total_pagefile_mb = cast(total_page_file_kb / 1024.0 as numeric(10,1)),
           avail_pagefile_mb = cast(available_page_file_kb / 1024.0 as numeric(10,1)),
           pagefile_pct      = cast(100.0 * available_page_file_kb / total_page_file_kb as numeric(10,1)),
           system_memory_state_desc
    FROM   sys.dm_os_sys_memory 

    -- Memory Health
    select * from sys.dm_os_performance_counters where object_name like '%manager%' and counter_name in ('Page life expectancy','Lazy writes/sec','Memory Grants Pending')

    -- Has Master Key Encryption Configured
    SELECT d.name, d.is_master_key_encrypted_by_server FROM sys.databases AS d

--EXEC sp_fkeys 'Clients'
--EXEC sp_fkeys 'Tokens'

-- Databases List
select @@SERVERNAME as instance, name, suser_sname(owner_sid) owner, recovery_model_desc, state_desc, convert(varchar(10), GETDATE(), 101) as check_date 
from sys.databases where database_id > 4 order by 2

--Availability group notes
select * from sys.availability_group_listeners
select * from sys.availability_group_listener_ip_addresses

select g.name, r1.replica_server_name, l.routing_priority, r2.replica_server_name, r2.read_only_routing_url 
 from sys.availability_read_only_routing_lists as l
 join sys.availability_replicas as r1 on l.replica_id = r1.replica_id
 join sys.availability_replicas as r2 on l.read_only_replica_id = r2.replica_id
 join sys.availability_groups as g on r1.group_id = g.group_id
order by 2,3

-- Maintenance Plans
select 
  p.name as 'Maintenance Plan'
, p.[description] as 'Description'
, p.[owner] as 'Plan Owner'
, sp.subplan_name as 'Subplan Name'
, sp.subplan_description as 'Subplan Description'
, j.name as 'Job Name'
, j.[description] as 'Job Description'  
from msdb..sysmaintplan_plans p
  inner join msdb..sysmaintplan_subplans sp on p.id = sp.plan_id
  inner join msdb..sysjobs j on sp.job_id = j.job_id
where j.[enabled] = 1

-- Job History
select j.name as job_name, SUSER_SNAME(j.owner_sid) AS owner 
    , h.step_id, h.step_name
    , msdb.dbo.agent_datetime(h.run_date, run_time) as run_date_time, h.run_duration
    , h.run_status, h.message
From msdb.dbo.sysjobs j 
    INNER JOIN msdb.dbo.sysjobhistory h ON j.job_id = h.job_id 
where j.enabled = 1 and h.step_id != 0
order by h.run_date desc, h.run_duration desc;

--Active System Waits - 8s
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

DECLARE @dm_os_wait_stats TABLE (id int, wait_type nvarchar(60), waiting_tasks_count bigint, wait_time_ms bigint, max_wait_time_ms bigint, signal_wait_time_ms bigint);
DECLARE @summary_stat     TABLE (wait_type nvarchar(60), waiting_tasks_count bigint, wait_time_ms bigint, signal_wait_time_ms bigint, todo_hint varchar(512));
DECLARE @sample_ms int, @total_ms bigint, @waitfor varchar(255);

SET @sample_ms = 8 * 1000;

INSERT INTO @dm_os_wait_stats SELECT 1, wait_type, waiting_tasks_count, wait_time_ms, max_wait_time_ms, signal_wait_time_ms FROM sys.dm_os_wait_stats;
SET @waitfor = CONVERT(varchar, DATEADD(ms, @sample_ms, 0), 114) WAITFOR DELAY @waitfor;
INSERT INTO @dm_os_wait_stats SELECT 2, wait_type, waiting_tasks_count, wait_time_ms, max_wait_time_ms, signal_wait_time_ms FROM sys.dm_os_wait_stats;

INSERT INTO @summary_stat
	SELECT 
		w1.wait_type,
		w2.waiting_tasks_count - w1.waiting_tasks_count,
		w2.wait_time_ms - w1.wait_time_ms,
		w2.signal_wait_time_ms - w1.signal_wait_time_ms,
		CASE WHEN w1.wait_type = 'ASYNC_NETWORK_IO' THEN 'Client is probably too slow. Data is ready but no one wants it. Check for network anomalies and application design.'
			 WHEN w1.wait_type = 'CXPACKET' THEN 'Unbalanced parallelism.  Check statistics.  Identify queries and attempt to tune with dop max / dop cost.'
			 WHEN w1.wait_type = 'PREEMPTIVE_OS_WRITEFILEGATHER' THEN 'File growth events, pre-plan and size file to minimize.'
			 WHEN w1.wait_type = 'PREEMPTIVE_OS_AUTHENTICATIONOPS' THEN 'Domain controller is sluggish.   Check with Infrastruture.'
			 WHEN w1.wait_type = 'WRITELOG' THEN 'Transaction Log I/O, Tune log file and reduce disk latency.'
			 WHEN w1.wait_type = 'SOS_SCHEDULER_YIELD' THEN 'Lots of small CPU intensive queries.  Try refactoring queries or add faster CPU.'
			 WHEN w1.wait_type LIKE 'LCK_M_%' THEN 'Locking a bit too much.  Review specific objects being held up.  Redesign Index, Isolation Levels, Transactional Flow.'
			 WHEN w1.wait_type LIKE 'PAGEIOLATCH_%' THEN 'DML I/O concurrency, Run latency query to see which Disk/File is involved.'
			 WHEN w1.wait_type LIKE 'LATCH%' THEN 'SQL Internal locks. Run latch query to see which mutex is in heavy use.'
			 WHEN w1.wait_type LIKE 'BACKUPIO' THEN 'I/O from backups. Increase log backup frequency or consider moving full backups to another time.'
			 ELSE NULL END AS TodoHint		
	FROM @dm_os_wait_stats w1
	JOIN @dm_os_wait_stats w2 ON w1.wait_type = w2.wait_type
	WHERE w1.id = 1 and w2.id = 2 and w2.waiting_tasks_count > w1.waiting_tasks_count and w2.wait_time_ms > w1.wait_time_ms
		  and w1.wait_type NOT IN (
			N'CLR_SEMAPHORE',      N'LAZYWRITER_SLEEP',      N'REQUEST_FOR_DEADLOCK_SEARCH',
			N'SLEEP_TASK',         N'SLEEP_SYSTEMTASK',      N'SQLTRACE_BUFFER_FLUSH', 
			N'WAITFOR',            N'CHECKPOINT_QUEUE',      N'HADR_FILESTREAM_IOMGR_IOCOMPLETION', 
			N'TRACEWRITE',         N'XE_TIMER_EVENT',        N'XE_DISPATCHER_JOIN', 
			N'LOGMGR_QUEUE',       N'BROKER_TASK_STOP',      N'FT_IFTS_SCHEDULER_IDLE_WAIT', 
			N'CLR_MANUAL_EVENT',   N'CLR_AUTO_EVENT',        N'DISPATCHER_QUEUE_SEMAPHORE',        
			N'XE_DISPATCHER_WAIT', N'BROKER_TO_FLUSH',       N'BROKER_EVENTHANDLER', 
			N'FT_IFTSHC_MUTEX',    N'DIRTY_PAGE_POLL',       N'SQLTRACE_INCREMENTAL_FLUSH_SLEEP',
			N'DBMIRROR_SEND',      N'DBMIRROR_DBM_MUTEX',    N'DBMIRROR_EVENTS_QUEUE',                
			N'DBMIRRORING_CMD',    N'ONDEMAND_TASK_QUEUE',   N'SP_SERVER_DIAGNOSTICS_SLEEP',
			N'RESOURCE_QUEUE',     N'BROKER_RECEIVE_WAITFOR' )

SELECT @total_ms = SUM(wait_time_ms) FROM @summary_stat;
SET @total_ms = CASE WHEN @total_ms < @sample_ms THEN @sample_ms ELSE @total_ms END;

SELECT wait_type as WaitType, waiting_tasks_count as TaskCount, wait_time_ms - signal_wait_time_ms as WaitTime
    , CAST(CONVERT(NUMERIC(10,1),100.0 * (wait_time_ms - signal_wait_time_ms)/@total_ms) AS VARCHAR) + '%' as Importance, todo_hint as TodoHint
FROM @summary_stat UNION

SELECT 'SIGNAL', SUM(waiting_tasks_count), SUM(signal_wait_time_ms)
     , CAST(CONVERT(NUMERIC(10,1),100.0 * SUM(signal_wait_time_ms)/@total_ms) AS VARCHAR) + '%', 'Ready to run, but CPU is busy.  Check server Power Plan, get faster/more CPUs, or reduce CPU needs.' 
FROM @summary_stat WHERE signal_wait_time_ms > 0 HAVING SUM(signal_wait_time_ms) > 0 UNION

SELECT '- - - - - -', 1, @sample_ms * CEILING(cpu_count / 2.0), null, '              - - - ( Significant Above ) - - -' FROM sys.dm_os_sys_info UNION
SELECT '- - - - - -', 1, @sample_ms,                            null, '                   - - - ( Single CPU ) - - -'   UNION
SELECT '- - - - - -', 1, @sample_ms / 4,                        null, '             - - - ( Insignificant Below ) - - -' 

ORDER BY WaitTime DESC, TodoHint DESC;


--Who detailed
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SELECT db_name(sdep.dbid) as database_name, login_name, local_net_address, sdes.*, sdec.*, sdest.*
FROM sys.dm_exec_sessions AS sdes
 JOIN sys.sysprocesses as sdep on sdes.session_id = sdep.spid
 JOIN sys.dm_exec_connections sdec ON sdec.session_id = sdes.session_id
 CROSS APPLY sys.dm_exec_sql_text(sdec.most_recent_sql_handle) AS sdest
ORDER BY database_name;


--Active Queries v2
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

DECLARE @dm_exec_requests TABLE (
    session_id smallint, connection_id uniqueidentifier, command nvarchar(32), blocking_session_id smallint, database_id smallint, total_elapsed_time bigint, cpu_time bigint, reads bigint, writes bigint, logical_reads bigint, transaction_isolation_level smallint,
    percent_complete real, estimated_completion_time bigint, row_count bigint, statement_start_offset bigint, statement_end_offset bigint, sql_handle varbinary(64), plan_handle varbinary(64), task_address varbinary(8)
);

INSERT INTO @dm_exec_requests 
   SELECT session_id, connection_id, command, blocking_session_id, database_id, total_elapsed_time, cpu_time, reads, writes, logical_reads, transaction_isolation_level
        , percent_complete, estimated_completion_time, row_count, statement_start_offset, statement_end_offset, sql_handle, plan_handle, task_address
   FROM sys.dm_exec_requests WITH (NOLOCK);

SELECT SessionId         = R.session_id
     , LoginName         = S.login_name
     , LoginHost         = S.host_name
     , CPUTime           = cast(R.cpu_time  / 1000.0 as decimal(10,1))
     , RunTime           = cast(R.total_elapsed_time / 1000.0 as decimal(10,1))
     , PctDone           = cast(R.percent_complete as decimal(10,1))
     , DoneTime          = cast(R.estimated_completion_time / 1000.0 as decimal(10,1))
     , RowsSent          = R.row_count
     , DbName            = DB_NAME(R.database_id)
     , Command           = R.command
     , Isolation         =
         CASE R.transaction_isolation_level
             WHEN 0 THEN 'Unspecified' 
             WHEN 1 THEN 'Read Uncommitted'
             WHEN 2 THEN 'Read Committed'
             WHEN 3 THEN 'Repeatable'
             WHEN 4 THEN 'Serializable'
             WHEN 5 THEN 'Snapshot'
         END
     , RunningSQL        = SUBSTRING(Q.text,R.statement_start_offset / 2+1 , 
         ( (CASE WHEN R.statement_end_offset = -1 
            THEN (LEN(CONVERT(nvarchar(max),Q.text)) * 2) 
            ELSE R.statement_end_offset END)- R.statement_start_offset) / 2+1 )
     , WaitType          = W.wait_type
     --, QueryPlan         = QP.query_plan
     , Software          = S.program_name
     , FullSQL           = Q.text
     , BlockingSessionId = BS.session_id
     , BlockingLoginName = BS.login_name
     , BlockingSQL       = SUBSTRING(BQ.text,BR.statement_start_offset / 2+1 , 
         ( (CASE WHEN BR.statement_end_offset = -1 
            THEN (LEN(CONVERT(nvarchar(max),BQ.text)) * 2) 
            ELSE BR.statement_end_offset END)- BR.statement_start_offset) / 2+1 )
FROM sys.dm_exec_connections AS C
    JOIN @dm_exec_requests AS R ON C.connection_id = R.connection_id
    JOIN sys.dm_exec_sessions AS S on R.session_id = S.session_id
    CROSS APPLY sys.dm_exec_sql_text(R.sql_handle) AS Q
    --CROSS APPLY sys.dm_exec_query_plan( R.plan_handle ) AS QP    
    LEFT JOIN sys.dm_exec_sessions AS BS ON BS.session_id = R.blocking_session_id
    LEFT JOIN @dm_exec_requests AS BR on BR.session_id = BS.session_id
    LEFT JOIN sys.dm_os_waiting_tasks AS W ON R.session_id = W.session_id and R.task_address = W.waiting_task_address
    OUTER APPLY sys.dm_exec_sql_text(BR.sql_handle) AS BQ
ORDER BY R.cpu_time DESC;


--Status on how the kill is going.
--kill 75 with statusonly

--Heavy Queries
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
WITH TBL AS (
	SELECT TOP 20
	   DatabaseName     = DB_NAME(CONVERT(int,pa1.value)),
	   ObjectName       = OBJECT_NAME(CONVERT(int, pa2.value),CONVERT(int, pa1.value)),
       SQLStatement     = SUBSTRING(t.text,s.statement_start_offset / 2+1 , 
         ( (CASE WHEN s.statement_end_offset = -1 
            THEN (LEN(CONVERT(nvarchar(max),t.text)) * 2) 
            ELSE s.statement_end_offset END)- s.statement_start_offset) / 2+1 ),	   
	   ExecutionCount   = s.execution_count, 
	   AvgExecutionTime = isnull( s.total_elapsed_time / s.execution_count, 0 ) / 1000000.0,
	   AvgWorkerTime    = s.total_worker_time / s.execution_count  / 1000000.0,
	   TotalWorkerTime  = s.total_worker_time / 1000000.0,
	   MaxLogicalReads  = s.max_logical_reads,
	   MaxPhysicalReads = s.max_physical_reads,
	   MaxLogicalWrites = s.max_logical_writes,
	   CreationDateTime = s.creation_time,
	   LastExecDateTime = s.last_execution_time,
	   CallsPerSecond   = isnull( s.execution_count / datediff( second, s.creation_time, getdate()), 0 ),
	   QueryPlan        = qp.query_plan,
	   ProcedureText    = t.text
	FROM sys.dm_exec_query_stats s
	   CROSS APPLY sys.dm_exec_sql_text( s.sql_handle ) as t
	   CROSS APPLY sys.dm_exec_query_plan( s.plan_handle ) AS qp
	   CROSS APPLY sys.dm_exec_plan_attributes( s.plan_handle) AS pa1
	   CROSS APPLY sys.dm_exec_plan_attributes( s.plan_handle) AS pa2
	WHERE 
	pa1.attribute = 'dbid' and pa2.attribute = 'objectid' and 
	s.last_execution_time > dateadd(day, -1, getdate()) and
    (s.execution_count > 10 or (s.total_elapsed_time / s.execution_count / 1000000.0 > 300))
	ORDER BY TotalWorkerTime DESC ) 
SELECT * FROM TBL ORDER BY TotalWorkerTime DESC

-- Heavy Query v2 (10s sample)

SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
DECLARE @dm_exec_query_stats TABLE (
    [sql_handle] [varbinary](64),
    [plan_handle] [varbinary](64),
    [statement_start_offset] [int],
    [statement_end_offset] [int],
    [execution_count] [bigint],
    [total_elapsed_time] [bigint],
    [total_worker_time] [bigint],
    [total_logical_reads] [bigint],
    [total_physical_reads] [bigint],
    [total_logical_writes] [bigint],
    [DateAdded] [datetime]);
    
INSERT INTO @dm_exec_query_stats SELECT qs.sql_handle
    , qs.plan_handle, qs.statement_start_offset, qs.statement_end_offset, qs.execution_count , qs.total_elapsed_time
    , qs.total_worker_time , qs.total_logical_reads, qs.total_physical_reads, qs.total_logical_writes , getdate()
FROM sys.dm_exec_query_stats AS qs

WAITFOR DELAY '00:00:08';

DECLARE @Results TABLE (
	[sql_handle] [varbinary](64),
	[plan_handle] [varbinary](64),
    [statement_start_offset] [int],
    [statement_end_offset] [int],
    [ExecutionCount] [bigint],
    [AvgExecutionTime] [numeric](20,10),
    [AvgWorkerTime] [numeric](20,10),
    [TotalWorkerTime] [numeric](20,10),
    [LogicalReads] [bigint],
    [PhysicalReads] [bigint],
    [LogicalWrites] [bigint],
    [CallsPerSecond] [numeric](10,1)
);

insert into @Results
select top 25
       qs.sql_handle, qs.plan_handle, qs.statement_start_offset, qs.statement_end_offset,
	   qs.execution_count - isnull(s.execution_count,0), 
	   (qs.total_elapsed_time - isnull(s.total_elapsed_time,0)) / (qs.execution_count - isnull(s.execution_count, 0)) / 1000000.0,
	   (qs.total_worker_time - isnull(s.total_worker_time,0)) / (qs.execution_count - isnull(s.execution_count,0))  / 1000000.0,
	   (qs.total_worker_time - isnull(s.total_worker_time,0)) / 1000000.0,
	   (qs.total_logical_reads - isnull(s.total_logical_reads,0)),
	   (qs.total_physical_reads - isnull(s.total_physical_reads,0)),
	   (qs.total_logical_writes - isnull(s.total_logical_writes,0)),
	   (qs.execution_count - 1.0 * isnull(s.execution_count,0)) / datediff( second, isnull(s.DateAdded, qs.creation_time), getdate())
from sys.dm_exec_query_stats qs
left join @dm_exec_query_stats s on qs.sql_handle = s.sql_handle and qs.plan_handle = s.plan_handle and qs.statement_start_offset = s.statement_start_offset
where qs.execution_count > isnull(s.execution_count,0)
order by qs.total_elapsed_time desc

select 
    DatabaseName     = DB_NAME(CONVERT(int, dbid.value)),
    ProcedureName    = OBJECT_NAME(CONVERT(int, objectid.value),CONVERT(int, dbid.value)),
    SQLStatement     = SUBSTRING(t.text,r.statement_start_offset / 2+1 , 
      ( (CASE WHEN r.statement_end_offset = -1 
         THEN (LEN(CONVERT(nvarchar(max),t.text)) * 2) 
         ELSE r.statement_end_offset END)- r.statement_start_offset) / 2+1 ),
    ExecutionCount, AvgExecutionTime, AvgWorkerTime, TotalWorkerTime,
    LogicalReads, PhysicalReads, LogicalWrites, CallsPerSecond,
    QueryPlan        = qp.query_plan,
    ProcedureText    = t.text
from @Results r
	CROSS APPLY sys.dm_exec_sql_text( r.sql_handle )  t
	CROSS APPLY sys.dm_exec_query_plan( r.plan_handle ) AS qp
    CROSS APPLY sys.dm_exec_plan_attributes( r.plan_handle) AS dbid
    CROSS APPLY sys.dm_exec_plan_attributes( r.plan_handle) AS objectid    
where dbid.attribute = 'dbid' and objectid.attribute = 'objectid'  
order by TotalWorkerTime desc;


-- current locks

SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SELECT  L.request_session_id AS SPID, 
        DB_NAME(L.resource_database_id) AS DatabaseName,
        O.Name AS LockedObjectName, 
        P.object_id AS LockedObjectId, 
        L.resource_type AS LockedResource, 
        L.request_mode AS LockType,
        L.request_status AS LockStatus,
        ST.text AS SqlStatementText,        
        ES.login_name AS LoginName,
        ES.host_name AS HostName,
        TST.is_user_transaction as IsUserTransaction,
        AT.name as TransactionName,
        CN.auth_scheme as AuthenticationMethod
FROM    sys.dm_tran_locks L
        JOIN sys.partitions P ON P.hobt_id = L.resource_associated_entity_id
        JOIN sys.objects O ON O.object_id = P.object_id
        JOIN sys.dm_exec_sessions ES ON ES.session_id = L.request_session_id
        JOIN sys.dm_tran_session_transactions TST ON ES.session_id = TST.session_id
        JOIN sys.dm_tran_active_transactions AT ON TST.transaction_id = AT.transaction_id
        JOIN sys.dm_exec_connections CN ON CN.session_id = ES.session_id
        CROSS APPLY sys.dm_exec_sql_text(CN.most_recent_sql_handle) AS ST
WHERE   resource_database_id = db_id()
ORDER BY L.request_session_id


-- Rows Per Second
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

DECLARE @Sample TABLE (tableid int, tablename VARCHAR(255), tablerows bigint, ts datetime);

INSERT INTO @Sample    
SELECT id, OBJECT_NAME(id), rows, GETDATE() FROM sysindexes WHERE indid < 2

WAITFOR DELAY '00:00:10';

SELECT s.tablename, s.tablerows, si.rows, si.rows - s.tablerows as rowdiff
    , (si.rows - s.tablerows) / datediff(second, s.ts, getdate()) as rps
FROM @Sample s
    join sysindexes si on s.tableid = si.id
WHERE si.indid < 2 and s.tablerows != si.rows;


--Clear Stats:  High CPU/Resource Command.
--DBCC FREEPROCCACHE
--DBCC DROPCLEANBUFFERS


     
--file latency
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
DECLARE @dm_io_virtual_file_stats TABLE (
    database_id SMALLINT,file_id SMALLINT,sample_ms INT,num_of_reads BIGINT,num_of_bytes_read BIGINT,
    io_stall_read_ms BIGINT,num_of_writes BIGINT,num_of_bytes_written BIGINT,io_stall_write_ms BIGINT,
    io_stall BIGINT,size_on_disk_bytes BIGINT,file_handle VARBINARY(500),[ts] [datetime] );
 
INSERT INTO @dm_io_virtual_file_stats SELECT dio.*,GETDATE() FROM sys.dm_io_virtual_file_stats(NULL,NULL) dio;

WAITFOR DELAY '00:00:20';

SELECT 
    LEFT ([mf].[physical_name], 2) AS [drive],
    DB_NAME ([I].[database_id]) AS [database],
	[mf].[physical_name],
    [read_latency_ms] =
        CASE WHEN [I].[num_of_reads] - [S].[num_of_reads] = 0
            THEN 0 ELSE (([I].[io_stall_read_ms] - [S].[io_stall_read_ms]) / ([I].[num_of_reads] - [S].[num_of_reads])) END,
    [write_latency_ms] =
        CASE WHEN [I].[num_of_writes] - [S].[num_of_writes] = 0
            THEN 0 ELSE (([I].[io_stall_write_ms] - [S].[io_stall_write_ms]) / ([I].[num_of_writes] - [S].[num_of_writes])) END,
    [read_kbps] =
        CASE WHEN [I].[num_of_bytes_read] - [S].[num_of_bytes_read] = 0
            THEN 0 ELSE convert(decimal(10,1),([I].[num_of_bytes_read] - [S].[num_of_bytes_read]) / 1024.0 / datediff( second, [S].ts, getdate())) END,
    [write_kbps] =
        CASE WHEN [I].[num_of_bytes_written] - [S].[num_of_bytes_written] = 0
            THEN 0 ELSE convert(decimal(10,1),([I].[num_of_bytes_written] - [S].[num_of_bytes_written]) / 1024.0 / datediff( second, [S].ts, getdate())) END,
    [read_ops] =
        CASE WHEN [I].[num_of_reads] - [S].[num_of_reads] = 0
            THEN 0 ELSE convert(decimal(10,1),([I].[num_of_reads] - [S].[num_of_reads]) / 1.0 / datediff( second, [S].ts, getdate())) END,
    [write_ops] =
        CASE WHEN [I].[num_of_writes] - [S].[num_of_writes] = 0
            THEN 0 ELSE convert(decimal(10,1),([I].[num_of_writes] - [S].[num_of_writes]) / 1.0 / datediff( second, [S].ts, getdate())) END
FROM  sys.dm_io_virtual_file_stats(NULL,NULL) I
    JOIN @dm_io_virtual_file_stats S ON I.database_id = S.database_id AND I.file_id = S.file_id
    JOIN sys.master_files AS [mf] ON [I].[database_id] = [mf].[database_id] AND [I].[file_id] = [mf].[file_id]
ORDER BY ([I].[num_of_reads] + [I].[num_of_writes] - [S].[num_of_reads] - [S].[num_of_writes]) desc


--is primary replica
SELECT count(*) FROM sys.databases d
JOIN sys.dm_hadr_availability_replica_states ars on d.replica_id = ars.replica_id
WHERE ars.role_desc = 'PRIMARY' and d.name = 'Inet_Hub_Content_6'
    
--Fragmentation for Currently Select DB
WITH tbl AS (
	SELECT      
		fi.index_id as Indexid     
		, fi.OBJECT_ID as Tableid
		, fi.index_type_desc AS IndexType 
		, CAST(fi.partition_number AS VARCHAR(10)) AS PartitionNumber     
		, fi.avg_page_space_used_in_percent AS CurrentDensity     
		, fi.avg_fragmentation_in_percent AS CurrentFragmentation    
		,page_count * 8 /1024 as SizeIndexMB
	FROM sys.dm_db_index_physical_stats(DB_ID(DB_NAME()), NULL, NULL, NULL, 'SAMPLED') AS fi      
	WHERE (fi.avg_fragmentation_in_percent >= 15  OR fi.avg_page_space_used_in_percent < 75)      
	  AND    page_count > 512     
	  -- Skip heaps     
	  AND fi.index_id > 0)
SELECT 
CurrTime = GETDATE(),
TableName = o.name,
SchemaName = s.name,
IndexName = i.Name,
Has_lob = CASE WHEN 1 = 0 THEN isnull ((select top 1 col.user_type_id from sys.columns col INNER JOIN sys.types ty ON col.user_type_id = ty.user_type_id WHERE col.object_id=w.Tableid   AND (ty.name IN('xml','image','text','ntext') OR (ty.name IN('varchar','nvarchar','varbinary') AND col.max_length = -1))) ,0)     
			ELSE isnull ((select top 1 col.user_type_id from sys.columns col INNER JOIN sys.types ty ON col.user_type_id = ty.user_type_id WHERE col.object_id=w.Tableid   AND (ty.name IN('image','text','ntext') )) ,0)     
			END,
PartitionCount = (SELECT COUNT(*) pcount     
	  FROM sys.partitions p     
	  where  p.Object_id = w.Tableid      
	  AND p.index_id = w.Indexid),
w.*, 
Page_Locks = i.allow_page_locks,
Object_Type=o.type,
Index_Disabled = i.is_disabled
FROM sys.objects o INNER JOIN 
     sys.schemas s ON o.schema_id = s.schema_id
	 INNER JOIN tbl w ON o.object_id = w.tableid 
	 INNER JOIN sys.indexes i ON w.tableid = i.object_id and w.indexid = i.index_id
ORDER BY CurrentFragmentation desc

--VLF Density
DECLARE @databaseList TABLE
( [dbid]             INT,    [dbname]           VARCHAR(256),    [executionOrder]   [int] IDENTITY(1,1) NOT NULL );
 
DECLARE @vlfDensity    TABLE
( [database_id]   INT,    [file_id]       INT,    [density]       DECIMAL(7,2),
  [unusedVLF]     INT,    [usedVLF]       INT,    [totalVLF]      INT );
 
-- Starting in SQL Server 2012, an extra column was added to LogInfo, named RecoveryUnitId
-- Need to accomodate SQL Server 2012 (version 11.0)
DECLARE @versionString VARCHAR(20), @serverVersion DECIMAL(10,5), @sqlServer2012Version DECIMAL(10,5);
 
SET        @versionString        = CAST(SERVERPROPERTY('productversion') AS VARCHAR(20));
SET        @serverVersion        = CAST(LEFT(@versionString,CHARINDEX('.', @versionString)) AS DECIMAL(10,5));
SET        @sqlServer2012Version = 11.0; -- SQL Server 2012
 
DECLARE @logInfoResult2012 TABLE
( [RecoveryUnitId]    INT NULL,    [FileId]            INT NULL,    [FileSize]          BIGINT NULL,
  [StartOffset]       BIGINT NULL, [FSeqNo]            INT NULL,    [Status]            INT NULL,
  [Parity]            TINYINT NULL,[CreateLSN]         NUMERIC(25, 0) NULL );

DECLARE @logInfoResult2008 TABLE
( [FileId]            INT NULL,    [FileSize]          BIGINT NULL, [StartOffset]       BIGINT NULL,
  [FSeqNo]            INT NULL,    [Status]            INT NULL,    [Parity]            TINYINT NULL,
  [CreateLSN]         NUMERIC(25, 0) NULL );
 
DECLARE
    @currentExecID  INT,
    @maxExecID      INT,
    @dbid               INT,
    @dbName             VARCHAR(256);
 
INSERT INTO @databaseList ([dbid], [dbname]) SELECT [database_id], [name] FROM [sys].[databases] where [state] = 0;
 
SELECT @currentExecID = MIN([executionOrder]),  @maxExecID = MAX([executionOrder]) FROM @databaseList;
 
WHILE @currentExecID <= @maxExecID
BEGIN

    SELECT @dbid = [dbid], @dbName = [dbname] FROM @databaseList WHERE [executionOrder] = @currentExecID;

    IF(@serverVersion >= @sqlServer2012Version)
        BEGIN
            -- Use the new version of the table 
            DELETE @logInfoResult2012 FROM @logInfoResult2012;

            INSERT INTO @logInfoResult2012
            EXEC('DBCC LOGINFO([' + @dbName + ']) WITH NO_INFOMSGS');

            INSERT INTO @vlfDensity ( [database_id], [density], [unusedVLF], [usedVLF], [totalVLF] )
            SELECT @dbid, null, 
                SUM(CASE WHEN [Status] = 0 THEN 1 ELSE 0 END), 
                SUM(CASE WHEN [Status] = 2 THEN 1 ELSE 0 END), 
                COUNT(*)
            FROM @logInfoResult2012
            GROUP BY FileId;
        END          
    ELSE
        BEGIN
            -- Use the old version of the table 
            DELETE @logInfoResult2008 FROM @logInfoResult2008;

            INSERT INTO @logInfoResult2008
            EXEC('DBCC LOGINFO([' + @dbName + ']) WITH NO_INFOMSGS');


            INSERT INTO @vlfDensity ( [database_id], [file_id], [density], [unusedVLF], [usedVLF], [totalVLF] )
            SELECT @dbid, FileId, null, 
                SUM(CASE WHEN [Status] = 0 THEN 1 ELSE 0 END), 
                SUM(CASE WHEN [Status] = 2 THEN 1 ELSE 0 END), 
                COUNT(*)
            FROM @logInfoResult2008 
            GROUP BY FileId;
        END      

    SET @currentExecID = @currentExecID + 1;
END
 
UPDATE @vlfDensity SET [density] = CASE WHEN [totalVLF] = 0 THEN 0 ELSE CONVERT(DECIMAL(7,2),[usedVLF]) / CONVERT(DECIMAL(7,2),[totalVLF]) * 100 END;

SELECT d.dbname, mf.name, mf.physical_name, vlf.density, vlf.unusedVLF, vlf.usedVLF, vlf.totalVLF
      ,CAST(ROUND(mf.size/128.0,1) as decimal(10,1)) AS [Size MB]
      ,CASE WHEN mf.is_percent_growth = 1 THEN CAST(mf.growth as varchar) + '%' ELSE CAST(FLOOR(ROUND(mf.growth/128.0,0)) as varchar) END AS [Growth]
FROM @vlfDensity vlf 
    LEFT JOIN @databaseList d on vlf.database_id = d.dbid
    LEFT JOIN sys.master_files mf on vlf.database_id = mf.database_id and vlf.file_id = mf.file_id
ORDER BY [totalVLF] DESC, [density] DESC;



--Backup History
SELECT bup.user_name AS [User],
 bup.database_name AS [Database],
 bup.server_name AS [Server],
 bup.type, convert(numeric(10,1), bup.backup_size / 1024 / 1024) as [SizeMB],
 bup.backup_start_date AS [Backup Started],
 bup.backup_finish_date AS [Backup Finished]
 ,CAST((CAST(DATEDIFF(s, bup.backup_start_date, bup.backup_finish_date) AS int))/3600 AS varchar) + ' hours, ' 
 + CAST((CAST(DATEDIFF(s, bup.backup_start_date, bup.backup_finish_date) AS int))/60 AS varchar)+ ' minutes, '
 + CAST((CAST(DATEDIFF(s, bup.backup_start_date, bup.backup_finish_date) AS int))%60 AS varchar)+ ' seconds'
 AS [Total Time]
FROM msdb.dbo.backupset bup
--WHERE bup.database_name = DB_NAME()
ORDER BY bup.backup_start_date desc
     

-- Table Sizes:
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SELECT s.Name AS SchemaName, t.NAME AS TableName, p.rows AS RowCounts,
    SUM(a.total_pages) / 128 AS TotalSpaceMB, SUM(a.used_pages) / 128 AS UsedSpaceMB, (SUM(a.total_pages) - SUM(a.used_pages)) / 128 AS UnusedSpaceMB,
    REPLACE(p.data_compression_desc,'NONE','') [Compression]
FROM sys.tables t
INNER JOIN sys.indexes i ON t.OBJECT_ID = i.object_id
INNER JOIN sys.partitions p ON i.object_id = p.OBJECT_ID AND i.index_id = p.index_id
INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
LEFT OUTER JOIN sys.schemas s ON t.schema_id = s.schema_id
WHERE t.NAME NOT LIKE 'dt%' 
    AND t.is_ms_shipped = 0
    AND i.OBJECT_ID > 255 
GROUP BY s.Name, t.Name, p.Rows, p.data_compression_desc
ORDER BY s.Name, t.Name;


-- Index Detailed
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SELECT DB_NAME() AS [database], OBJECT_SCHEMA_NAME(i.object_id) AS [schema], OBJECT_NAME(i.object_id) AS [table], i.name AS [index]
  , p.rows 
  , (select SUM(used_pages)/128 from sys.allocation_units a where a.container_id = p.partition_id) as size_mb
  , ius.user_seeks, ius.user_scans, ius.user_lookups, ius.user_updates, ius.last_user_seek, ius.last_user_scan, ius.last_user_lookup, ius.last_user_update
  , i.type_desc, i.is_primary_key, i.is_unique, i.fill_factor, i.is_disabled
  , SUBSTRING((SELECT ', ' + c.name  
               FROM sys.index_columns ic
                   JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
               WHERE ic.object_id = i.object_id AND ic.index_id = i.index_id and ic.is_included_column = 0
               ORDER BY ic.key_ordinal FOR XML PATH('')), 3, 2048) 'columns'
  , SUBSTRING((SELECT ', ' + c.name  
               FROM sys.index_columns ic
                   JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
               WHERE ic.object_id = i.object_id AND ic.index_id = i.index_id and ic.is_included_column = 1
               ORDER BY ic.key_ordinal FOR XML PATH('')), 3, 2048) 'include'
FROM sys.indexes AS i 
  LEFT JOIN sys.dm_db_index_usage_stats AS ius ON ius.database_id = DB_ID() and ius.index_id = i.index_id and ius.object_id = i.object_id
  INNER JOIN sys.partitions AS p on p.object_id = i.object_id and p.index_id = i.index_id
WHERE i.type > 0 and OBJECT_SCHEMA_NAME(i.object_id) != 'sys'
ORDER by [database], [schema], [table], [columns], [index]


-- Index Fragmentation
SELECT OBJECT_NAME(ind.OBJECT_ID) AS TableName, 
    ind.name AS IndexName, indexstats.index_type_desc AS IndexType, 
    indexstats.avg_fragmentation_in_percent 
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, NULL) indexstats 
INNER JOIN sys.indexes ind ON ind.object_id = indexstats.object_id AND ind.index_id = indexstats.index_id 
WHERE indexstats.avg_fragmentation_in_percent > 30 
ORDER BY indexstats.avg_fragmentation_in_percent DESC
   
-- Physical Only Health Check
DECLARE @dbs TABLE ( db_name varchar(255), db_check int ) 
DECLARE @db_name varchar(255)
DECLARE @sql nvarchar(1000)
DECLARE @msg nvarchar(1000)
DECLARE @max int
DECLARE @itr int

SET NOCOUNT ON

INSERT INTO @dbs 
SELECT name, 0 FROM sys.databases WHERE state_desc = 'ONLINE' and name != 'tempdb';

SELECT @itr = 1, @max = COUNT(*) FROM @dbs
WHILE @itr <= @max
BEGIN
	SET @itr = @itr + 1
    SELECT top 1 @db_name = db_name FROM @dbs WHERE db_check = 0
    SET @sql = N'dbcc checkdb (' + @db_name + ') with physical_only'
	SET @msg = char(13) + Convert(nvarchar(255),GETDATE(),120) + char(13) +  @sql
    RAISERROR( @msg, 0 ,1 ) WITH NOWAIT
    exec sp_executesql @sql
	UPDATE @dbs SET db_check = 1 where db_name = @db_name
END

SET NOCOUNT OFF


--2012+ SQL ERRORLOG Location
SELECT is_enabled,[path],max_size,max_files
FROM Sys.dm_os_server_diagnostics_log_configurations
   
   
--FileGroup File Health
use [LoggingDB];
SELECT
  CAST(100.0 * (f.size - CAST(FILEPROPERTY(f.name, 'SpaceUsed') AS int)) / f.size AS decimal(10,1)) AS [Percentage Free]
, CAST(f.size/128.0 - CAST(FILEPROPERTY(f.name, 'SpaceUsed') AS int)/128.0 AS decimal(10,2)) AS [Available Space In MB]
, CAST((f.size/128.0) AS decimal(10,2)) AS [Total Size in MB]
, f.*
, fg.*
, d.*
FROM sys.databases d WITH (NOLOCK)
  JOIN sys.master_files f WITH (NOLOCK) ON d.database_id = f.database_id
  LEFT OUTER JOIN sys.data_spaces AS fg WITH (NOLOCK) ON f.data_space_id = fg.data_space_id
WHERE d.name = DB_NAME() OPTION (RECOMPILE);

--Drive Space
--2008+
SELECT 
  DISTINCT DB_NAME(dovs.database_id) DBName
, mf.physical_name PhysicalFileLocation
, dovs.logical_volume_name AS LogicalName
, dovs.volume_mount_point AS Drive
, CONVERT(INT,dovs.available_bytes/1048576.0) AS FreeSpaceInMB
FROM sys.master_files mf
  CROSS APPLY sys.dm_os_volume_stats(mf.database_id, mf.FILE_ID) dovs
ORDER BY FreeSpaceInMB ASC
GO

--Drive Space
--2005
DECLARE @t TABLE ( Name NVARCHAR(50), FreeSpaceMB INT ) 
INSERT INTO @t EXEC xp_fixeddrives 
SELECT * from @t
GO


    
-- Transactions Per Second
-- ignore master as it's mostly in memory tps regarding perf monitor and system internals
DECLARE @dm_os_performance_counters TABLE (object_name nchar(128), counter_name nchar(128), instance_name nchar(128), cntr_value bigint, cntr_type int, ts datetime)

INSERT INTO @dm_os_performance_counters
SELECT object_name, counter_name, instance_name, cntr_value, cntr_type, GETDATE() FROM sys.dm_os_performance_counters WHERE counter_name = 'Transactions/sec' 

WAITFOR DELAY '00:00:10';

SELECT d1.instance_name, (d2.cntr_value - d1.cntr_value)/DATEDIFF(second, ts, GETDATE()) as tps
FROM @dm_os_performance_counters  d1
JOIN sys.dm_os_performance_counters d2 on d1.object_name = d2.object_name and d1.counter_name = d2.counter_name and d1.instance_name = d2.instance_name
WHERE d2.cntr_value > d1.cntr_value and d1.instance_name not in ('_Total','master')
ORDER BY TPS DESC    

--System Waits
WITH [Waits] AS
    (SELECT
        [wait_type],
        [wait_time_ms] / 1000.0 AS [WaitS],
        ([wait_time_ms] - [signal_wait_time_ms]) / 1000.0 AS [ResourceS],
        [signal_wait_time_ms] / 1000.0 AS [SignalS],
        [waiting_tasks_count] AS [WaitCount],
        100.0 * [wait_time_ms] / SUM ([wait_time_ms]) OVER() AS [Percentage],
        ROW_NUMBER() OVER(ORDER BY [wait_time_ms] DESC) AS [RowNum]
    FROM sys.dm_os_wait_stats
    WHERE [wait_type] NOT IN (
        N'BROKER_EVENTHANDLER',             N'BROKER_RECEIVE_WAITFOR',
        N'BROKER_TASK_STOP',                N'BROKER_TO_FLUSH',
        N'BROKER_TRANSMITTER',              N'CHECKPOINT_QUEUE',
        N'CHKPT',                           N'CLR_AUTO_EVENT',
        N'CLR_MANUAL_EVENT',                N'CLR_SEMAPHORE',
        N'DBMIRROR_DBM_EVENT',              N'DBMIRROR_EVENTS_QUEUE',
        N'DBMIRROR_WORKER_QUEUE',           N'DBMIRRORING_CMD',
        N'DIRTY_PAGE_POLL',                 N'DISPATCHER_QUEUE_SEMAPHORE',
        N'EXECSYNC',                        N'FSAGENT',
        N'FT_IFTS_SCHEDULER_IDLE_WAIT',     N'FT_IFTSHC_MUTEX',
        N'HADR_CLUSAPI_CALL',               N'HADR_FILESTREAM_IOMGR_IOCOMPLETION',
        N'HADR_LOGCAPTURE_WAIT',            N'HADR_NOTIFICATION_DEQUEUE',
        N'HADR_TIMER_TASK',                 N'HADR_WORK_QUEUE',
        N'KSOURCE_WAKEUP',                  N'LAZYWRITER_SLEEP',
        N'LOGMGR_QUEUE',                    N'ONDEMAND_TASK_QUEUE',
        N'PWAIT_ALL_COMPONENTS_INITIALIZED',
        N'QDS_PERSIST_TASK_MAIN_LOOP_SLEEP',
        N'QDS_CLEANUP_STALE_QUERIES_TASK_MAIN_LOOP_SLEEP',
        N'REQUEST_FOR_DEADLOCK_SEARCH',     N'RESOURCE_QUEUE',
        N'SERVER_IDLE_CHECK',               N'SLEEP_BPOOL_FLUSH',
        N'SLEEP_DBSTARTUP',                 N'SLEEP_DCOMSTARTUP',
        N'SLEEP_MASTERDBREADY',             N'SLEEP_MASTERMDREADY',
        N'SLEEP_MASTERUPGRADED',            N'SLEEP_MSDBSTARTUP',
        N'SLEEP_SYSTEMTASK',                N'SLEEP_TASK',
        N'SLEEP_TEMPDBSTARTUP',             N'SNI_HTTP_ACCEPT',
        N'SP_SERVER_DIAGNOSTICS_SLEEP',     N'SQLTRACE_BUFFER_FLUSH',
        --N'SQLTRACE_INCREMENTAL_FLUSH_SLEEP',
        N'SQLTRACE_WAIT_ENTRIES',           N'WAIT_FOR_RESULTS',
        N'WAITFOR',                         N'WAITFOR_TASKSHUTDOWN',
        N'WAIT_XTP_HOST_WAIT',              N'WAIT_XTP_OFFLINE_CKPT_NEW_LOG',
        N'WAIT_XTP_CKPT_CLOSE',             N'XE_DISPATCHER_JOIN',
        N'DBMIRROR_DBM_MUTEX',              N'DBMIRROR_SEND',
        N'XE_DISPATCHER_WAIT',              N'XE_TIMER_EVENT')
    AND [waiting_tasks_count] > 0
 )
SELECT
    MAX ([W1].[wait_type]) AS [WaitType],
    CAST (MAX ([W1].[WaitS]) AS DECIMAL (16,2)) AS [Wait_S],
    CAST (MAX ([W1].[ResourceS]) AS DECIMAL (16,2)) AS [Resource_S],
    CAST (MAX ([W1].[SignalS]) AS DECIMAL (16,2)) AS [Signal_S],
    MAX ([W1].[WaitCount]) AS [WaitCount],
    CAST (MAX ([W1].[Percentage]) AS DECIMAL (5,2)) AS [Percentage],
    CAST ((MAX ([W1].[WaitS]) / MAX ([W1].[WaitCount])) AS DECIMAL (16,4)) AS [AvgWait_S],
    CAST ((MAX ([W1].[ResourceS]) / MAX ([W1].[WaitCount])) AS DECIMAL (16,4)) AS [AvgRes_S],
    CAST ((MAX ([W1].[SignalS]) / MAX ([W1].[WaitCount])) AS DECIMAL (16,4)) AS [AvgSig_S]
FROM [Waits] AS [W1]
INNER JOIN [Waits] AS [W2]
    ON [W2].[RowNum] <= [W1].[RowNum]
GROUP BY [W1].[RowNum]
HAVING SUM ([W2].[Percentage]) - MAX ([W1].[Percentage]) < 95; -- percentage threshold
GO


--Compression Status
SELECT object_name(sp1.object_id), 100.0 * sp1.rows / sp2.rows, * 
FROM sys.partitions sp1
    JOIN sys.partitions sp2 on sp1.object_id = sp2.object_id and sp1.index_id = sp2.index_id
WHERE sp1.data_compression_desc != 'NONE' AND sp2.data_compression_desc = 'NONE' 


--Table Row Count:

SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET NOCOUNT ON;

declare @table_rowcount table (db_name nvarchar(128), schema_name sysname, object_name sysname, row_count bigint, total_size numeric(10,2), index_size numeric(10,2))

declare @databases table (itr int identity, dbname sysname);
declare @itr int, @total int, @dbname sysname, @sql nvarchar(1024);
insert into @databases (dbname) select name from sys.databases where state = 0 and database_id > 4;
select @itr = min(itr), @total = count(*) from @databases;
while @itr <= @total
begin
	select @itr = itr + 1, @dbname = dbname from @databases where itr = @itr;
	set @sql = 'use [' + @dbname + ']; 
        select DB_NAME(), OBJECT_SCHEMA_NAME(ps.object_id), t.name, SUM(CASE WHEN (ps.index_id < 2) THEN row_count ELSE 0 END), SUM (ps.used_page_count) / 128.0, 
               SUM (ps.used_page_count - 
                    CASE WHEN (ps.index_id < 2) THEN (ps.in_row_data_page_count + ps.lob_used_page_count + ps.row_overflow_used_page_count)
                         ELSE (ps.lob_used_page_count + ps.row_overflow_used_page_count) END ) / 128.0
        from sys.dm_db_partition_stats ps
        join sys.tables t on ps.object_id = t.object_id
        group by ps.object_id, t.name'
    insert into @table_rowcount
        exec sp_executesql @sql;
end 

select * from @table_rowcount order by row_count desc



--- Duplicate Index Finder ---
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
with index_details as (
SELECT DB_NAME() AS [database], OBJECT_SCHEMA_NAME(i.object_id) AS [schema], OBJECT_NAME(i.object_id) AS [table], i.name AS [index]
  , p.rows 
  , (select SUM(used_pages)/128 from sys.allocation_units a where a.container_id = p.partition_id) as size_mb
  , ius.user_seeks, ius.user_scans, ius.user_lookups, ius.user_updates, ius.last_user_seek, ius.last_user_scan, ius.last_user_lookup, ius.last_user_update
  , i.type_desc, i.is_primary_key, i.is_unique, i.fill_factor, i.is_disabled
  , SUBSTRING((SELECT ', ' + c.name  
     FROM sys.index_columns ic
       JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
     WHERE ic.object_id = i.object_id AND ic.index_id = i.index_id and ic.is_included_column = 0
     ORDER BY ic.key_ordinal FOR XML PATH('')), 3, 2048) 'columns'
  , SUBSTRING((SELECT ', ' + c.name  
     FROM sys.index_columns ic
       JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
     WHERE ic.object_id = i.object_id AND ic.index_id = i.index_id and ic.is_included_column = 1
     ORDER BY ic.key_ordinal FOR XML PATH('')), 3, 2048) 'include'
FROM sys.indexes AS i 
  LEFT JOIN sys.dm_db_index_usage_stats AS ius ON ius.database_id = DB_ID() and ius.index_id = i.index_id and ius.object_id = i.object_id
  INNER JOIN sys.partitions AS p on p.object_id = i.object_id and p.index_id = i.index_id
WHERE i.type > 0 and OBJECT_SCHEMA_NAME(i.object_id) != 'sys'
--ORDER by [database], [schema], [table], [columns], [index]
), dupfinder as (
select MIN([index]) a, MAX([index]) b from index_details
group by [table],[schema]
having COUNT(*) > 1 and (MIN([columns]) = MAX([columns]) 
                      or MIN([columns]) + ';' like replace(MAX([columns]),',','%') + ';%'
                      or MAX([columns]) + ';' like replace(MIN([columns]),',','%') + ';%' ))
select id.* from index_details id
join dupfinder df on id.[index] in (df.a, df.b)
ORDER by [database], [schema], [table], [columns], [index] desc


--- Statistics Detail ---
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SELECT OBJECT_NAME(sp.object_id) AS TableName
  , sp.stats_id, s.name, sp.last_updated, sp.rows, sp.rows_sampled, sp.unfiltered_rows, sp.modification_counter
FROM sys.stats AS s
  OUTER APPLY sys.dm_db_stats_properties (s.object_id,s.stats_id) AS sp
WHERE OBJECTPROPERTY(s.OBJECT_ID,'IsUserTable') = 1
ORDER BY sp.modification_counter desc;

--- Index Me please ---
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET NOCOUNT ON;

declare @table_rowcount table (database_id bigint, object_id bigint, row_count bigint);

declare @databases table (itr int identity, dbname sysname);
declare @itr int, @total int, @dbname sysname, @sql nvarchar(512), @uptime int;

select @uptime = datediff(minute,create_date,getdate()) from sys.databases where NAME='tempdb'

insert into @databases (dbname) select name from sys.databases where state = 0 and database_id > 4;
select @itr = min(itr), @total = count(*) from @databases;

while @itr <= @total
begin
	select @itr = itr + 1, @dbname = dbname from @databases where itr = @itr;
	set @sql = 'use [' + @dbname + ']; select DB_ID(), ps.object_id, SUM (row_count) 
		from sys.dm_db_partition_stats ps join sys.tables t on ps.object_id = t.object_id
		where index_id in (0,1) group by ps.object_id'
	insert into @table_rowcount
		exec sp_executesql @sql;
end

select id.[statement] as table_fullname
     , id.[equality_columns], id.[inequality_columns], id.[included_columns] 
     , gs.[unique_compiles] as compiles, gs.[user_seeks] as seeks, 60 * gs.[user_seeks] / @uptime as seek_per_hour
     , cast(gs.[avg_total_user_cost] as numeric(20,5)) AS [avg_cost], gs.[avg_user_impact] as [avg_impact]
     , cast(gs.[user_seeks] * gs.[avg_total_user_cost] * (gs.[avg_user_impact] * 0.01) as numeric(20,2)) AS index_advantage
     , tr.row_count
     , 'CREATE INDEX [DBA_IX_' + replace(OBJECT_SCHEMA_NAME(id.[object_id], db.[database_id]) + '_','dbo_','') + OBJECT_NAME(id.[object_id], db.[database_id]) + '_' + REPLACE(REPLACE(REPLACE(ISNULL(id.[equality_columns], ''), ', ', '_'), '[', ''), ']', '') + CASE
        WHEN id.[equality_columns] IS NOT NULL
            AND id.[inequality_columns] IS NOT NULL
            THEN '_'
        ELSE ''
        END + REPLACE(REPLACE(REPLACE(ISNULL(id.[inequality_columns], ''), ', ', '_'), '[', ''), ']', '') + '] ON ' + id.[statement] + ' (' + ISNULL(id.[equality_columns], '') + CASE
        WHEN id.[equality_columns] IS NOT NULL
            AND id.[inequality_columns] IS NOT NULL
            THEN ','
        ELSE ''
        END + ISNULL(id.[inequality_columns], '') + ')' + ISNULL(' INCLUDE (' + id.[included_columns] + ')', '') + ' WITH (ONLINE=ON)' AS [ProposedIndex]
     , gs.[last_user_seek] 
FROM [sys].[dm_db_missing_index_group_stats] gs 
    join [sys].[dm_db_missing_index_groups] ig  ON gs.[group_handle] = ig.[index_group_handle]
    join [sys].[dm_db_missing_index_details] id ON ig.[index_handle] = id.[index_handle]
    join [sys].[databases] db                   ON db.[database_id] = id.[database_id]
    join @table_rowcount tr                     ON db.[database_id] = tr.database_id and id.object_id = tr.object_id
WHERE gs.last_user_seek > GETDATE() - 1 and id.database_id > 4
ORDER BY index_advantage DESC
OPTION (RECOMPILE);

-- Auto Growth Data/Log Trace
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

DECLARE @active_trc varchar(MAX);
DECLARE @startat_trc varchar(MAX);

DECLARE @curr_idx varchar(6);
DECLARE @startat_idx varchar(6);
DECLARE @lookback int;

SET @lookback = 5;

SELECT @active_trc = path, @lookback = case when @lookback <= max_files then max_files - 1 else @lookback end FROM sys.traces WHERE is_default = 1;

SET @curr_idx = substring(@active_trc, charindex('_',@active_trc, len(@active_trc) - 10) + 1, len(@active_trc) - charindex('_',@active_trc, len(@active_trc) - 10) - 4);
SET @startat_idx = CASE WHEN cast(@curr_idx as int) <= @lookback THEN '1' ELSE cast(cast(@curr_idx as int) - @lookback as varchar) END;
SET @startat_trc = replace(@active_trc, '_' + @curr_idx + '.', '_' + @startat_idx + '.');

print 'Starting at trace file : ' + @startat_trc;

SELECT SessionLoginName, te.Name as EventClass, DatabaseName, FileName, SUM(IntegerData)/128.0 AS GrowthMB, StartTime, Duration/1000 AS DurationMS
FROM ::fn_trace_gettable(@startat_trc, default) trc
    JOIN sys.trace_events te on te.trace_event_id = trc.EventClass
WHERE EventClass in (92, 93) -- File Auto Grow
GROUP BY DatabaseName, te.Name , SessionLoginName, FileName, IntegerData, StartTime, Duration
ORDER BY StartTime DESC;

GO

-- Using Enterprise Features
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET NOCOUNT ON;

declare @dm_db_persisted_sku_features table (dbname sysname, feature_name sysname, feature_id int);

declare @databases table (itr int identity, dbname sysname);
declare @itr int, @total int, @dbname sysname, @sql nvarchar(512), @uptime int;

insert into @databases (dbname) select name from sys.databases where state = 0 and database_id > 4;
select @itr = min(itr), @total = count(*) from @databases;

while @itr <= @total
begin
	select @itr = itr + 1, @dbname = dbname from @databases where itr = @itr;
	set @sql = 'use [' + @dbname + ']; SELECT DB_NAME(), * FROM sys.dm_db_persisted_sku_features '
	insert into @dm_db_persisted_sku_features
		exec sp_executesql @sql;
end

select * from @dm_db_persisted_sku_features

--generate definition for system tables
declare @systbl varchar(255);
declare @definetbl nvarchar(max);

set @systbl = 'master_files';

set @definetbl = 'declare @' + @systbl + ' table (';
select @definetbl = @definetbl + c.name + ' ' + 
   t.name +
   case when t.name in ('char', 'varchar','nchar','nvarchar') then '('+
             case when c.length=-1 then 'max'
                  else convert(varchar(4),
                               case when t.name in ('nchar','nvarchar')
                               then  c.length/2 else c.length end )
                  end +')'
          when t.name in ('decimal','numeric')
                  then '('+ convert(varchar(4),c.xprec)+','
                          + convert(varchar(4),c.xscale)+')'
                  else '' end + ', '
from    
    sys.syscolumns c
inner join 
    sys.systypes t on c.xtype = t.xtype and c.usertype = t.usertype
where
    c.id = object_id('sys.' + @systbl)
order by c.colorder

select left(@definetbl,len(@definetbl) - 1) + ');'

-- Encryption Status
SELECT
    db.name,
    db.is_encrypted,
    dm.encryption_state,
    dm.percent_complete,
    dm.key_algorithm,
    dm.key_length
FROM
    sys.databases db
    LEFT OUTER JOIN sys.dm_database_encryption_keys dm
        ON db.database_id = dm.database_id;
GO
--- cpu affinity calculation
select power(2,15) *      0 -- CPU 16
   +   power(2,14) *      0 -- CPU 15
   +   power(2,13) *      0 -- CPU 14
   +   power(2,12) *      0 -- CPU 13
   +   power(2,11) *      0 -- CPU 12
   +   power(2,10) *      0 -- CPU 11
   +   power(2,9)  *      0 -- CPU 10
   +   power(2,8)  *      0 -- CPU 9
   +   power(2,7)  *      0 -- CPU 8
   +   power(2,6)  *      0 -- CPU 7
   +   power(2,5)  *      0 -- CPU 6
   +   power(2,4)  *      0 -- CPU 5
   +   power(2,3)  *      0 -- CPU 4
   +   power(2,2)  *      0 -- CPU 3
   +   power(2,1)  *      1 -- CPU 2
   +   power(2,0)  *      1 -- CPU 1


--- admin audit

SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
select loginname, is_disabled, sysadmin, securityadmin, serveradmin, setupadmin, processadmin, diskadmin, dbcreator, bulkadmin, is_policy_checked 
from sys.syslogins s left join sys.sql_logins sl on s.sid = sl.sid
where 1 in (sysadmin, securityadmin, serveradmin, setupadmin, processadmin, diskadmin, dbcreator, bulkadmin)

-- login review:
select createdate, loginname, sysadmin, is_disabled from sys.syslogins s left join sys.sql_logins sl on s.sid = sl.sid;



-- Last DBCC Check
DBCC DBINFO (AdventureWorks2008R2) WITH TABLERESULTS
-- Look for dbi_dbccLastKnownGood

