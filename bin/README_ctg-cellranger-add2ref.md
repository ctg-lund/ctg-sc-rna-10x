# ctg-cellranger-add2ref
### Add custom gene to cellranger reference

## usage

```
ctg-cellranger-add2ref 

mandatory arguments:
 -i id           : ID of gene to add
 -l length       : Length of gene to add 
 -f custom fasta : full path to fasta file to add to reference (e.g. /full/path/to/custom_gene.fa)
 -r orig ref     : full path to original cellranger ref genome  to manipulate (e.g. /full/path/to/refdata-gex-mm10-2020-A/fasta/genome.fa)
 -g orig gtf     : full path to original cellranger ref gtf to manipulate (e.g. /full/path/to/refdata-gex-mm10-2020-A/genes/genes.gtf)
 -s refbase      : 'hg38' or 'mm10'. The name of the base reference. 
 -h help         : print this help message
```

### Recommened usage:
Run from within a 'custom_genome' folder in which you have the custom_gene.fa file. All output files will be written to this (current) directory.

### Example:
1. `cd project-folder`

2. `mkdir custom-genome`

3. `cd custom-genome`

4. Add fasta for the custom gene to custom-genome
5. 
```
ctg-cellranger-add2ref \ 
   -i geneX \
   -l 2032 \
   -f custom_gene.fa \
   -r /ref/hg38/cellranger/refdata-gex-GRCh38-2020-A/fasta/genome.fa 
   -g /ref/hg38/cellranger/refdata-gex-GRCh38-2020-A/genes/genes.gtf 
   -s hg38
```

### Requirements

- `cellranger rna` (v3.1 or above)
- `slurm`

