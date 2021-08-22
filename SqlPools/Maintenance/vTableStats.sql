SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[vTableStats]') AND type in (N'V'))
EXEC dbo.sp_executesql @statement = N'CREATE VIEW [dbo].[vTableStats] AS SELECT 1 as Dummy'
GO
ALTER VIEW [dbo].[vTableStats] AS with
/*
	Description:Return data on outdated and missing statistics. Use this for Index Maintenance
	Source:		https://github.com/ProdataSQL/SynapseTools
				Concept copied from https://github.com/abrahams1/Azure_Synapse_Toolbox/tree/master/SQL_Queries/Statistics 
	History:	12/08/2021 Bob, Created
*/
cmp_summary as
(
	select tm.object_id, sum(ps.row_count) cmp_row_count
	, case when sum(ps.row_count) =0 then  100 else sqrt(sum(ps.row_count)) *1000/ sum(ps.row_count)*100 end as stats_sample_rate
	, convert(bigint,SQRT(1000 * sum(ps.row_count)))  as dynamic_threshold_rows
	from sys.dm_pdw_nodes_db_partition_stats ps
		inner join sys.pdw_nodes_tables nt on nt.object_id=ps.object_id and ps.distribution_id=nt.distribution_id 
		inner join sys.pdw_table_mappings tm on tm.physical_name=nt.name
	where ps.index_id<2
	group by tm.object_id

)
, ctl_summary as
(
	select  t.object_id, s.name [schema_name], t.name table_name,  i.type_desc table_type, dp.distribution_policy_desc distribution_type, sum(p.rows) ctl_row_count
	from sys.schemas s
		inner join sys.tables t on t.schema_id=s.schema_id
		inner join sys.pdw_table_distribution_properties dp on dp.object_id=t.object_id
		inner join sys.indexes i on i.object_id=t.object_id and i.index_id<2
		inner join sys.partitions p on p.object_id=t.object_id and p.index_id=i.index_id
	group by t.object_id, s.name, t.name, i.type_desc, dp.distribution_policy_desc
)
, [all_results] as
(
	select ctl.object_id, ctl.[schema_name], ctl.table_name, ctl.table_type, ctl.distribution_type
		, ctl.ctl_row_count as stats_row_count, cmp.cmp_row_count as actual_row_count, convert(decimal(10,2),(abs(ctl.ctl_row_count - cmp.cmp_row_count)*100.0 / nullif(cmp.cmp_row_count,0))) stats_difference_percent
		, convert(int,case when cmp.stats_sample_rate < 1 then 1 when cmp.stats_sample_rate > 100 then 100 else cmp.stats_sample_rate  end ) as stats_sample_rate
		, cmp.dynamic_threshold_rows
	from ctl_summary ctl
		inner join cmp_summary cmp on ctl.object_id=cmp.object_id
)
select [object_id], [schema_name], [table_name], [table_type], [distribution_type], [stats_row_count], [actual_row_count], [stats_difference_percent]
, dynamic_threshold_rows
, [stats_sample_rate]
, case when stats_difference_percent >=20  or abs([actual_row_count] - [stats_row_count]) > dynamic_threshold_rows then 1 else 0 end as recommend_update
,  'UPDATE STATISTICS ' + quotename([schema_name]) + '.' + quotename([table_name]) 
	+ coalesce(case when stats_sample_rate  >=100 THEN ' WITH FULLSCAN' ELSE  ' WITH SAMPLE ' + convert(varchar,stats_sample_rate)  + ' PERCENT' END,'') as sqlCommand
from [all_results];
GO


