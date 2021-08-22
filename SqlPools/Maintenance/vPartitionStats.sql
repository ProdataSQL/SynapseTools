SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[vPartitionStats]') AND type in (N'V'))
EXEC dbo.sp_executesql @statement = N'CREATE VIEW [dbo].[vPartitionStats] AS SELECT 1 as Dummy'
GO
ALTER VIEW [dbo].[vPartitionStats]
AS with
/*
	Description:Return data on outdated and missing statistics. Use this for Index Maintenance
	Source:		https://github.com/ProdataSQL/SynapseTools
				Concept copied from https://github.com/abrahams1/Azure_Synapse_Toolbox/tree/master/SQL_Queries/Statistics 
	History:	12/08/2021 Bob, Created
*/
cmp_summary as
(
	select tm.object_id, ps.partition_number, sum(ps.row_count) cmp_row_count
	from sys.dm_pdw_nodes_db_partition_stats ps
		inner join sys.pdw_nodes_tables nt on nt.object_id=ps.object_id and ps.distribution_id=nt.distribution_id 
		inner join sys.pdw_table_mappings tm on tm.physical_name=nt.name
	group by tm.object_id, ps.partition_number

)
, ctl_summary as
(
	select  t.object_id, s.name [schema_name], t.name table_name, case when ps.name is not null then p.partition_number end as partition_number, ps.name as partition_scheme, i.type_desc table_type, dp.distribution_policy_desc distribution_type, sum(p.rows) ctl_row_count
	from sys.schemas s
		inner join sys.tables t on t.schema_id=s.schema_id
		inner join sys.pdw_table_distribution_properties dp on dp.object_id=t.object_id
		inner join sys.indexes i on i.object_id=t.object_id and i.index_id<2
		inner join sys.partitions p on p.object_id=t.object_id and p.index_id=i.index_id
		left join sys.partition_schemes ps on ps.data_space_id=i.data_space_id
	group by t.object_id, s.name, t.name, i.type_desc, dp.distribution_policy_desc,p.partition_number, ps.name
)
, [all_results] as
(
	select ctl.object_id, ctl.[schema_name], ctl.table_name, ctl.partition_number, ctl.table_type, ctl.distribution_type
		, ctl.ctl_row_count as stats_row_count, cmp.cmp_row_count as actual_row_count, convert(decimal(10,2),(abs(ctl.ctl_row_count - cmp.cmp_row_count)*100.0 / nullif(cmp.cmp_row_count,0))) stats_difference_percent
		
	from ctl_summary ctl
		inner join cmp_summary cmp on ctl.object_id=cmp.object_id and (ctl.partition_number=cmp.partition_number or ctl.partition_number is null)

)
select * from [all_results];
GO


