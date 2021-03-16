***************************************************************************************************************
*********** PROGRAM TO PREPARE DATA FOR CHILD MORTALITY HISTORY ANALYSIS USING LONGITUDINAL DATA
// as in - Bocquier et al. 2021, "The Crucial Role of Mothers and Siblings in Child Survival: Evidence from 29 Health and Demographic Surveillance Systems in sub-Saharan Africa" //
/*
**This program uses Health and Demographic Surveillance System data, readily available from the INDEPTH iShare platform (http://www.indepth-ishare.org/)
The data from 29 sites were combined into onefile, here called "ConsolidatedData2018_analysis". This file was cleaned by checking for consistency of events, and ensured uniform coding.

The 29 sites used were as follows:
BF021	Nanoro
BF031	Nouna
BF041	Ouagadougou
CI011	Taabo
ET021	Gilgel Gibe
ET031	Kilite Awlaelo
ET041	Kersa
ET042	Harar Urban
ET051	Dabat
ET061	Arba Minch 
GH011	Navrongo 
GH021	Kintampo 
GH031	Dodowa <=2011
GM011	Farafenni 
KE031	Nairobi
KE051	Kombewa
MW011	Karonga
MZ021	Chokwe  
NG011	Nahuche
SN011	Bandafassi
SN012	Mlomp
SN013	Niakhar
TZ011	Ifakara Rural
TZ012	Rufiji
TZ021	Magu
UG011	Iganga/Mayuge
ZA011	Agincourt
ZA021	Dikgale / Dimamo
ZA031	Africa Centre

The variable "EventCode" is coded as below:
	1. ENU Enumeration
    2. BTH Birth
    3. IMG In-migration
    4. OMG Out-migration
    5. EXT Exit from household
    6. ENT Enter household
    7. DTH Death

This program does the following:
1. Introduces a time-varying covariate for a 6-month period before the birth of a child ("confirmed pregnancy")
2. Identifies mothers, and defines a period around her death (6 months before and after), and her time-varying migration status (in-site)  
3. Identifies siblings, and defines period around their deaths (6 months before and after), and creates birth interval variables
3. Prepares the data to merge the events of the index child and the events of his/her siblings and mother, in temporal order ("tmerge"). This requires that the right-censoring be the same for all individuals. 
	- Note: tmerge is an ado created for Stata that merges data for survival analysis
4. Analysis of child mortality using Cox models, using file named "child_mother_sibling.dta"
*/
********************************************************************************************************************************************


* Change to your own suitable directory
cd "C:\XXX\"

use ConsolidatedData2018_analysis.dta,clear

* converts HDSS site into numeric values 
capture drop CentreLab
encode CentreId, gen(CentreLab)

*unique individual identifier across all HDSS sites
capture drop concat_IndividualId
egen concat_IndividualId=concat(CentreId IndividualId)
order CentreId CentreLab LocationId concat_IndividualId IndividualId

* correction for UG011 (reverse coding of Sex)
replace Sex=cond(Sex==1,2,1) if CentreId=="UG011"

save ConsolidatedData2018_analysis, replace


* TIME-VARYING COVARIATE FOR 6-MONTH PERIOD BEFORE DoB OF CHILDREN BORN IN HDSS
*Create an extra line for 3-month pregnant event (DoB - 6 months)
sort concat_IndividualId EventDate
expand 2 if EventCode==2, gen(duplicatep)

*Delete information on duplicated row
foreach var of varlist EventDate EventCode{
	bys concat_IndividualId : replace `var'=. if duplicatep==1
}

*Replace dates of birth with (DoB - 6 months) for the duplicates
display %20.0f (365.25/2)*24*60*60*1000 // 15778800000 = 6 months in milliseconds
bys concat_IndividualId : replace EventDate=(DoB -15778800000) if duplicatep==1
bys concat_IndividualId : replace EventCode=11 if duplicatep==1

label define eventlab 1 "ENU" 2 "BTH" 3 "IMG" 4 "OMG" 5 "EXT" 6 "ENT" ///
	7 "DTH" 8"-6mDTH" 9 "OBE" 10 "DLV" 11"PREGNANT" 18 "OBS" 19 "OBL"  21 "NewAgeGroup", modify
label val EventCode eventlab

*getting rid of unimportant data for easier management
drop if EventCode==30 	// drop "period" event (e.g. 1st Jan 2000)
drop calendar_*			// and corresponding variables
drop censor_*
drop duplicatep

* To get the same OBE for all individuals of the same HDSS (needed for tmerge)
by CentreId (EventDate), sort: gen last_obs = (_n == _N)
gen double last_record_date = EventDate if last_obs==1
format last_record_date %tC
bysort CentreId (EventDate): replace last_record_date = last_record_date[_N]
sort concat_IndividualId EventDate EventCode
expand=2 if concat_IndividualId!=concat_IndividualId[_n+1] & EventDate<last_record_date, gen(duplicate)
sort concat_IndividualId EventDate EventCode duplicate
by concat_IndividualId : replace EventDate=last_record_date  if duplicate==1
drop duplicate
drop last_obs
sort concat_IndividualId
save residency_pregnancy.dta, replace

*******************************************************************************************************************************
// 1. MERGING MOTHER EVENTS WITH INDEX CHILD EVENTS, INCLUDING MATERNAL COVARIATES//
		
/****************CREATING dataset with MotherId ***************/
use ConsolidatedData2018_analysis.dta, clear
keep CountryId CentreId MotherId 
keep if MotherId!=.
egen concat_MotherId =concat(CountryId CentreId MotherId)
duplicates drop concat_MotherId, force 
rename concat_MotherId concat_IndividualId
sort concat_IndividualId
merge 1:m concat_IndividualId using ConsolidatedData2018_analysis.dta
keep if _merge==3
rename DoB DoB_mother
rename concat_IndividualId concat_MotherId
keep CountryId CentreId concat_MotherId  DoB_mother
duplicates drop
sort CountryId CentreId concat_MotherId  
save Mother, replace 

**select and keep children only with motherid
use ConsolidatedData2018_analysis.dta,clear
egen concat_MotherId =concat(CountryId CentreId MotherId)
sort concat_MotherId
merge m:1 concat_MotherId using Mother.dta
keep if _merge==3 // select only children with identified mothers
keep CountryId CentreId concat_IndividualId DoB Sex EventCode concat_MotherId DoB_mother
sort CountryId CentreId concat_MotherId concat_IndividualId 
* Keep only episodes of BTH to be able to count how many kids per mother
* => Delete children with MotherId but not born in the HDSS
drop if EventCode!=2
* Delete women with more than 15 children and MotherId missing
capture drop nb_children
bysort CountryId CentreId concat_MotherId (concat_IndividualId): ///
			egen nb_children = sum(EventCode==2) 
sort concat_IndividualId
save Children_Mother, replace

**** to create file of unique mother-id- ****************
//by first identifying the mothers, then creating file just with one line per mother and then combining (using individualid)- to identify who the mothers are and include their events

use residency_pregnancy, clear
drop MotherId DeliveryId
* combine mother's events into main file
merge m:1 concat_IndividualId using Children_Mother.dta
keep if _merge==3
drop _merge
sort concat_IndividualId EventDate EventCode

*check to see end date of hdss
capture drop maxEventDate
bysort concat_IndividualId (EventDate) : egen double maxEventDate=max(EventDate/(1000*60*60*24))
format %td maxEventDate
tab maxEventDate, mis

*************Create Mother_Children data in wide format with child rank************
keep concat_IndividualId concat_MotherId DoB DoB_mother
duplicates drop
rename concat_IndividualId concat_ChildId
rename concat_MotherId concat_IndividualId
sort concat_IndividualId
bysort concat_IndividualId (DoB) : gen child_rank = _n
reshape wide concat_ChildId DoB, i(concat_IndividualId) j(child_rank)
save Mother_Children, replace


************** Merge Residency data with Mother_Children to get a Mother file***********
use residency_pregnancy, clear
merge m:1 concat_IndividualId using Mother_Children.dta
drop concat_ChildId*
drop DoB1-DoB16
keep if _merge==3 //just working on mothers
drop _merge
drop MotherId DeliveryId
drop DoB

* to check that all EventDate end up same 1 Jan 
capture drop maxEventDate
bysort concat_IndividualId (EventDate) : egen double maxEventDate=max(EventDate/(1000*60*60*24))
format maxEventDate %td
tab maxEventDate, mis
drop maxEventDate 

******Mother's death********************
* Create date of death of the mother
capture drop deadMO
bysort concat_IndividualId (EventDate): egen double deadMO = max(EventCode==7) // 1=dead, 0=alive
replace deadMO=. if deadMO==0
capture drop DoDMO
bysort concat_IndividualId (EventDate): egen double DoDMO = max(deadMO*EventDate*(EventCode==7)) //for date of death
format DoDMO %tC

**Create an extra line 6 month before mother's death 
sort concat_IndividualId EventDate EventCode
capture drop duplicated
expand 2 if EventCode==7, gen(duplicated)
* Delete information on duplicated row
foreach var of varlist EventDate EventCode {
	bys concat_IndividualId : replace `var'=. if duplicated==1
}
* Replace with date 6 months before death
display %20.0f 30.4375*24*60*60*1000*6 // 6 months in milliseconds
bys concat_IndividualId : replace EventDate=(DoDMO -15778800000) if duplicated==1
* Replace code 
bys concat_IndividualId : replace EventCode=80 if duplicated==1
sort concat_IndividualId EventDate EventCode
bys concat_IndividualId (EventDate EventCode): replace residence=residence[_n+1] ///
		if EventCode==80 & EventCode[_n+1]!=7

**Create an extra line 6 month after mother's death 
sort concat_IndividualId EventDate
capture drop duplicated
expand 2 if EventCode==7,gen(duplicated)
* Delete information on duplicated row
foreach var of varlist EventDate EventCode {
	bys concat_IndividualId : replace `var'=. if duplicated==1
}
bys concat_IndividualId : replace EventDate=(DoDMO + 15778800000) if duplicated==1
bys concat_IndividualId : replace EventCode=89 if duplicated==1
label define eventlab 1 "ENU" 2 "BTH" 3 "IMG" 4 "OMG" 5 "EXT" 6 "ENT" ///
	7 "DTH" 80 "-6mDTH" 89 "+6mDTH" 9 "OBE" 10 "DLV" 11 "PREGNANT" 18 "OBS" 19 "OBL" 20 "1Jan" 21 "NewAgeGroup", modify
label val EventCode eventlab
drop duplicated
replace residence=0 if EventCode==89

* Create variable that helps in computing exposure time in survival analysis 
capture drop datebeg
sort concat_IndividualId EventDate EventCode
qui by concat_IndividualId: gen double datebeg=cond(_n==1, DoB_mother, EventDate[_n-1]) // first line is Date of Birth
format datebeg %tC

capture drop censort_DTH6MO
gen censort_DTH6MO = (EventCode==89)
label var censort_DTH6MO "6 month after mother death"

*to get periods before and after death (with 6 before and 6 after)
stset EventDate if deadMO==1 & (EventCode==89 | EventCode==9 | residence==1), id(concat_IndividualId) failure(censort_DTH6MO==1) time0(datebeg) ///
				origin(time DoDMO-15778800000) scale(31557600000) 
capture drop mdth6m_3m_15j_15j_3m_6m
stsplit mdth6m_3m_15j_15j_3m_6m , at(0 0.25 .45833333 .54166667 .54166667 .75) 
replace mdth6m_3m_15j_15j_3m_6m=6 if mdth6m_3m_15j_15j_3m_6m==. & EventDate>DoDMO
stset, clear

drop censort_DTH6MO
capture drop MO_DTH_TVC
recode mdth6m_3m_15j_15j_3m_6m (0=1 "-6m to -3m MO DTH")(.25=2 "-3m to -15d MO DTH") ///
			(.45833333 = 3 "+/- 15d MO DTH") (.5416667=4 "15d to 3m MO DTH") ///  
			(.75=5 "3m to 6m after MO DTH") (6=6 "6m&+ MO DTH") (.=0 "mother alive or <=-6m MO DTH"),gen(MO_DTH_TVC) label(MO_DTH_TVC)
lab var MO_DTH_TVC "Mother's death TVC"
sort concat_IndividualId EventDate EventCode

replace EventCode=81 if MO_DTH_TVC==1
replace EventCode=82 if MO_DTH_TVC==2 & EventCode==7
replace EventCode=87 if MO_DTH_TVC==3 & (EventCode==89 | EventCode==9) & EventDate<last_record_date 
replace EventCode=88 if MO_DTH_TVC==4 & (EventCode==89 | EventCode==9) & EventDate<last_record_date
replace EventCode=89 if MO_DTH_TVC==5 & (EventCode==89 | EventCode==9) & EventDate<last_record_date
replace EventCode=7 if EventDate==DoDMO

label define eventlab 1 "ENU" 2 "BTH" 3 "IMG" 4 "OMG" 5 "EXT" 6 "ENT" ///
	7 "DTH" 80 "-6mDTH" 81 "-3mDTH" 82 "-15dDTH" 87 "+15dDTH" 88 "+3mDTH"  89 "+6mDTH" ///
	9 "OBE" 10 "DLV" 11 "PREGNANT" 18 "OBS" 19 "OBL" 20 "1Jan" 21 "NewAgeGroup", modify
label val EventCode eventlab

drop if EventDate<DoB & (EventCode>=80 & EventCode<90)
drop if EventDate>last_record_date

* Correction: Residence of the mother should be 0 after her death
replace residence=0 if MO_DTH_TVC==4 | MO_DTH_TVC==5 | MO_DTH_TVC==6


******Mother's in-migration status (time-varying covariate)*********************

* Generate count variable of periods following in-migration
cap drop count_inmig 
bysort concat_IndividualId (EventDate): ///
		gen count_inmig=sum(EventCode[_n-1]!=1 & EventCode[_n-1]!=2 ///
		& residence==1 & residence[_n-1]==0) 

* Generate periods according to the duration of residence since last in-migration
* 1. Set the analysis time to duration of residence since last in-migration only
sort concat_IndividualId count_inmig EventDate 
cap drop concat_IndividualId_inmig 
* Create a new identifier combining individual ID and period after in-migration
capture drop concat_IndividualId_inmig
gen concat_IndividualId_inmig=concat_IndividualId + string(count_inmig)
* Compute time at in-migration for each period after in-migration
cap drop time_inmig
bysort concat_IndividualId_inmig (EventDate) : gen double time_inmig=datebeg[1] if count_inmig>0  
format time_inmig %tC

* 2. Split duration at 6 months, 2 years, 5 years and 10 years for each period after in-migration
* 	6 months refers to the minimum duration for residence otherwise there could be bias
gen byte censor_death=(EventCode==7)
stset EventDate, id(concat_IndividualId_inmig) failure(censor_death==1) time0(datebeg) ///
				origin(time_inmig) scale(31557600000) if(residence==1)
capture drop inmig6m2_5_10y
stsplit inmig6m2_5_10y if count_inmig>0, at(0.5 2 5 10)
sort concat_IndividualId EventDate
bysort concat_IndividualId: replace EventCode=23 if EventCode==EventCode[_n+1] ///
		& inmig6m2_5_10y==0 & inmig6m2_5_10y!=inmig6m2_5_10y[_n+1] & concat_IndividualId==concat_IndividualId[_n+1]
bysort concat_IndividualId: replace EventCode=24 if EventCode==EventCode[_n+1] ///
		& inmig6m2_5_10y==0.5 & inmig6m2_5_10y!=inmig6m2_5_10y[_n+1] & concat_IndividualId==concat_IndividualId[_n+1]
bysort concat_IndividualId: replace EventCode=25 if EventCode==EventCode[_n+1] ///
		& inmig6m2_5_10y==2 & inmig6m2_5_10y!=inmig6m2_5_10y[_n+1] & concat_IndividualId==concat_IndividualId[_n+1]
bysort concat_IndividualId: replace EventCode=26 if EventCode==EventCode[_n+1] ///
		& inmig6m2_5_10y==5 & inmig6m2_5_10y!=inmig6m2_5_10y[_n+1] & concat_IndividualId==concat_IndividualId[_n+1]
label define eventlab 1 "ENU" 2 "BTH" 3 "IMG" 4 "OMG" 5 "EXT" 6 "ENT" ///
	7 "DTH" 80 "-6mDTH" 81 "-3mDTH" 82 "-15dDTH" 87 "+15dDTH" 88 "+3mDTH"  89 "+6mDTH" ///
	9 "OBE" 10 "DLV" 11 "PREGNANT" 18 "OBS" 19 "OBL" 20 "1Jan" 21 "NewAgeGroup" ///
		20 "1Jan" 23 "in6m" 24 "in2y" 25 "in5y" 26 "in10y" 29 "out3y", modify 
	
capture drop migrant_status
recode inmig6m2_5_10y (0 .5=1 "in-mig 6-24m") (2=2 "in-mig 2y-5y") ///
			 (5 10 .=0 "permanent res. or in-mig 5y+") ///
		if residence==1, gen(migrant_statusMO) label(migrant_status)
lab var migrant_statusMO "Mother's migration status"

* Censoring variables are safer recomputed after each stplit 
* NB: 	Because we stset with EventDate and time0(datebeg), neither EventDate nor datebeg need to be recomputed
sort concat_IndividualId EventDate EventCode
cap drop censor_deathMO 
gen censor_deathMO=(EventCode==7) if residence==1

drop count_inmig concat_IndividualId_inmig time_inmig
drop censor_death
stset, clear
rename residence residenceMO

compress
save mother, replace 

************** Merge Residency data with Mother_Children to get a mother file***********

/************Child with event history of the mother***********/

use mother, clear
merge m:1 concat_IndividualId using Mother_Children.dta //identifying kids with motherid
drop _merge
drop Sex

capture drop episode
gen episode=_n
reshape long concat_ChildId DoB, i(episode) j(child_rank) 
drop if concat_ChildId=="" | concat_ChildId==" "
drop episode
capture drop maxEventDate
capture drop datebeg
order CountryId SubContinent CentreId CentreLab LocationId concat_IndividualId child_rank 
rename EventCode EventCodeMO
rename EventDate EventDateMO
rename concat_IndividualId MotherId
rename concat_ChildId concat_IndividualId
order CountryId SubContinent CentreId CentreLab LocationId concat_IndividualId child_rank MotherId EventDateMO EventCodeMO 	
sort concat_IndividualId EventDateMO EventCodeMO
save childMO, replace 

use residency_pregnancy.dta, clear
merge m:1 concat_IndividualId using Children_Mother
keep if _merge==3
sort concat_IndividualId EventDate EventCode

* Create date of death of the child
capture drop dead
bysort concat_IndividualId (EventDate): egen dead = max(EventCode==7)
replace dead=. if dead==0
capture drop DoD
bysort concat_IndividualId (EventDate): egen double DoD = max(dead*EventDate*(EventCode==7))
format DoD %tC

**Create an extra line 6 month before child's death 
sort concat_IndividualId EventDate EventCode
capture drop duplicated
expand 2 if EventCode==7, gen(duplicated)
* Delete information on duplicated row
foreach var of varlist EventDate EventCode {
	bys concat_IndividualId : replace `var'=. if duplicated==1
}
* Replace with date 6 months before death
display %20.0f 30.4375*24*60*60*1000*6 // 6 months in milliseconds
bys concat_IndividualId : replace EventDate=(DoD -15778800000) if duplicated==1
* Replace event code 
bys concat_IndividualId : replace EventCode=80 if duplicated==1
sort concat_IndividualId EventDate EventCode
bys concat_IndividualId (EventDate EventCode): replace residence=residence[_n+1] ///
		if EventCode==80 & EventCode[_n+1]!=7

**Create an extra line 6 month after child's death 
sort concat_IndividualId EventDate
capture drop duplicated
expand 2 if EventCode==7, gen(duplicated)
* Delete information on duplicated row
foreach var of varlist EventDate EventCode {
	bys concat_IndividualId : replace `var'=. if duplicated==1
}
bys concat_IndividualId : replace EventDate=(DoD + 15778800000) if duplicated==1
bys concat_IndividualId : replace EventCode=89 if duplicated==1
label define eventlab 1 "ENU" 2 "BTH" 3 "IMG" 4 "OMG" 5 "EXT" 6 "ENT" ///
	7 "DTH" 80 "-6mDTH" 89 "+6mDTH" 9 "OBE" 10 "DLV" 11 "PREGNANT" 18 "OBS" 19 "OBL" 20 "1Jan" 21 "NewAgeGroup", modify
label val EventCode eventlab
drop duplicated
replace residence=0 if EventCode==89
capture drop datebeg
sort concat_IndividualId EventDate EventCode
qui by concat_IndividualId: gen double datebeg=cond(_n==1, DoB, EventDate[_n-1])
format datebeg %tC

capture drop censort_DTH6
gen censort_DTH6 = (EventCode==89)
label var censort_DTH6 "6 month after child death"

stset EventDate if dead==1 & (EventCode==89 | EventCode==9 | residence==1), id(concat_IndividualId) failure(censort_DTH6==1) time0(datebeg) ///
				origin(time DoD-15778800000) scale(31557600000) 
capture drop mdth6m_3m_15j_15j_3m_6m
stsplit mdth6m_3m_15j_15j_3m_6m , at(0 0.25 .45833333 .54166667 .54166667 .75)
replace mdth6m_3m_15j_15j_3m_6m=6 if mdth6m_3m_15j_15j_3m_6m==. & EventDate>DoD
stset, clear
drop censort_DTH6
capture drop DTH_TVC
recode mdth6m_3m_15j_15j_3m_6m (0=1 "-6m to -3m  DTH")(.25=2 "-3m to -15d  DTH") ///
			(.45833333 = 3 "+/- 15d  DTH") (.5416667=4 "15d to 3m  DTH") ///  
			(.75=5 "3m to 6m after  DTH") (6=6 "6m&+  DTH") (.=0 "child alive or <=-6m  DTH"), gen(DTH_TVC) label(DTH_TVC)
lab var DTH_TVC "child's death TVC"
sort concat_IndividualId EventDate EventCode

replace EventCode=81 if DTH_TVC==1
replace EventCode=82 if DTH_TVC==2 & EventCode==7
replace EventCode=87 if DTH_TVC==3 & (EventCode==89 | EventCode==9) & EventDate<last_record_date
replace EventCode=88 if DTH_TVC==4 & (EventCode==89 | EventCode==9) & EventDate<last_record_date
replace EventCode=89 if DTH_TVC==5 & (EventCode==89 | EventCode==9) & EventDate<last_record_date
replace EventCode=7 if EventDate==DoD

label define eventlab 1 "ENU" 2 "BTH" 3 "IMG" 4 "OMG" 5 "EXT" 6 "ENT" ///
	7 "DTH" 80 "-6mDTH" 81 "-3mDTH" 82 "-15dDTH" 87 "+15dDTH" 88 "+3mDTH"  89 "+6mDTH" ///
	9 "OBE" 10 "DLV" 11 "PREGNANT" 18 "OBS" 19 "OBL" 20 "1Jan" 21 "NewAgeGroup", modify
label val EventCode eventlab

drop if EventDate<DoB & (EventCode>=80 & EventCode<90)
drop if EventDate>last_record_date

drop MotherId DeliveryId concat_MotherId DoB_mother _merge
sort concat_IndividualId EventDate EventCode
save child, replace 

/*********TMERGE child file with mother variables file *******************************/

// Tmerge is an ado file external to Stata that needs to be installed before use //
* It is available in the Annex of Bocquier & Ginsburg 2017, "Manual of Event History Data Analysis using Longitudinal Data"

//Important conditions for using tmerge//
//  1) all individuals in file1 have to be in file2 (using child id to merge - concat_IndividualId) and 2) all individuals must have the same date for OBE (within the site) in both files 

clear
capture erase child_mother.dta
tmerge concat_IndividualId child(EventDate) childMO(EventDateMO) child_mother(EventDate_final)
		// tmerge id file1(date) file2(date2) namefile1+2(combined dates) *output file
		
capture drop datebeg

format EventDate_final %tC
drop EventDate 
rename EventDate_final EventDate

order CountryId SubContinent CentreId CentreLab LocationId concat_IndividualId EventDate EventCode
sort concat_IndividualId EventDate EventCode

* _File is a variable created with the values: 1= observation from child file, 2 observation from mother file, 3 = event from both files (eg migration of both at same time)- but only one line is kept
replace EventCode = 18 if _File==2 // this is to identify that the line of event comes from mother and not the child- the type of event is coded in eventcodeMO
replace EventCodeMO = 18 if _File==1

rename _File child_mother_file

save child_mother, replace

* recreating/updating  datebeg and censordeath after merge
capture drop datebeg
bysort concat_IndividualId (EventDate): gen double datebeg=cond(_n==1,DoB,EventDate[_n-1])
format datebeg %tC
sort concat_IndividualId EventDate EventCode
cap drop censor_death
gen byte censor_death=(EventCode==7) if residence==1

clear

****************************************************************************************************
// 2. MERGING SIBLING EVENTS WITH INDEX CHILD EVENTS, INCLUDING SIBLING COVARIATES //

*** Step 1: define sibling true rank
* The child_mother is merged with the Mother_Children file to identify the rank of Ego among siblings:
use child_mother, clear
bysort concat_IndividualId (EventDate): gen byte last_obs=(_N==_n)
keep if last_obs==1 
keep concat_IndividualId MotherId last_record_date
duplicates drop
rename concat_IndividualId EgoId
rename MotherId concat_IndividualId
merge m:1 concat_IndividualId using Mother_Children.dta // file with one line per child- and all related siblings
drop _merge 

*The file is reshaped into long format (one sibling per record identified by ChildId):
rename concat_IndividualId MotherId 
reshape long concat_ChildId DoB, i(EgoId MotherId) j(child_rank) 
drop if concat_ChildId ==""
drop if concat_ChildId ==" "

*The index child (ego) is identified among the siblings by the individual identifier using an indicator variable:
gen Ego= EgoId==concat_ChildId
sort EgoId DoB

*To determine the birth order of children born of the same mother:
gen true_child_rank=1
bysort EgoId (DoB) : replace true_child_rank = ///
		cond(DoB>DoB[_n-1],true_child_rank[_n-1]+1,true_child_rank[_n-1]) ///
		if _n!=1

*The rank of the index child is identified using the indicator variable for Ego:
bysort EgoId (DoB) : egen Ego_rank = max(cond(Ego==1,true_child_rank,0))
save child_mother_Ego, replace

**** Step 2: create files for the twin sibling, and the younger and older siblings
*Select the twin siblings:
use child_mother_Ego, clear 
bysort EgoId (child_rank) : keep if true_child_rank==Ego_rank & concat_ChildId!=EgoId
keep EgoId concat_ChildId last_record_date
sort concat_ChildId EgoId
bysort concat_ChildId (EgoId): gen sibling=_n
reshape wide EgoId, i(concat_ChildId) j(sibling)
duplicates drop
rename concat_ChildId concat_IndividualId
sort concat_IndividualId
save twin, replace

*Select the non-twin siblings:
use child_mother_Ego, clear 
bysort EgoId (child_rank) : gen twin= true_child_rank==true_child_rank[_n+1] | true_child_rank==true_child_rank[_n-1]   
bysort EgoId (child_rank) : drop if twin==1
keep concat_ChildId last_record_date
duplicates drop
rename concat_ChildId concat_IndividualId
sort concat_IndividualId
save non_twin, replace

*Merge the file for twin with the core residency file to get their event history:
use child_mother, clear
sort concat_IndividualId
merge m:1 concat_IndividualId using twin.dta
keep if _merge==3
drop _merge
keep concat_IndividualId EventDate EventCode Sex DoB residence DTH_TVC EgoId*
rename concat_IndividualId TwinId
rename EventDate EventDateTwin
rename EventCode EventCodeTwin
rename Sex SexTwin
rename DoB DoBTwin
rename residence residenceTwin
rename DTH_TVC Twin_DTH_TVC 
duplicates drop
reshape long EgoId, i(TwinId EventDateTwin) j(sibling)
drop if EgoId==""
drop if EgoId==" "
rename EgoId concat_IndividualId
sort concat_IndividualId TwinId EventDateTwin
order concat_IndividualId
append using non_twin 

* Recode OBE for non-twin
recode EventCodeTwin .=9
replace EventDateTwin=last_record_date if EventDateTwin==.
sort concat_IndividualId EventDateTwin
bysort concat_IndividualId : gen chck_OBEt = cond(_n==_N,EventCodeTwin[_N],0) 
bysort concat_IndividualId : gen chck_dateOBEt = cond(_n==_N,EventDateTwin[_N],0)
tab1 EventCode chck_OBEt chck_dateOBEt
drop chck_OBEt chck_dateOBEt
compress
save twin, replace
erase non_twin.dta

*Select the younger siblings (including younger twin siblings):
use child_mother_Ego, clear 
bysort EgoId (child_rank) : keep if true_child_rank==Ego_rank+1
keep EgoId concat_ChildId last_record_date
bysort concat_ChildId (EgoId): gen sibling=_n
reshape wide EgoId, i(concat_ChildId) j(sibling)
duplicates drop
rename concat_ChildId concat_IndividualId
sort concat_IndividualId
save ysibling, replace

* Children with no younger sibling (last rank)
use child_mother_Ego, clear 
bysort EgoId (child_rank) : egen max_child_rank=max(true_child_rank)
bysort EgoId (child_rank) : keep if true_child_rank==max_child_rank
keep concat_ChildId last_record_date
duplicates drop
rename concat_ChildId concat_IndividualId
sort concat_IndividualId
save non_ysibling, replace

*Merge the file of younger siblings with the core residency file to get their event history:
use child_mother, clear
sort concat_IndividualId
merge m:1 concat_IndividualId using ysibling.dta
keep if _merge==3
drop _merge
keep concat_IndividualId EventDate EventCode Sex DoB residence DTH_TVC EgoId*
rename concat_IndividualId YsiblingId
rename EventDate EventDateYsibling
rename EventCode EventCodeYsibling
rename Sex SexYsibling
rename DoB DoBYsibling
rename residence residenceYsibling
rename DTH_TVC Y_DTH_TVC 
sort YsiblingId EventDateYsibling EventCodeYsibling
duplicates drop
reshape long EgoId, i(YsiblingId EventDateYsibling) j(sibling)
drop if EgoId==""
drop if EgoId==" "
drop sibling
rename EgoId concat_IndividualId
sort concat_IndividualId YsiblingId EventDateYsibling
order concat_IndividualId
append using non_ysibling

* Recode OBE for non-younger siblings
recode EventCodeYsibling .=9
replace EventDateYsibling=last_record_date if EventDateYsibling==.
sort concat_IndividualId EventDateYsibling

capture drop datebeg
sort YsiblingId EventDateYsibling EventCodeYsibling
qui by YsiblingId: gen double datebeg=cond(_n==1, DoBYsibling, EventDateYsibling[_n-1])
format datebeg %tC

capture drop censor_BTH
gen censor_BTH = (EventCodeYsibling==2)

// to get duration of period after birth of younger sibling, as well as during preganancy period

display %20.0f  (365.25*0.5) * 24 * 60 * 60 * 1000
* 15778800000  
display %20.0f  365.25 * 24 * 60 * 60 * 1000 
* 31557600000

stset EventDate, id(YsiblingId) failure(censor_BTH==1) time0(datebeg) ///
				origin(time DoBYsibling-15778800000) scale(31557600000) 

gen YsiblingId_EgoId = YsiblingId + concat_IndividualId
capture drop datebeg
sort YsiblingId_EgoId EventDateYsibling EventCodeYsibling
qui by YsiblingId_EgoId: gen double datebeg=cond(_n==1, DoBYsibling, EventDateYsibling[_n-1])
format datebeg %tC

sort YsiblingId_EgoId EventDateYsibling EventCodeYsibling
cap drop lastrecord
qui by YsiblingId_EgoId: gen lastrecord=_n==_N
stset EventDateYsibling, id(YsiblingId_EgoId) failure(lastrecord==1) ///
		time0(datebeg) origin(time DoBYsibling-15778800000)

capture drop birth_int
stsplit birth_int, at(0 15778800000 31557600000 47336400000)

recode birth_int (0=1 "pregnant_YS") (15778800000=2 "0-6m") ///
			(31557600000=3 "6-12m") (47336400000=4 "12m&+"), ///
			gen(birth_int_YS) label(lbirth_int_YS)

sort YsiblingId EventDateYsibling EventCodeYsibling
drop lastrecord
drop birth_int
drop _*

capture drop datebeg
sort YsiblingId EventDateYsibling EventCodeYsibling
qui by YsiblingId: gen double datebeg=cond(_n==1, DoBYsibling, EventDateYsibling[_n-1])
format datebeg %tC

save ysibling, replace
erase non_ysibling.dta

*The same is done for the older siblings. Select the older siblings (including twin older siblings):
use child_mother_Ego, clear 
bysort EgoId (child_rank) : keep if true_child_rank==Ego_rank-1
keep EgoId concat_ChildId last_record_date
bysort concat_ChildId (EgoId): gen sibling=_n
reshape wide EgoId, i(concat_ChildId) j(sibling)
duplicates drop
rename concat_ChildId concat_IndividualId
sort concat_IndividualId
save osibling, replace

* Children with no older sibling (first rank)
use child_mother_Ego, clear 
bysort EgoId (child_rank) : egen min_child_rank=min(true_child_rank)
bysort EgoId (child_rank) : keep if true_child_rank==min_child_rank
keep concat_ChildId last_record_date
duplicates drop
rename concat_ChildId concat_IndividualId
sort concat_IndividualId
save non_osibling, replace

*Merge the file of older siblings with the core residency file to get their event history
use child_mother, clear
sort concat_IndividualId
merge m:1 concat_IndividualId using osibling.dta
keep if _merge==3
drop _merge
keep concat_IndividualId EventDate EventCode Sex DoB residence DTH_TVC EgoId*
rename concat_IndividualId OsiblingId
rename EventDate EventDateOsibling
rename EventCode EventCodeOsibling
rename Sex SexOsibling
rename DoB DoBOsibling
rename residence residenceOsibling
rename DTH_TVC O_DTH_TVC 
duplicates drop
reshape long EgoId, i(OsiblingId EventDateOsibling) j(sibling)
drop if EgoId==""
drop if EgoId==" "
drop sibling
rename EgoId concat_IndividualId
sort concat_IndividualId OsiblingId EventDateOsibling
order concat_IndividualId
append using non_osibling

* Recode OBE for non-older siblings
recode EventCodeOsibling .=9
replace EventDateOsibling=last_record_date if EventDateOsibling==.
sort concat_IndividualId EventDateOsibling
save osibling, replace
erase non_osibling.dta

*** Step 3: merge the younger and older sibling files with children file
*Merge the file of twin with the child file that already includes parents’ history:
clear
capture erase child_mother_twin.dta
tmerge concat_IndividualId child_mother(EventDate) twin(EventDateTwin) ///
		child_mother_twin(EventDate_final)

format EventDate_final %tC
drop EventDate 
rename EventDate_final EventDate
replace EventCode = 18 if _File==2
replace EventCodeTwin = 18 if _File==1
drop _File
order concat_IndividualId EventDate EventCode
sort concat_IndividualId EventDate EventCode
save child_mother_twin, replace

*Merge the file of younger siblings with the children file that already includes parents’ and twin’s history:
clear
capture erase child_mother_t_y.dta
tmerge concat_IndividualId child_mother_twin(EventDate) ysibling(EventDateY) ///
		child_mother_t_y(EventDate_final)

format EventDate_final %tC
drop EventDate 
rename EventDate_final EventDate
replace EventCode = 18 if _File==2
replace EventCodeY = 18 if _File==1
drop _File
order concat_IndividualId EventDate EventCode
sort concat_IndividualId EventDate EventCode
save child_mother_t_y, replace

use osibling

*Merge the file of older siblings with the children file that includes parents’ and younger siblings’ histories:
clear
capture erase child_mother_sibling.dta
tmerge concat_IndividualId child_mother_t_y(EventDate) osibling(EventDateO) ///
		child_mother_sibling(EventDate_final)

format EventDate_final %tC
drop EventDate 
rename EventDate_final EventDate
replace EventCode = 18 if _File==2
replace EventCodeO = 18 if _File==1
order concat_IndividualId EventDate EventCode
sort concat_IndividualId EventDate EventCode


**Correction residenceYsibling residenceOsibling - to make sure we dont have residence values before birth of siblings
replace residenceYsibling=. if EventDate<=DoBYsibling & residenceYsibling!=.
replace residenceOsibling=. if EventDate<=DoBOsibling & residenceOsibling!=.
replace residenceTwin=. if EventDate<=DoBTwin & residenceTwin!=.
replace DoBYsibling=. if residenceYsibling==.
replace DoBOsibling=. if residenceOsibling==.
replace DoBTwin=. if residenceTwin==.

bysort concat_IndividualId (DoBOsibling): replace DoBOsibling = DoBOsibling[1]
bysort concat_IndividualId (DoBYsibling): replace DoBYsibling = DoBYsibling[1]
bysort concat_IndividualId (DoBTwin): replace DoBTwin = DoBTwin[1]
format DoBYsibling %tC
format DoBOsibling %tC
format DoBTwin %tc


drop mdth6m_3m_15j_15j_3m_6m EventDateMO deadMO DoDMO inmig6m2_5_10y censor_deathMO child_mother_file 
drop EventDateTwin 
drop EventDateYsibling  YsiblingId_EgoId 
drop EventDateOsibling  
drop censor_BTH datebeg _File 

order CentreId CentreLab LocationId concat_IndividualId EventDate EventCode
compress
save child_mother_sibling, replace

***	Step 4: Restricting observation to under-5 year olds

use child_mother_sibling, clear
capture drop censor_death 
gen censor_death=(EventCode==7) if residence==1
capture drop datebeg
bysort concat_IndividualId (EventDate): gen double datebeg=cond(_n==1,DoB,EventDate[_n-1])
format datebeg %tC

stset EventDate if residence==1, id(concat_IndividualId) failure(censor_death==1) ///
		time0(datebeg) origin(time DoB) exit(time .)  

		capture drop fifthbirthday
display %20.0f (5*365.25*24*60*60*1000)+212000000 /* adding 2 days */
* 158000000000
stsplit fifthbirthday, at(158000000000) trim
drop if fifthbirthday!=0
compress

save child_mother_sibling, replace

**********************************************************************************************************************************************************************************
// 3. MODELLING CHILD SURVIVAL //

//a. PREPARING COVARIATES //

* Generate indicator variables for death of mother and siblings:
capture drop Dead*
bysort concat_IndividualId (EventDate): gen byte DeadMO=sum(EventCodeMO[_n-1]==7) 
bysort concat_IndividualId (EventDate): gen byte DeadY =sum(EventCodeY[_n-1]==7) 
bysort concat_IndividualId (EventDate): gen byte DeadO =sum(EventCodeO[_n-1]==7) 
bysort concat_IndividualId (EventDate): gen byte DeadTwin =sum(EventCodeTwin[_n-1]==7) 
replace DeadMO= 1 if DeadMO>1 & DeadMO!=. 
replace DeadY = 1 if DeadY >1 & DeadY !=. 
replace DeadO = 1 if DeadO >1 & DeadO !=. 
replace DeadTwin = 1 if DeadTwin >1 & DeadTwin !=. 

* New variable for residence accounting for death: 
capture drop MigDead*
gen byte MigDeadMO=(1+residenceMO+2*DeadMO) 
recode MigDeadMO (4 = 3)
lab def MigDeadMO 1"mother non resident" 2 "mother res" 3 "mother dead" 4 "mother res dead",  modify
lab val MigDeadMO MigDeadMO
replace MigDeadMO=3 if MO_DTH_TVC==4 | MO_DTH_TVC==5 //fixing errors due to duplications from tmerge (mother is dead after death)

*migrant status of mother if non-resident needs to be fixed
replace migrant_statusMO = 0 if MigDeadMO==1 
bysort concat_IndividualId (EventDate): replace migrant_statusMO = migrant_statusMO[1] if migrant_statusMO==.

gen byte MigDeadY=cond(residenceY==., 0, 1 + (residenceY==1) + 2*(DeadY==1)) //residence missing when not yet born
recode MigDeadY(4=3) 
lab def MigDeadY 0 "no young sib" 1 "y sib non-res" 2 "y sib resident" 3 "y sib dead" 4 "y sib res dead",  modify
lab val MigDeadY MigDeadY
replace MigDeadY=2 if MigDeadY==3 & Y_DTH_TVC<3
replace MigDeadY=3 if MigDeadY!=3 & (Y_DTH_TVC==4 | Y_DTH_TVC==5)

gen byte MigDeadTwin=cond(residenceTwin==., 0, 1 + (residenceTwin==1) + 2*(DeadTwin==1)) 
recode MigDeadTwin(4=3) 
lab def MigDeadTwin 0 "no twin" 1 "twin non-res" 2 "twin resident" 3 "twin dead" 4 "twin res dead",  modify
lab val MigDeadTwin MigDeadTwin
replace MigDeadTwin=2 if MigDeadTwin==3 & Twin_DTH_TVC<3
replace MigDeadTwin=3 if MigDeadTwin!=3 & (Twin_DTH_TVC==4 | Twin_DTH_TVC==5)

gen byte MigDeadO=cond(residenceO==., 0, 1 + (residenceO==1) + 2*(DeadO==1))
recode MigDeadO(4=3) 
lab def MigDeadO 0 "no older sib" 1 "o sib non-res" 2 "o sib resident" 3 "o sib dead" 4 "o sib res dead",  modify
lab val MigDeadO MigDeadO
replace MigDeadO=2 if MigDeadO==3 & O_DTH_TVC<3
replace MigDeadO=3 if MigDeadO!=3 & (O_DTH_TVC==4 | O_DTH_TVC==5)

** Generate calendar periods
cap drop lastrecord
qui bys concat_IndividualId (EventDate): gen byte lastrecord=(_n==_N) 
tab lastrecord

//dropping redundant lines that were created for periods before the start of the surveillance (eg. 6m before death)
sort concat_IndividualId EventDate 
summarize EventDate if concat_IndividualId!=concat_IndividualId[_n-1] & CentreId=="BF021" ///
	& EventDateg<clock("01jan2010","DMY"), format detail
drop if CentreId=="BF021" & EventDate<clock("25mar2009","DMY")
summarize EventDate if concat_IndividualId!=concat_IndividualId[_n-1] & CentreId=="BF031" ///
	& EventDate<clock("01jul1999","DMY"), format detail
drop if CentreId=="BF031" & EventDate<clock("08sep1995","DMY")
summarize EventDate if concat_IndividualId!=concat_IndividualId[_n-1] & CentreId=="BF041" ///
	& EventDate<clock("01jul2009","DMY"), format detail
drop if CentreId=="BF041" & datebeg<clock("10sep1998","DMY")
summarize EventDate if concat_IndividualId!=concat_IndividualId[_n-1] & CentreId=="CI011" ///
	& EventDate<clock("01jul2009","DMY"), format detail
drop if CentreId=="CI011" & EventDate<clock("05mar2009","DMY")
summarize EventDate if concat_IndividualId!=concat_IndividualId[_n-1] & CentreId=="ET021" ///
	& EventDate<clock("01jul2006","DMY"), format detail
drop if CentreId=="ET021" & EventDate<clock("01jan2006","DMY")
summarize EventDate if concat_IndividualId!=concat_IndividualId[_n-1] & CentreId=="ET031" ///
	& EventDate<clock("01jul2010","DMY"), format detail
drop if CentreId=="ET031" & EventDate<clock("01jan2010","DMY")
summarize EventDate if concat_IndividualId!=concat_IndividualId[_n-1] & CentreId=="ET041" ///
	& EventDate<clock("01jul2008","DMY"), format detail
drop if CentreId=="ET041" & EventDate<clock("19oct1995","DMY")
summarize EventDate if concat_IndividualId!=concat_IndividualId[_n-1] & CentreId=="ET042" ///
	& EventDate<clock("01jan2013","DMY"), format detail
drop if CentreId=="ET042" & EventDate<clock("01sep2012","DMY")
summarize EventDate if concat_IndividualId!=concat_IndividualId[_n-1] & CentreId=="ET051" ///
	& EventDate<clock("01jul2009","DMY"), format detail
drop if CentreId=="ET051" & EventDate<clock("01jan2009","DMY")
summarize EventDate if concat_IndividualId!=concat_IndividualId[_n-1] & CentreId=="ET061" ///
	& EventDate<clock("01jul2010","DMY"), format detail
drop if CentreId=="ET061" & EventDate<clock("01jan2010","DMY")
summarize EventDate if concat_IndividualId!=concat_IndividualId[_n-1] & CentreId=="GH011" ///
	& EventDate<clock("01jan1994","DMY"), format detail
drop if CentreId=="GH011" & EventDate<clock("01sep1984","DMY")
summarize EventDate if concat_IndividualId!=concat_IndividualId[_n-1] & CentreId=="GH021" ///
	& EventDate<clock("01jul2006","DMY"), format detail
drop if CentreId=="GH021" & EventDate<clock("10may1997","DMY")
summarize EventDate if concat_IndividualId!=concat_IndividualId[_n-1] & CentreId=="GM011" ///
	& EventDate<clock("01jan1990","DMY"), format detail
drop if CentreId=="GM011" & EventDate<clock("10apr1975","DMY")
summarize EventDate if concat_IndividualId!=concat_IndividualId[_n-1] & CentreId=="KE031" ///
	& EventDate<clock("01jul2003","DMY"), format detail
drop if CentreId=="KE031" & EventDate<clock("01jan2003","DMY")
summarize EventDate if concat_IndividualId!=concat_IndividualId[_n-1] & CentreId=="KE051" ///
	& EventDate<clock("01jul2011","DMY"), format detail
drop if CentreId=="KE051" & EventDate<clock("20jan2011","DMY")
summarize EventDate if concat_IndividualId!=concat_IndividualId[_n-1] & CentreId=="MW011" ///
	& EventDate<clock("01jul2003","DMY"), format detail
drop if CentreId=="MW011" & EventDate<clock("01jan2003","DMY")
summarize EventDate if concat_IndividualId!=concat_IndividualId[_n-1] & CentreId=="MZ021" ///
	& EventDate<clock("01jan2011","DMY"), format detail
drop if CentreId=="MZ021" & EventDate<clock("14jun2010","DMY")
summarize EventDate if concat_IndividualId!=concat_IndividualId[_n-1] & CentreId=="NG011" ///
	& EventDate<clock("01jul2011","DMY"), format detail
drop if CentreId=="NG011" & EventDate<clock("01jan2011","DMY")
summarize EventDate if concat_IndividualId!=concat_IndividualId[_n-1] & CentreId=="SN011" ///
	& EventDate<clock("01jul1989","DMY"), format detail
drop if CentreId=="SN011" & EventDate<clock("15apr1974","DMY")
summarize EventDate if concat_IndividualId!=concat_IndividualId[_n-1] & CentreId=="SN012" ///
	& EventDate<clock("01jul1989","DMY"), format detail
drop if CentreId=="SN012" & EventDate<clock("10apr1986","DMY")
summarize EventDate if concat_IndividualId!=concat_IndividualId[_n-1] & CentreId=="SN013" ///
	& EventDate<clock("01jul1989","DMY"), format detail
drop if CentreId=="SN013" & EventDate<clock("20jun1985","DMY")
summarize EventDate if concat_IndividualId!=concat_IndividualId[_n-1] & CentreId=="TZ011" ///
	& EventDate<clock("01jul1998","DMY"), format detail
drop if CentreId=="TZ011" & EventDate<clock("01jan1997","DMY")
summarize EventDate if concat_IndividualId!=concat_IndividualId[_n-1] & CentreId=="TZ021" ///
	& EventDate<clock("01jan1995","DMY"), format detail
drop if CentreId=="TZ021" & EventDate<clock("30jul1994","DMY")
summarize EventDate if concat_IndividualId!=concat_IndividualId[_n-1] & CentreId=="UG011" ///
	& EventDate<clock("01may2005","DMY"), format detail
drop if CentreId=="UG011" & EventDate<clock("28sept1981","DMY")
summarize EventDate if concat_IndividualId!=concat_IndividualId[_n-1] & CentreId=="ZA011" ///
	& EventDate<clock("01jul1993","DMY"), format detail
drop if CentreId=="ZA011" & EventDate<clock("01jan1993","DMY")
summarize EventDate if concat_IndividualId!=concat_IndividualId[_n-1] & CentreId=="ZA021" ///
	& EventDate<clock("01jul1996","DMY"), format detail
drop if CentreId=="ZA021" & EventDate<clock("27jan1996","DMY")

stset EventDate if residence==1, id(concat_IndividualId) failure(lastrecord==1) ///
		time0(datebeg)  
		
* To get values of 01Jan for each year
foreach num in 1990 1995 2000 2005 2010 2015 {
	display %20.0f clock("01Jan`num'","DMY")
}

capture drop period 
stsplit period, at(946771200000 1104537600000 1262304000000 ///
			1420156800000 1577923200000 1735689600000)
recode period (946771200000=1990) (1104537600000=1995) (1262304000000=2000) ///
			(1420156800000=2005) (1577923200000=2010) (1735689600000=2015)
label variable period period

sort concat_IndividualId EventDate
by concat_IndividualId: replace EventCode=30 if EventCode==EventCode[_n+1] ///
		& period!=. & period!=period[_n+1] & concat_IndividualId==concat_IndividualId[_n+1]
label define eventlab 30 "Period", modify
lab val EventCode eventlab

sort concat_IndividualId EventDate EventCode
cap drop censor_death
gen byte censor_death=(EventCode==7) if residence==1
stset EventDate if residence==1, id(concat_IndividualId) failure(censor_death==1) ///
			time0(datebeg) origin(time DoB) exit(time .) scale(31557600000)

* clean some inconsistent out-of-period data for some sites
tab CentreId period [iw=_t-_t0],  missing
format datebeg %tC

drop if period==0 | period==.

***Age of mother at birth of child
capture drop mother_age_birth
gen mother_age_birth = (DoB - DoB_mother)/31557600000

*remove mothers who were below 13 years old or over 52 years at time of birth
capture drop error_m_age
gen byte error_m_age = cond(mother_age_birth==.,.,cond(mother_age_birth<13| mother_age_birth>52,1,0))
drop if error_m_age == 1
drop error_m_age

capture drop y3_mother_age_birth
gen int_mother_age_birth=int(mother_age_birth)
recode int_mother_age_birth (min/17=15 "15-17") (18/20=18 "18–20") (21/23=21 "21–23") ///
		(24/26=24 "24–26") (27/29=27 "27–29") (30/32=30 "30–32") (33/35=33 "33–35") ///
		(36/38=36 "36–38") (39/41=39 "39–41") (42/max=42 "42+") (.=99 "Missing"), gen(y3_mother_age_birth)
drop int_mother_age_birth

***creating birth intervals (in months)
capture drop ecart_O 
gen ecart_O = (DoB - DoBOsibling)*12/31557600000

capture drop gp_ecart_O_new
gen byte gp_ecart_O_new = cond(ecart_O==.,0, ///
				cond(ecart_O<12,1, ///
				cond(ecart_O<18,2, ///
				cond(ecart_O<24,3, ///
				cond(ecart_O<30,4, ///
				cond(ecart_O<36,5, ///
				cond(ecart_O<42,6, ///
				cond(ecart_O<48,7, ///
				8))))))))
label def lgp_ecart_O_new 0"NoOS" 1"<12 months" 2"12-17 months" 3"18-23 months" ///
		4 "24-29 months" 5 "30-35 months" 6 "36-41 months" 7 "42-47 months" 8 "48 months +",modify
label val gp_ecart_O_new lgp_ecart_O_new

capture drop ecart_Y 
gen ecart_Y = (DoBYsibling - DoB)*12/31557600000
				
gen byte gp_ecart_Y_new = cond(ecart_Y==.,0, ///
				cond(ecart_Y<12,1, ///
				cond(ecart_Y<18,2, ///
				cond(ecart_Y<24,3, ///
				cond(ecart_Y<30,4, ///
				cond(ecart_Y<36,5, ///
				cond(ecart_Y<42,6, ///
				cond(ecart_Y<48,7, ///
				8))))))))
label def lgp_ecart_Y_new 0 "NoYS" 1 "<12 months" 2 "12-17 months" 3 "18-23 months" ///
		4 "24-29 months" 5 "30-35 months" 6 "36-41 months" 7 "42-47 months" 8 "48 months +" 
label val gp_ecart_Y_new lgp_ecart_Y_new

*** Data errors:
* Gap between sibling and index child date of birth is less than 9 months
drop if ecart_Y<8
drop if ecart_O<8

 
//identifies if the kid is resident or not- and then takes birth interval
gen byte gp_ecart_Yres = cond(MigDeadY==2,gp_ecart_Y,0)
gen byte gp_ecart_Ores = cond(MigDeadO==2,gp_ecart_O,0)
gen byte gp_ecart_Ores_new = cond(MigDeadO==2,gp_ecart_O_new,0)
label val gp_ecart_Yres gp_age_sy
label val gp_ecart_Ores gp_age_so
label val gp_ecart_Ores_new lgp_ecart_O_new

//creating dummy variables of each category of birth intervals-when resident
sort concat_IndividualId EventDate
gen byte birth_int_Yres_12m = cond(gp_ecart_Y_new==1&MigDeadY==2,birth_int_YS ,0)
replace birth_int_Yres_12m=1 if birth_int_YS==1 & gp_ecart_Y_new[_n+1]==1
label val birth_int_Yres_12m lbirth_int_YS

gen byte birth_int_Yres_12_17m = cond(gp_ecart_Y_new==2&MigDeadY==2,birth_int_YS ,0)
replace birth_int_Yres_12_17m=1 if birth_int_YS==1 & gp_ecart_Y_new[_n+1]==2
label val birth_int_Yres_12_17m lbirth_int_YS

gen byte birth_int_Yres_18_23m = cond(gp_ecart_Y_new==3&MigDeadY==2,birth_int_YS ,0)
replace birth_int_Yres_18_23m=1 if birth_int_YS==1 & gp_ecart_Y_new[_n+1]==3
label val birth_int_Yres_18_23m lbirth_int_YS

gen byte birth_int_Yres_24_29m = cond(gp_ecart_Y_new==4&MigDeadY==2,birth_int_YS ,0)
replace birth_int_Yres_24_29m=1 if birth_int_YS==1 & gp_ecart_Y_new[_n+1]==4
label val birth_int_Yres_24_29m lbirth_int_YS

gen byte birth_int_Yres_30_35m = cond(gp_ecart_Y_new==5&MigDeadY==2,birth_int_YS ,0)
replace birth_int_Yres_30_35m=1 if birth_int_YS==1 & gp_ecart_Y_new[_n+1]==5
label val birth_int_Yres_30_35m lbirth_int_YS

gen byte birth_int_Yres_36_41m  = cond(gp_ecart_Y_new==6&MigDeadY==2,birth_int_YS ,0)
replace birth_int_Yres_36_41m=1 if birth_int_YS==1 & gp_ecart_Y_new[_n+1]==6
label val birth_int_Yres_36_41m lbirth_int_YS

gen byte birth_int_Yres_42_47m  = cond(gp_ecart_Y_new==7&MigDeadY==2,birth_int_YS ,0)
replace birth_int_Yres_42_47m=1 if birth_int_YS==1 & gp_ecart_Y_new[_n+1]==7
label val birth_int_Yres_42_47m lbirth_int_YS

gen byte birth_int_Yres_48_more  = cond(gp_ecart_Y_new==8&MigDeadY==2,birth_int_YS ,0)
replace birth_int_Yres_48_more=1 if birth_int_YS==1 & gp_ecart_Y_new[_n+1]==8
label val birth_int_Yres_48_more lbirth_int_YS

//combination of birth interval and period after birth (including pregnancy)
capture drop gp_birth_int_YS
gen int gp_birth_int_YS= MigDeadY*1000 + birth_int_Yres_12m + ///
	cond(birth_int_Yres_12_17m==0,0,10+ birth_int_Yres_12_17m) + ///
	cond(birth_int_Yres_18_23m==0,0,20+ birth_int_Yres_18_23m) + ///
	cond(birth_int_Yres_24_29m==0,0,30+ birth_int_Yres_24_29m) + ///
	cond(birth_int_Yres_30_35m==0,0,40+ birth_int_Yres_30_35m) + ///
	cond(birth_int_Yres_36_41m==0,0,50+ birth_int_Yres_36_41m) + ///
	cond(birth_int_Yres_42_47m==0,0,60+ birth_int_Yres_42_47m) + ///
	cond(birth_int_Yres_48_more==0,0,70+ birth_int_Yres_48_more)

label define lgp_birth_int_YS ///
0 "NoYS"	///
1 "Int <12m - pregnant" ///	
11 "Int 12-17m - pregnant" ///	
21 "Int 18-23m - pregnant" ///	
31 "Int 24-29m - pregnant" ///	
41 "Int 30-35m - pregnant" ///	
51 "Int 36-41m - pregnant" ///	
61 "Int 42-47m - pregnant" ///
71 "Int >=48m + - pregnant" ///	
1000 "y sibling non-res" ///
2002 "Int <12m - 0-6m" ///	
2003 "Int <12m - 6-12m" ///	
2004 "Int <12m - 12m +" ///	
2012 "Int 12-17m - 0-6m" ///	
2013 "Int 12-17m - 6-12m" ///	
2014 "Int 12-17m - 12m +" ///	
2022 "Int 18-23m - 0-6m" ///	
2023 "Int 18-23m - 6-12m" ///	
2024 "Int 18-23m - 12m +" ///	
2032 "Int 24-29m - 0-6m" ///	
2033 "Int 24-29m - 6-12m" ///	
2034 "Int 24-29m - 12m +" ///	
2042 "Int 30-35m - 0-6m" ///	
2043 "Int 30-35m - 6-12m" ///	
2044 "Int 30-35m - 12m +" ///	
2052 "Int 36-41m - 0-6m" ///	
2053 "Int 36-41m - 6-12m" ///	
2054 "Int 36-41m - 12m +" ///	
2062 "Int 42-47m - 0-6m" ///	
2063 "Int 42-47m - 6-12m" ///	
2064 "Int 42-47m - 12m +" ///	
2072 "Int >=48m + - 0-6m" ///	
2073 "Int >=48m + - 6m +" ///	
2074 "Int >=48m + - 12m +" ///	
3000 "y sibling dead", modify	

label val gp_birth_int_YS lgp_birth_int_YS

recode gp_birth_int_YS (2074=2073)
* Same variable but with different coding order
recode gp_birth_int_YS ///
(0 =0 "NoYS"					) ///
(1 =1 "Int <12m - pregnant" 	) ///	
(11=11 "Int 12-17m - pregnant" 	) ///	
(21=21 "Int 18-23m - pregnant" 	) ///	
(31=31 "Int 24-29m - pregnant" 	) ///	
(41=41 "Int 30-35m - pregnant" 	) ///	
(51=51 "Int 36-41m - pregnant" 	) ///	
(61=61 "Int 42-47m - pregnant" 	) ///
(71=71 "Int >=48m+ - pregnant" ) ///	
(1000=100 "y sibling non-res" 	) ///
(2002=200 "Int <12m - 0-6m" 	) ///	
(2003=300 "Int <12m - 6-12m" 	) ///	
(2004=400 "Int <12m - 12m+" 	) ///	
(2012=210 "Int 12-17m - 0-6m" 	) ///	
(2013=310 "Int 12-17m - 6-12m" 	) ///	
(2014=410 "Int 12-17m - 12m+" 	) ///	
(2022=220 "Int 18-23m - 0-6m" 	) ///	
(2023=320 "Int 18-23m - 6-12m" 	) ///	
(2024=420 "Int 18-23m - 12m+" 	) ///	
(2032=230 "Int 24-29m - 0-6m" 	) ///	
(2033=330 "Int 24-29m - 6-12m" 	) ///	
(2034=430 "Int 24-29m - 12m+" 	) ///	
(2042=240 "Int 30-35m - 0-6m" 	) ///	
(2043=340 "Int 30-35m - 6-12m" 	) ///	
(2044=440 "Int 30-35m - 12m+" 	) ///	
(2052=250 "Int 36-41m - 0-6m" 	) ///	
(2053=350 "Int 36-41m - 6-12m" 	) ///	
(2054=450 "Int 36-41m - 12m+"	) ///	
(2062=260 "Int 42-47m - 0-6m" 	) ///	
(2063=360 "Int 42-47m - 6-12m" 	) ///	
(2064=460 "Int 42-47m - 12m+" 	) ///	
(2072=270 "Int >=48m+ - 0-6m" 	) ///	
(2073=270 "Int >=48m+ - 6m+" 	) ///	
(3000=500 "y sibling dead"		), gen(birth_int_gp_YS)	
 
capture drop pregnant_YS
gen byte pregnant_YS = (birth_int_YS==1)
lab define pregnant 1 "3-9m pregnant" 0 "No this period"
label val pregnant_YS pregnant

capture drop twin
gen byte twin = (TwinId!="")
label define twin 1 "Yes" 0 "No"
label val twin twin


foreach var of varlist birth_int_Yres_12m birth_int_Yres_12_17m  ///
                       birth_int_Yres_18_23m birth_int_Yres_24_29m birth_int_Yres_30_35m birth_int_Yres_36_41m ///
                       birth_int_Yres_42_47m birth_int_Yres_48_more migrant_statusMO {
					   
					   replace `var' = 0 if `var'==.
					   }

*adding the period around the death of mother (& sibling) to migration-death variable of mother	(& sibling)				   
capture drop MigDeadMO_MO_DTH_TVC
gen MigDeadMO_MO_DTH_TVC=	cond(MigDeadMO==2 & MO_DTH_TVC==0,0, cond(MigDeadMO==1 & MO_DTH_TVC==0,1, ///
							cond(MO_DTH_TVC==1,2, cond(MO_DTH_TVC==2,3, cond(MO_DTH_TVC==3,4, ///
							cond(MO_DTH_TVC==4,5, cond(MO_DTH_TVC==5,6, 7)))))))
label define lMigDeadMO_MO_DTH_TVC 0 "mother resident" 	1 "mother non resident" ///
						2 "-6m to -3m mother's death" 	3 "-3m to -15d mother's death" ///
						4 "+/- 15d mother's death" 		5 "15d to 3m mother's death" ///
						6 "+3m to +6m mother's death" 	7 "6m+ mother's death", modify
label val MigDeadMO_MO_DTH_TVC lMigDeadMO_MO_DTH_TVC

capture drop MigDeadO_O_DTH_TVC
gen MigDeadO_O_DTH_TVC=	cond(MigDeadO==2 & O_DTH_TVC==0,0, cond(MigDeadO==1 & O_DTH_TVC==0,1, ///
							cond(O_DTH_TVC==1,2, cond(O_DTH_TVC==2,3, cond(O_DTH_TVC==3,4, ///
							cond(O_DTH_TVC==4,5, cond(O_DTH_TVC==5,6, 7)))))))
replace MigDeadO_O_DTH_TVC=9 if MigDeadO==0
label define lMigDeadO_O_DTH_TVC 0 "O sib resident" 	1 "O sib non resident" ///
						2 "-6m to -3m O sib's death" 	3 "-3m to -15d O sib's death" ///
						4 "+/- 15d O sib's death" 		5 "15d to 3m O sib's death" ///
						6 "+3m to +6m O sib's death" 	7 "6m+ O sib's death" ///
						9 "no O sib", modify
label val MigDeadO_O_DTH_TVC lMigDeadO_O_DTH_TVC

capture drop MigDeadY_Y_DTH_TVC
gen MigDeadY_Y_DTH_TVC=	cond(MigDeadY==2 & Y_DTH_TVC==0,0, cond(MigDeadY==1 & Y_DTH_TVC==0,1, ///
							cond(Y_DTH_TVC==1,2, cond(Y_DTH_TVC==2,3, cond(Y_DTH_TVC==3,4, ///
							cond(Y_DTH_TVC==4,5, cond(Y_DTH_TVC==5,6, 7)))))))
replace MigDeadY_Y_DTH_TVC=9 if MigDeadY==0
label define lMigDeadY_Y_DTH_TVC 0 "Y sib resident" 	1 "Y sib non resident" ///
						2 "-6m to -3m Y sib's death" 	3 "-3m to -15d Y sib's death" ///
						4 "+/- 15d Y sib's death" 		5 "15d to 3m Y sib's death" ///
						6 "+3m to +6m Y sib's death" 	7 "6m+ Y sib's death" ///
						9 "no Y sib", modify
label val MigDeadY_Y_DTH_TVC lMigDeadY_Y_DTH_TVC

capture drop MigDeadTwin_Twin_DTH_TVC
gen MigDeadTwin_Twin_DTH_TVC=	cond(MigDeadTwin==2 & Twin_DTH_TVC==0,0, cond(MigDeadTwin==1 & Twin_DTH_TVC==0,1, ///
							cond(Twin_DTH_TVC==1,2, cond(Twin_DTH_TVC==2,3, cond(Twin_DTH_TVC==3,4, ///
							cond(Twin_DTH_TVC==4,5, cond(Twin_DTH_TVC==5,6, 7)))))))
replace MigDeadTwin_Twin_DTH_TVC=9 if MigDeadTwin==0
label define lMigDeadTwin_Twin_DTH_TVC 0 "Twin resident" 	1 "Twin non resident" ///
						2 "-6m to -3m Twin's death" 	3 "-3m to -15d Twin's death" ///
						4 "+/- 15d Twin's death" 		5 "15d to 3m Twin's death" ///
						6 "+3m to +6m Twin's death" 	7 "6m+ Twin's death" ///
						9 "no Twin", modify
label val MigDeadTwin_Twin_DTH_TVC lMigDeadTwin_Twin_DTH_TVC

recode birth_int_Yres_48_more (4=3) //combined because there are not a lot of cases in this category 
label define lbirth_int_Yres_48_more 1 "pregnant_YS" 2 "0-6m" 3 "6m +", modify
label val birth_int_Yres_48_more lbirth_int_Yres_48_more

gen byte res_O_DTH_TVC= cond(MigDeadO<2,0, O_DTH_TVC) //adds whether resident or not to death categories
lab val res_O_DTH_TVC DTH_TVC 

gen byte res_Y_DTH_TVC= cond(MigDeadY<2,0, Y_DTH_TVC)
lab val res_Y_DTH_TVC DTH_TVC 

gen byte res_Twin_DTH_TVC= cond(MigDeadTwin<2,0, Twin_DTH_TVC)
lab val res_Twin_DTH_TVC DTH_TVC 


gen byte MigDeadO_interv= MigDeadO*10 + gp_ecart_O_new*(MigDeadO==2) 
label def lMigDeadO_interv 0 "No Old sib" 10 "O sib non resident" 21 "O int <12m" ///
		22 "O int 12-17m" 23 "O int 18-23m" 24 "O int 24-29m" 25 "O int 30-35m" ///
		26 "O int 36-41m" 27 "O int 42-47m" 28 "O int 48m +" 30 "O sib dead", modify
lab val MigDeadO_interv lMigDeadO_interv

recode MigDeadO_interv 30=24 // recode dead in the Ref category "O int 24-29m"

* Same with younger sibling:
recode birth_int_gp_YS 500=230 // recode dead in the Ref category "Int 24-29m - 0-6m"

* covariate combining HDSS and time period
egen Centre_period=group(CentreLab period), label
tab Centre_period [iw=_t-_t0]
recode Centre_period (35 36 37=38)

save child_mother_sibling, replace


* Extract indicator of Older sibling death (including before index child birth)
use osibling.dta, clear
keep if OsiblingId!=""
bysort concat_IndividualId (EventDate): egen byte everDeadO =max(EventCodeO==7) 
keep concat_IndividualId everDeadO
duplicates drop
save everDeadO, replace

use child_mother_sibling,clear
merge m:1 concat_IndividualId using everDeadO.dta
drop if _merge==2
drop _merge
recode everDeadO (.=0)
capture drop DeadOafterDoB
bysort concat_IndividualId (EventDate): egen byte DeadOafterDoB =max(res_O_DTH_TVC!=0) 
capture drop DeadObeforeDoB
gen byte DeadObeforeDoB=everDeadO==1 & DeadOafterDoB==0 & MigDeadO!=1

save child_mother_sibling, replace

************************************************************************************

*** Setting mortality analysis <5-year-old 
stset EventDate if residence==1, id(concat_IndividualId) failure(censor_death==1) ///
		time0(datebeg) origin(time DoB) exit(time DoB+(31557600000*5)+212000000) scale(31557600000)

compress
keep if _st==1 //ie keeping cases that follow conditions in stset

drop if Sex==9 //remove kids whose sex is not identified

// Main model - under five year olds
stcox 	i.Sex ib75.Centre_period ///
		ib21.y3_mother_age_birth ib0.MigDeadMO_MO_DTH_TVC ib0.migrant_statusMO ///
		ib0.MigDeadTwin_Twin_DTH_TVC ///
		DeadObeforeDoB ib24.MigDeadO_int ib0.res_O_DTH_TVC ///
        ib230.birth_int_gp_YS ib0.res_Y_DTH_TVC ///
		, vce(cluster MotherId) iter(10) 
est store u5

// Infant mortality only (under 12 months) - without twin or younger sibling (as in Molitoris et al (2019))
stset EventDate if residence==1, id(concat_IndividualId) failure(censor_death==1) ///
		time0(datebeg) origin(time DoB) exit(time DoB+31557600000+106000000) scale(31557600000)
stcox 	i.Sex ib75.Centre_period ///
		ib21.y3_mother_age_birth ib0.MigDeadMO_MO_DTH_TVC ib0.migrant_statusMO ///
		DeadObeforeDoB ib24.MigDeadO_int ib0.res_O_DTH_TVC ///
        if MigDeadTwin_Twin_DTH_TVC==9  ///
		, vce(cluster MotherId) iter(10) 

// 1-4 year old mortality only 
stset EventDate if residence==1, id(concat_IndividualId) failure(censor_death==1) ///
		time0(datebeg) origin(time DoB+31557600000+106000000) ///
		exit(time DoB+(5*31557600000)+212000000) scale(31557600000)

stcox 	i.Sex ib75.Centre_period ///
		ib21.y3_mother_age_birth ib0.MigDeadMO_MO_DTH_TVC ib0.migrant_statusMO ///
		ib0.MigDeadTwin_Twin_DTH_TVC  ///
		DeadObeforeDoB ib24.MigDeadO_int ib0.res_O_DTH_TVC ///
        ib230.birth_int_gp_YS ib0.res_Y_DTH_TVC  ///
		, vce(cluster MotherId) iter(10)
		

