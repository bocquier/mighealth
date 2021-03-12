*! version 3.0 11/11/93 by Philippe Bocquier
To perform a match merge according to time (survival analysis)
-----------------------------------------------------------------------------

	^tmerge^ identifier_var file_nameA^(^time_varA^)^ file_nameB^(^time_varB^)^
			new_file_name^(^new_time_var^)^ 

This command merges two files both of which can contain several lines 
referring to periods of time. Files A and B must contain the same 
identifier_var that identifies individuals. time_varA and time_varB must 
refer to the time at transition and be expressed in the same scale. 
Moreover, for each individual, the time at censoring must be the same in 
both files. The output file (new_file_name) will be ordered according to 
new_time_var. 

The command creates a new variable, _File, which indicates the file from 
which the transition originated.

Example: 
-------
file job  				file mariage
id	 birth	tjob	 prof	id	 birth	 car1	tmar 	car2
 2	    63	  80	    3	 2	    63	    1	  78 	   4
 2	    63	  84	    1	 2	    63	    2	  89 	   3
 2	    63	  85	    2          
 2	    63	  89	    1          

Time variables (tjob in file job, tmar in file mariage) are expressed 
in the same scale. In each file censoring time is 89. The program is 
interrupted and an error message appear if times at censoring are not the 
same in both files. The command could read:

	^tmerge^ id job^(^tjob^)^ mariage^(^tmar^)^ job_mar^(^time^)^ 

The resulting file job_mar would be:

id	birth	tjob	prof	time	car1	tmar	car2	_File
2	63	80	3	78	1	78	4	mariage
2	63	80	3	80	2	89	3	job
2	63	84	1	84	2	89	3	job
2	63	85	2	85	2	89	3	job
2	63	89	1	89	2	89	3	both

NB: Original dates tjob and tmar are not modified. 

The variables common to both files are stored according to the values of the 
first file, using the same rule as ^merge^ command.

