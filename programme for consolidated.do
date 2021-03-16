// PROGRAM TO SHAPE THE HDSS DATA AVAILABLE ON INDEPTH ISHARE FOR EVENT HISTORY ANALYSIS
* 2018 release  
* only sub-Saharan African HDSS 
* https://www.indepth-ishare.org/index.php/catalog/central


//////////////////////////////////////////////////////////////////////////////////////

* Change to your own suitable directory
cd "HDSS\2018 release\"

* Consolidate all datasets
clear
foreach file in BF021.CMD2014.v1.csv BF031.CMD2015.v1.csv BF041.CMD2015.v2.csv CI011.CMD2016.v1.csv ET021.CMD2015.v2.csv ///
				ET031.CMD2014.v1.csv ET041.CMD2016.v1.csv ET042.CMD2016.v1.csv ET051.CMD2015.v2.csv ET061.CMD2015.v2.csv ///
				GH011.CMD2014.v1.csv GH021.CMD2014.v1.csv GH031.CMD2011.v1.csv GM011.CMD2015.v2.csv KE031.CMD2015.v2.csv ///
				KE051.CMD2015.v2.csv MW011.CMD2016.v1.csv MZ021.CMD2015.v2.csv NG011.CMD2014.v1.csv ///
				SN011.CMD2016.v1.csv SN012.CMD2016.v1.csv SN013.CMD2016.v1.csv TZ011.CMD2014.v1.csv TZ012.CMD2014.v1.csv ///
				TZ021.CMD2012.v1.csv UG011.CMD2015.v1.csv ZA011.CMD2016.v1.csv ZA021.CMD2016.v2.csv ZA031.CMD2016.v1.csv {
	import delimited `file'
	if "`file'"=="MW011.CMD2016.v1.csv" | "`file'"=="SN011.CMD2016.v1.csv" | "`file'"=="SN012.CMD2016.v1.csv" {
	* In these HDSS observationdate is always missing and stored as byte 
	* (and not string as in other HDSS) so append didn't work - 12/02/2019
		tostring observationdate, replace 
		replace observationdate=""
	}
	capture	append using ConsolidatedData
	save ConsolidatedData, replace 
	clear
}

/* 
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
ZA021	Dikgale
ZA031	Africa Centre
*/

********************************************************************************

use "ConsolidatedData.dta", clear

duplicates drop
tab centreid, miss
drop recnr
rename countryid       CountryId
rename centreid        CentreId
rename individualid    IndividualId
rename sex             Sex
rename dob             DoB
rename eventcount      EventCount
rename eventnr         EventNr
rename eventcode       EventCode
rename eventdate       EventDate
rename observationdate ObservationDate
rename locationid      LocationId
rename motherid        MotherId
rename deliveryid      DeliveryId

drop EventNr EventCount
 
* Change format of EventCode to numeric
label define eventlab 	1 "ENU" 2 "BTH" 3 "IMG" 4 "OMG" 5 "EXT" 6 "ENT" 7 "DTH" ///
			9 "OBE" 10 "DLV" 18 "OBS" 19 "OBL" 20 "IPT" 30 "PER" 40 "AGE", modify
encode EventCode, gen(eventlab)
drop EventCode
rename eventlab EventCode
compress
numlabel, add
tab EventCode, miss

* Change format of EventDate to numeric
* NB: note the use of "double" format
capt drop newEventDate
gen double newEventDate=Cmdyhms(real(substr(EventDate,6,2)),real(substr(EventDate,9,2)),real(substr(EventDate,1,4)), ///
						real(substr(EventDate,12,2)),real(substr(EventDate,15,2)),real(substr(EventDate,18,2)))
format newEventDate %tC
drop EventDate
rename newEventDate EventDate
lab var EventDate "EventDate"

capt drop newDoB
gen double newDoB=Cmdyhms(real(substr(DoB,6,2)),real(substr(DoB,9,2)),real(substr(DoB,1,4)), ///
						real(substr(DoB,12,2)),real(substr(DoB,15,2)),real(substr(DoB,18,2)))
format newDoB %tC
drop DoB 
rename newDoB DoB
lab var DoB "DoB"

capt drop newObservationDate
gen double newObservationDate=Cmdyhms(real(substr(ObservationDate,6,2)),real(substr(ObservationDate,9,2)),real(substr(ObservationDate,1,4)), ///
						real(substr(ObservationDate,12,2)),real(substr(ObservationDate,15,2)),real(substr(ObservationDate,18,2)))
format newObservationDate %tC
drop ObservationDate
rename newObservationDate ObservationDate
lab var ObservationDate "ObservationDate"

* Recode all OBL into OBE: 
* only the first OBE will be taken into account (see consistency matrix below)
gen codeOBL=(EventCode==19)
table CentreId, cont(sum codeOBL freq) format(%10.0f) cellwidth(20)
drop codeOBL
sort CountryId CentreId IndividualId EventDate EventCode
drop if EventCode==19 & IndividualId==IndividualId[_n+1]
recode EventCode 19=9 if IndividualId!=IndividualId[_n+1]
drop if EventCode==9 & EventCode[_n+1]==9 & IndividualId==IndividualId[_n+1]

* drop internal moves (EXT->ENT) same day
capture drop simult*
bysort CountryId CentreId IndividualId (EventDate EventCode): ///
	gen simultEXT_ENT=(EventDate==EventDate[_n+1] & EventCode==5 & EventCode[_n+1]==6)
bysort CountryId CentreId IndividualId (EventDate EventCode): ///
	replace simultEXT_ENT=(EventDate==EventDate[_n-1] & EventCode[_n-1]==5 & EventCode==6)
table CentreId, cont(sum simultEXT_ENT freq) format(%10.0f) cellwidth(20)

**Cases with ENTRY preceded by EXIT and duration of more than 180 days:
** => replace ENTRY by IMG:
bysort CountryId CentreId IndividualId: replace EventCode=3 if ///
		(EventCode==6 & EventCode[_n-1]==5 & EventDate-EventDate[_n-1]>15778800000)

** => replace EXIT by OMG:
bysort CountryId CentreId IndividualId: replace EventCode=4 if ///
		(EventCode==5 & EventCode[_n+1]==6 & EventDate[_n+1]-EventDate>15778800000)

* drop external moves (IMG->OMG) same day
bysort CountryId CentreId IndividualId (EventDate EventCode): ///
	gen simultIMG_OMG=(EventDate==EventDate[_n+1] & EventCode==3 & EventCode[_n+1]==4)
bysort CountryId CentreId IndividualId (EventDate EventCode): ///
	replace simultIMG_OMG=1 if EventDate==EventDate[_n-1] & EventCode[_n-1]==3 & EventCode==4
table CentreId, cont(sum simultIMG_OMG freq) format(%10.0f) cellwidth(20)
drop simult*

* TO AVOID SIMULTANEITY OF SOME EVENTS IN A DAY
* Add 6 hours for BTH, DLV and change of AGE group events
replace EventDate=DoB if EventCode==2
replace EventDate=EventDate+ (6*60*60*1000) if EventCode==2 | EventCode==10 | EventCode==40
replace DoB=DoB + (6*60*60*1000) /* to match correction for BTH */

* Add 6 hours for ENT after EXT the same day
replace EventDate=EventDate+ (6*60*60*1000) if EventCode==6 & EventCode[_n-1]==5 ///
		& IndividualId==IndividualId[_n-1] & EventDate==EventDate[_n-1] 

* Add 12 hours for IMG, OMG, ENT, EXT (if not the same day)
replace EventDate=EventDate+ (12*60*60*1000) if EventCode>=3 & EventCode<=6

* Add 12 hours for ENU, OBS, and IPT (imputed) events
replace EventDate=EventDate+ (12*60*60*1000) if EventCode==1 | EventCode==18 | EventCode==19 | EventCode==20

* Add 18 hours for DTH event
replace EventDate=EventDate+ (18*60*60*1000) if EventCode==7

* Note: only calendar events OBE and PER are set to 00:00:00 hour

* Case of DLV before 10-year old
capt drop dateDLV
bysort CountryId CentreId IndividualId (EventDate EventCode): ///
	egen dateDLV=max(EventCode==10 & EventDate<DoB+10*365.25*24*60*60*1000)
table CentreId if EventCode==10, cont(sum dateDLV freq) format(%10.0f) cellwidth(20)
drop dateDLV

* Delete records for individual with missing date of birth
drop if DoB==.

* Errors in date of birth > date of event
bysort CountryId CentreId IndividualId (EventDate EventCode): ///
		egen double earliestEventDate=min(EventDate)
format earliestEventDate %tC
capture drop errorDoB
gen errorDoB=(DoB>earliestEventDate)
table CentreId, cont(sum errorDoB freq) format(%10.0f) cellwidth(20)

capture drop EventSucc
bysort CountryId CentreId IndividualId (EventDate EventCode): gen EventSucc=EventCode[_n+1] 
lab val EventSucc eventlab

sort CountryId CentreId IndividualId
tab EventCode EventSucc if errorDoB==1 & IndividualId==IndividualId[_n+1], missing

br IndividualId EventCode EventDate DoB ObservationDate if errorDoB==1

gen dummy=1 if errorDoB==1 & EventCode==1 ///
		& DoB>=EventDate & EventDate[_n+1]>DoB & IndividualId==IndividualId[_n+1]
replace EventCode=2 if dummy==1
replace EventDate=DoB if dummy==1
drop dummy

capture drop earliestEventDate
bysort CountryId CentreId IndividualId (EventDate EventCode): ///
		egen double earliestEventDate=min(EventDate)
format earliestEventDate %tC
capture drop errorDoB
gen errorDoB=(DoB>earliestEventDate)
tab EventCode EventSucc if errorDoB==1 & IndividualId==IndividualId[_n+1], missing

br IndividualId EventCode EventDate DoB ObservationDate if errorDoB==1
table CentreId if EventCode==9 & EventSucc==2, cont(sum errorDoB freq) format(%10.0f) cellwidth(20)
* Individuals recorded after the OBE in ET051 (Dabat)
save ConsolidatedData2018_clean, replace

* delete individuals with date of birth (DoB) inconsistent with other events
drop if errorDoB==1
drop errorDoB earliestEventDate

* delete individuals with out of range date of birth >115-year old 
bysort CountryId CentreId IndividualId (EventDate EventCode): ///
		egen age115=max(EventDate>DoB+115*365.25*24*60*60*1000)
table CentreId, cont(sum age115 freq) format(%10.0f) cellwidth(20)
drop if age115==1
drop age115

order CountryId CentreId LocationId IndividualId Sex DoB ///
		ObservationDate EventCode EventDate MotherId DeliveryId

capture drop EventSucc
duplicates drop
compress
save ConsolidatedData2018_clean.dta, replace

* EVENT CONSISTENCY MATRIX CHECKS
use ConsolidatedData2018_clean.dta, clear
set more off
sort CountryId CentreId IndividualId
capture drop EventSucc
bysort CountryId CentreId IndividualId (EventDate EventCode): gen EventSucc=EventCode[_n+1] 
lab val EventSucc eventlab

tab EventCode EventSucc if EventDate==EventDate[_n+1] & IndividualId==IndividualId[_n+1], missing

* Drop simultaneous records that are not consistent:
capture drop simult*
* Identify records with ENU succeeded by IMG / OMG / OBE / OBL at the same date
bysort CountryId CentreId IndividualId (EventDate EventCode): ///
	gen simultENU_ANY=(EventDate==EventDate[_n+1] & EventCode==1 & ///
							(EventCode[_n+1]==3 | EventCode[_n+1]==4 | EventCode[_n+1]==9 | EventCode[_n+1]==19))
* Identify records with OMG / OBS / OBE / OBL preceeded by ENU at the same date
bysort CountryId CentreId IndividualId (EventDate EventCode): ///
	replace simultENU_ANY=1 if EventDate==EventDate[_n-1] & EventCode[_n-1]==1 & ///
							(EventCode==4 | EventCode==18 | EventCode==9 | EventCode==19)
table CentreId, cont(sum simultENU_ANY freq) format(%10.0f) cellwidth(20)

* Identify records with IMG succeeded by OMG / OBE / OBL at the same date
bysort CountryId CentreId IndividualId (EventDate EventCode): ///
	gen simultIMG_ANY=(	EventDate==EventDate[_n+1] & EventCode==3 & ///
							(EventCode[_n+1]==4 | EventCode[_n+1]==9 | EventCode[_n+1]==19))
* Identify records with OBS / OBE / OBL preceeded by IMG at the same date
bysort CountryId CentreId IndividualId (EventDate EventCode): ///
	replace simultIMG_ANY=1 if EventDate==EventDate[_n-1] & EventCode[_n-1]==3 & ///
							(EventCode==4 | EventCode==18 | EventCode==9 | EventCode==19)
table CentreId, cont(sum simultIMG_ANY freq) format(%10.0f) cellwidth(20)

* Delete DLV same day as BTH
capture drop simultBTH_DLV
bysort CountryId CentreId IndividualId (EventDate EventCode): ///
	gen simultBTH_DLV=(	EventDate==EventDate[_n-1] & EventCode==10 & ///
							(EventCode[_n-1]==2 | EventCode[_n-1]==10)) 
table CentreId, cont(sum simultBTH_DLV freq) format(%10.0f) cellwidth(20)

* Delete false twins (same DeliveryId)
capture drop falsetwin
bysort CountryId CentreId IndividualId (EventDate EventCode): ///
	gen falsetwin=( EventDate==EventDate[_n-1] & EventCode==10 & ///
							(EventCode[_n-1]==10 & DeliveryId==DeliveryId[_n-1]))
table CentreId, cont(sum falsetwin freq) format(%10.0f) cellwidth(20)

drop if simultENU_ANY==1
drop if simultIMG_ANY==1
drop if simultBTH_DLV==1
drop if falsetwin==1

capture drop simult*
capture drop falsetwin

* Assume that simultaneous DLV are multiple births only if DeliveryId different
* Twins: substract 1 hour to one of the deliveries
bysort CountryId CentreId IndividualId (EventDate EventCode): ///
	replace EventDate=EventDate-(1*60*60*1000) ///
						if EventDate==EventDate[_n+1] & EventCode==10 & ///
							(EventCode[_n+1]==10 & DeliveryId!=DeliveryId[_n+1])
* Triplets: add 1 hour to one of the deliveries
bysort CountryId CentreId IndividualId (EventDate EventCode): ///
	replace EventDate=EventDate+(1*60*60*1000) ///
						if EventDate==EventDate[_n-1] & EventCode==10 & ///
							(EventCode[_n-1]==10 & DeliveryId!=DeliveryId[_n-1])
* NB: MULTIPLE BIRTHS ARE RECORDED UNDER SAME DeliveryId

capture drop EventSucc
bysort CountryId CentreId IndividualId (EventDate EventCode): gen EventSucc=EventCode[_n+1] 
lab val EventSucc eventlab
sort CountryId CentreId IndividualId EventDate EventCode
tab EventCode EventSucc if EventDate==EventDate[_n+1] & IndividualId==IndividualId[_n+1], missing

*****************************************************************************************************************
* FINAL EVENT CONSISTENCY MATRIX
tab EventCode EventSucc , missing
compress
save ConsolidatedData2018_basic.dta, replace
*********************************************************************************************************************


* CREATING RESIDENCE VARIABLE (with a 6-month threshold)

* First extract the DLV episodes (to be reinserted later with tmerge)
use ConsolidatedData2018_basic.dta, clear
capture drop lastrecord
bysort CountryId CentreId IndividualId (EventDate EventCode): gen lastrecord=_n==_N
keep if EventCode==10 | lastrecord==1 
rename EventDate EventDateDLV
rename EventCode EventCodeDLV
gen tempId=string(CountryId)+CentreId+string(IndividualId)
* to avoid issue of different OBE with ConsolidatedData2018_basic.dta
expand =2 if lastrecord==1, gen(matchOBE)
di %20.0g tC(01Jan2018 00:00:00)
replace EventDateDLV=1830384027000 if matchOBE==1
replace EventCodeDLV=100 if matchOBE==1
save ConsolidatedData2018_DLV.dta, replace

use ConsolidatedData2018_basic.dta, clear
capture drop lastrecord
bysort CountryId CentreId IndividualId (EventDate EventCode): gen lastrecord=_n==_N
drop if EventCode==10 & lastrecord!=1

capture drop EventSucc
bysort CountryId CentreId IndividualId (EventDate EventCode): gen EventSucc=EventCode[_n+1] 
bysort CountryId CentreId IndividualId (EventDate EventCode): gen EventPrec=EventCode[_n-1] 
lab val EventSucc eventlab
* Matrix without DLV
tab EventCode EventSucc, missing
capture drop error_matrix
gen error_matrix= ( EventCode!=. & (EventSucc==1 | EventSucc==2) ) ///
				| ( EventCode!=. & EventPrec==9 ) ///
				| ( (EventCode==10 | EventCode==7) & (EventPrec==. | EventPrec==7 | EventSucc==.) ) ///
				| ( (EventCode==4 | EventCode==5 | EventCode==6) & (EventPrec==. | EventPrec==7 | EventPrec==4) ) ///
				| ( (EventCode==9 | EventCode==7) & EventPrec==. ) ///
				| ( EventCode==9 & EventSucc!=. ) ///
				| ( EventCode==1 & EventSucc==3 ) ///
				| ( EventCode==2 & (EventSucc==. | EventSucc==3) ) ///
				| ( EventCode==3 & (EventSucc==3 | EventSucc==6 | EventSucc==.) ) ///
				| ( EventCode==4 & (EventSucc==4 | EventSucc==6 | EventSucc==.))
replace error_matrix=100*error_matrix
table CentreId, cont(mean error_matrix freq) format(%10.2f) cellwidth(20)
* Percentage errors in consistency matrix before corrections out of total number of records:
* !!! HDSS WITH MORE THAN *1% ERRORS SHOULD BE ANALYSED WITH CAUTION !!!
		

set linesize 200
* Check again consistency matrix and clean data inconsistencies (without DLV)
* Delete any event before ENU or BTH
forval n = 1/12 {
	capture drop lastrecord
	bysort CountryId CentreId IndividualId (EventDate EventCode): gen lastrecord=_n==_N
	capture drop EventSucc
	bysort CountryId CentreId IndividualId (EventDate EventCode): gen EventSucc=EventCode[_n+1] 
	lab val EventSucc eventlab
* To produce the Event Consistency Matrix
	tab EventCode EventSucc, missing
	drop if EventCode!=. & (EventSucc==1 | EventSucc==2) & lastrecord!=1
}
* Delete any event after OBE 
forval n = 1/12 {
	capture drop lastrecord
	bysort CountryId CentreId IndividualId (EventDate EventCode): gen lastrecord=_n==_N
	capture drop EventPrec
	bysort CountryId CentreId IndividualId (EventDate EventCode): gen EventPrec=EventCode[_n-1] 
	lab val EventPrec eventlab
	tab EventPrec EventCode , missing
	drop if EventCode!=. & EventPrec==9 & lastrecord!=1
	drop if (EventCode==10 | EventCode==7) 				& (EventPrec==. | EventPrec==7) & lastrecord!=1
	drop if (EventCode==4 | EventCode==5 | EventCode==6) & (EventPrec==. | EventPrec==7) & lastrecord!=1
	drop if EventCode==9 & EventPrec==. & lastrecord!=1
	drop if EventCode==7 & EventPrec==. & lastrecord!=1
}
capture drop EventSucc
bysort CountryId CentreId IndividualId (EventDate EventCode): gen EventSucc=EventCode[_n+1] 
lab val EventSucc eventlab
tab EventCode EventSucc, missing
* Delete remaining inconsistencies:
* ENU with IMG as succeeding event
drop if EventCode==1 & EventSucc==3 & lastrecord!=1
* BTH with IMG as succeeding event or missing succedinc event
drop if EventCode==2 & (EventSucc==. | EventSucc==3) & lastrecord!=1
* IMG with IMG as succeeding event
drop if EventCode==3 & EventSucc==3 & lastrecord!=1
* drop if no code for event
drop if EventCode==. & lastrecord!=1

tab EventCode EventSucc, missing

capture drop error_matrix
gen error_matrix= ( EventCode!=. & (EventSucc==1 | EventSucc==2) ) ///
				| ( EventCode!=. & EventPrec==9 ) ///
				| ( (EventCode==10 | EventCode==7) & (EventPrec==. | EventPrec==7 | EventSucc==.) ) ///
				| ( (EventCode==4 | EventCode==5 | EventCode==6) & (EventPrec==. | EventPrec==7 | EventPrec==4) ) ///
				| ( (EventCode==9 | EventCode==7) & EventPrec==. ) ///
				| ( EventCode==9 & EventSucc!=. ) ///
				| ( EventCode==1 & EventSucc==3 ) ///
				| ( EventCode==2 & (EventSucc==. | EventSucc==3) ) ///
				| ( EventCode==3 & (EventSucc==3 | EventSucc==6 | EventSucc==.) ) ///
				| ( EventCode==4 & (EventSucc==4 | EventSucc==6 | EventSucc==.))
replace error_matrix=100*error_matrix
table CentreId, cont(mean error_matrix freq) format(%10.2f) cellwidth(20)
replace error_matrix=error_matrix/100
table CentreId, cont(sum error_matrix freq) format(%10.0f) cellwidth(20) row

recode EventCode (2=0 "BTH") (7=1 "DTH") (3 4 5=2 "MIG") (*=.), gen(simpleCode)
tab CentreId simpleCode, row nofreq
                                                     
drop simpleCode                                                         
* COMPUTE RESIDENCE VARIABLE 
capture drop residence
gen byte residence=.

***ENUMERATED
sort CountryId CentreId IndividualId EventDate EventCode
bysort CountryId CentreId IndividualId: replace residence=0 if EventCode==1 & (EventCode[_n+1]!=1)
***BIRTH
replace residence=0 if residence==. & EventCode==2
***EXIT
replace residence=1 if residence==. & EventCode==5
***DEATH
replace residence=1 if residence==. & EventCode==7

***ENTRY
**Cases with ENTRY preceded by EXIT and less than 180-day duration
bysort CountryId CentreId IndividualId: replace residence=1 if residence==. & ///
(EventCode==6 & EventCode[_n-1]==5 & EventDate-EventDate[_n-1]<=15778800000)
**Cases with ENTRY preceded by EXIT and duration of more than 180 days
bysort CountryId CentreId IndividualId: replace residence=0 if residence==. & ///
(EventCode==6 & EventCode[_n-1]==5 & EventDate-EventDate[_n-1]>15778800000)

**Cases with ENTRY preceded by OMG and less than 180-day duration
bysort CountryId CentreId IndividualId: replace residence=1 if residence==. & ///
(EventCode==6 & EventCode[_n-1]==7 & EventDate-EventDate[_n-1]<=15778800000)
**Cases with ENTRY preceded by OMG and duration of more than 180 days
bysort CountryId CentreId IndividualId: replace residence=0 if residence==. & ///
(EventCode==6 & EventCode[_n-1]==7 & EventDate-EventDate[_n-1]>15778800000)
**Cases of ENTRY as a first event (clearly a reconciliation issue)
bysort CountryId CentreId IndividualId: replace residence=0 if residence==. & ///
	EventCode==6 & _n==1 

* For the specific cases where ENT was not preceded by EXT
replace residence=1 if EventCode==6 & residence==.

***IN-MIGRANT
**Cases with IMG preceded by OMG and less than 180-day duration
bysort CountryId CentreId IndividualId: replace residence=1 if residence==. & ///
(EventCode==3 & EventCode[_n-1]==4 & EventDate-EventDate[_n-1]<=15778800000)
**Cases with IMG preceded by OMG and duration of more than 180 days
bysort CountryId CentreId IndividualId: replace residence=0 if residence==. & ///
		(EventCode==3 & EventCode[_n-1]==4 & EventDate-EventDate[_n-1]>15778800000)
bysort CountryId CentreId IndividualId: replace residence=0 if residence==. & ///
		EventCode==3 & EventCode[_n-1]==.

***OUT-MIGRANT
bysort CountryId CentreId IndividualId: replace residence=1 if residence==. & EventCode==4 
bysort CountryId CentreId IndividualId: replace residence=0 if residence==1 & ///
		(EventCode==4 & (EventCode[_n-1]==4 | EventCode[_n-1]==3) & /// 
		residence[_n-1]==0 & EventDate-EventDate[_n-1]<=15778800000)

***OBE
bysort CountryId CentreId IndividualId: replace residence=1 if EventCode==9 & ///
		EventCode[_n-1]!=4 & EventCode[_n-1]!=5 & EventCode[_n-1]!=7 & ///
		EventCode[_n-1]!=19 
bysort CountryId CentreId IndividualId: replace residence=0 if EventCode==9 & ///
		(EventCode[_n-1]==4 | EventCode[_n-1]==5 | EventCode[_n-1]==7 | ///
		EventCode[_n-1]==19) 

drop if EventCode==. & lastrecord!=1
capture drop EventSucc
bysort CountryId CentreId IndividualId (EventDate EventCode): gen EventSucc=EventCode[_n+1] 
lab val EventSucc eventlab
tab EventCode EventSucc, missing

* Check for cases with missing values for residence
capture drop misresidence
egen misresidence=max(residence==.), by(CountryId CentreId IndividualId)
sort CountryId CentreId IndividualId EventDate EventCode
tab EventCode if residence==.
table CentreId, cont(sum misresidence freq) format(%10.0f) cellwidth(20)
tabulate residence EventCode, missing

drop misresidence

* If no specific corrections, recode all remaining missing "residence" into 0 (=not resident)
recode residence .=0
tabulate residence EventCode, missing

drop error_matrix EventPrec lastrecord EventSucc
compress
save ConsolidatedData2018_basic.dta, replace

use ConsolidatedData2018_basic.dta, clear
gen tempId=string(CountryId)+CentreId+string(IndividualId)
rename EventDate EventDateMain
bysort CountryId CentreId IndividualId (EventDateMain EventCode): gen lastrecord=_n==_N
expand =2 if lastrecord==1, gen(matchOBE)
di %20.0g tC(01Jan2018 00:00:00)
replace EventDate=1830384027000 if matchOBE==1
replace EventCode=100 if matchOBE==1
compress
save ConsolidatedData2018_main.dta, replace

clear
* tmerge with the DLV episodes
tmerge tempId 	ConsolidatedData2018_main(EventDateMain) ///
				ConsolidatedData2018_DLV(EventDateDLV) ///
				ConsolidatedData2018_analysis(EventDate) 

format EventDate %tC
replace EventCode=EventCodeDLV if _File==2
drop if EventCode==100
drop if EventCode!=10 & _File==2
drop _File

sort CountryId CentreId IndividualId EventDate EventCode

* After including DLV : Check again consistency matrix and clean data inconsistencies 
forval n = 1/10 {
	capture drop EventSucc
	bysort CountryId CentreId IndividualId (EventDate EventCode): gen EventSucc=EventCode[_n+1] 
	lab val EventSucc eventlab
	capture drop EventPrec
	bysort CountryId CentreId IndividualId (EventDate EventCode): gen EventPrec=EventCode[_n-1] 
	lab val EventPrec eventlab
	display "Consistency matrix at iteration # " `n' 
	tab EventCode EventSucc, missing
* Delete any event before ENU / BTH
	drop if EventCode!=. & (EventSucc==1 | EventSucc==2)
* DLV or BTH as last event 
	drop if (EventCode==2 | EventCode==10) & EventSucc==. 
* DLV / EXT before IMG 
	drop if (EventCode==10 | EventCode==5) & EventSucc==3 
* Delete any event after OBE / DTH / missing
	drop if EventCode==7 & (EventPrec==. | EventPrec==7 | EventPrec==9)
	drop if EventCode==10 & (EventPrec==. | EventPrec==7 | EventPrec==9)
	drop if (EventCode==4 | EventCode==5 | EventCode==6) & (EventPrec==. | EventPrec==7 | EventPrec==9)
	drop if EventCode==9 & (EventPrec==. | EventPrec==9)
	drop if EventCode!=. & EventPrec==9 
* EXT / ENT after OMG  
	drop if (EventCode==5 | EventCode==6) & EventPrec==4
* DLV after OMG / DTH / OBE
	drop if EventCode==10 & (EventPrec==4 | EventPrec==7 | EventPrec==9)
* OBE after missing  
	drop if EventCode==9 & EventPrec==. 
}

capture drop datebeg
bysort CountryId CentreId IndividualId (EventDate EventCode): ///
		gen double datebeg=cond(_n==1, DoB, EventDate[_n-1])
format datebeg %tC
lab var datebeg "Date of beginning"

drop tempId EventDateMain lastrecord EventCodeDLV EventDateDLV EventPrec
* Create a unique numerical ID
gen numId=0
replace numId=sum(IndividualId!=IndividualId[_n-1])
compress

cap drop censor_death 
gen byte censor_death=(EventCode==7) if residence==1

drop matchOBE
save ConsolidatedData2018_analysis.dta, replace

use ConsolidatedData2018_analysis.dta, clear
* Split by calendar year (split by agegroup is not necessary)
stset EventDate if residence==1, id(numId) failure(censor_death==1) time0(datebeg)
* 
/* to get the exact value for 1 January of each year
forval year=1990/2016 {
	di %20.0g tC(01Jan`year' 00:00:00) " : `year'"
}
*/
* split observation time at each 1 January every 5 years from 1990
capture drop calendar_year
stsplit calendar_year, at( ///
       946771215000, /// 
       1104537619000, ///
       1262304022000, ///
       1420156822000, ///
       1577923224000, ///
       1735689625000) 
recode calendar_year ///
       946771215000=1990 ///
       1104537619000=1995 ///
       1262304022000=2000 ///
       1420156822000=2005 ///
       1577923224000=2010 ///
       1735689625000=2015
label variable calendar_year calendar_year

drop EventSucc

* Recode EventCode for calendar_year change
sort CountryId CentreId IndividualId EventDate EventCode
bysort CountryId CentreId IndividualId (EventDate EventCode): ///
		replace EventCode=30 if residence==1 & censor_death==. ///
		& EventCode==EventCode[_n+1]& (calendar_year==calendar_year[_n+1]-5 | calendar_year==0)

capture drop datebeg
bysort CountryId CentreId IndividualId (EventDate EventCode): ///
		gen double datebeg=cond(_n==1, DoB, EventDate[_n-1])
format datebeg %tC
lab var datebeg "Date of beginning"
stset EventDate if residence==1, id(numId) failure(censor_death==1) time0(datebeg) scale(31557600000)
table CentreId calendar_year [iw=_t-_t0], cont(sum residence) format(%10.0f) column //PERSON YEARS

* Given date inconsistencies consider all calendar_years before start of HDSS 
* as calendar_year of non-residence
gen calendar_day=(dofC(EventDate))
format calendar_day %td
stset EventDate if residence==1, id(numId) failure(censor_death==1) time0(datebeg)

capture drop startENU
di %20.0g tC(01Jan1998 00:00:00) 
stsplit startENU if CentreId=="BF031", at(1199232021000)
replace residence=0 if startENU==0
bysort CountryId CentreId IndividualId (EventDate EventCode): ///
	replace EventCode=30 if startENU==0 & startENU[_n+1]>0

capture drop startENU
di %20.0g tC(01Jan2009 00:00:00)
stsplit startENU if ///
	(CentreId=="BF021" | CentreId=="BF041" | CentreId=="CI011") ///
	, at(1546387224000)
replace residence=0 if startENU==0
bysort CountryId CentreId IndividualId (EventDate EventCode): ///
	replace EventCode=30 if startENU==0 & startENU[_n+1]>0

capture drop startENU
di %20.0g tC(01Jan1990 00:00:00)
stsplit startENU if ///
	(CentreId=="GM011" | CentreId=="SN011" | CentreId=="SN012" | CentreId=="SN013" ) ///
	, at(946771215000)
replace residence=0 if startENU==0
bysort CountryId CentreId IndividualId (EventDate EventCode): ///
	replace EventCode=30 if startENU==0 & startENU[_n+1]>0

capture drop startENU
di %20.0g tC(01Jan1993 00:00:00)
stsplit startENU if (CentreId=="ZA011") ///
	, at(1041465617000)
replace residence=0 if startENU==0
bysort CountryId CentreId IndividualId (EventDate EventCode): ///
	replace EventCode=30 if startENU==0 & startENU[_n+1]>0

capture drop startENU
di %20.0g tC(01Jan1994 00:00:00)
stsplit startENU if (CentreId=="GH011" ) ///
	, at(1073001618000)
replace residence=0 if startENU==0
bysort CountryId CentreId IndividualId (EventDate EventCode): ///
	replace EventCode=30 if startENU==0 & startENU[_n+1]>0

capture drop startENU
di %20.0g tC(01Jan2006 00:00:00)
stsplit startENU if (CentreId=="GH031" | CentreId=="ET021" | CentreId=="GH021") ///
	, at(1451692823000)
replace residence=0 if startENU==0
bysort CountryId CentreId IndividualId (EventDate EventCode): ///
	replace EventCode=30 if startENU==0 & startENU[_n+1]>0

capture drop startENU
di %20.0g tC(01Jan2008 00:00:00)
stsplit startENU if (CentreId=="ET041") ///
	, at(1514764823000)
replace residence=0 if startENU==0
bysort CountryId CentreId IndividualId (EventDate EventCode): ///
	replace EventCode=30 if startENU==0 & startENU[_n+1]>0

capture drop startENU
di %20.0g tC(01Jan2010 00:00:00)
stsplit startENU if ///
	(CentreId=="ET031" | CentreId=="ET061" | CentreId=="MZ021") ///
	, at(1577923224000)
replace residence=0 if startENU==0
bysort CountryId CentreId IndividualId (EventDate EventCode): ///
	replace EventCode=30 if startENU==0 & startENU[_n+1]>0

capture drop startENU
di %20.0g tC(01Jan1997 00:00:00)
stsplit startENU if (CentreId=="TZ011") ///
	, at(1167696020000)
replace residence=0 if startENU==0
bysort CountryId CentreId IndividualId (EventDate EventCode): ///
	replace EventCode=30 if startENU==0 & startENU[_n+1]>0

capture drop startENU
di %20.0g tC(01Jan1999 00:00:00)
stsplit startENU if (CentreId=="TZ012") ///
	, at(1230768022000)
replace residence=0 if startENU==0
bysort CountryId CentreId IndividualId (EventDate EventCode): ///
	replace EventCode=30 if startENU==0 & startENU[_n+1]>0

capture drop startENU
di %20.0g tC(01Jan2000 00:00:00)
stsplit startENU if (CentreId=="ZA031" ) ///
	, at(1262304022000)
replace residence=0 if startENU==0
bysort CountryId CentreId IndividualId (EventDate EventCode): ///
	replace EventCode=30 if startENU==0 & startENU[_n+1]>0

capture drop startENU
di %20.0g tC(01Jan2003 00:00:00)
stsplit startENU if ///
	(CentreId=="KE031" | CentreId=="MW011" ) ///
	, at(1356998422000)
replace residence=0 if startENU==0
bysort CountryId CentreId IndividualId (EventDate EventCode): ///
	replace EventCode=30 if startENU==0 & startENU[_n+1]>0

capture drop startENU
di %20.0g tC(01Jan2005 00:00:00)
stsplit startENU if (CentreId=="UG011" ) ///
	, at(1420156822000)
replace residence=0 if startENU==0
bysort CountryId CentreId IndividualId (EventDate EventCode): ///
	replace EventCode=30 if startENU==0 & startENU[_n+1]>0

capture drop startENU
di %20.0g tC(01Jan2012 00:00:00)
stsplit startENU if	(CentreId=="ET042") ///
	, at(1640995224000)
replace residence=0 if startENU==0
bysort CountryId CentreId IndividualId (EventDate EventCode): ///
	replace EventCode=30 if startENU==0 & startENU[_n+1]>0

capture drop startENU
di %20.0g tC(01Jan2009 00:00:00)
stsplit startENU if	(CentreId=="ET051" | CentreId=="KE041") ///
	, at(1546387224000)
replace residence=0 if startENU==0
bysort CountryId CentreId IndividualId (EventDate EventCode): ///
	replace EventCode=30 if startENU==0 & startENU[_n+1]>0

capture drop startENU
di %20.0g tC(01Jan2011 00:00:00)
stsplit startENU if	(CentreId=="KE051" | CentreId=="NG011") ///
	, at(1609459224000)
replace residence=0 if startENU==0
bysort CountryId CentreId IndividualId (EventDate EventCode): ///
	replace EventCode=30 if startENU==0 & startENU[_n+1]>0

capture drop startENU
di %20.0g tC(01Jan1994 00:00:00)
stsplit startENU if	(CentreId=="TZ021") ///
	, at(1073001618000)
replace residence=0 if startENU==0
bysort CountryId CentreId IndividualId (EventDate EventCode): ///
	replace EventCode=30 if startENU==0 & startENU[_n+1]>0

capture drop startENU
di %20.0g tC(01Jan1996 00:00:00)
stsplit startENU if (CentreId=="ZA021") ///
	, at(1136073620000)
replace residence=0 if startENU==0
bysort CountryId CentreId IndividualId (EventDate EventCode): ///
	replace EventCode=30 if startENU==0 & startENU[_n+1]>0

drop startENU

capture drop EventSucc
bysort CountryId CentreId IndividualId (EventDate EventCode): gen EventSucc=EventCode[_n+1] 
lab val EventSucc eventlab
capture drop EventPrec
bysort CountryId CentreId IndividualId (EventDate EventCode): gen EventPrec=EventCode[_n-1] 
lab val EventPrec eventlab
tab EventCode EventSucc, missing

drop EventPrec EventSucc
compress
cap drop censor_death 
gen byte censor_death=(EventCode==7) if residence==1
capture drop datebeg
bysort CountryId CentreId IndividualId (EventDate EventCode): ///
		gen double datebeg=cond(_n==1, DoB, EventDate[_n-1])
format datebeg %tC
lab var datebeg "Date of beginning"
stset EventDate if residence==1, id(numId) failure(censor_death==1) time0(datebeg) scale(31557600000)
table CentreId calendar_year [iw=_t-_t0], cont(sum residence) format(%10.0f) column

* Person-years for children under-5 (not restricted to those born in HDSS)
stset EventDate if residence==1, id(numId) failure(censor_death==1) time0(datebeg) ///
				origin(time DoB) exit(time DoB+(31557600000*5)+212000000) scale(31557600000)

table CentreId calendar_year [iw=_t-_t0], cont(sum residence) format(%10.0f) column row 

stset, clear
drop numId
drop ObservationDate
order CountryId CentreId LocationId IndividualId MotherId DeliveryId Sex DoB EventCode datebeg EventDate  

* Error in naming variables in Karonga
gen DeliveryId2=MotherId if CentreId=="MW011"
replace MotherId=DeliveryId if CentreId=="MW011"
replace DeliveryId=DeliveryId2 if CentreId=="MW011"
drop DeliveryId2


save ConsolidatedData2018_analysis, replace

/*
note : remain small errors of date/birthdate with no consequence on further analyses
note : split by calendar year (1st January 1990 to 2015 by step of 5 years)
*/

erase ConsolidatedData2018_main.dta
erase ConsolidatedData2018_basic.dta
erase ConsolidatedData2018_DLV.dta
erase ConsolidatedData2018_clean.dta

