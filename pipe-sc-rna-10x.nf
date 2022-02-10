#!/usr/bin/env nextFlow

// Base params
runfolder = params.runfolder
basedir = params.basedir
metaid = params.metaid

// Output dirs
outdir = params.outdir
fqdir = params.fqdir
ctgqc = params.ctgqc

// Demux args
b2farg = params.bcl2fastqarg
index = params.index
demux = params.demux

// Read and process CTG samplesheet (must be plain .csv - not directly from excel)
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
    .map { row -> tuple( row.Sample_ID, row.Sample_Project, row.Sample_Species, row.nuclei, row.force, row.agg) }
    .tap{infoall}
    .into { crCount_csv; cragg_ch; mvfastq_csv }

// all samplesheet info
Channel
    .fromPath(chsheet)
    .splitCsv(header:true)
    .map { row -> tuple( row.Sample_Project, row.email, row.deliver) }
    .unique()
    .tap{delinfo}
    .into { deliveryInfo; deliver_auto }

// Projects
Channel
    .fromPath(chsheet)
    .splitCsv(header:true)
    .map { row -> row.Sample_Project }
    .unique()
    .tap{infoProject}
    .into { count_summarize; mqc_cha_init_uniq }

println " > Samples to process: "
println "[Sample_ID,Sample_Name,Sample_Project,Sample_Species,nuclei,forcecells,aggregate]"
infoall.subscribe { println "Info: $it" }

println " > Projects to process : "
println "[Sample_Project]"
infoProject.subscribe { println "Info Projects: $it" }

println " > Delivery mails "
println "[Project,Email]"
delinfo.subscribe { println "$it" }

process delivery_info {

	tag "$metaid"

	input:
	set projid, email, deliver from deliveryInfo

	"""
	mkdir -p ${outdir}/${projid}	
	deliveryinfo="${outdir}/${projid}/ctg-delivery.info.csv"
	echo "projid,${projid}" > \$deliveryinfo
	echo "email,${email}" >> \$deliveryinfo
	echo "pipeline,sc-rna-10x" >> \$deliveryinfo
	"""
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
	val "x" into demux_qc

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
    set sid, projid, ref, nuclei, force, agg from mvfastq_csv

    output:
    val "y" into crCount
    set sid, projid, ref, nuclei, force, agg into fqc_ch

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

// Channel to start analysis if demux == 'n'
// Projects
if ( demux == 'n' ) {
   Channel
	 .from("1")
	 .set{ crCount }
}

process count {

	tag "${sid}-${projid}"
	publishDir "${outdir}/${projid}/count-cr/", mode: "move", overwrite: true

	input: 
	val y from crCount.collect()
        set sid, projid, ref, nuclei, force, agg from crCount_csv

	output:
        file "${sid}/outs/" into samplename
        val "${outdir}/${projid}/qc/cellranger/${sid}.metrics_summary.csv" into count_metrics
	val "${outdir}/${projid}/aggregate/${sid}.molecule_info.h5" into count_agg

	script:
	// Set force-cells if force not "n"
	forcecells=""
	if ( force != "n" && force != "null" ) {
	   forcecells="--force-cells=" + force }

	// Set nuclei if nuclei is 'y'
	includeintrons=""
	if ( nuclei == "y" ) {
	   includeintrons="--include-introns" }

	// Get reference
	if ( ref == "Human" || ref == "human") {
	   genome=params.human }
	else if ( ref == "mouse" || ref == "Mouse") {
	   genome=params.mouse }
	else if ( ref == "hs-mm" || ref == "hsmm") {
	   genome=params.mixed_genome }   
	else if ( ref == "custom" || ref == "Custom") {
	   genome=params.custom_genome }
	else {
	   print ">ERROR: Species not recognized" 
	   genome="ERR" }

	// Set outdir
	prcountdir = outdir + projid + "/count-cr/"
	file(prcountdir).mkdir()   

	fastq_count = outdir + "/" + projid + "/fastq/" + sid 
	if ( demux == "n" ) {
	   fastq_count = fqdir 
        }
	   
	"""
	cellranger count \\
	     --id=$sid \\
	     --fastqs=${fastq_count} \\
	     --sample=$sid \\
             --project=$projid \\
	     --transcriptome=$genome \\
             --localcores=19 --localmem=120 \\
             $includeintrons $forcecells

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
        cp ${sid}/outs/cloupe.cloupe ${outdir}/${projid}/summaries/cloupe/${sid}.cloupe

	## Copy to CTG QC dir 
        cp ${sid}/outs/web_summary.html ${ctgqc}/${projid}/web-summaries/${sid}.web_summary.html

	"""

}

process fastqc {

	tag "${sid}-${projid}"

	input:
	set sid, projid, ref, nuclei, force, agg from fqc_ch	
        
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


// Run-based demux multiqc 
process multiqc_demux {

    tag "${projid}"

    input:
    val x from demux_qc

    script:
    """
    mkdir -p ${ctgqc}/${metaid}/
    mkdir -p ${ctgqc}/${metaid}/qc
    mkdir -p ${ctgqc}/${metaid}/qc/multiqc

    multiqc ${fqdir} -f --outdir ${ctgqc}/${metaid}/qc/multiqc -n DEMUXqc_${metaid}_multiqc_report.html

    """
}


// aggregation
process gen_aggCSV {

    tag "${sid}_${projid}"

    input:
    set sid, projid, ref, nuclei, force, agg from cragg_ch

    output:
    set projid, ref, agg into craggregate
    
    """

    if [ "$agg" == "y" ] && [ "$ref" != "hs-mm" ]; then
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
    else
        echo "No aggregation performed - agg != 'y'"
    fi
    """
}

process aggregate {

    tag "$projid"
  
    input:
    set projid, ref, agg from craggregate.unique()
    val moleculeinfo from count_agg.collect()

    output:
    val projid into md5_proj
    val "x" into md5_wait

    """
    if [ "$agg" == "y" ] && [ "$ref" != "hs-mm" ]; then
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

       ## Move output to delivery
       if [ -d \${aggdir}/${projid}_agg ]; then
           rm -r \${aggdir}/${projid}_agg
       fi
       mv ${projid}_agg \${aggdir}/

	## Remove the molecule_info.h5 files that are stored in the aggregate folder (the original files are still in count-cr/../outs 
    	rm ${outdir}/${projid}/aggregate/*h5
    else
        echo "No aggregation performed - agg != 'y'"
    fi

      
    """

}

process md5sum {

	input:
	val x from md5_wait.collect()
        set projid, projid2 from md5_proj.unique().phase(multiqc_outch.unique())


	output:
	val "md5done" into md5done

	"""
	cd ${outdir}/${projid}/
	find -type f -exec md5sum '{}' \\; > ctg-md5.${projid}.txt

        """ 

}

process deliverAuto {

	input:
	set projid, email, deliver from deliver_auto
	val "md5" from md5done

	output:
	val "sent" into deliverDone

	when:
	deliver == "y"

	"""

	cd ${outdir}

	bash $basedir/bin/ctg-deliver-sc-rna-10x.sh -u per -d ${projid}

	"""
	

}

// write to cronlog when pipeline is ready
process sc_rna_10x_done {
	
	input:
	val mdone from deliverDone

	""" 

	touch $runfolder/ctg.sc-rna-10x.done

	cronlog="/projects/fs1/shared/ctg-cron/ctg-sc-rna-10x-cron/cron-ctg-sc-rna-10x.log"
	cronlog_all="/projects/fs1/shared/ctg-cron/ctg-cron.log"
	
	rf=\$(basename $runfolder)
  	echo "\$(date): \$rf: DONE: sc-rna-10x" >> \$cronlog
    	echo "\$(date): \$rf: DONE: sc-rna-10x" >> \$cronlog_all

	"""

}