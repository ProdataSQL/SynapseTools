-- ================================================================================
-- Create View template for Azure SQL Database and Azure Synapse Analytics Database
-- ================================================================================

IF object_id(N'vTableStats', 'V') IS NOT NULL
	DROP VIEW vTableStats
GO
CREATE VIEW vTableStats
AS
with
/*
	Description: Return data on outdated and missing statistics 
	Source:		
	History:	12/08/2021 Bob, Created
*/
Variables as 
(select 1000 as missing_row_count, 20 as OutdatedStatsPercent)
,
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
		, case 
			when (ctl.ctl_row_count = variables.missing_row_count) then 'missing stats'
			when ((ctl.ctl_row_count <> cmp.cmp_row_count) and ((abs(ctl.ctl_row_count - cmp.cmp_row_count)*100.0 / nullif(cmp.cmp_row_count,0)) > variables.OutdatedStatsPercent)) then 'outdated stats'
			else null
		  end stat_info
	from ctl_summary ctl
		inner join cmp_summary cmp on ctl.object_id=cmp.object_id and (ctl.partition_number=cmp.partition_number or ctl.partition_number is null)
		CROSS JOIN Variables
)
select * from [all_results]
