*! version 3.0 11/11/93 by Philippe Bocquier
* As you can see, this is not new! 
* The very first version dates back from 1990 
* when I was working on my PhD thesis (defended 02/11/1992)

* revised 1/04/2004 for Stata 8
* So far, it was not necessary to update to higher version. That being said, 
* the syntax could probably be improved using recent Stata version.
program define tmerge
	version 3.0
	capture describe, short
	if _result(1)!=0 | _result(2)!=0 {
		error 18 /* No file should be loaded in memory */
	}
* The syntax is (below are the word identifiers attributed by the parse command):
* tmerge identifier_var file_nameA(time_varA) file_nameB(time_varB) new_file_name(new_time_var) 
*             `1'  `2' `3'  `4'  `5'   `6'   `7'  `8'  `9'     `10'   `11'   `12'  `13'
	parse "`*'", parse(" ()")
* This is a basic check that the command has the right number of words 
	if "`13'"!=")" | "`14'"!="" {
		di "See help tmerge"
		exit 198
	}

quietly {
	tempfile fichB fichA
	tempvar dumA dumBd dumBf error

* Use the file B
	use `6'
	capture drop _merge
* Generate a new time variable with the same value as the original time variable
* with as much precision as available (double)
	gen double `12'=`8'
* Make sure the file is well-sorted by identifier and time
	sort `1' `12'
* Generate a dummy variable being the last variable of file B
	gen byte `dumBf'=1
	save `fichB'

* Use the file A
	use `2'
	capture drop _merge
* Make it the output file 
	capture save `10'
* Should be a new file or replace existing one
	if _rc!=0 {
		di " "
		noi di "File `10' already exists. Replace?" _request(oui)
		if "%oui"=="oui" | "%oui"=="o" | "%oui"=="O" | "%oui"=="Y" | "%oui"=="yes" | "%oui"=="y" {
			save `10', replace
		}
	}
* Generate an indicator of file A
	gen byte `dumA'=1
* Generate a new time variable with the same value as the original time variable
* with as much precision as available (double)
* NB: same name as in file B
	gen double `12'=`4'
	quietly order `1'  
* Make sure the file is well-sorted by identifier and time
	sort `1' `12'
* Generate a dummy variable being the last variable of file A
* (it will become the first variable of file B after merging)
	gen byte `dumBd'=1
	save `fichA'
* Merge file A with file B (keys: individual identifier & new time variable)
	capture drop _merge
	merge `1' `12' using `fichB'
	erase `fichB'
* Tricky part: reverse time
	replace `12'=-`12'
* Sort on reverse time (last record is now the first)
	sort `1' `12'

* VERY IMPORTANT: the last-become-first record (censoring date) should be the same
* in both file A and B, i.e. _merge==3
* This is because in biographical files the relevant event and date of event
* are at the end of an episode
	capture assert _merge==3 if `1'!=`1'[_n-1] 
	if _rc==9 {
		noi di "Some individuals are not censored at the same time in both files."
		noi di "Please check your files for..."
		gen byte `error'=1-(_merge==3) if `1'!=`1'[_n-1] 
		di count if _merge==1 & `1'!=`1'[_n-1]
		noi di "...errors (possibly no records) in `fichB' "
		di count if _merge==2 & `1'!=`1'[_n-1]
		noi di "...errors (possibly no records) in `fichA' "
		noi list `1' `4' `8' _merge if `error'==1
		drop _all
		exit 
	}
}
* NB: the simple merge above creates 
* - missing values for File A variables for File B event dates
* - missing values for File B variables for File A event dates
* => need to repeat variables' values for event dates of the other file
	di "Please wait..."
* Run a sub-routine (see below) to replace the values of File A variables
* for records coming from File B (_merge==2)
	_crctmge `1'-`dumA' if _merge==2
* Run a sub-routine (see below) to replace the values of File B variables
* for records coming from File A (_merge==1)
	_crctmge `dumBd'-`dumBf' if _merge==1
	drop `dumA' `dumBd' `dumBf'
* Back to normal time
	quietly replace `12'=-`12'
	sort `1' `12' 
	capture drop _File
* For more explicit names after the merge:
	rename _merge _File
	capture lab def _File 1 "`2'" 2 "`6'" 3 "both"
	lab val _File _File
	lab var _File "Record from file..."
	di " "
	di "The variable '_File' indicates in which file the time change is originated,"
	di "either `2' , `6' , or both."
	tab _File
	save `10', replace
	erase `fichA'
end

* NB: a characteristic identified by a variable is valid up to the end of an episode
* i.e. missing values have to be replaced by values of the most recent (following) record.
* (see example in tmerge.hlp)
* But it is not possible in Stata to make these replacement sequentially in reverse
* (from the last to the first record). Hence the use of reverse time where 
* the value in current observation is replaced by the value of previous observation. 
program define _crctmge
	version 3.0
	local varlist "req"
	local if "opt"
	parse "`*'"
	parse "`varlist'", parse(" ")
	while "`2'"!="" {
		quietly replace `2'=`2'[_n-1] `if'
		macro shift
	}
End
