/****** Object:  StoredProcedure [dbo].[sp_WhoIsActive]    Script Date: 08/05/2021 18:10:05 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROC [dbo].[sp_WhoIsActive] AS
/*
	Desc: Return Running Statements
	History: 29/03/2021 Bob, Created
*/
BEGIN
    SET NOCOUNT ON
	DECLARE @distribution_id int, @spid int
	
	SELECT * FROM dbo.Requests where status='running'

	SELECT TOP 1 @distribution_id= distribution_id , @spid=spid FROM sys.dm_pdw_sql_requests where status='running'
	IF @distribution_id is not null 
	BEGIN
		DBCC PDW_SHOWEXECUTIONPLAN (@distribution_id, @spid);
	END

	select* from  sys.dm_pdw_sql_requests where status='running'
END
GO


