/****** Object:  View [dbo].[Requests]    Script Date: 08/05/2021 18:09:21 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE VIEW [dbo].[Requests] AS WITH
/*
	Description: Return Data for SQLDW Requets, Steps, Operations in summary from
	used By:	 sp_WhoIsActive, sp_WhoWasActive
	History:	 11/04/2021 Bob, Created for Perf Tuning
				 11/04/2021 Bob, Filtered out Requests with no steps
*/
requests as 
	(
		select row_number() over (order by r.request_id desc ) as [#] ,   r.request_id, r.session_id, r.command 
		, r.submit_time, r.start_time, r.total_elapsed_time
		, end_time
		, r.status
		, r.resource_class
		, getdate() as collection_time 
		, s.login_name
		, s.app_name
		, s.client_id
		, s.sql_spid
		from sys.dm_pdw_exec_requests r
		INNER JOIN sys.dm_pdw_exec_sessions s on s.session_id=r.session_id
		WHERE r.session_id <> SESSION_ID ( ) 
		AND app_name <> 'Microsoft SQL Server Management Studio'
	),	steps as (
			select   request_id, operation_type , total_elapsed_time, SUBSTRING(command,1,(CHARINDEX(' ',command + ' ')-1)) as command
			From sys.dm_pdw_request_steps
			WHERE location_type='Compute'
	)
	select TOP 5000 r.[#], r.request_id,
	r.start_time	
	, r.end_time	
	, FORMAT(datediff( hh ,r.start_time	,r.end_time	 ), 'D2')  + ':' + FORMAT(datediff( mi ,r.start_time	,r.end_time	 ) % 60, 'D2') 
	+ ':' + FORMAT(datediff( ss ,r.start_time	,r.end_time	 ) % 60 % 60, 'D2') AS [Duration]
	, r.status,  r.total_elapsed_time as request_time_ms
	, m.total_elapsed_time as step_time_ms
	, r.command
	, m.steps, op.op_commands, m.operations
	, r.session_id
	, r.submit_time

		, r.resource_class
		, r.collection_time 
		, r.login_name
		, r.app_name
		, r.client_id
		, r.sql_spid
	from requests r
	LEFT JOIN (
		SELECT request_id, string_agg(command,',') WITHIN GROUP (ORDER BY total_elapsed_time DESC) as op_commands
		FROM (
			SELECT request_id, command + '(' + convert(varchar,count(*)) + ':' + convert(varchar,sum(total_elapsed_time)) +'ms)' as command , sum(total_elapsed_time) as total_elapsed_time
			FROM STEPS
			WHERE operation_type='OnOperation'
			group by request_id,command
		) op1
		GROUP BY request_id
	) op on op.request_id= r.request_id
	INNER JOIN (
		SELECT request_id, string_agg(operation,',') WITHIN GROUP (ORDER BY total_elapsed_time DESC) as operations, count(*) as steps, sum(total_elapsed_time) as total_elapsed_time
		FROM (
			SELECT request_id, replace(operation_type,'Operation','') + '(' + convert(varchar,count(*)) + ':' + convert(varchar,sum(total_elapsed_time)) +'ms)' as operation, sum(total_elapsed_time) as total_elapsed_time, count(*) as steps
			FROM STEPS
			group by request_id,operation_type
		) m1
		GROUP BY request_id
	) m on m.request_id= r.request_id
	order by r.submit_time desc;
GO


