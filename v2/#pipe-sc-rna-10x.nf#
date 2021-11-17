#!/usr/bin/env nextFlow

// Base params
runfolder = params.runfolder
basedir = params.basedir
metaid = params.metaid

// Output dirs
outdir = params.outdir
outmeta = params.outmeta
fqdir = params.fqdir
ctgqc = params.ctgqc

// Demux args
b2farg = params.bcl2fastqarg
index = params.index
demux = params.demux

// Read and process CTG samplesheet 
sheet = file(params.sheet)

println "============================="
println ">>> sc-rna-10x pipeline for multiple projects / run >>>"
println ""
println "> INPUT: "
println ""
println "> runfolder		: $runfolder "
println "> sample-sheet		: $sheet "
println "> run-meta-id		: $metaid "
println "> basedir		: $basedir "
println ""
println " - demultiplexing arguments "
println "> bcl2fastq-arg        : '${b2farg}' "
println "> demux                : $demux " 
println "> index                : $index "
println ""
println "> - output directories "
println "> output-dir           : $outdir "
println "> output-meta          : $outmeta "
println "> fastq-dir            : $fqdir "
println "> ctg-qc-dir           : $ctgqc "
println "============================="

// set new samplesheets for channels and demux
chsheet = file("$basedir/sample-sheet.nf.channel.csv")
demuxsheet = file("$basedir/sample-sheet.nf.demux.csv")

// Read and process sample sheet                                                                                                          
all_lines = sheet.readLines()
write_b = false // if next lines has sample info
chsheet.text=""

for ( line in all_lines ) { 
    if ( write_b ) {
        chsheet.append(line + "\n")
	}
    if (line.contains("[Data]")){
        write_b = true
    }
}   

// all samplesheet info
Channel
    .fromPath(chsheet)
    .splitCsv(header:true)
    .map { row -> tuple( row.Sample_ID, row.Sample_Project, row.Sample_Species, row.nuclei) }
    .tap{infoall}
    .into { crCount_csv; cragg_ch; mvfastq_csv }

// Projects
Channel
    .fromPath(chsheet)
    .splitCsv(header:true)
    .map { row -> row.Sample_Project }
    .unique()
    .tap{infoProject}
    .into { count_summarize; mqc_cha_init_uniq }

println " > Samples to process: "
println "[Sample_ID,Sample_Name,Sample_Project,Sample_Species,nuclei]"
infoall.subscribe { println "Info: $it" }

println " > Projects to process : "
println "[Sample_Project]"
infoProject.subscribe { println "Info Projects: $it" }


// Channel to start count if demux == 'n'
if ( demux == 'n' ) {
   Channel
	 .from("1")
    	 .set{ crCount }
}

// Parse samplesheet
process parsesheet {

	tag "$metaid"

	input:
	val chsheet
	val index

	output:
	val demuxsheet into demux_sheet

	when:
	demux == 'y'

	"""
python $basedir/bin/ctg-parse-samplesheet.10x.py -s $chsheet -o $demuxsheet -i $index
	"""
}

	

// Run mkFastq
process mkfastq {

	tag "$metaid"

	input:
        val sheet from demux_sheet

	output:
	val 1 into moveFastq

	when:
	demux == 'y'

	"""
cellranger mkfastq \\
	   --id=$metaid \\
	   --run=$runfolder \\
	   --samplesheet=$sheet \\
	   --jobmode=local \\
	   --localmem=100 \\
	   --output-dir $fqdir \\
	   $b2farg
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
    mkdir -p ${outdir}/${projid}
    mkdir -p ${outdir}/${projid}/fastq

    mkdir -p ${outdir}/${projid}/fastq/$sid

    if [ -d ${fqdir}/${projid}/$sid ]; then
        mv ${fqdir}/${projid}/$sid ${outdir}/${projid}/fastq/
    else
	mv ${fqdir}/${projid}/${sid}_S* ${outdir}/${projid}/fastq/$sid/
    fi
    """

}

process count {

	tag "${sid}-${projid}"
	publishDir "${outdir}/${projid}/count-cr/", mode: "copy", overwrite: true

	input: 
	val sheet
	val y from crCount.collect()
        set sid, projid, ref, nuclei from crCount_csv

	output:
        file "${sid}/outs/" into samplename
        val "${outdir}/${projid}/qc/cellranger/${sid}.metrics_summary.csv" into count_metrics
	val "${outdir}/${projid}/aggregate/${sid}.molecule_info.h5" into count_agg

	script:
	if ( ref == "Human" || ref == "human") {
	   genome=params.human 
	   }	   
	else if ( ref == "mouse" || ref == "Mouse") {
	   genome=params.mouse
	   }
	else if ( ref == "custom" || ref == "Custom") {
	   genone=params.custom_genome
	   }
	else {
	   print ">ERROR: Species not recognized" 
	   genome="ERR"
	   }

	prcountdir = outdir + projid + "/count-cr/"
	file(prcountdir).mkdir()   

	if ( nuclei == "y" ) 
		"""
		cellranger count \\
	     --id=$sid \\
	     --fastqs=${outdir}/$projid/fastq/$sid \\
	     --sample=$sid \\
	     --include-introns \\
             --project=$projid \\
	     --transcriptome=\$genome \\
             --localcores=20 --localmem=128 
	     """
	else
	"""
		cellranger count \\
	     --id=$sid \\
	     --fastqs=${outdir}/$projid/fastq/$sid \\
	     --sample=$sid \\
             --project=$projid \\
	     --transcriptome=\$genome \\
             --localcores=20 --localmem=128 
"""

	"""
        mkdir -p ${outdir}
        mkdir -p ${outdir}/${projid}
        mkdir -p ${outdir}/${projid}/summaries
        mkdir -p ${outdir}/${projid}/summaries/cloupe
        mkdir -p ${outdir}/${projid}/summaries/web-summaries

	mkdir -p ${ctgqc}/${projid}
	mkdir -p ${ctgqc}/${projid}/web-summaries

	## Copy h5 file for aggregation
	aggdir=$outdir/$projid/aggregate
	mkdir -p \$aggdir
	cp ${sid}/outs/molecule_info.h5 ${outdir}/${projid}/aggregate/${sid}.molecule_info.h5

	## Copy metrics file for qc
	# Remove if it exists
	if [ -f ${outdir}/${projid}/qc/cellranger/${sid}.metrics_summary.csv ]; then
	    rm -r ${outdir}/${projid}/qc/cellranger/${sid}.metrics_summary.csv
	fi
	mkdir -p ${outdir}/${projid}/qc/
	mkdir -p ${outdir}/${projid}/qc/cellranger/

        cp ${sid}/outs/metrics_summary.csv ${outdir}/${projid}/qc/cellranger/${sid}.metrics_summary.csv

	## Copy to delivery folder 
        cp ${sid}/outs/web_summary.html ${outdir}/${projid}/summaries/web-summaries/${sid}.web_summary.html
        cp ${sid}/outs/cloupe.cloupe ${outdir}/${projid}/summaries/cloupe/${sid}_cloupe.cloupe

	## Copy to CTG QC dir 
        cp ${sid}/outs/web_summary.html ${ctgqc}/${projid}/web-summaries/${sid}.web_summary.html

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

        mkdir -p ${outdir}/${projid}/qc
        mkdir -p ${outdir}/${projid}/qc/fastqc

        for file in ${outdir}/${projid}/fastq/${sid}/*fastq.gz
            do fastqc -t ${task.cpus} \$file --outdir=${outdir}/${projid}/qc/fastqc
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

	cd $outdir/$projid
	mkdir -p ${outdir}/${projid}/
	mkdir -p ${outdir}/${projid}/qc
	mkdir -p ${outdir}/${projid}/qc/cellranger
	
	python $basedir/bin/ctg-sc-count-metrics-concat.py -i ${outdir}/${projid}/ -o ${outdir}/${projid}/qc/cellranger

	# Copy to summaries delivery folder
	cp ${outdir}/${projid}/qc/cellranger/ctg-cellranger-count-summary_metrics.csv ${outdir}/${projid}/summaries/web-summaries/
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
    
    cd $outdir/$projid
    multiqc -f ${outdir}/$projid  --outdir ${outdir}/$projid/qc/multiqc/ -n ${projid}_multiqc_report.html

    mkdir -p ${ctgqc}
    mkdir -p ${ctgqc}/$projid

    cp -r ${outdir}/$projid/qc ${ctgqc}/$projid/

    """
}

process multiqc_count_run {

    tag "${metaid}"

    input:
    val x from run_summarize.collect()
        
    output:
    val "x" into summarized

    """
    cd $outdir 
    multiqc -f ${fqdir} ${outdir}/*/qc/cellranger/ --outdir ${ctgqc}/${metaid}/ -n ${metaid}_run_sc-rna-10x_summary_multiqc_report.html

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
    aggdir=$outdir/$projid/aggregate
    mkdir -p \$aggdir
    aggcsv=\$aggdir/${projid}_libraries.csv
    if [ -f \$aggcsv ]
    then
        if grep -q $sid \$aggcsv
        then
             echo ""
        else
             sleep 3 
             echo "${sid},${outdir}/${projid}/aggregate/${sid}.molecule_info.h5" >> \$aggcsv
        fi
    else
        echo "sample_id,molecule_h5" > \$aggcsv
	sleep 2
        echo "${sid},${outdir}/${projid}/aggregate/${sid}.molecule_info.h5" >> \$aggcsv
    fi

    """
}

process aggregate {

    publishDir "${outdir}/${projid}/aggregate/", mode: 'move', overwrite: true
    tag "$projid"
  
    input:
    val projid from craggregate.unique()
    val moleculeinfo from count_agg.collect()

    output:
    file "${projid}_agg/outs" into doneagg
    val projid into md5_proj
    val "x" into md5_wait

    """
    aggdir="$outdir/$projid/aggregate"

    cellranger aggr \
       --id=${projid}_agg \
       --csv=\${aggdir}/${projid}_libraries.csv \
       --normalize=mapped

    ## Copy to delivery folder 
    cp ${projid}_agg/outs/web_summary.html ${outdir}/${projid}/summaries/web-summaries/${projid}_agg.web_summary.html
    cp ${projid}_agg/outs/count/cloupe.cloupe ${outdir}/${projid}/summaries/cloupe/${projid}_agg_cloupe.cloupe
    
    ## Copy to CTG QC dir 
    cp ${outdir}/${projid}/summaries/web-summaries/${projid}_agg.web_summary.html ${ctgqc}/${projid}/web-summaries/
    cp ${outdir}/${projid}/summaries/cloupe/${projid}_agg_cloupe.cloupe ${ctgqc}/${projid}/web-summaries/

    ## Remove the molecule_info.h5 files that are stored in the aggregate folder (the original files are still in count-cr/../outs 
    rm ${outdir}/${projid}/aggregate/*h5

    """

}

process md5sum {

	input:
	val projid from md5_proj.unique()
	val x from md5_wait.collect()
	
	"""
	cd ${outdir}/${projid}/
	find -type f -exec md5sum '{}' \\; > ctg-md5.${projid}.txt

	touch $runfolder/ctg.sc-rna-10x.done
        """ 

}