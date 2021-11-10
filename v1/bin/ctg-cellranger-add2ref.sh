#!/bin/bash

echo "##########################"
echo "# ctg-cellranger-add2ref #"
echo "##########################"

id="" # Name of gene to add
len="" # length of gene to add
origref="" # original cellranger reference to manipulate (e.g. refdata-gex-mm10-2020-A/fasta/genome.fa)
origgtf="" # original cellranger gtf to manipulate (e.g. refdata-gex-mm10-2020-A/genes/genes.gtf )
refbase="" # mm10/hg38
customfa="" # fasta file with new sequence to add

# Path to singularity with cellranger
sing="singularity exec --bind /projects/ /projects/fs1/shared/ctg-containers/sc-rna-10x/sc-rna-10x.v6/sc-rna-10x.v6.sif"

# usage message 
usage() {

    echo ""
    echo "Usage: ctg-cellranger-add2ref 

mandatory arguments:
 -i id           : ID of gene to add
 -l length       : Length of gene to add 
 -f fasta        : full path to fasta file to add to reference (e.g. /full/path/to/custom_gene.fa)
 -r orig ref     : full path to original cellranger ref genome  to manipulate (e.g. /full/path/to/refdata-gex-mm10-2020-A/fasta/genome.fa)
 -g orig gtf     : full path to original cellranger ref gtf to manipulate (e.g. /full/path/to/refdata-gex-mm10-2020-A/genes/genes.gtf)
 -s refbase      : 'hg38' or 'mm10'. The name of the base reference. 
 -h help         : print this help message

recommened usage:
Run from within a 'custom_genome' folder in which you have the custom_gene.fa file. All output files will be written to current directory.
"
}

# Exit with usage
exit_abnormal(){
    usage
    exit 1
}

# Read and control input arguments 
while getopts i:l:f:r:g:s:h opt; do
    case $opt in
	i) id=$OPTARG
	    ;;
	l) len=$OPTARG
	    ;;
	f) customfa=$OPTARG
	    ;;
	r) origref=$OPTARG
	    ;;
	g) origgtf=$OPTARG
	    ;;
	s) refbase=$OPTARG
	    ;;
       	h) exit_abnormal
	    ;;
	\?) echo "> Error: Invalid option -$OPTARG" >&2
	    exit_abnormal ;;
	:) echo "> Error: -${OPTARG} requires an argument.. "
	    exit_abnormal ;;
    esac
done

## Check that all variables are specified
if [ -z $id ]; then 
    echo "Error: -i id is not specified."
    exit_abnormal
fi
if [ -z $len ]; then 
    echo "Error: -l len is not specified."
    exit_abnormal
fi
if [ -z $customfa ]; then 
    echo "Error: -f custom fasta is not specified."
    exit_abnormal
elif [ ! -f $customfa ]; then
    echo "Error: The specified -f [custom fasta] ($customfa) does not exist!"
    exit_abnormal
fi
if [ -z $origref ]; then 
    echo "Error: -r original fasta is not specified."
    exit_abnormal
elif [ ! -f $origref ]; then
    echo "Error: The specified -r [original fasta] ($origref) does not exist!"
    exit_abnormal
fi
if [ -z $origgtf ]; then 
    echo "Error: -g original gtf is not specified."
    exit_abnormal
elif [ ! -f $origgtf ]; then
    echo "Error: The specified -g [original gtf] ($origgtf) does not exist!"
    exit_abnormal
fi
if [ -z $refbase ]; then 
    echo "Error: -s reference base (hg38 or mm10) is not specified."
    exit_abnormal
fi

## Print arguments
echo "Creating custom reference based on the following arguments:"
echo "ID of custom gene      : $id"
echo "Length of custom gene  : $len"
echo "Fasta with custom gene : $customfa"
echo "Original fasta         : $origref"
echo "Original gtf           : $origgtf"
echo "Reference              : $refbase"

read -p "Are these arguments correct? 

(y/n) .. " prompt

if [[ $prompt == 'y' ]]; then
    
    echo "1: Generage custom GTF.." 
    gtfgen="echo -e \"$id\tunknown\texon\t1\t$len\t.\t+\t.\tgene_id \"$id\"; transcript_id \"$id\"; gene_name \"$id\"; gene_biotype \"protein_coding\";\" > $id.gtf"
    echo $gtfgen
    echo -e "$id\tunknown\texon\t1\t$len\t.\t+\t.\tgene_id \"$id\"; transcript_id \"$id\"; gene_name \"$id\"; gene_biotype \"protein_coding\";" > $id.gtf
    echo "New gtf:"
    #cat $id.gtf
    echo "..done"    
    echo

    echo "2: Add custom GTF to genes.gtf"
    echo "2.1: Make a copy of original gtf.. "
    cpgtf="cp $origgtf ${refbase}.genes_${id}.gtf"
    echo $cpgtf
    #$cpgtf
    echo "..done"    
    echo

    echo "2.2: Append custom gtf to it.."
    catgtf="cat $id.gtf >> ${refbase}.genes_${id}.gtf"
    echo $catgtf
    #cat $id.gtf >> ${refbase}.genes_${id}.gtf
    echo "..done"    
    echo

    echo "3: Add custom Fasta to original reference genome.. "
    echo "3.1: Make a copy of original fasta"
    cpfasta="cp $origref ${refbase}_genome_${id}.fa"
    echo $cpfasta
    #$cpfasta
    echo "..done"
    echo

    echo "3.2: Append custom fasta to it.."
    catfasta="cat $customfa >> ${refbase}_genome_${id}.fa"
    echo $catfasta
    #cat $customfa >> ${refbase}_genome_${id}.fa
    echo "..done"
    echo

    echo "4: Generate the reference with cellranger.. "
    genref="$sing cellranger mkref --genome=${refbase}_genome_${id} --fasta=${refbase}_genome_${id}.fa --genes=${refbase}.genes_${id}.gtf"
    echo $genref

    sb=mkref.$id.script.sh
    echo "#!/bin/bash -ue " > $sb
    echo "#SBATCH -c 16 " >> $sb
    echo "#SBATCH -t 48:00:00 " >> $sb
    echo "#SBATCH --mem 170G " >> $sb
    echo "#SBATCH -J mkref_$id " >> $sb
    echo "#SBATCH -o mkref_$id.out " >> $sb
    echo "#SBATCH -e mkref_$id.err " >> $sb

    echo $genref >> $sb
    sbatch $sb

    echo
    echo "..Submitted to slurm. This will take some minutes.."

else
    echo "Please enter correct arguments"
    exit_abnormal
fi
