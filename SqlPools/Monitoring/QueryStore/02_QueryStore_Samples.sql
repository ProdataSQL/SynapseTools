

/* Slowest Queries in last Week  */
SELECT TOP 10 *
FROM QueryStore
WHERE [last_execution_time] > DATEADD(day, -7, GETUTCDATE())
ORDER BY avg_Duration desc 

/* Last 10 Queries Ran  */
SELECT TOP 10 *
FROM QueryStore
ORDER BY last_execution_time desc 


/* Queries with > 1 Plan Executed in last week */
SELECT query_id
	, min(query_text) as query_text
	, count(*) as Plans
	, sum(count_executions) as executions
	, sum(avg_duration * count_executions) / sum(count_executions) as avg_duration
	, min(min_duration) as min_duration 
	, max(max_duration) as max_duration , max(last_execution_time) as last_execution_time
FROM QueryStore
WHERE [last_execution_time] > DATEADD(day, -7, GETUTCDATE())
GROUP BY query_id
HAVING COUNT(*) > 1
order by count(*) desc 

/* Show all the Plans for the query with most plans*/
SELECT TOP 10 * from QueryStore
where query_id=1949 


/* Find all calls from a Stored Procedure */
SELECT * FROM dbo.QueryStore 
WHERE  [object_id] = OBJECT_ID(N'Sales.usp_MyProc');


