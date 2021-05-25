# ctg-sc-rna-10x 
## Nextflow pipeline for preprocessing of 10x chromium sc-RNA data with cellranger. 

- Designed to handle multiple projects in one sequencing run (but also works with only one project)
- Supports mm10 and hg38 references, but can also be run with custom reference genome and annotation (must be added via nextflow.config). See custom genome below.
- Supports nuclei samples

## USAGE

1. For reproducibility, create a project / run directory in which you clone this repository, containing the nextflow.config, nf-pipeline, bin
2. Clone and build the Singularity container for this pipeline: (https://github.com/perllb/ctg-sc-rna-10x/tree/master/container/sc-rna-10x.v6)
3. Edit the nextflow.config file to fit your project and system. Set current directory as `basedir`. (from where you execute the pipeline).
4. Edit your samplesheet to match the example samplesheet (same columns, with Sample_Species, count, agg, nuclei params for each sample added)
5. Run pipeline 
```
nohup nextflow run pipe-sc-rna-10x.nf > log.pipe-sc-rna-10x.txt &
```


## Pipeline steps:

Cellranger version: cellranger v6.0 

* `Demultiplexing` (cellranger mkfastq): Converts raw basecalls to fastq, and demultiplex samples based on index (https://support.10xgenomics.com/single-cell-gene-expression/software/pipelines/6.0/using/mkfastq).
* `FastQC`: FastQC calculates quality metrics on raw sequencing reads (https://www.bioinformatics.babraham.ac.uk/projects/fastqc/). MultiQC summarizes FastQC reports into one document (https://multiqc.info/).
* `Align` + `Counts` (cellranger count): Aligns fastq files to reference genome, counts genes for each cell/barcode, perform secondary analysis such as clustering and generates the cloupe files (https://support.10xgenomics.com/single-cell-gene-expression/software/pipelines/6.0/using/count).
* `Aggregation` (cellranger aggr): Automatically creates the input csv pointing to molecule_info.h5 files for each sample to be aggregated and executes aggregation (https://support.10xgenomics.com/single-cell-gene-expression/software/pipelines/latest/using/aggregate). 
* `Cellranger count metrics` (bin/ctg-sc-count-metrics-concat.py): Collects main count metrics (#cells and #reads/cell etc.) from each sample and collect in table
* `multiQC`: Compile fastQC and cellranger count metrics in multiqc report
* `md5sum`: md5sum of all generated files


## Output:
* ctg-PROJ_ID-output
    * `qc`: Quality control output. 
        * cellranger metrics: Main metrics summarising the count / cell output 
        * fastqc output (https://www.bioinformatics.babraham.ac.uk/projects/fastqc/)
        * multiqc output: Summarizing FastQC output and demultiplexing (https://multiqc.info/)
    * `fastq`: Contains raw fastq files from cellranger mkfastq.
    * `count-cr`: Cellranger count output. Here you find gene/cell count matrices, secondary analysis output, and more. Please go to (https://support.10xgenomics.com/single-cell-gene-expression/software/pipelines/6.0/using/count) for more information on the output files.
    * `summaries`: 
        * web-summary files which provide an overview of essential metrics from the 10x run. 
        * cloupe files which can be used to explore the data interactively in the Loupe browser (https://support.10xgenomics.com/single-cell-gene-expression/software/visualization/latest/what-is-loupe-cell-browser)  
    * `aggregate`:
        * Output from cellranger aggregation. 
    * `ctg-md5.PROJ_ID.txt`: text file with md5sum recursively from output dir root    


## Samplesheet requirements:

Note: no header! only the rows shown below, starting with the column names.

 | Sample_ID | Sample_Name | index | Sample_Project | Sample_Species | nuclei | 
 | --- | --- | --- | --- | --- | --- | 
 | Si1 | Sn1 | SI-GA-D9 | proj_2021_012 | human | n | 
 | Si2 | Sn2 | SI-GA-H9 | proj_2021_012 | human | n | 
 | Sample1 | S1 | SI-GA-C9 | proj_2021_013 | mouse | y | 
 | Sample2 | S23 | SI-GA-C9 | proj_2021_013 | mouse | y |

```

The nf-pipeline takes the following Columns from samplesheet to use in channels:

- Sample_ID ('Sample_Name' will be ignored)
- Index (Must use index ID!)
- Sample_Project (Project ID)
- Sample_Species (human/mouse/custom - if custom, see below how to edit the config file)
- nuclei ('y' if the sample is nuclei) 
```


## Container
- `sc-rna-10x`: For 10x single cell mRNA-seq. Based on cellranger.
https://github.com/perllb/ctg-sc-rna-10x/tree/master/container/sc-rna-10x.v6

### Build containers from recipes

NOTE: Environment.yml file has to be in current working directory
```
sudo -E singularity build sc-rna-10x.v6.sif sc-rna-10x.v6-builder
```
Add path to .sif in nextflow.config


### Run command with container
```
singularity exec --bind /fs1 sc-rna-10x.v6.sif cellranger count (..arguments..)
```

## Custom genome 

If custom genome (not hg38 or mm10) is used

1. Set "Sample_Species" column to 'custom' in samplesheet:

Example:
 | Sample_ID | Sample_Name | index | Sample_Project | Sample_Species | nuclei | 
 | --- | --- | --- | --- | --- | --- | 
 | Si1 | Sn1 | SI-GA-D9 | proj_2021_012 | **custom** | n | 
 | Si2 | Sn2 | SI-GA-H9 | proj_2021_012 | **custom** | n | 
 
 2. In nextflow.config, set 
 `custom_genome=/PATH/TO/CUSTOMGENOME`
 
### Add custom genes (e.g. reporters) to cellranger annotation

Use the `ctg-cellranger-add2ref` script. 

https://github.com/perllb/ctg-cellranger-add2ref


