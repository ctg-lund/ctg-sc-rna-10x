# ctg-sc-rna-10x 
## Nextflow pipeline for preprocessing of 10x chromium sc-RNA data with cellranger. 

- Designed to handle multiple projects in one sequencing run (but also works with only one project)
- Supports mm10 and hg38 references, but can also be run with custom reference genome and annotation (must be added via nextflow.config). See custom genome below.
- Supports nuclei samples

## USAGE

1. Clone and build the Singularity container for this pipeline: https://github.com/perllb/ctg-sc-rna-10x/tree/master/container/sc-rna-10x.v6
2. Edit your samplesheet to match the example samplesheet. See section `SampleSheet` below
3. Edit the nextflow.config file to fit your project and system. 
4. Run pipeline 
```
nohup nextflow run pipe-sc-rna-10x.nf > log.pipe-sc-rna-10x.txt &
```

## Input Files

The following files must be in the runfolder to start pipeline successfully.

1. Samplesheet (CTG_SampleSheet.sc-rna.10x.csv)

(Note that if running without demux, another samplesheet is needed! See below https://github.com/perllb/ctg-sc-rna-10x/blob/master/README.md#running-without-demux-with-existing-fastq-files)

### Samplesheet requirements:

Note: One samplesheet pr project!
Note: Must be in comma-separated values format (.csv)

| [Data] | , | , | , | , | , | , | , | , |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **Lane** | **Sample_ID** | **index** | **Sample_Project** | **Sample_Species** | **nuclei** | **force** | **email** | **deliver** |
|  | Si1 | SI-GA-D9 | proj_2021_012 | human | n | n | cus@mail.com;cust2@mail.com | y |
|  | Si2 | SI-GA-H9 | proj_2021_192 | hs-mm | y | 5000 | cus3@mail.com | n |


- Lane can also be specified if needed:

 | Lane | Sample_ID | index | Sample_Project | Sample_Species | nuclei | force | email | deliver |
 | --- | --- | --- | --- | --- | --- | --- | --- | --- |
 | 1 | Si1 | SI-GA-D9 | proj_2021_012 | human | n | n | cu@mail.com;cust2@mail.com | y |
 | 1 | Si2 | SI-GA-H9 | proj_2021_192 | hs-mm | y | 5000 | cur@mail.com;cu2@mail.com | n |


The nf-pipeline takes the following Columns from samplesheet to use in channels:

- `Sample_ID` : ID of sample. Sample_ID can only contain a-z, A-Z and "_".  E.g space and hyphen ("-") are not allowed! If 'Sample_Name' is present, it will be ignored. 
- `Sample_Project` : Project ID. E.g. 2021_033, 2021_192.
- `Sample_Species` : Only 'human'/'mouse'/'hs-mm'/'custom' are accepted. If you want to run the mixed GRCh38+mm10 genome, set "hs-mm". If species is not human or mouse (or mixed - "hs-mm") - or if an alternative reference e.g. with added gene/sequnece - set 'custom'. This custom reference genome has to be specified in the nextflow config file. See below how to edit the config file. Alternatively, when running driver, you can specify the path command line with the -c flag: `sc-rna-10x-driver -c /full/path/to/reference` 
- `nuclei` : Set to 'y' if the sample is nuclei, otherwise 'n'. 
- `force`  : Set to 'n' if NOT running with --force-cells. If you want to force cells for the sample, set this to the number you want to force


**Delivery-email generation:**
- `email`  : Column should have the email adresses for recipients of delivery mail. If multiple emails, separate with ";" 
- `deliver`: Set to 'y' if data should be automatically transferred to lfs603 and email sent to customer (defined in `email`) after pipeline is executed. Otherwise, set to 'n'.


**Only needed for demux**
- `index` : Must use index ID (10x ID) if dual index. For single index, the index sequence works too.
- `Lane` : Only needed to add if you actually sequence the project on a specific lane. Else, this column can be omitted. 

### Samplesheet template (.csv)

#### Name : `CTG_SampleSheet.sc-rna-10x.csv`
```
metaid,2021_012
[Data]
Lane,Sample_ID,index,Sample_Project,Sample_Species,nuclei,email,deliver
,Si1,SI-GA-D9,2021_012,human,n,n,cst1@mail.com;cst2@mail.com,y
,Si2,SI-GA-H9,2021_012,hs-mm,y,5000,cst4@mail.com,y
``` 
## Running without demux (with existing fastq files)

The main difference of the samplesheet is that `fastqpath` is added to samplesheet header:
```
metaid,2021_012
fastqpath,/path/to/fastq
[Data]
Lane,Sample_ID,index,Sample_Project,Sample_Species,nuclei,email,deliver
,Si1,SI-GA-D9,2021_012,human,n,n,cst1@mail.com;cst2@mail.com,y
,Si2,SI-GA-H9,2021_012,hs-mm,y,5000,cst4@mail.com,y
``` 
- The `fastqpath` has to point to a directory which has "<fastqpath>/sid...fastq" structure. That is, the `fastqpath` folder has to contain all fastq files for each sample, with name starting with the corresponding `Sample_ID`.
```
__ fastqpath
           |__ Sample_ID*R1*fastq
           |__ Sample_ID*R2*fastq
           |__ Sample_ID*I1*fastq
           |__ Sample_ID*I2*fastq
            ....
```

The driver can be executed from wherever.

## Pipeline steps:

Cellranger version: cellranger v6.0 

* `Demultiplexing` (cellranger mkfastq): Converts raw basecalls to fastq, and demultiplex samples based on index (https://support.10xgenomics.com/single-cell-gene-expression/software/pipelines/6.0/using/mkfastq).
* `FastQC`: FastQC calculates quality metrics on raw sequencing reads (https://www.bioinformatics.babraham.ac.uk/projects/fastqc/). MultiQC summarizes FastQC reports into one document (https://multiqc.info/).
* `Align` + `Counts` (cellranger count): Aligns fastq files to reference genome, counts genes for each cell/barcode, perform secondary analysis such as clustering and generates the cloupe files (https://support.10xgenomics.com/single-cell-gene-expression/software/pipelines/6.0/using/count).
* `Aggregation` (cellranger aggr): Automatically creates the input csv pointing to molecule_info.h5 files for each sample to be aggregated and executes aggregation (https://support.10xgenomics.com/single-cell-gene-expression/software/pipelines/latest/using/aggregate). This is only run if there is more than one sample pr project.
* `Cellranger count metrics` (bin/ctg-sc-count-metrics-concat.py): Collects main count metrics (#cells and #reads/cell etc.) from each sample and collect in table
* `multiQC`: Compile fastQC and cellranger count metrics in multiqc report
* `md5sum`: md5sum of all generated files
* `delivery`: Sending data to lfs603 delivery folder (created by script); and send email with download instruction to customer - also attach qc files and ctg-delivery-guide. 


## Output:
* ctg-PROJ_ID-output
    * `qc`: Quality control output. 
        * cellranger metrics: Main metrics summarising the count / cell output 
        * fastqc output (https://www.bioinformatics.babraham.ac.uk/projects/fastqc/)
        * multiqc output: Summarizing FastQC output and demultiplexing (https://multiqc.info/)
    * `fastq`: Contains raw fastq files from cellranger mkfastq.
    * `count-cr`: Cellranger count output. Here you find gene/cell count matrices, secondary analysis output, and more. See (https://support.10xgenomics.com/single-cell-gene-expression/software/pipelines/6.0/using/count) for more information on the output files.
    * `summaries`: 
        * web-summary files which provide an overview of essential metrics from the 10x run. 
        * cloupe files which can be used to explore the data interactively in the Loupe browser (https://support.10xgenomics.com/single-cell-gene-expression/software/visualization/latest/what-is-loupe-cell-browser)  
    * `aggregate`:
        * Output from cellranger aggregation. This is only run if there is more than one sample pr project.
    * `ctg-md5.PROJ_ID.txt`: text file with md5sum recursively from output dir root    


## Container
https://github.com/perllb/ctg-containers/tree/main/sc-rna-10x/sc-rna-10x.v6

## Custom genome 

If custom genome (not hg38 or mm10) is used

1. Set "Sample_Species" column to 'custom' in samplesheet:

Example:

 | Sample_ID | Sample_Name | index | Sample_Project | Sample_Species | nuclei | 
 | --- | --- | --- | --- | --- | --- | 
 | Si1 | Sn1 | SI-GA-D9 | proj_2021_012 | **custom** | y | 
 | Si2 | Sn2 | SI-GA-H9 | proj_2021_012 | **custom** | y |  
 
 2. In nextflow.config, set 
 `custom_genome=/PATH/TO/CUSTOMGENOME`
 
## Add custom genes (e.g. reporters) to cellranger annotation

You can use this script to add custom genes to the cellranger ref
https://github.com/perllb/ctg-cellranger-add2ref
