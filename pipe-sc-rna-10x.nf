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
index = params.index

// Read and process CTG samplesheet 
sheet = file(params.sheet)

// create new samplesheet in cellranger mkfastq IEM (--samplesheet) format. This will be used only for demultiplexing
newsheet = "$basedir/samplesheet.nf.sc-rna-10x.csv"

println "============================="
println ">>> sc-rna-10x pipeline for multiple projects / run >>>"
println ""
println "> INPUT: "
println "> runfolder		: $exp "
println "> sample-sheet		: $sheet "
println "> run-meta-id		: $metaID "
println "> basedir		: $basedir "
println "> bcl2fastq-arg        : '${b2farg}' "
println "> demux                : $demux " 
println "> index                : $index "
println ""
println "> OUTPUT: "
println "> output-dir           : $OUTDIR "
println "> fastq-dir            : $FQDIR "
println "> ctg-qc-dir           : $CTGQC "
println "============================="


// all samplesheet info
Channel
    .fromPath(sheet)
    .splitCsv(header:true)
    .map { row -> tuple( row.Sample_ID, row.Sample_Project, row.Sample_Species, row.nuclei) }
    .tap{infoall}
    .into { crCount_csv; cragg_ch; mvfastq_csv }

// Projects
Channel
    .fromPath(sheet)
    .splitCsv(header:true)
    .map { row -> row.Sample_Project }
    .unique()
    .tap{infoProject}
    .into { count_summarize; mqc_cha_init_uniq }


// Channel to start count if demux == 'n'
if ( demux == 'n' ) {
   Channel
	 .from("1")
    	 .set{ crCount }
}

println " > Samples to process: "
println "[Sample_ID,Sample_Name,Sample_Project,Sample_Species,nuclei]"
infoall.subscribe { println "Info: $it" }

println " > Projects to process : "
println "[Sample_Project]"
infoProject.subscribe { println "Info Projects: $it" }

// Parse samplesheet
process parsesheet {

	tag "$metaID"

	input:
	val sheet
	val index

	output:
	val newsheet into demux_sheet

	when:
	demux == 'y'

	"""
#!/opt/conda/bin/python

# import libs
import csv

with open(\'$newsheet\', 'w', newline='') as outfile:
    writer = csv.writer(outfile)
    writer.writerow(['[Data]'])
    
    if \'$index\' == 'dual':
        writer.writerow(['Lane','Sample_ID','Sample_Name','Sample_Plate','Sample_Well','I7_Index_ID','index','I5_Index_ID','index2','Sample_Project'])
    else:
        writer.writerow(['Lane','Sample_ID','index','Sample_Project'])

    with open(\'$sheet\', 'r') as infile:
        my_reader = csv.reader(infile, delimiter=',')
        # row counter to define first line
        row_idx=0
        for row in my_reader:
            # if first line - get index of the 3 columns needed
            if row_idx == 0:
                laneidx = row.index('Lane')
                sididx  = row.index('Sample_ID')
                idxidx  = row.index('index')
                projidx = row.index('Sample_Project')
            else:
                currlane = row[laneidx]
                currsid = row[sididx]
                curridx = row[idxidx]
                currproj = row[projidx]

                if \'$index\' == 'dual':
                    writer.writerow([currlane,currsid,currsid,'','',curridx,curridx,curridx,curridx,currproj])
                else:
                    writer.writerow([currlane,currsid,curridx,currproj])

		   
            row_idx += 1

	"""
}

	

// Run mkFastq
process mkfastq {

	tag "$metaID"

	input:
        val sheet from demux_sheet

	output:
	val 1 into moveFastq

	when:
	demux == 'y'

	"""
cellranger mkfastq \\
	   --id=$metaID \\
	   --run=$exp \\
	   --samplesheet=$sheet \\
	   --jobmode=local \\
	   --localmem=100 \\
	   --output-dir $FQDIR \\
	   $b2farg


## multiqc on all fastq (mkfastq check)
multiqc -f ${FQDIR} --outdir ${CTGQC}/$metaID/ -n ${metaID}_mkfastq_multiqc.report.html

"""

}

process moveFastq {

    tag "${sid}-${projid}"

    input:
    val x from moveFastq
    set sid, projid, ref, nuclei from mvfastq_csv

    output:
    val "y" into crCount
    set sid, projid, ref, nuclei into fqc_ch

    when:
    demux = 'y'

    """
    mkdir -p ${OUTDIR}/${projid}
    mkdir -p ${OUTDIR}/${projid}/fastq

    mkdir -p ${OUTDIR}/${projid}/fastq/$sid

    if [ -d ${FQDIR}/${projid}/$sid ]; then
        mv ${FQDIR}/${projid}/$sid ${OUTDIR}/${projid}/fastq/
    else
	mv ${FQDIR}/${projid}/$sid* ${OUTDIR}/${projid}/fastq/$sid/
    fi
    """

}

process count {

	tag "${sid}-${projid}"
	publishDir "${OUTDIR}/${projid}/count-cr/", mode: "copy", overwrite: true

	input: 
	val sheet
	val y from crCount.collect()
        set sid, projid, ref, nuclei from crCount_csv

	output:
        file "${sid}/outs/" into samplename
        val "${OUTDIR}/${projid}/qc/cellranger/${sid}.metrics_summary.csv" into count_metrics
	val "${OUTDIR}/${projid}/aggregate/${sid}.molecule_info.h5" into count_agg

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

	if [ $nuclei == "y" ]
	then
		cellranger count \\
	     --id=$sid \\
	     --fastqs=${OUTDIR}/$projid/fastq/$sid \\
	     --sample=$sid \\
	     --include-introns \\
             --project=$projid \\
	     --transcriptome=\$genome \\
             --localcores=20 --localmem=110 
	else
		cellranger count \\
	     --id=$sid \\
	     --fastqs=${OUTDIR}/$projid/fastq/$sid \\
	     --sample=$sid \\
             --project=$projid \\
	     --transcriptome=\$genome \\
             --localcores=20 --localmem=110 
	fi

        mkdir -p ${OUTDIR}
        mkdir -p ${OUTDIR}/${projid}
        mkdir -p ${OUTDIR}/${projid}/summaries
        mkdir -p ${OUTDIR}/${projid}/summaries/cloupe
        mkdir -p ${OUTDIR}/${projid}/summaries/web-summaries

	mkdir -p ${CTGQC}/${projid}
	mkdir -p ${CTGQC}/${projid}/web-summaries

	## Copy h5 file for aggregation
	aggdir=$OUTDIR/$projid/aggregate
	mkdir -p \$aggdir
	cp ${sid}/outs/molecule_info.h5 ${OUTDIR}/${projid}/aggregate/${sid}.molecule_info.h5

	## Copy metrics file for qc
	# Remove if it exists
	if [ -f ${OUTDIR}/${projid}/qc/cellranger/${sid}.metrics_summary.csv ]; then
	    rm -r ${OUTDIR}/${projid}/qc/cellranger/${sid}.metrics_summary.csv
	fi
	mkdir -p ${OUTDIR}/${projid}/qc/
	mkdir -p ${OUTDIR}/${projid}/qc/cellranger/

        cp ${sid}/outs/metrics_summary.csv ${OUTDIR}/${projid}/qc/cellranger/${sid}.metrics_summary.csv

	## Copy to delivery folder 
        cp ${sid}/outs/web_summary.html ${OUTDIR}/${projid}/summaries/web-summaries/${sid}.web_summary.html
        cp ${sid}/outs/cloupe.cloupe ${OUTDIR}/${projid}/summaries/cloupe/${sid}_cloupe.cloupe

	## Copy to CTG QC dir 
        cp ${sid}/outs/web_summary.html ${CTGQC}/${projid}/web-summaries/${sid}.web_summary.html

	"""

}

process fastqc {

	tag "${sid}-${projid}"

	input:
	set sid, projid, ref, nuclei from fqc_ch	
        
        output:
        val projid into mqc_cha
	val "x" into mqc_cha_init

	"""

        mkdir -p ${OUTDIR}/${projid}/qc
        mkdir -p ${OUTDIR}/${projid}/qc/fastqc

        for file in ${OUTDIR}/${projid}/fastq/${sid}/*fastq.gz
            do fastqc -t ${task.cpus} \$file --outdir=${OUTDIR}/${projid}/qc/fastqc
        done
	"""
    
}

process summarize_count {

	tag "${projid}"

	input:
	val metrics from count_metrics.collect()
	val projid from count_summarize 

	output:
	val projid into mqc_count 	
	val "x" into run_summarize

	"""

	cd $OUTDIR/$projid
	mkdir -p ${OUTDIR}/${projid}/
	mkdir -p ${OUTDIR}/${projid}/qc
	mkdir -p ${OUTDIR}/${projid}/qc/cellranger
	
	python $basedir/bin/ctg-sc-count-metrics-concat.py -i ${OUTDIR}/${projid}/ -o ${OUTDIR}/${projid}/qc/cellranger

	# Copy to summaries delivery folder
	cp ${OUTDIR}/${projid}/qc/cellranger/ctg-cellranger-count-summary_metrics.csv ${OUTDIR}/${projid}/summaries/web-summaries/

	"""
}
	
// Project specific multiqc 
process multiqc {

    tag "${projid}"

    input:
    set projid, projid2 from mqc_cha.unique().phase(mqc_count.unique())

    output:
    val projid into multiqc_outch

    script:
    """
    
    cd $OUTDIR/$projid
    multiqc -f ${OUTDIR}/$projid -f --outdir ${OUTDIR}/$projid/qc/multiqc/ -n ${projid}_multiqc_report.html

    mkdir -p ${CTGQC}
    mkdir -p ${CTGQC}/$projid

    cp -r ${OUTDIR}/$projid/qc ${CTGQC}/$projid/

    """
}

process multiqc_count_run {

    tag "${metaID}"

    input:
    val x from run_summarize.collect()
        
    output:
    val "x" into summarized

    """
    cd $OUTDIR 
    multiqc -f ${FQDIR} ${OUTDIR}/*/qc/cellranger/ --outdir ${CTGQC} -n ${metaID}_run_sc-rna-10x_summary_multiqc_report.html

    """

}

// aggregation
process gen_aggCSV {

    tag "${sid}_${projid}"

    input:
    set sid, projid, ref, nuclei from cragg_ch

    output:
    val projid into craggregate

    """
    
    aggdir=$OUTDIR/$projid/aggregate

    mkdir -p \$aggdir

    aggcsv=\$aggdir/${projid}_libraries.csv

    if [ -f \$aggcsv ]
    then
        if grep -q $sid \$aggcsv
        then
             echo ""
        else
             echo "${sid},${OUTDIR}/${projid}/aggregate/${sid}.molecule_info.h5" >> \$aggcsv
        fi
    else
        echo "sample_id,molecule_h5" > \$aggcsv
        echo "${sid},${OUTDIR}/${projid}/aggregate/${sid}.molecule_info.h5" >> \$aggcsv
    fi


    """
}

process aggregate {

    publishDir "${OUTDIR}/${projid}/aggregate/", mode: 'move', overwrite: true
    tag "$projid"
  
    input:
    val projid from craggregate.unique()
    val moleculeinfo from count_agg.collect()

    output:
    file "${projid}_agg/outs" into doneagg
    val projid into md5_proj
    val "x" into md5_wait

    """

    aggdir="$OUTDIR/$projid/aggregate"

    cellranger aggr \
       --id=${projid}_agg \
       --csv=\${aggdir}/${projid}_libraries.csv \
       --normalize=mapped

    ## Copy to delivery folder 
    cp ${projid}_agg/outs/web_summary.html ${OUTDIR}/${projid}/summaries/web-summaries/${projid}_agg.web_summary.html
    cp ${projid}_agg/outs/count/cloupe.cloupe ${OUTDIR}/${projid}/summaries/cloupe/${projid}_agg_cloupe.cloupe
    
    ## Copy to CTG QC dir 
    cp ${OUTDIR}/${projid}/summaries/web-summaries/${projid}_agg.web_summary.html ${CTGQC}/${projid}/web-summaries/
    cp ${OUTDIR}/${projid}/summaries/cloupe/${projid}_agg_cloupe.cloupe ${CTGQC}/${projid}/web-summaries/

    ## Remove the molecule_info.h5 files that are stored in the aggregate folder (the original files are still in count-cr/../outs 
    rm ${OUTDIR}/${projid}/aggregate/*h5

    """

}

process md5sum {

	input:
	val projid from md5_proj.unique()
	val x from md5_wait.collect()
	
	"""
	cd ${OUTDIR}/${projid}/
	find -type f -exec md5sum '{}' \\; > ctg-md5.${projid}.txt
        """ 

}