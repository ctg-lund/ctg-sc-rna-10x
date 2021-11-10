#!/usr/bin/env nextFlow

// set variables
exp = params.experiment
basedir = params.basedir
metaID = params.metaid
OUTDIR = params.outdir
FQDIR = params.fqdir
CTGQC = params.ctgqc
demux = params.demux
b2farg = params.bcl2fastqarg

// Read and process sample sheet
sheet = file(params.sheet)

// create new file for reading into channels that provide sample info!
newsheet = file("$basedir/samplesheet.nf.sc-rna-10x.csv")

// Read and process sample sheet
all_lines = sheet.readLines()
write_b = false // if next lines has sample info
newsheet.text=""     

for ( line in all_lines ) {

    if ( write_b ) {
	newsheet.append(line + "\n")
    }
    if (line.contains("[Data]")) {
	write_b = true
    }
}

println "============================="
println ">>> sc-rna-10x pipeline for multiple projects / run >>>"
println ""
println "> INPUT: "
println "> runfolder		: $exp "
println "> sample-sheet		: $sheet "
println "> run-meta-id		: $metaID "
println "> basedir		: $basedir "
println "> bcl2fastq-arg        : '${b2farg}' "
println "> demux 		: $demux " 
println ""
println "> OUTPUT: "
println "> output-dir		: $OUTDIR "
println "> fastq-dir		: $FQDIR "
println "> ctg-qc-dir		: $CTGQC "
println "============================="


// all samplesheet info
Channel
    .fromPath(newsheet)
    .splitCsv(header:true)
    .map { row -> tuple( row.Sample_ID, row.Sample_Name, row.Sample_Project, row.Sample_ref, row.count, row.agg, row.nuclei) }
    .tap{infoall}
    .into { crCount_csv; cragg_ch; mvfastq_csv; crCountNuc_csv }

// Projects
Channel
    .fromPath(newsheet)
    .splitCsv(header:true)
    .map { row -> tuple( row.agg, row.Sample_Project) }
    .unique()
    .tap{infoProject}

println " > Samples to process: "
println "[Sample_ID,Sample_Name,Sample_Project,Sample_ref,count,agg,nuclei]"
infoall.subscribe { println "Info: $it" }

println " > Projects to process : "
println "[agg,Sample_Project]"
infoProject.subscribe { println "Info Projects: $it" }


// Run mkFastq
process mkfastq {

	input:
        val sheet 

	output:
	val 1 into moveFastq

	when:
	demux == 'y'

	"""
cellranger mkfastq \\
	   --id=$metaID \\
	   --run=$exp \\
	   --csv=$sheet \\
	   --jobmode=local \\
	   --localmem=100 \\
	   --output-dir $FQDIR \\
	   $b2farg


## multiqc on all fastq (mkfastq check)
multiqc ${FQDIR} --outdir ${CTGQC}/$metaID/ -n ${metaID}_mkfastq_multiqc.report.html

"""

}

process moveFastq {

    input:
    val x from moveFastq
    set sid, sname, projid, ref, count, agg, nuclei from mvfastq_csv

    output:
    val "y" into crCountNuc
    val "y" into crCount
    set sid, sname, projid, ref, count, agg, nuclei into fqc_ch

    when:
    demux = 'y'

    """
    mkdir -p ${OUTDIR}/${projid}
    mkdir -p ${OUTDIR}/${projid}/fastq


    ## Check if folder with SID exists
    if [ -d ${FQDIR}/${projid}/${sid} ]
    then
	mv ${FQDIR}/${projid}/${sid} ${OUTDIR}/${projid}/fastq/
	
    ## Check if folder with SNAME exists
    elif [ -d  ${FQDIR}/${projid}/${sname} ]
    then 
    	 mv ${FQDIR}/${projid}/${sname} ${OUTDIR}/${projid}/fastq/

    ## If not, then all fastq files should be directly under proj_id folder, so move that 
    
    else 
    	 mkdir -p ${OUTDIR}/${projid}/fastq/${sname}/
    	 mv ${FQDIR}/${projid}/$sname* ${OUTDIR}/${projid}/fastq/${sname}/
    fi
    
    """

}

// Channel to start count if demux == 'n'
// Projects
if ( demux == 'n' ) {

   Channel
	 .from("1")
    	 .set{ crCount }

}



process count {

	publishDir "${OUTDIR}/${projid}/count-cr/", mode: "move", overwrite: true

	input: 
	val sheet
	val y from crCount.collect()
        set sid, sname, projid, ref, count, agg, nuclei from crCount_csv

	output:
        file "${sname}" into samplename
        val "x" into count_agg

	when:
	count == "y" && nuclei == "n"

	"""
        if [ $ref == "Human" ] || [ $ref == "human" ]
        then
            genome="/projects/fs1/shared/references/hg38/cellranger/refdata-gex-GRCh38-2020-A"
        elif [ $ref == "mouse" ] || [ $ref == "Mouse" ]
        then
            genome="/projects/fs1/shared/references/mm10/cellranger/refdata-gex-mm10-2020-A"
        elif [ $ref == "custom"  ] || [ $ref == "Custom" ] 
        then
            genome=${params.custom_genome}
        else
            echo ">SPECIES NOT RECOGNIZED!"
            genome="ERR"
        fi

        mkdir -p ${OUTDIR}/${projid}/count-cr/

	cellranger count \\
	     --id=$sname \\
	     --fastqs=${OUTDIR}/$projid/fastq/$sname \\
	     --sample=$sname \\
             --project=$projid \\
	     --transcriptome=\$genome \\
             --localcores=20 --localmem=110 

        mkdir -p ${OUTDIR}
        mkdir -p ${OUTDIR}/${projid}
        mkdir -p ${OUTDIR}/${projid}/summaries
        mkdir -p ${OUTDIR}/${projid}/summaries/cloupe
        mkdir -p ${OUTDIR}/${projid}/summaries/web-summaries

	mkdir -p ${CTGQC}/${projid}
	mkdir -p ${CTGQC}/${projid}/web-summaries

	## Copy to delivery folder 
        cp ${sname}/outs/web_summary.html ${OUTDIR}/${projid}/summaries/web-summaries/${sname}.web_summary.html
        cp ${sname}/outs/cloupe.cloupe ${OUTDIR}/${projid}/summaries/cloupe/${sname}_cloupe.cloupe

	## Copy to CTG QC dir 
        cp ${sname}/outs/web_summary.html ${CTGQC}/${projid}/web-summaries/${sname}.web_summary.html

	"""

}


process count_nuc {

	publishDir "${OUTDIR}/${projid}/count-cr/", mode: "move", overwrite: true

	input: 
	val y from crCountNuc.collect()
        set sid, sname, projid, ref, count, agg, nuclei from crCountNuc_csv

	output:
        file "${sname}" into samplenameNuc
        val "x" into countNuc_agg

	when:
	count == "y" && nuclei == "y"

	"""
        if [ $ref == "Human" ] || [ $ref == "human" ]
        then
            genome="/projects/fs1/shared/references/hg38/cellranger/refdata-gex-GRCh38-2020-A"
        elif [ $ref == "mouse" ] || [ $ref == "Mouse" ]
        then
            genome="/projects/fs1/shared/references/mm10/cellranger/refdata-gex-mm10-2020-A"
        elif [ $ref == "custom"  ] || [ $ref == "Custom" ] 
        then
            genome=${params.custom_genome}
        else
            echo ">SPECIES NOT RECOGNIZED!"
            genome="ERR"
        fi

        mkdir -p ${OUTDIR}/${projid}/count-cr/

	cellranger count \\
	     --id=$sname \\
	     --fastqs=${OUTDIR}/$projid/fastq/$sname \\
	     --sample=$sname \\
	     --include-introns \\
             --project=$projid \\
	     --transcriptome=\$genome \\
             --localcores=20 --localmem=110 

        mkdir -p ${OUTDIR}
        mkdir -p ${OUTDIR}/${projid}
        mkdir -p ${OUTDIR}/${projid}/summaries
        mkdir -p ${OUTDIR}/${projid}/summaries/cloupe
        mkdir -p ${OUTDIR}/${projid}/summaries/web-summaries

	mkdir -p ${CTGQC}/${projid}
	mkdir -p ${CTGQC}/${projid}/web-summaries

	## Copy to delivery folder 
        cp ${sname}/outs/web_summary.html ${OUTDIR}/${projid}/summaries/web-summaries/${sname}.web_summary.html
        cp ${sname}/outs/cloupe.cloupe ${OUTDIR}/${projid}/summaries/cloupe/${sname}_cloupe.cloupe

	## Copy to CTG QC dir 
        cp ${sname}/outs/web_summary.html ${CTGQC}/${projid}/web-summaries/${sname}.web_summary.html

	"""

}

process fastqc {

	input:
	set sid, sname, projid, ref, count, agg, nuclei from fqc_ch	
        
        output:
        val projid into mqc_cha

	"""

        mkdir -p ${OUTDIR}/${projid}/qc
        mkdir -p ${OUTDIR}/${projid}/qc/fastqc

        for file in ${OUTDIR}/${projid}/fastq/${sname}/*fastq.gz
            do fastqc \$file --outdir=${OUTDIR}/${projid}/qc/fastqc
        done
	"""
    
}

process multiqc {

    input:
    val projid from mqc_cha.unique()

    output:
    val "x" into multiqc_outch

    script:
    """
    
    cd $OUTDIR/$projid
    multiqc . -f --outdir ${OUTDIR}/$projid/qc/ -n ${projid}_multiqc_report.html

    mkdir -p ${CTGQC}
    mkdir -p ${CTGQC}/$projid

    cp -r ${OUTDIR}/$projid/qc ${CTGQC}/$projid/

    """
}


// aggregation
process gen_aggCSV {

    input:
    set sid, sname, projid, ref, count, agg, nuclei from cragg_ch

    output:
    set projid, agg into craggregate

    when:
    agg == "y"

    """
    
    aggdir=$OUTDIR/$projid/aggregate

    mkdir -p \$aggdir

    aggcsv=\$aggdir/${projid}_libraries.csv

    if [ -f \$aggcsv ]
    then
        if grep -q $sname \$aggcsv
        then
             echo ""
        else
             echo "${sname},${OUTDIR}/${projid}/count-cr/${sname}/outs/molecule_info.h5" >> \$aggcsv
        fi
    else
        echo "library_id,molecule_h5" > \$aggcsv
        echo "${sname},${OUTDIR}/${projid}/count-cr/${sname}/outs/molecule_info.h5" >> \$aggcsv
    fi


    """
}



process aggregate {

    publishDir "${OUTDIR}/${projid}/aggregate/", mode: 'move', overwrite: true
  
    input:
    set projid, agg from craggregate.unique()
    val x from count_agg.collect()
    val y from countNuc_agg.collect()

    output:
    file "${projid}_agg" into doneagg

    when:
    agg == "y"

    """

    aggdir="$OUTDIR/$projid/aggregate"

    cellranger aggr \
       --id=${projid}_agg \
       --csv=\${aggdir}/${projid}_libraries.csv \
       --normalize=mapped

    """

}


