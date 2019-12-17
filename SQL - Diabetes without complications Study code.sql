
--Getting unique members with effdate>=01/01/2years back
if exists(SELECT * FROM tempdb.dbo.sysobjects WHERE ID = OBJECT_ID(N'tempdb..##asilva4_ek')) 
	DROP TABLE ##asilva4_ek

;WITH ek AS (
	SELECT DISTINCT memid
				, carriermemid AS MRN
				, effdate
				, termdate
				, CASE
					WHEN planid ='Code1' THEN 'DSNP'
					WHEN planid ='Code2' THEN 'GOLD'
					WHEN planid ='Code3' THEN 'PLATINUM'
				  END AS LOB
				, ROW_NUMBER() OVER(partition by memid ORDER BY lastUpdate DESC) AS DateOrder
	FROM YOURSERVER.DATABASE.SCHEMA.TABLE
	WHERE planid IN ('Code1', 'Code2', 'Code3') -- Limiting by Medicare Advantage plans
			AND effdate>=DATEADD(year, DATEDIFF(year, 0, DATEADD(year, -2, GETDATE())), 0) --01/01/YearBeforeLastyear
			AND effdate< termdate 
			AND effdate!=termdate --eliminating voids
			AND termdate>=DATEADD(year, DATEDIFF(year, 0, DATEADD(year, -1, GETDATE())), 0) --01/01/Lastyear
			
)
SELECT memid
		, MRN
		, effdate
		, termdate
		, LOB
INTO ##asilva4_ek
FROM ek
WHERE ek.DateOrder=1 -- eliminating duplicates


--Getting claims 2018 or later that match memid from asilva_ek. 

if exists(SELECT * FROM tempdb.dbo.sysobjects WHERE ID = OBJECT_ID(N'tempdb..##asilva4_claims')) 
	DROP TABLE ##asilva4_claims

SELECT DISTINCT c.*
INTO ##asilva4_claims
FROM (SELECT DISTINCT memid
				, LEFT(claimid, 11) AS claimid--use a left function to get the core claimid
				, startdate
				, enddate
				, status
				, provid
				, affiliationid
				, createdate
				, ROW_NUMBER() OVER(PARTITION BY LEFT(claimid, 11) ORDER BY lastupdate DESC) AS rown
		FROM YOURSERVER.DATABASE.SCHEMA.CLAIM
		WHERE memid IN (SELECT DISTINCT memid
				FROM ##asilva4_ek)
			  AND enddate>=DATEADD(year, DATEDIFF(year, 0, DATEADD(year, -1, GETDATE())), 0) --01/01/lastyear 
			  AND status IN ('PAID', 'DENIED')
			  AND planid IN ('Code1', 'Code2',' Code3')-- Limiting by Medicare Advantage plans
			  ) AS c
WHERE c.rown=1



------getting the claim diag codes that match the claimIDs deom ##asilva_claims for diabetes with and without complications
if exists(SELECT * FROM tempdb.dbo.sysobjects WHERE ID = OBJECT_ID(N'tempdb..##asilva4_claimdiag1')) 
	DROP TABLE ##asilva4_claimdiag1

SELECT DISTINCT memid
				, c.claimid
				, REPLACE(cd.codeid,'.','') AS DiagCode
INTO ##asilva4_claimdiag1
FROM YOURSERVER.DATABASE.SCHEMA.CLAIMDIAG AS cd
	INNER JOIN (SELECT DISTINCT memid, claimid, startdate, createdate
				FROM ##asilva4_claims) AS c
	ON c.claimid=LEFT(cd.claimid,11)
GROUP BY memid, c.claimid, cd.createdate, cd.codeid
HAVING cd.createdate>=MIN(c.startdate)--limit the claimdiag date starting on the oldest claim in asilva_claims

------getting the claimIDs and diag codes that match the diabetes with and without complications

if exists(SELECT * FROM tempdb.dbo.sysobjects WHERE ID = OBJECT_ID(N'tempdb..##asilva4_claimdiag')) 
	DROP TABLE ##asilva4_claimdiag

SELECT DISTINCT memid
				, claimid
				, DiagCode
INTO ##asilva4_claimdiag
FROM ##asilva4_claimdiag1
WHERE DiagCode IN ('E089'/*Diab wo comp*/, 'E099'/* Drug or chemical induced Diab wo comp*/
								,'E109'/*Diab T1 wo comp*/,'E119'/*Diab T2 wo comp*/,'E139'/*Other specified Diab wo comp*/ 
								--diabetes with complication codes
								, 'E0800','E0801','E0810','E0811','E0821','E0822','E0829','E0831','E08319','E08321',
								'E08329','E08331','E08339','E08341','E08349','E08351','E08352','E08353','E08354','E08355',
								'E0837','E0839','E0840','E0841','E0842','E0843','E0844','E0849','E0851','E0852',
								'E08618','E08620','E08621','E08622','E08628','E08630','E08638','E08641','E08649','E0865',
								'E0900','E0901','E0910','E0911','E0921','E0922','E0929','E0931','E09319','E09321',
								'E09339','E09341','E09349','E09351','E09352','E09353','E09354','E09355','E09359','E0936',
								'E0940','E0941','E0942','E0943','E0944','E0949','E0951','E0952','E0959','E09610',
								'E09621','E09622','E09628','E09630','E09638','E09641','E09649','E0965','E0969','E098',
								'E1021','E1022','E1029','E1031','E10319','E10321','E10329','E10331','E10339','E10341',
								'E10352','E10353','E10354','E10355','E10359','E1036','E1037','E1039','E1040','E1041',
								'E1044','E1049','E1051','E1052','E1059','E10610','E10618','E10620','E10621','E10622',
								'E10638','E10641','E10649','E1065','E1069','E108','E1100','E1101','E1110','E1111',
								'E1129','E1131','E11319','E11321','E11329','E11331','E11339','E11341','E11349','E11351',
								'E11354','E11355','E11359','E1136','E1137','E1139','E1140','E1141','E1142','E1143',
								'E1151','E1152','E1159','E11610','E11618','E11620','E11621','E11622','E11628','E11630',
								'E11649','E1165','E1169','E118','E1300','E1301','E1310','E1311','E1321','E1322',
								'E13319','E13321','E13329','E13331','E13339','E13341','E13349','E13351','E13352','E13353',
								'E13359','E1336','E1337','E1339','E1340','E1341','E1342','E1343','E1344','E1349',
								'E1359','E13610','E13618','E13620','E13621','E13622','E13628','E13630','E13638','E13641',
								'E1369', 'E138')


--------------to select only the members and claimids where the member only had diab without complications----------------

if exists(SELECT * FROM tempdb.dbo.sysobjects WHERE ID = OBJECT_ID(N'tempdb..##asilva4_diabWoComp')) 
	DROP TABLE ##asilva4_diabWoComp

;WITH WComp AS (
	SELECT DISTINCT memid, claimid
		FROM ##asilva4_claimdiag
		WHERE DiagCode NOT IN ('E089', 'E099','E109', 'E119', 'E139')
)

SELECT DISTINCT WoC.memid, WoC.claimid
INTO ##asilva4_diabWoComp
FROM ##asilva4_claimdiag AS WoC --without comp
WHERE WoC.memid NOT IN (SELECT DISTINCT memid
							FROM WComp)

--------------to select all diag codes for the members that only had diab without complications----------------

if exists(SELECT * FROM tempdb.dbo.sysobjects WHERE ID = OBJECT_ID(N'tempdb..##asilva4_DiagCodesAlongDiabWoComp')) 
	DROP TABLE ##asilva4_DiagCodesAlongDiabWoComp

SELECT DISTINCT LEFT(claimid,11) AS claimid, REPLACE(codeid,'.','') AS DiagCode
INTO ##asilva4_DiagCodesAlongDiabWoComp
FROM YOURSERVER.DATABASE.SCHEMA.CLAIMDIAG
WHERE LEFT(claimid,11) IN (SELECT DISTINCT claimid FROM ##asilva4_diabWoComp)
----------


--Getting claimids and Diag_codes for unique members including the diabetes for 2018 or later

if exists(SELECT * FROM tempdb.dbo.sysobjects WHERE ID = OBJECT_ID(N'tempdb..##asilva4_chronicReview')) 
	DROP TABLE ##asilva4_chronicReview

;WITH  ClaimIdExclusion AS(--To flag all claimIDs with only Diab wo comp in their Diag codes
		SELECT DISTINCT claimid
		FROM ##asilva4_DiagCodesAlongDiabWoComp
		GROUP BY claimid
		HAVING COUNT(diagcode)=1
)
SELECT DISTINCT ek.*
				, d.claimid
				, c.startdate
				, c.enddate
				, c.status
				, cd.DiagCode
				, c.provid
				, p.fullname as ProviderName
				, CONCAT(RTRIM(LTRIM(e.phyaddr1)), ', ', RTRIM(LTRIM(e.phyaddr2))) AS ProvAddress
				, e.city AS ProvCity
				, e.county AS ProvCounty
				, e.state AS ProvState
				, e.phyzip AS ProvZip
				, e.phone AS ProvPhone
INTO ##asilva4_chronicReview
FROM ##asilva4_ek AS ek
	--to filter only the members and claimids where the member only had diab without complications
	INNER JOIN ##asilva4_diabWoComp AS d
	ON ek.memid=d.memid
	LEFT JOIN ##asilva4_claims AS c
	ON c.claimid=d.claimid
	LEFT JOIN ##asilva4_DiagCodesAlongDiabWoComp AS cd
	ON cd.claimid=d.claimid
	--getting provider info
	LEFT JOIN (SELECT DISTINCT affiliationid, provid
				FROM YOURSERVER.DATABASE.SCHEMA.affiliation) AS a 
	ON a.affiliationid = c.affiliationid
	LEFT JOIN (SELECT DISTINCT provid, fullname, entityid
				FROM YOURSERVER.DATABASE.SCHEMA.provider) AS p 
	ON p.provid = a.ProvId
	LEFT JOIN (SELECT DISTINCT *, ROW_NUMBER() OVER(PARTITION BY entid ORDER BY lastupd DESC) AS rown
				FROM YOURSERVER.DATABASE.SCHEMA.[entity]) AS e
	ON p.entityid=e.entid AND e.rown=1
WHERE d.claimid NOT IN (SELECT DISTINCT * FROM ClaimIdExclusion)


--------------------------------Identifying the members that potentially could have diabetes with complications----------------------------
if exists(SELECT * FROM tempdb.dbo.sysobjects WHERE ID = OBJECT_ID(N'tempdb..##asilva4_MembersPotencialDiabWcomp')) 
	DROP TABLE ##asilva4_MembersPotencialDiabWcomp

;WITH ClaimIDSelection AS ( --To set the base for the claims exclusion
	SELECT DISTINCT claimid, DiagCode
from ##asilva4_chronicReview
WHERE DiagCode IN 
 ( 'E089', 'E099','E109', 'E119', 'E139',--diabets without complications code
   'E872', 'N181', 'N182', 'N183', 'N184', 'N185', 'N186', 'N189','N289', 'N070','N070','N071','N072','N073','N074','N075'
  ,'N076','N077','N078','N079','H3500', 'H35021', 'H35022', 'H35023', 'H35029', 'H35031', 'H35032', 'H35033', 'H35039',
  'H25011','H25012','H25013','H25019','H25031','H25032','H25033','H25039','H25041','H25042','H25043','H25049','H25091',
  'H25092','H25093','H25099','H2510','H2511','H2512','H2513','H2520','H2521','H2522','H2523','H25811','H25812','H25813',
  'H25819','H2589','H259','H2620','H26211','H26212','H26213','H26219','H26221','H26222','H26223','H26229','H26231',
  'H26232','H26233','H26239','H2630','H2631','H2632','H2633','H2640','H26411','H26412','H26413','H26419','H26491',
  'H26492','H26493','H26499','H268','H269','H4010','H4011','H40111','H40112','H40113','H40119','H40121','H40122',
  'H40123','H40129','H40131','H40132','H40133','H40139','H40141','H40142','H40143','H40149','H40151','H40152',
  'H40153','H40159','H40211','H40212','H40213','H40219','H40221','H40222','H40223','H40229','H40231','H40232',
  'H40233','H40239','H26219','H40241','H40242','H40243','H40249','H4030','H4031','H4032','H4033','H4040','H4041','H4042',
  'H4043','H4050','H4051','H4052','H4053','H4060','H4061','H4062','H4063','H40811','H40812','H40813','H40819','H40821',
  'H40822','H40823','H40829','H40831','H40832','H40833','H40839','H4089','H409','H42','G580','G587','G588','G589','G600',
  'G601','G602','G603','G608','G609','G610','G611','G6181','G6182','G6189','G619','G620','G621','G622','G6281','G6282',
  'G6289','G629','G63','G718', 'G1221', 'G1225', 'G545', 'Q798', 'I999', 'I679', 'I739''I7389','M1460','M1461','M1462',
  'M1463','M1464','M1465','M1466','M1467','M1468','M1469','L309','L308','L97401','L97402','L97403','L97404','L97405',
  'L97406','L97829','L97407','L97408','L97409','L97411','L97412','L97413','L97414','L97415','L97901', 'L97416','L97417',
  'L97418','L97419','L97421','L97422','L97423','L97424','L97902','L97425','L97426','L97427','L97428','L97429','L97501',
  'L97502','L97503','L97903','L97504','L97505','L97506','L97507','L97508','L97509','L97101','L97102','L97904',
  'L97103','L97104','L97105','L97106','L97107','L97108','L97109','L97201','L97905','L97202','L97203','L97204','L97205',
  'L97206','L97207','L97208','L97209','L97906','L97210','L97211','L97212','L97213','L97214','L97215','L97216','L97217','L97907',
  'L97218','L97219','L97220','L97221','L97222','L97223','L97224','L97225','L97908','L97226','L97227','L97228','L97229',
  'L97301','L97302','L97303','L97304','L97909','L97305','L97306','L97307','L97308','L97309','L97310','L97311','L97312','L97910',
  'L97313','L97314','L97315','L97316','L97317','L97318','L97319','L97320','L97911','L97321','L97322','L97323','L97324',
  'L97325','L97326','L97327','L97328','L97912','L97329','L97511','L97512','L97513','L97514','L97515','L97516','L97517','L97913',
  'L97518','L97519','L97520','L97521','L97522','L97523','L97524','L97525','L97914','L97526','L97527','L97528','L97529',
  'L97801','L97802','L97803','L97804','L97915','L97805','L97806','L97807','L97808','L97809','L97810','L97811','L97812','L97916',
  'L97813','L97814','L97815','L97816','L97817','L97818','L97819','L97820','L97917','L97821','L97822','L97823','L97824',
  'L97825','L97826','L97827','L97828','L97918', 'L97919','L97920','L97921','L97922','L97923','L97924','L97925','L97926','L97927',
  'L97928','L97929','L98411','L98412','L98413','L98414','L98415','L98416','L98417','L98418','L98419','L98420','L98421',
  'L98422','L98423','L98424','L98425','L98426','L98427','L98428','L98429','L98491','L98492','L98493','L98494','L98495','L98496',
  'L98497','L98498','L98499','K055','K056','E161','E162','R739')
)
, ClaimIDExclusion AS (--To flag all claimIDs with only Diab wo comp codes in their Diag codes but no other diag codes
		SELECT DISTINCT claimid
		FROM ClaimIDSelection
		GROUP BY claimid
		HAVING COUNT(DiagCode)=1
)
SELECT DISTINCT MEMID, MRN, effdate, termdate, claimid, startdate, enddate, DiagCode,dd.SHORT_DESCRIPTION 
				, provid, ProviderName, ProvAddress, ProvCity, ProvCounty, ProvState, ProvPhone
INTO ##asilva4_MembersPotencialDiabWcomp
FROM ##asilva4_chronicReview AS cr
	LEFT JOIN (SELECT DISTINCT DIAGNOSIS_CODE, SHORT_DESCRIPTION
				FROM YOURSERVER.DATABASE.SCHEMA.[CMS_HCC_Risk_Model]
				WHERE HCC_MOD_YEAR='2018') Dd
	ON cr.DiagCode=dd.DIAGNOSIS_CODE
WHERE cr.claimid NOT IN (SELECT DISTINCT * FROM ClaimIDExclusion)
	  AND DiagCode IN --limiting the codes for diab wo complications + the combination that would make it diab with complications
 ( 'E089', 'E099','E109', 'E119', 'E139',--diabets without complications code
   'E872', 'N181', 'N182', 'N183', 'N184', 'N185', 'N186', 'N189','N289', 'N070','N070','N071','N072','N073','N074','N075'
  ,'N076','N077','N078','N079','H3500', 'H35021', 'H35022', 'H35023', 'H35029', 'H35031', 'H35032', 'H35033', 'H35039',
  'H25011','H25012','H25013','H25019','H25031','H25032','H25033','H25039','H25041','H25042','H25043','H25049','H25091',
  'H25092','H25093','H25099','H2510','H2511','H2512','H2513','H2520','H2521','H2522','H2523','H25811','H25812','H25813',
  'H25819','H2589','H259','H2620','H26211','H26212','H26213','H26219','H26221','H26222','H26223','H26229','H26231',
  'H26232','H26233','H26239','H2630','H2631','H2632','H2633','H2640','H26411','H26412','H26413','H26419','H26491',
  'H26492','H26493','H26499','H268','H269','H4010','H4011','H40111','H40112','H40113','H40119','H40121','H40122',
  'H40123','H40129','H40131','H40132','H40133','H40139','H40141','H40142','H40143','H40149','H40151','H40152',
  'H40153','H40159','H40211','H40212','H40213','H40219','H40221','H40222','H40223','H40229','H40231','H40232',
  'H40233','H40239','H26219','H40241','H40242','H40243','H40249','H4030','H4031','H4032','H4033','H4040','H4041','H4042',
  'H4043','H4050','H4051','H4052','H4053','H4060','H4061','H4062','H4063','H40811','H40812','H40813','H40819','H40821',
  'H40822','H40823','H40829','H40831','H40832','H40833','H40839','H4089','H409','H42','G580','G587','G588','G589','G600',
  'G601','G602','G603','G608','G609','G610','G611','G6181','G6182','G6189','G619','G620','G621','G622','G6281','G6282',
  'G6289','G629','G63','G718', 'G1221', 'G1225', 'G545', 'Q798', 'I999', 'I679', 'I739''I7389','M1460','M1461','M1462',
  'M1463','M1464','M1465','M1466','M1467','M1468','M1469','L309','L308','L97401','L97402','L97403','L97404','L97405',
  'L97406','L97829','L97407','L97408','L97409','L97411','L97412','L97413','L97414','L97415','L97901', 'L97416','L97417',
  'L97418','L97419','L97421','L97422','L97423','L97424','L97902','L97425','L97426','L97427','L97428','L97429','L97501',
  'L97502','L97503','L97903','L97504','L97505','L97506','L97507','L97508','L97509','L97101','L97102','L97904',
  'L97103','L97104','L97105','L97106','L97107','L97108','L97109','L97201','L97905','L97202','L97203','L97204','L97205',
  'L97206','L97207','L97208','L97209','L97906','L97210','L97211','L97212','L97213','L97214','L97215','L97216','L97217','L97907',
  'L97218','L97219','L97220','L97221','L97222','L97223','L97224','L97225','L97908','L97226','L97227','L97228','L97229',
  'L97301','L97302','L97303','L97304','L97909','L97305','L97306','L97307','L97308','L97309','L97310','L97311','L97312','L97910',
  'L97313','L97314','L97315','L97316','L97317','L97318','L97319','L97320','L97911','L97321','L97322','L97323','L97324',
  'L97325','L97326','L97327','L97328','L97912','L97329','L97511','L97512','L97513','L97514','L97515','L97516','L97517','L97913',
  'L97518','L97519','L97520','L97521','L97522','L97523','L97524','L97525','L97914','L97526','L97527','L97528','L97529',
  'L97801','L97802','L97803','L97804','L97915','L97805','L97806','L97807','L97808','L97809','L97810','L97811','L97812','L97916',
  'L97813','L97814','L97815','L97816','L97817','L97818','L97819','L97820','L97917','L97821','L97822','L97823','L97824',
  'L97825','L97826','L97827','L97828','L97918', 'L97919','L97920','L97921','L97922','L97923','L97924','L97925','L97926','L97927',
  'L97928','L97929','L98411','L98412','L98413','L98414','L98415','L98416','L98417','L98418','L98419','L98420','L98421',
  'L98422','L98423','L98424','L98425','L98426','L98427','L98428','L98429','L98491','L98492','L98493','L98494','L98495','L98496',
  'L98497','L98498','L98499','K055','K056','E161','E162','R739')
  ORDER BY claimid


----------------Identifying the members from MOR HCC19=1 that potentially could have diabetes with complications still with us---
if exists(SELECT * FROM tempdb.dbo.sysobjects WHERE ID = OBJECT_ID(N'tempdb..##asilva4_MembersPotencialDiabWcompMOR')) 
	DROP TABLE ##asilva4_MembersPotencialDiabWcompMOR

;WITH membersMOR AS(
		SELECT DISTINCT HICN
					, Last_Name
					, First_Name
					, DOB
					, CASE
						WHEN HCC17='1' THEN 'HCC17'
						WHEN HCC18='1' THEN 'HCC18'
						WHEN HCC19='1' THEN 'HCC19'
					  END AS MOR_HCC_Flag
					, ROW_NUMBER()OVER(PARTITION BY HICN ORDER BY import_date DESC) AS rown
		FROM YOURSERVER.DATABASE.SCHEMA.[Part_C_HCC_V22] 
		WHERE import_date>=DATEADD(year, DATEDIFF(year, 0, GETDATE()), 0) -- return 01/01/current year
				AND (HCC17='1' OR HCC18='1' OR HCC19='1')
)
SELECT DISTINCT pm.*, m.HICN, Last_Name, First_Name, DOB, MOR_HCC_Flag
INTO ##asilva4_MembersPotencialDiabWcompMOR
FROM ##asilva4_MembersPotencialDiabWcomp pm
		LEFT JOIN (SELECT DISTINCT HIC, memid, HICN, ROW_NUMBER() OVER(PARTITION BY memid ORDER BY LastUpdate DESC) AS rown
					FROM YOURSERVER.DATABASE.SCHEMA.[MemberCmsHic] AS mc
						LEFT JOIN (SELECT DISTINCT HICN, MBI, ROW_NUMBER() OVER(PARTITION BY MBI ORDER BY import_date DESC) AS rown
									FROM YOURSERVER.DATABASE.SCHEMA.[vw_CMS_HICN_MBI_Crosswalk]) cw
							ON cw.MBI=mc.HIC AND cw.rown=1) h
					--WHERE memid='MEM00000065631') h
		ON h.memid=pm.memid AND h.rown=1
		LEFT JOIN membersMOR m
		ON (m.HICN=h.HIC OR m.HICN=H.HICN) AND m.rown=1
WHERE pm.termdate>GETDATE()

------------------------------------------- At this point you already have the target members list

---Separating members that had chart review in 2018

--Selecting members without Diab with complications from Chart Review 2018
if exists(SELECT * FROM tempdb.dbo.sysobjects WHERE ID = OBJECT_ID(N'tempdb..##asilva4_CR2018NoDiabWithComp')) 
	DROP TABLE ##asilva4_CR2018NoDiabWithComp

;WITH DBcomp AS (
		SELECT DISTINCT [HICN]
		FROM YOURSERVER.DATABASE.SCHEMA.[CHARTREVIEWRAPS2018_DETAIL]
		WHERE REPLACE(Dx_Code,'.','') IN (--'E089'/*Diab wo comp*/, 'E099'/* Drug or chemical induced Diab wo comp*/
								--,'E109'/*Diab T1 wo comp*/,'E119'/*Diab T2 wo comp*/,'E139'/*Other specified Diab wo comp*/ 
								--diabetes with complication codes
								 'E0800','E0801','E0810','E0811','E0821','E0822','E0829','E0831','E08319','E08321',
								'E08329','E08331','E08339','E08341','E08349','E08351','E08352','E08353','E08354','E08355',
								'E0837','E0839','E0840','E0841','E0842','E0843','E0844','E0849','E0851','E0852',
								'E08618','E08620','E08621','E08622','E08628','E08630','E08638','E08641','E08649','E0865',
								'E0900','E0901','E0910','E0911','E0921','E0922','E0929','E0931','E09319','E09321',
								'E09339','E09341','E09349','E09351','E09352','E09353','E09354','E09355','E09359','E0936',
								'E0940','E0941','E0942','E0943','E0944','E0949','E0951','E0952','E0959','E09610',
								'E09621','E09622','E09628','E09630','E09638','E09641','E09649','E0965','E0969','E098',
								'E1021','E1022','E1029','E1031','E10319','E10321','E10329','E10331','E10339','E10341',
								'E10352','E10353','E10354','E10355','E10359','E1036','E1037','E1039','E1040','E1041',
								'E1044','E1049','E1051','E1052','E1059','E10610','E10618','E10620','E10621','E10622',
								'E10638','E10641','E10649','E1065','E1069','E108','E1100','E1101','E1110','E1111',
								'E1129','E1131','E11319','E11321','E11329','E11331','E11339','E11341','E11349','E11351',
								'E11354','E11355','E11359','E1136','E1137','E1139','E1140','E1141','E1142','E1143',
								'E1151','E1152','E1159','E11610','E11618','E11620','E11621','E11622','E11628','E11630',
								'E11649','E1165','E1169','E118','E1300','E1301','E1310','E1311','E1321','E1322',
								'E13319','E13321','E13329','E13331','E13339','E13341','E13349','E13351','E13352','E13353',
								'E13359','E1336','E1337','E1339','E1340','E1341','E1342','E1343','E1344','E1349',
								'E1359','E13610','E13618','E13620','E13621','E13622','E13628','E13630','E13638','E13641',
								'E1369', 'E138')
)
, DiabWoCompCR2018 AS (
SELECT DISTINCT d.[HICN]--, REPLACE(Dx_Code,'.','') AS CRDiagCode
FROM YOURSERVER.DATABASE.SCHEMA.[CHARTREVIEWRAPS2018_DETAIL] AS d
	LEFT JOIN DBcomp AS dc
	ON dc.HICN=d.HICN
WHERE dc.HICN IS NULL
)
SELECT DISTINCT d.HICN, mc.MemId
INTO ##asilva4_CR2018NoDiabWithComp	
FROM DiabWoCompCR2018 AS d
	LEFT JOIN (SELECT DISTINCT HICN, MBI, ROW_NUMBER() OVER(PARTITION BY MBI ORDER BY import_date DESC) AS rown
				FROM YOURSERVER.DATABASE.SCHEMA.[vw_CMS_HICN_MBI_Crosswalk]) cw
	ON (d.HICN=cw.HICN OR d.HICN=cw.MBI) AND cw.rown=1
	LEFT JOIN (SELECT DISTINCT HIC, memid, ROW_NUMBER() OVER(PARTITION BY memid ORDER BY LastUpdate DESC) AS rown
					FROM YOURSERVER.DATABASE.SCHEMA.[MemberCmsHic]) AS mc
	ON (RTRIM(d.HICN)=mc.Hic OR cw.MBI=mc.Hic OR cw.HICN=mc.Hic) AND mc.rown=1


----Selecting potential members Diab with complication that Diab with comp were not found in the Chart Review 2018

if exists(SELECT * FROM tempdb.dbo.sysobjects WHERE ID = OBJECT_ID(N'tempdb..##asilva4_MembersNotCR2018')) 
	DROP TABLE ##asilva4_MembersNotCR2018

;WITH EM AS (--member detail from enrollment
			SELECT DISTINCT [MRN]
					  , MEDICARE_NUM
					  ,[MEMBER_NAME]
					  ,[MEMBER_DOB_DATE]
					  ,[MEMBER_SEX]
					  ,ROW_NUMBER() OVER(PARTITION BY MRN ORDER BY [DATE_ENTERED] DESC) rown
				  FROM YOURSERVER.DATABASE.SCHEMA.[vw_m_ENROLLMENT_MONTHS_MAPD] em
				  WHERE YEAR([DATE_ENTERED])>='2018'--AND SCCC IS NULL -- AND FIPS_CODE IS NOT NULL
)
, Prov AS (--getting provider info
select DISTINCT p1.provid as PCP_ID, p1.provtype, p1.fullname as PCP_Name, p1.status,p1.npi
,aff.affiltype,  aff.affiliateid as affiliated_provider, 
provgrp.fullname as affilate_name, aff2.affiltype AS affiltype2, provgrp2.provid,provgrp2.fedid,provgrp2.fullname
,isnull(tin.network_code,'COMM') as network_code
from YOURSERVER.DATABASE.SCHEMA.provider p1(nolock) 
  inner join YOURSERVER.DATABASE.SCHEMA.affiliation aff(nolock) on p1.provid=aff.provid
  inner join YOURSERVER.DATABASE.SCHEMA.provider provgrp(nolock) on aff.affiliateid=provgrp.provid
   inner join YOURSERVER.DATABASE.SCHEMA.affiliation aff2(nolock) on provgrp.provid=aff2.provid and aff2.affiltype = 'MGMT'
  inner join YOURSERVER.DATABASE.SCHEMA.provider provgrp2(nolock) on aff2.affiliateid=provgrp2.provid
  left join  YOURSERVER.DATABASE.SCHEMA.[TINCrosswalk] tin(nolock) on provgrp2.fedid=tin.tax_id
where aff.affiltype='SERVICE'
and p1.provid in (SELECT DISTINCT provid FROM ##asilva4_MembersPotencialDiabWcompMOR)
)
SELECT DISTINCT d.memid, d.MRN, em.member_name, em.member_dob_date, d.effdate, d.termdate
				, d.claimid, d.startdate, d.termdate, d.ProviderName, p.affilate_name, p.network_code
INTO ##asilva4_MembersNotCR2018
--SELECT DISTINCT d.memid
FROM ##asilva4_MembersPotencialDiabWcompMOR AS d
	INNER JOIN ##asilva4_CR2018NoDiabWithComp AS cr
	ON cr.MemId=d.memid
	LEFT JOIN EM
	ON em.mrn=d.MRN AND em.rown=1
	LEFT JOIN Prov AS p
	ON d.provid=p.PCP_ID

	
--Selecting potential members Diab with complication that did not have Chart Review 2018
if exists(SELECT * FROM tempdb.dbo.sysobjects WHERE ID = OBJECT_ID(N'tempdb..##asilva4_CR2018memid')) 
	DROP TABLE ##asilva4_CR2018memid

SELECT DISTINCT d.HICN, mc.MemId
INTO ##asilva4_CR2018memid	
FROM (SELECT DISTINCT [HICN]
		FROM YOURSERVER.DATABASE.SCHEMA.[CHARTREVIEWRAPS2018_DETAIL]) AS d
	LEFT JOIN (SELECT DISTINCT HICN, MBI, ROW_NUMBER() OVER(PARTITION BY MBI ORDER BY import_date DESC) AS rown
				FROM YOURSERVER.DATABASE.SCHEMA.[vw_CMS_HICN_MBI_Crosswalk]) cw
	ON (d.HICN=cw.HICN OR d.HICN=cw.MBI) AND cw.rown=1
	LEFT JOIN (SELECT DISTINCT HIC, memid, ROW_NUMBER() OVER(PARTITION BY memid ORDER BY LastUpdate DESC) AS rown
					FROM YOURSERVER.DATABASE.SCHEMA.[MemberCmsHic]) AS mc
	ON (RTRIM(d.HICN)=mc.Hic OR cw.MBI=mc.Hic OR cw.HICN=mc.Hic) AND mc.rown=1




--------------------------------Getting member info and calculating $ difference----------------------------
if exists(SELECT * FROM tempdb.dbo.sysobjects WHERE ID = OBJECT_ID(N'tempdb..##asilva4_EnrollMonths')) 
	DROP TABLE ##asilva4_EnrollMonths

;WITH EM AS (--member detail from enrollment
			SELECT DISTINCT [HMO_ORGANIZATION] AS LOB
					  ,[MRN]
					  , MEDICARE_NUM
					  --, HMC.MBI
					  ,[MEMBER_NAME]
					  ,[MEMBER_DOB_DATE]
					  ,[MEMBER_SEX]
					  ,[FIPS_CODE]
					  ,[PCP_ID]
					  , SCCC
					  ,[EFF_DATE]
					  ,[TERM_DATE]
					  ,ROW_NUMBER() OVER(PARTITION BY MRN ORDER BY [DATE_ENTERED] DESC) rown
				  FROM YOURSERVER.DATABASE.SCHEMA.[vw_m_ENROLLMENT_MONTHS_MAPD] em
				  WHERE YEAR([DATE_ENTERED])>='2018'--AND SCCC IS NULL -- AND FIPS_CODE IS NOT NULL
)
SELECT DISTINCT *
INTO ##asilva4_EnrollMonths
FROM EM
WHERE rown=1

	-----------------Calculating the $ increase
	if exists(SELECT * FROM tempdb.dbo.sysobjects WHERE ID = OBJECT_ID(N'tempdb..##asilva4_Premium')) 
		DROP TABLE ##asilva4_Premium

	;WITH  MMR AS (
		SELECT DISTINCT HICNUMBER
				,CAST(((PtARiskAdjMthlyRateAmtForPymtAdj + PtBRiskAdjMthlyRateAmtForPymtAdj)*.98) as DECIMAL(10,2)) as PremiumBase
				, RAFactorTypeCode AS RAF
				, OrigReasonForEntitlementCode AS OREC
				, StateCountyCode
				, LEFT(paymentdate,4) AS YEAR
				, Sex
				--, DateOfBirth
				, FLOOR(DATEDIFF(DAY, DateOfBirth, GETDATE()) / 365.25) AS Age
				, ROW_NUMBER() OVER(PARTITION BY HICNUMBER ORDER BY importdate DESC) rown
		FROM YOURSERVER.DATABASE.SCHEMA.[vw_CMSMthlyMshp_MonthlyMembershipDetail_MAPD]
		WHERE LEFT(paymentdate,4)='2019'
				AND (PtARiskAdjMthlyRateAmtForPymtAdj + PtBRiskAdjMthlyRateAmtForPymtAdj)>0
				--AND RAF IS NOT NULL
	)

	, MMR2 AS (
			SELECT DISTINCT *, 'HCC' AS HCC 
			FROM MMR
			WHERE rown=1
	) 
	, HCCFactors AS(
			SELECT DISTINCT *
			FROM YOURSERVER.DATABASE.SCHEMA.[HCC_RS_Factors]
			WHERE CY_YEAR=YEAR(GETDATE()) AND HCC IN ('HCC18', 'HCC19')
	)
	, LowestScore AS (--To bring the lowest score of each HCC
			SELECT DISTINCT HCC_NUM
			, Description
			, Models
			, Scores
			, ROW_NUMBER() OVER(partition by unpvt.HCC_NUM ORDER BY unpvt.Scores ASC) AS ScoreOrder
			FROM YOURSERVER.DATABASE.SCHEMA.[HCC_RS_Factors]     
			UNPIVOT 
			( 
				Scores FOR Models  in (CMM_ND_AGED, CMM_ND_DSBD, CMM_FD_AGED, CMM_FD_DSBD, CMM_PD_AGED, CMM_PD_DSBD, INSTITUTIONAL)
			)unpvt
			WHERE CY_YEAR=YEAR(GETDATE())--current year

	)
	, ESRD AS (---To get the ESRD score
			SELECT DISTINCT [HCC]
		  ,[Dialysis]
		  ,[Community]
		  ,[Institutionalized]
	   FROM YOURSERVER.DATABASE.SCHEMA.[ESRD_RS_Factors]
	  WHERE CY_Year=YEAR(GETDATE())
	)

	SELECT DISTINCT mmr2.*
				, CASE 
						WHEN RTRIM(MMR2.RAF)='CN' AND MMR2.OREC='0' THEN mmr2.PremiumBase*hf.CMM_ND_AGED -- Community Non-Dual Aged
						WHEN RTRIM(MMR2.RAF)='CN' AND MMR2.OREC IN ('1','3') THEN mmr2.PremiumBase*hf.CMM_ND_DSBD -- Community Non-Dual Disabled
						WHEN RTRIM(MMR2.RAF)='CF' AND MMR2.OREC='0' THEN mmr2.PremiumBase*hf.CMM_FD_AGED -- Community Full Dual Aged
						WHEN RTRIM(MMR2.RAF)='CF' AND MMR2.OREC IN ('1','3') THEN mmr2.PremiumBase*hf.CMM_FD_DSBD -- Community Full Dual Disabled
						WHEN RTRIM(MMR2.RAF)='CP' AND MMR2.OREC='0' THEN mmr2.PremiumBase*hf.CMM_PD_AGED -- Community Partial Dual Aged
						WHEN RTRIM(MMR2.RAF)='CP' AND MMR2.OREC IN ('1','3') THEN mmr2.PremiumBase*hf.CMM_PD_DSBD -- Community Partial Dual Disabled
						WHEN RTRIM(MMR2.RAF)='I' THEN hf.INSTITUTIONAL -- Institutional
						WHEN RTRIM(MMR2.RAF)='E' OR MMR2.RAF IS NULL THEN mmr2.PremiumBase*ls.scores -- Lowest Score
						WHEN RTRIM(MMR2.RAF)='D' THEN mmr2.PremiumBase*e.[Dialysis] -- ESRD score
						WHEN RTRIM(MMR2.RAF)='C1' AND MMR2.Age>=65 THEN mmr2.PremiumBase*2.562 --Community PostGraft 4-9 mo 65+
						WHEN RTRIM(MMR2.RAF)='C1' AND MMR2.Age<65 THEN mmr2.PremiumBase*2.174 --Community PostGraft 4-9 mo >65
						WHEN RTRIM(MMR2.RAF)='C2' AND MMR2.Age>=65 THEN mmr2.PremiumBase*1.121--Community PostGraft 10+ mo 65+
						WHEN RTRIM(MMR2.RAF)='C2' THEN mmr2.PremiumBase*0.84 --Community PostGraft 10+ mo >65
				   END AS Premium
				, hf.hcc AS HCCFactor
	INTO ##asilva4_Premium
	FROM MMR2
		LEFT JOIN HCCFactors AS hf
		ON LEFT(hf.hcc, 3)=mmr2.HCC
		LEFT JOIN LowestScore AS ls
		ON hf.HCC_Num=ls.HCC_Num AND ls.ScoreOrder=1
		LEFT JOIN ESRD AS e
		ON hf.HCC=e.HCC


--Bringing member data and $ increase together
--I am still getting dups as NULLS from some members.
SELECT DISTINCT pd.memid
				, pd.MRN
				, pd.effdate
				, pd.termdate
				, em.MEDICARE_NUM
				, em.[MEMBER_NAME]
				, em.[MEMBER_DOB_DATE]
				, em.[MEMBER_SEX]
				, em.LOB
				, p19.Premium AS DiabWOcompPremium
				, p18.Premium AS  DiabWcompPremium
				, p18.Premium-p19.Premium AS PremiumDifference
		
FROM ##asilva4_MembersPotencialDiabWcompMOR AS pd
		LEFT JOIN ##asilva4_EnrollMonths em
	ON pd.MRN=em.MRN
	LEFT JOIN YOURSERVER.DATABASE.SCHEMA.[MemberCmsHic] AS mCMShic
	ON mCMShic.MemId=pd.MEMID
	LEFT JOIN YOURSERVER.DATABASE.SCHEMA.[vw_CMS_HICN_MBI_Crosswalk] AS HMC 
	ON mCMShic.Hic=HMC.HICN
	LEFT JOIN (SELECT DISTINCT * 
				FROM ##asilva4_Premium
				WHERE HCCFactor='HCC18') AS p18
	ON COALESCE(mcmshic.HIC, HMC.MBI, em.medicare_num)=p18.HICNUMBER
	LEFT JOIN (SELECT DISTINCT * 
				FROM ##asilva4_Premium
				WHERE HCCFactor='HCC19') AS p19
	ON COALESCE(mcmshic.HIC, HMC.MBI, em.medicare_num)=p19.HICNUMBER



			
