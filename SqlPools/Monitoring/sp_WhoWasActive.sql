/****** Object:  StoredProcedure [dbo].[sp_WhoWasActive]    Script Date: 08/05/2021 18:10:25 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROC [dbo].[sp_WhoWasActive] AS
/*
	Desc: Return Running Statements
	History: 29/03/2021 Bob, Created
*/
BEGIN
    SET NOCOUNT ON;
	
	SELECT TOP 500 * FROM Requests 
	ORDER BY submit_time desc 

END
GO


