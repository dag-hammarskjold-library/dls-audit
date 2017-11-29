# dls-audit
compare DLS export file with Hzn database and produce MARC XML to correct missing data

<h3>Scripts</h3>

1. audit.pl
    * options
        * -i: input file path (DLS "excel export")
        * -o: output file path (comparison report)
    * loads DLS data from DLS "excel export" using paramters 035__a,191__a,856__u,998__a,998__c
    * loads Hzn audit data from bib_control table in Hzn database
    * iterates through eligible MARC records in Hzn database and uses loaded data to look up DLS counterpart, and writes the following data to a line in the output TSV: <br>
        1. Hzn id (bib#)
        2. DLS id
        3. last changed date of the MARC record in Hzn
        4. last changed date on the MARC record in DLS
        5. string representing the language file links to ODS in Hzn
        6. string representing the language files present in DLS
    * output file is for use by subsequent scripts for further action

2. analyze.pl
    * options
        * -i: input file path (output file from the last script)
    * iterates through the records in report from previous script
    * writes 4 output files (each record only appears on one file):
        1. to_update.tsv - bib#s where the last changed date in Hzn database is greater than the last changed date in the DLS record (the DLS record is out of date) - run import in REPLACE mode (update)
        2. add_files.tsv - bib# and languages for DLS records with missing files - ~~run import in APPEND mode with only FFT fields for missing files~~ run import in REPLACE mode. 
        3. missing.tsv - bib# for records in Horizon that are eliglible for export but are not in DL - run in import in NEW mode
		4. to_delete.tsv - records that are no longer in Horizon and should be deleted from DLS.

3. deletes.pl
	* options 
		* -i: input file
	* writes "delete.xml" for import that appends a 980 DELETED field 
		
3. ~~fft_appends.pl~~
   * ~~options~~
      * ~~-i: input file path (missing.tsv)~~
      * ~~-o: output file path (xml for import)~~
   * ~~derives missing languges from the input file and composes import xml file containing missing files to append~~

<h4>Then:</h4>

1. run exports
	* the records in to_update.tsv, missing.tsv, and add_files.tsv can be exported from Hzn using the normal export script, by running the exports script with option -l set to the path of the tsv.
  
2. run deletes.pl
	* skip if to_delete.tsv is empty.
	
3. run imports
	* import the four import files to DLS 
