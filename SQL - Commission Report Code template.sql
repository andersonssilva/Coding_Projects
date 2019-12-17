DECLARE @ReportDate datetime --declaring variable that will receive the report's date of execution
SET @ReportDate='10/11/2019'; --insert here the initial date you are running the report

DECLARE @dateRef datetime --declaring variable that will read the commission report's month reference from SSRS. 
SET @dateRef = DATEADD(month, DATEDIFF(month, 0, @ReportDate), 0); --Setting as the first day of the month

DECLARE @reportYear AS date;--declaring variable that will hold the first date of the year for reconciliation purposes. 
SET @reportYear=DATEADD(year, DATEDIFF(year, 0, @dateRef), 0); --Getting 01/01 of the report current year

--------------------------------------------------------------------------------------------------------------------------------------------

if exists(SELECT * FROM tempdb.dbo.sysobjects WHERE ID = OBJECT_ID(N'tempdb..##asilva4_BrokerCompComm')) 
	DROP TABLE ##asilva4_BrokerCompComm

	--The code is to make sure all members are in the CMS Broker Compensation File can be found and connected to Ids table through the mCMShic.MemId for Commission 
;WITH BrokerCompComm AS(
	--From members where mCMShic has the HICN as value for the Commission side of the report
	SELECT DISTINCT bcf.Beneficiary_ID
		 , mCMShic.MemId
		 , mCMShic.Hic AS HIC
		 , CONCAT(bcf.Last_Name, ', ', bcf.First_Name, ' ', bcf.Middle_Initial) AS Member_Name
		 , bcf.DOB
		 , bcf.Effdate AS BCompEffdate
		 , bcf.Prior_Plan_Type
		 , bcf.Cycle_Year_as_of_Report_Generation_Date
		 , bcf.Report_Generation_Date
		 , bcf.Correction_AgentGroup4icator
	FROM YOURSERVER.DATABASE.SCHEMA.[MemberCmsHic] AS mCMShic
	JOIN YOURSERVER.DATABASE.SCHEMA.[vw_Agent_Broker_Compensation_File_MAPD_Most_Recent_Record] AS bcf ON RTRIM(mCMShic.HIC)=bcf.[Beneficiary_ID] 
		AND bcf.Effdate=@dateRef --filtering register from broker comp file by the member effdate
	UNION
	--From members where mCMShic has the MBI as value for the Commission side of the report
	SELECT DISTINCT bcf.Beneficiary_ID
		 , mCMShic.MemId
		 , HMC.HICN AS HIC
		 , CONCAT(bcf.Last_Name, ', ', bcf.First_Name, ' ', bcf.Middle_Initial) AS Member_Name
		 , bcf.DOB
		 , bcf.Effdate AS BCompEffdate
		 , bcf.Prior_Plan_Type
		 , bcf.Cycle_Year_as_of_Report_Generation_Date
		 , bcf.Report_Generation_Date
		 , bcf.Correction_AgentGroup4icator
	FROM YOURSERVER.DATABASE.SCHEMA.[MemberCmsHic] AS mCMShic
	JOIN YOURSERVER.DATABASE.SCHEMA.[vw_CMS_HICN_MBI_Crosswalk] AS HMC ON mCMShic.Hic=HMC.MBI
	JOIN YOURSERVER.DATABASE.SCHEMA.[vw_Agent_Broker_Compensation_File_MAPD_Most_Recent_Record] AS bcf ON RTRIM(HMC.HICN)=bcf.[Beneficiary_ID]
		AND bcf.Effdate=@dateRef --filtering register from broker comp file by the member effdate
	)
SELECT *
INTO ##asilva4_BrokerCompComm
FROM BrokerCompComm
--------------------------------------------------------------------------------------------------------------------------------------------

if exists(SELECT * FROM tempdb.dbo.sysobjects WHERE ID = OBJECT_ID(N'tempdb..##asilva4_BrokerCompCB')) 
	DROP TABLE ##asilva4_BrokerCompCB
	-- Claw back: retrieve previously paid commission due to member disenrollment
	--The code is to make sure all members in bcf can be found and connected to Ids table through the mCMShic.MemId for Clawback
;WITH BrokerCompCB AS(	
	--From members where mCMShic has the HICN as value for the Claw Back side of the report
	SELECT DISTINCT bcf.Beneficiary_ID
		 , mCMShic.MemId
		 , mCMShic.Hic AS HIC
		 , CONCAT(bcf.Last_Name, ', ', bcf.First_Name, ' ', bcf.Middle_Initial) AS Member_Name
		 , bcf.DOB
		 , bcf.Effdate AS BCompEffdate
		 , bcf.Prior_Plan_Type
		 , bcf.Cycle_Year_as_of_Report_Generation_Date
		 , bcf.Report_Generation_Date
		 , bcf.Correction_AgentGroup4icator
	FROM YOURSERVER.DATABASE.SCHEMA.[MemberCmsHic] AS mCMShic
	JOIN YOURSERVER.DATABASE.SCHEMA.[vw_Agent_Broker_Compensation_File_MAPD_Most_Recent_Record] AS bcf ON mCMShic.HIC=bcf.[Beneficiary_ID] 
	UNION
	--From members where mCMShic has the MBI as value for the Claw Back side of the report
	SELECT DISTINCT bcf.Beneficiary_ID
		 , mCMShic.MemId
		 , HMC.HICN AS HIC
		 , CONCAT(bcf.Last_Name, ', ', bcf.First_Name, ' ', bcf.Middle_Initial) AS Member_Name
		 , bcf.DOB
		 , bcf.Effdate AS BCompEffdate
		 , bcf.Prior_Plan_Type
		 , bcf.Cycle_Year_as_of_Report_Generation_Date
		 , bcf.Report_Generation_Date
		 , bcf.Correction_AgentGroup4icator
	FROM YOURSERVER.DATABASE.SCHEMA.[MemberCmsHic] AS mCMShic
	JOIN YOURSERVER.DATABASE.SCHEMA.[vw_CMS_HICN_MBI_Crosswalk] AS HMC ON mCMShic.Hic=HMC.MBI
	JOIN YOURSERVER.DATABASE.SCHEMA.[vw_Agent_Broker_Compensation_File_MAPD_Most_Recent_Record] AS bcf ON HMC.HICN=bcf.[Beneficiary_ID]
	)
SELECT *
INTO ##asilva4_BrokerCompCB
FROM BrokerCompCB

--------------------------------------------------------------------------------------------------------------------------------------------

-- Setting the base commission calculation

if exists(SELECT * FROM tempdb.dbo.sysobjects WHERE ID = OBJECT_ID(N'tempdb..##asilva4_COMM')) 
	DROP TABLE ##asilva4_COMM

;WITH COMM AS ( 
	SELECT DISTINCT
			B.brokerid AS Broker_ID
			, b.fullname Broker_Name
			, b.ExternalId AS Broker_Group
			, CONCAT(DATENAME(month, @dateRef),' / ', YEAR(@dateRef)) AS Reference --or paid in?
			, CASE --defining the commission rates
				WHEN b.ExternalId='AgentGroup1' THEN $125.00
				WHEN b.ExternalId='AgentGroup2' THEN $185.00
				-- member was not new to MAPD plan
				WHEN (b.ExternalId='AgentGroup3' OR b.ExternalId='AgentGroup4') AND (BC.[Prior_Plan_Type]='MAPD' OR BC.[Prior_Plan_Type]='MA') THEN STR((200.00/12)*(13-MONTH(ek.effdate)),6,2)--Round up result and keeping 2 decimal places
				--Member is new to MAPD plan
				WHEN (b.ExternalId='AgentGroup3' OR b.ExternalId='AgentGroup4') AND (BC.[Prior_Plan_Type]!='MAPD' OR BC.[Prior_Plan_Type]!='MA') THEN 400
			  END AS Comm_Rate
			, CASE -- admin fee
				WHEN b.ExternalId='AgentGroup3' THEN $150.00
				ELSE $0.00
			  END AS AdminFee
			, ek.enrollid
			, RTRIM(ek.carriermemid) AS Member_ID
			, CAST(ek.effdate AS date) AS effdate
			--, BC.Member_Name
			, m.fullname AS Member_Name
			, ISNULL(BC.[Prior_Plan_Type], '') AS PriorPlanType
	FROM YOURSERVER.DATABASE.SCHEMA.ENROLLBROKER EB JOIN YOURSERVER.DATABASE.SCHEMA.BROKER B ON EB.BrokerId=B.brokerid
	JOIN YOURSERVER.DATABASE.SCHEMA.enrollkeys ek ON ek.enrollid=eb.EnrollId
	LEFT JOIN ##asilva4_BrokerCompComm BC ON ek.memid=BC.MemId
	JOIN YOURSERVER.DATABASE.SCHEMA.member m ON ek.memid=m.memid
	WHERE ek.effdate=@dateRef
		AND EK.effdate < EK.termdate -- filter out termdate lower than effdate
		AND EK.effdate != EK.termdate -- filter out the void
		AND ek.PROGRAMID IN ('Program1','Program2') --Member in Medicare Advantage
		--AND b.ExternalId = 'AgentGroup1'--Filter to AgentGroup1 broker group only. b.ExternalId IN ('AgentGroup2', 'AgentGroup3', 'AgentGroup4','AgentGroup1') 

	)
SELECT *
INTO ##asilva4_COMM
FROM COMM

--------------------------------------------------------------------------------------------------------------------------------------------
-- Setting the base clawback calculation

if exists(SELECT * FROM tempdb.dbo.sysobjects WHERE ID = OBJECT_ID(N'tempdb..##asilva4_CB')) 
	DROP TABLE ##asilva4_CB

;WITH CB AS (
	SELECT DISTINCT
			B.brokerid AS Broker_ID
			, b.fullname Broker_Name
			, b.ExternalId AS Broker_Group
			, CONCAT(DATENAME(month, @dateRef),' / ', YEAR(@dateRef)) AS Reference 
			, CASE --defining the commission rates
			
				WHEN DATEDIFF(month, DATEADD(month, 0, ek.effdate), ek.termdate)<=2 THEN
					CASE --Rapid Disenrollment
						WHEN b.ExternalId='AgentGroup1' THEN $125.00
						WHEN b.ExternalId='AgentGroup2' THEN $185.00
						WHEN (b.ExternalId='AgentGroup3' OR b.ExternalId='AgentGroup4') AND (BC.[Prior_Plan_Type]='MAPD' OR BC.[Prior_Plan_Type]='MA') THEN $200.00
						WHEN (b.ExternalId='AgentGroup3' OR b.ExternalId='AgentGroup4') AND (BC.[Prior_Plan_Type]!='MAPD' OR BC.[Prior_Plan_Type]!='MA') THEN $400.00
					END
				WHEN DATEDIFF(month, DATEADD(month, -1, ek.effdate), ek.termdate)>3 THEN 
					CASE
						WHEN (b.ExternalId='AgentGroup3' OR b.ExternalId='AgentGroup4') AND (BC.[Prior_Plan_Type]='MAPD' OR BC.[Prior_Plan_Type]='MA') THEN STR((200.00/12)*(12-MONTH(ek.termdate)),6,2)--Round up result and keeping 2 decimal places3
						WHEN (b.ExternalId='AgentGroup3' OR b.ExternalId='AgentGroup4') AND (BC.[Prior_Plan_Type]!='MAPD' OR BC.[Prior_Plan_Type]!='MA') THEN STR((400.00/12)*((MONTH(ek.effdate)-1)+(12-MONTH(ek.termdate))),6,2)--Round up result and keeping 2 decimal places
					END
			  END AS CB_Rate
			, CASE -- admin fee will be discounted if Rapid disenrollment happens
				WHEN b.ExternalId='AgentGroup3' AND DATEDIFF(month, DATEADD(month, 0, ek.effdate), ek.termdate)<=2 THEN $150.00
				ELSE $0.00
			  END AS AdminFee
			, ek.enrollid
			, RTRIM(ek.carriermemid) AS Member_ID
			, CAST(ek.effdate AS date) AS effdate
			, CAST(ek.termdate AS date) AS termdate
			, DATEDIFF(month, DATEADD(month, -1, ek.effdate), ek.termdate) AS Months_Enrolled
			, CASE--avoid exclusion of NULL values when filter in the by the termination reasons
					WHEN TermReason.DisenrollmentReasonCode IS NULL THEN 'UNKOWN'
					ELSE TermReason.DisenrollmentReasonCode
				END AS TermReason
			--Creating a rank to later use as a filter to avoid duplicate rows
			, ROW_NUMBER() OVER(partition by [carriermemid] ORDER BY [DisenrollmentReasonCode] DESC) AS Unique_Rank
			, m.fullname AS Member_Name
			, ISNULL(BC.[Prior_Plan_Type], '') AS PriorPlanType
	FROM YOURSERVER.DATABASE.SCHEMA.ENROLLBROKER EB JOIN YOURSERVER.DATABASE.SCHEMA.BROKER B ON EB.BrokerId=B.brokerid
	JOIN YOURSERVER.DATABASE.SCHEMA.enrollkeys ek ON ek.enrollid=eb.EnrollId
	LEFT JOIN ##asilva4_BrokerCompCB BC ON ek.memid=BC.MemId
	JOIN YOURSERVER.DATABASE.SCHEMA.member m ON ek.memid=m.memid
	LEFT JOIN YOURSERVER.DATABASE.SCHEMA..[vw_H9877_DTRRD_MAPD] AS TermReason ON TermReason.HICN=BC.Beneficiary_ID
	AND TermReason.TransactionTypeCode IN ('51','54')
	WHERE ek.effdate<=@dateRef--insert "<" instead of "<=" to exclude members that effdate and termdate are in the same month
		AND EK.effdate != EK.termdate -- filter out the void
		AND ek.termdate!='12/31/2078' -- filter out active members
		AND EK.effdate < EK.termdate -- filter out termdate lower than effdate
		AND	ek.termdate >=@dateRef --setting lower date limit for termdate to avoid pick up termed members already in previous reports
		AND ek.termdate< DATEADD(month, 1, @dateRef)  --setting the higher date limit for termdate (1st day of the following month)
		AND ek.PROGRAMID IN ('Program1','Program2') -- ONLY Medicare Advantage members
		AND YEAR(ek.effdate)=YEAR(ek.termdate)--Filter out when effdate and termdate are in different years
		AND DATEDIFF(month, DATEADD(month, -1, ek.effdate), ek.termdate)<12--filter out members with more than 11 months enrolled
		
	)
SELECT *
INTO ##asilva4_CB
FROM CB

--------------------------------------------------------------------------------------------------------------------------------------------
/*
Setting the base commission reconcile calculation because there may be members acquired by the agents in the past that were only added in the enrollment
table later on
*/
	if exists(SELECT * FROM tempdb.dbo.sysobjects WHERE ID = OBJECT_ID(N'tempdb..##asilva4_COMM_R')) 
	DROP TABLE ##asilva4_COMM_R

;WITH COMM_R AS (
	SELECT DISTINCT
			B.brokerid AS Broker_ID
			, b.fullname Broker_Name
			, b.ExternalId AS Broker_Group
			, CONCAT(DATENAME(month, @dateRef),' / ', YEAR(@dateRef)) AS Reference --or paid in?
			, CASE --defining the commission rates
				WHEN b.ExternalId='AgentGroup1' THEN $125.00
				WHEN b.ExternalId='AgentGroup2' THEN $185.00
				-- member was not new to MAPD plan
				WHEN (b.ExternalId='AgentGroup3' OR b.ExternalId='AgentGroup4') AND (BC.[Prior_Plan_Type]='MAPD' OR BC.[Prior_Plan_Type]='MA') THEN STR((200.00/12)*(13-MONTH(ek.effdate)),6,2)--Round up result and keeping 2 decimal places
				--Member is new to MAPD plan
				WHEN (b.ExternalId='AgentGroup3' OR b.ExternalId='AgentGroup4') AND (BC.[Prior_Plan_Type]!='MAPD' OR BC.[Prior_Plan_Type]!='MA') THEN 400
			  END AS Comm_Rate
			, CASE -- admin fee
				WHEN b.ExternalId='AgentGroup3' THEN $150.00
				ELSE $0.00
			  END AS AdminFee
			, ek.enrollid
			, RTRIM(ek.carriermemid) AS Member_ID
			, CAST(ek.effdate AS date) AS effdate
			--, BC.Member_Name
			, m.fullname AS Member_Name
			, ISNULL(BC.[Prior_Plan_Type], '') AS PriorPlanType
	FROM YOURSERVER.DATABASE.SCHEMA.ENROLLBROKER EB JOIN YOURSERVER.DATABASE.SCHEMA.BROKER B ON EB.BrokerId=B.brokerid
	JOIN YOURSERVER.DATABASE.SCHEMA.enrollkeys ek ON ek.enrollid=eb.EnrollId
	LEFT JOIN ##asilva4_BrokerCompComm BC ON ek.memid=BC.MemId
	JOIN YOURSERVER.DATABASE.SCHEMA.member m ON ek.memid=m.memid
	WHERE ek.effdate < @dateRef 
			AND ek.effdate>=(CASE
								WHEN MONTH(@dateRef)=1 THEN DATEADD(year, -1, @reportYear)
								ELSE @reportYear
							END) -- setting the range of search from the 01/01/(year of the report) and the report date 
		AND EK.effdate < EK.termdate -- filter out termdate in the past of the effdate
		AND EK.effdate != EK.termdate -- filter out the void
		AND ek.PROGRAMID IN ('Program1','Program2') -- Bringing only MAPD members
		--AND b.ExternalId = 'AgentGroup1'--b.ExternalId IN ('AgentGroup2', 'AgentGroup3', 'AgentGroup4','AgentGroup1')
	)
SELECT *
INTO ##asilva4_COMM_R
FROM COMM_R

--------------------------------------------------------------------------------------------------------------------------------------------
/*
Setting the base commission reconcile calculation because there may be members acquired by the agents in the past that disenrolled and was updated 
in the enrollment table later on
*/
if exists(SELECT * FROM tempdb.dbo.sysobjects WHERE ID = OBJECT_ID(N'tempdb..##asilva4_CB_R')) 
	DROP TABLE ##asilva4_CB_R

;WITH CB_R AS (
	SELECT DISTINCT
			B.brokerid AS Broker_ID
			, b.fullname Broker_Name
			, b.ExternalId AS Broker_Group
			, CONCAT(DATENAME(month, @dateRef),' / ', YEAR(@dateRef)) AS Reference --or paid in?
			, CASE --defining the commission rates
			--The best solution will verify how much was paid instead of use Prior_Plan_Type, but so far this is what is available
				WHEN DATEDIFF(month, DATEADD(month, 0, ek.effdate), ek.termdate)<=2 THEN
					CASE --Rapid Disenrollment
						WHEN b.ExternalId='AgentGroup1' THEN $125.00
						WHEN b.ExternalId='AgentGroup2' THEN $175.00
						WHEN (b.ExternalId='AgentGroup3' OR b.ExternalId='AgentGroup4') AND (BC.[Prior_Plan_Type]='MAPD' OR BC.[Prior_Plan_Type]='MA') THEN $200.00
						WHEN (b.ExternalId='AgentGroup3' OR b.ExternalId='AgentGroup4') AND (BC.[Prior_Plan_Type]!='MAPD' OR BC.[Prior_Plan_Type]!='MA') THEN $400.00
					END
				WHEN DATEDIFF(month, DATEADD(month, -1, ek.effdate), ek.termdate)>3 THEN 
					CASE
						WHEN (b.ExternalId='AgentGroup3' OR b.ExternalId='AgentGroup4') AND (BC.[Prior_Plan_Type]='MAPD' OR BC.[Prior_Plan_Type]='MA') THEN STR((200.00/12)*(12-MONTH(ek.termdate)),6,2)--Round up result and keeping 2 decimal places3
						WHEN (b.ExternalId='AgentGroup3' OR b.ExternalId='AgentGroup4') AND (BC.[Prior_Plan_Type]!='MAPD' OR BC.[Prior_Plan_Type]!='MA') THEN STR((400.00/12)*((MONTH(ek.effdate)-1)+(12-MONTH(ek.termdate))),6,2)--Round up result and keeping 2 decimal places
					END
			  END AS CB_Rate
			, CASE -- admin fee will be discounted if Rapid disenrollment happens
				WHEN b.ExternalId='AgentGroup3' AND DATEDIFF(month, DATEADD(month, 0, ek.effdate), ek.termdate)<=2 THEN $150.00
				ELSE $0.00
			  END AS AdminFee
			, ek.enrollid
			, RTRIM(ek.carriermemid) AS Member_ID
			--, BC.Member_Name
			, CAST(ek.effdate AS date) AS effdate
			, CAST(ek.termdate AS date) AS termdate
			, DATEDIFF(month, DATEADD(month, -1, ek.effdate), ek.termdate) AS Months_Enrolled
			, CASE
					WHEN TermReason.DisenrollmentReasonCode IS NULL THEN 'UNKOWN'
					ELSE TermReason.DisenrollmentReasonCode
				END AS TermReason
			--, TermReason.TransactionTypeCode
			, ROW_NUMBER() OVER(partition by [carriermemid] ORDER BY [DisenrollmentReasonCode] DESC) AS Unique_Rank
			, m.fullname AS Member_Name
			, ISNULL(BC.[Prior_Plan_Type], '') AS PriorPlanType
	FROM YOURSERVER.DATABASE.SCHEMA.ENROLLBROKER EB JOIN YOURSERVER.DATABASE.SCHEMA.BROKER B ON EB.BrokerId=B.brokerid
	JOIN YOURSERVER.DATABASE.SCHEMA.enrollkeys ek ON ek.enrollid=eb.EnrollId
	LEFT JOIN ##asilva4_BrokerCompCB BC ON ek.memid=BC.MemId
	JOIN YOURSERVER.DATABASE.SCHEMA.member m ON ek.memid=m.memid
	LEFT JOIN YOURSERVER.DATABASE.SCHEMA..[vw_H9877_DTRRD_MAPD] AS TermReason ON TermReason.HICN=BC.Beneficiary_ID
	AND TermReason.TransactionTypeCode IN ('51','54')
	WHERE ek.effdate < @dateRef 
			AND ek.effdate>=(CASE
								WHEN MONTH(@dateRef)=1 THEN DATEADD(year, -1, @reportYear)
								ELSE @reportYear
							END)  -- setting the range of search from the 01/01/(year of the report) and the report date 
		--convert a given date to the first of the the month/year of that date and gets the effdate of the previous month
		AND EK.effdate != EK.termdate -- filter out the void
		AND ek.termdate!='12/31/2078' -- filter out active members
		AND EK.effdate < EK.termdate -- filter out termdate in the past of the effdate
		AND	ek.termdate > @reportYear --setting lower date limit for termdate
		AND ek.termdate< @dateRef  --setting the higher date limit for termdate
		AND ek.PROGRAMID IN ('Program1','Program2')
		AND YEAR(ek.effdate)=YEAR(ek.termdate)--Filter out when effdate and termdate are in different years
		AND DATEDIFF(month, DATEADD(month, -1, ek.effdate), ek.termdate)<12--filter out members with more than 11 months enrolled
		--AND b.ExternalId = 'AgentGroup1'--b.ExternalId IN ('AgentGroup2', 'AgentGroup3', 'AgentGroup4','AgentGroup1')
	)
SELECT *
INTO ##asilva4_CB_R
FROM CB_R

--------------------------------------------------------------------------------------------------------------------------------------------
-- Setting the base dates to compare with commission table when reconciling

if exists(SELECT * FROM tempdb.dbo.sysobjects WHERE ID = OBJECT_ID(N'tempdb..##asilva4_PreviousReportDate')) 
	DROP TABLE ##asilva4_PreviousReportDate

;WITH PreviousReportDate AS (
		SELECT DISTINCT CONVERT(date, Actual_Report) AS Ref
					  , CONVERT(date,Data_Run_Date) AS RepDate
		FROM YOURSERVER.DATABASE.SCHEMA.[MAPD_Commission_Report_Extract_MemberID2019]
		WHERE Data_Run_Date IS NOT NULL 
)
SELECT *
INTO ##asilva4_PreviousReportDate
FROM PreviousReportDate

--------------------------------------------------------------------------------------------------------------------------------------------

-- Setting the correct (unique)  clawback dates

if exists(SELECT * FROM tempdb.dbo.sysobjects WHERE ID = OBJECT_ID(N'tempdb..##asilva4_CBReason')) 
	DROP TABLE ##asilva4_CBReason

;WITH CBReason AS (
	SELECT DISTINCT CB_R.enrollid
					, MIN(ea.Time_Of_Change) AS Min_change_date
					, MAX(ea.Time_Of_Change) AS Max_change_date
	FROM ##asilva4_CB_R AS CB_R JOIN YOURSERVER.DATABASE.SCHEMA.EnrollKeys_Audit AS ea ON CB_R.enrollid=ea.enrollid
			JOIN ##asilva4_PreviousReportDate PRD ON DATEADD(month, DATEDIFF(month, 0, CB_R.termdate), 0)=PRD.Ref
	WHERE CB_R.termdate=ea.termdate AND PRD.RepDate<=ea.Time_Of_Change
	GROUP BY CB_R.enrollid
)

SELECT *
INTO ##asilva4_CBReason
FROM CBReason

--------------------------------------------------------------------------------------------------------------------------------------------



/*
Generating the final output which is the combination of current and reconciled Commission and Claw Back.

Trans_Type - Transaction Type
C - Commission
CB - Claw Back
RD - Rapid Disenrollment
CRecon - Commission Reconcile
CBRecon - Claw Back Reconcile
RDRecon	- Rapid Disenrollment Reconcile
CRenew - Commission Renewal
CBRenew - Claw Back Renewal
RDRenew - Rapid Disenrollment Renewal
*/

										-----Commission ----
	SELECT 	COMM.Broker_Group
			, COMM.Broker_Name
			, RTRIM(COMM.Broker_ID) AS Broker_ID
			, comm.enrollid AS Member_Enrollid
			, comm.Member_ID
			, comm.Member_Name AS Member_Name
			, comm.PriorPlanType AS Prior_Plan_Type
			, COMM.effdate AS Effdate
			, 'C' AS Trans_Type
			--, comm.Reference
			, comm.Comm_Rate AS Commission
			, comm.AdminFee AS AdminFee
			, NULL AS Termdate
			, NULL AS Months_Enrolled
			, NULL AS Claw_Back
			, '' AS Reason
			-- Expected_Report and Actual_Report will differ in case of reconciliation
			, CAST(@dateRef as date) AS Expected_Report
			, CAST(@dateRef as date) AS Actual_Report
			, CAST(@ReportDate as date) AS Data_Run_Date-- Date the data was extracted from the database to create the report
	FROM ##asilva4_COMM AS COMM
	WHERE COMM.Broker_ID!='P9065494'

	UNION
	
	
										-----Claw Back ----

	SELECT 	CB.Broker_Group
			, CB.Broker_Name
			, RTRIM(CB.Broker_ID) AS Broker_ID
			, CB.enrollid AS Member_Enrollid
			, CB.Member_ID
			, CB.Member_Name AS Member_Name
			, CB.PriorPlanType AS Prior_Plan_Type
			, CB.effdate AS Effdate
			, CASE
				WHEN CB.Months_Enrolled<=3 THEN 'RD'
				ELSE 'CB'
				END AS Trans_Type
			, NULL AS Commission
			, NULL AS AdminFee
			, CB.termdate AS Termdate
			, CB.Months_Enrolled AS Months_Enrolled
			, CASE --admin fee with Rapid disenrollment
				WHEN CB.Broker_Group='AgentGroup3' AND DATEDIFF(month, DATEADD(month, 0, CB.effdate), CB.termdate)<=2 THEN ISNULL(CB_Rate,0.00)+ISNULL(CB.AdminFee,0.00)
				ELSE ISNULL(CB_Rate,0.00)
			  END AS Claw_Back
			, '' AS Reason
			, CAST(@dateRef as date) AS Expected_Report
			, CAST(@dateRef as date) AS Actual_Report
			, CAST(@ReportDate as date) AS Data_Run_Date-- Date the data was extracted from the database to create the report
	FROM ##asilva4_CB AS CB
	WHERE CB.Broker_ID!='P9065494' AND TermReason NOT IN ('01','02','05','06','08','09','10','14','30','41','48','65','91','92') --applying term reason exclusion
		AND (CASE WHEN TermReason='UNKOWN' AND Unique_Rank>=2 THEN 'Repetition' 
				ELSE 'Unique'
				END)='Unique' -- To avoid duplicates
	UNION
											-----Commission Reconcile----
	SELECT DISTINCT COMM_R.Broker_Group
				, RTRIM(COMM_R.Broker_Name) AS Broker_Name
				, RTRIM(COMM_R.Broker_ID) AS Broker_ID
				, COMM_R.enrollid AS Member_Enrollid
				, COMM_R.Member_ID
				--, ED.Member_ID
				, COMM_R.Member_Name AS Member_Name
				, COMM_R.PriorPlanType AS Prior_Plan_Type
				, COMM_R.effdate AS Effdate
				, 'CRecon' AS Trans_Type
				, COMM_R.Comm_Rate AS Commission
				, COMM_R.AdminFee AS AdminFee
				, NULL AS Termdate
				, NULL AS Months_Enrolled
				, NULL AS Claw_Back
				, CASE --automating the reasons for why the member was not included before
					WHEN eb.CreateDate>=PRD.RepDate 
					THEN CONCAT('The member''s was associated in the database to the broker after the '								
								, CONCAT(DATENAME(month, PRD.Ref),'/', YEAR(PRD.Ref))								
								,' commission report generation date')																
					ELSE ''
				  END AS Reason
				--, '' AS TermReason
				, CAST(COMM_R.effdate as date) AS Expected_Report --Which report month the commission should have been reported
				, CAST(@dateRef as date) AS Actual_Report -- Which report month the commission was actually reported
			    , CAST(@ReportDate as date) AS Data_Run_Date -- Date the data was extracted from the database to create the report
		FROM ##asilva4_COMM_R AS COMM_R LEFT JOIN YOURSERVER.DATABASE.SCHEMA.[MAPD_Commission_Report_Extract_MemberID2019] AS ED ON COMM_R.Member_ID=ED.Member_ID
			JOIN YOURSERVER.DATABASE.SCHEMA.enrollkeys ek ON COMM_R.enrollid=ek.enrollid
			JOIN YOURSERVER.DATABASE.SCHEMA.ENROLLBROKER EB ON ek.enrollid=eb.EnrollId
			JOIN ##asilva4_PreviousReportDate AS PRD ON COMM_R.effdate=PRD.Ref
		WHERE COMM_R.Broker_ID!='P9065494'
				AND ED.Termdate IS NULL AND ED.Member_ID IS NULL --To pick only the members with commission that were not in the original report
	
UNION
											-----Claw Back Reconcile ----
SELECT 	DISTINCT CB_R.Broker_Group
				, RTRIM(CB_R.Broker_Name) AS Broker_Name
				, RTRIM(CB_R.Broker_ID) AS Broker_ID
				, CB_R.enrollid AS Member_Enrollid
				, CB_R.Member_ID
				--, ED.Member_ID
				, CB_R.Member_Name AS Member_Name
				, CB_R.PriorPlanType AS Prior_Plan_Type
				, CB_R.effdate AS Effdate
				, CASE 
					WHEN CB_R.Months_Enrolled<=3 
					THEN 'RDRecon' 
					ELSE 'CBRecon'
					END AS Trans_Type
				, NULL AS Commission
				, NULL AS AdminFee
				, CB_R.termdate AS Termdate
				, CB_R.Months_Enrolled AS Months_Enrolled
				, CASE --admin fee with Rapid disenrollment
					WHEN CB_R.Broker_Group='AgentGroup3' AND DATEDIFF(month, DATEADD(month, 0, CB_R.effdate), CB_R.termdate)<=2 THEN ISNULL(CB_R.CB_Rate,0.00)+ISNULL(CB_R.AdminFee,0.00)
					ELSE ISNULL(CB_R.CB_Rate,0.00)
				  END AS Claw_Back
				, CASE --automating the reasons for why the member was not included before
					WHEN CBR.Min_change_date>PRD.RepDate 
					THEN CONCAT('The member''s termdate was updated after the '								
								, CONCAT(DATENAME(month, PRD.Ref),'/', YEAR(PRD.Ref))								
								,' commission report generation date')																
					 ELSE ''
				  END AS Reason
				--, CB_R.TermReason
				, CONVERT(date, DATEADD(month, DATEDIFF(month, 0, CB_R.termdate), 0)) AS Expected_Report --Which report month the clawback should have been reported
				, CAST(@dateRef as date) AS Actual_Report -- Which report month the commission was actually reported
			    , CAST(@ReportDate as date) AS Data_Run_Date -- Date the data was extracted from the database to create the report
		FROM ##asilva4_CB_R AS CB_R LEFT JOIN YOURSERVER.DATABASE.SCHEMA.[MAPD_Commission_Report_Extract_MemberID2019] AS ED ON CB_R.Member_ID=ED.Member_ID
			LEFT JOIN ##asilva4_CBReason AS CBR ON CBR.enrollid=CB_R.enrollid

			JOIN ##asilva4_PreviousReportDate AS PRD ON DATEADD(month, DATEDIFF(month, 0, CB_R.termdate), 0)=PRD.Ref
		WHERE CB_R.Broker_ID!='P9065494' 
			AND NOT EXISTS (SELECT DISTINCT Member_ID
							FROM YOURSERVER.DATABASE.SCHEMA.[MAPD_Commission_Report_Extract_MemberID2019] md2
							WHERE CB_R.Member_ID=md2.Member_ID AND Commission IS NULL) --To pick only the members with clawback that were not in the original report
			AND TermReason NOT IN ('01','02','05','06','08','09','10','14','30','41','48','65','91','92') --applying term reason exclusion
			AND (CASE WHEN TermReason='UNKOWN' AND Unique_Rank>=2 THEN 'Repetition' 
					ELSE 'Unique'
					END)='Unique' -- To avoid duplicates
	
