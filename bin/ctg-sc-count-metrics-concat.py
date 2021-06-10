#!/usr/bin/python3.4

import pandas as pd
import numpy as np
import sys, getopt
import os

def main(argv):
    projdir = ''
    outputdir = ''

    usage='> Usage: ctg-sc-count-mterics-concat.py -i PROJECT-OUTDIR -o SUMMARY-OUTDIR'

    try:
        opts, args = getopt.getopt(argv,"hi:o:",["projdir=", "outdir="])
    except getopt.GetoptError:
        print(usage)
        sys.exit(2)
    if len(sys.argv) <= 2:
        print("> Error: No project dir / output dir entered:")
        print(usage)
        sys.exit()
    for opt, arg in opts:
        if opt == '-h':
            print(usage)
            sys.exit()
        elif opt in ("-i", "--projdir"):
            projdir = arg
        elif opt in ("-o", "--outdir"):
            outputdir = arg

    out1 = outputdir + "/ctg-cellranger-count-summary_metrics.csv"
    out2 = outputdir + "/cellranger-count_summary_metrics_mqc.csv"

    projid=os.path.basename(os.path.normpath(projdir))

    # list all metricsfiles
    samples = os.listdir(projdir + '/count-cr/')

    # get id of metricfile
    sname = samples[0]
    fname = projdir + "/qc/cellranger/" + sname + ".metrics_summary.csv"
    final = pd.read_csv(fname)
    final.index = [projid + "-" + sname]

    # concatenate all sample tables to one
    for sname in samples[1:]:
        fname = projdir + "/qc/cellranger/" + sname + ".metrics_summary.csv"
        data = pd.read_csv(fname)
        data.index = [projid + "-" + sname]
        final = pd.concat([final,data],axis=0)
    
    # Write csv file        
    cols = final.columns.tolist()
    cols = list( cols[i] for i in [0,1,2,3,17,18,4,5,6,7,8,9,10,11,12,13,14,15,16] )
    final = final[cols]
    final.replace(",","",regex=True)
    final.index.name = "Sample"
    final.to_csv(out1,sep=",")

    # Parse csv file to mqc
    # parse % input
    def p2f(x):
        return float(x.strip('%'))
    # parse integers with comma
    def s2i(x):
        return int(x.replace(",",""))

    mqdf = pd.read_csv(out1,
                       converters={'Estimated Number of Cells':s2i,
                                   'Mean Reads per Cell':s2i,
                                   'Median Genes per Cell':s2i,
                                   'Number of Reads':s2i,
                                   'Total Genes Detected':s2i,
                                   'Median UMI Counts per Cell':s2i,
                                   'Valid Barcodes':p2f,
                                   'Sequencing Saturation':p2f,
                                   'Q30 Bases in Barcode':p2f,
                                   'Q30 Bases in RNA Read':p2f,
                                   'Q30 Bases in UMI':p2f,
                                   'Reads Mapped to Genome':p2f,
                                   'Reads Mapped Confidently to Genome':p2f,
                                   'Reads Mapped Confidently to Intergenic Regions':p2f,
                                   'Reads Mapped Confidently to Intronic Regions':p2f,
                                   'Reads Mapped Confidently to Exonic Regions':p2f,
                                   'Reads Mapped Confidently to Transcriptome':p2f,
                                   'Reads Mapped Antisense to Gene':p2f,
                                   'Fraction Reads in Cells':p2f
                               })
    
    orig_cols = mqdf.columns
    mqdf.columns = ['SampleID','col2','col3','col4','col5','col6','col7','col8','col9','col10','col11','col12','col13','col14','col15','col16','col17','col18','col19','col20']
    
    f = open(out2,'a')
    f.write("# plot_type: 'table'" + "\n")
    f.write("# section_name: 'Cellranger Metrics'\n")
    f.write("# description: 'Cellranger 10x-RNA count metrics'\n")
    f.write("# pconfig:\n")
    f.write("#     namespace: 'CTG'\n") 
    f.write("# headers:\n")
    f.write("#     col1:\n")
    f.write("#         title: 'Sample'\n")
    f.write("#         description: 'CTG Project ID - Sample ID'\n")
    f.write("#     col2:\n")
    f.write("#         title: 'Estimated Number of Cells'\n")
    f.write("#         description: 'Estimated number of cells'\n")
    f.write("#         format: '{:.0f}'\n")
    f.write("#     col3:\n")
    f.write("#         title: 'Mean Reads per Cell'\n")
    f.write("#         description: 'Mean Reads per Cell'\n")
    f.write("#         format: '{:.0f}'\n")
    f.write("#     col4:\n")
    f.write("#         title: 'Median Genes per Cell'\n")
    f.write("#         description: 'Median Genes per Cell'\n")
    f.write("#         format: '{:.0f}'\n")
    f.write("#     col5:\n")
    f.write("#         title: 'Number of Reads'\n")
    f.write("#         description: 'Number of Reads'\n")
    f.write("#         format: '{:.0f}'\n")
    f.write("#     col6:\n")
    f.write("#         title: 'Total Genes Detected'\n")
    f.write("#         description: 'Total Genes Detected'\n")
    f.write("#         format: '{:.0f}'\n")
    f.write("#     col7:\n")
    f.write("#         title: 'Median UMI Counts per Cell'\n")
    f.write("#         description: 'Median UMI Counts per Cell'\n")
    f.write("#         format: '{:.0f}'\n")
    f.write("#     col8:\n")
    f.write("#         title: 'Valid Barcodes'\n")
    f.write("#         description: 'Valid Barcodes'\n")
    f.write("#         min: 0 \n")
    f.write("#         max: 100 \n")
    f.write("#         format: '{:.1f}'\n")
    f.write("#         suffix: '%'\n")
    f.write("#     col9:\n")
    f.write("#         title: 'Sequencing Saturation'\n")
    f.write("#         description: 'Sequencing Saturation'\n")
    f.write("#         format: '{:.1f}'\n")
    f.write("#         suffix: '%'\n")
    f.write("#         min: 0 \n")
    f.write("#         max: 100 \n")
    f.write("#     col10:\n")
    f.write("#         title: 'Q30 Bases in Barcode'\n")
    f.write("#         description: 'Q30 Bases in Barcode'\n")
    f.write("#         format: '{:.1f}'\n")
    f.write("#         suffix: '%'\n")
    f.write("#         min: 0 \n")
    f.write("#         max: 100 \n")
    f.write("#     col11:\n")
    f.write("#         title: 'Q30 Bases in RNA Read'\n")
    f.write("#         description: 'Q30 Bases in RNA Read'\n")
    f.write("#         format: '{:.1f}'\n")
    f.write("#         suffix: '%'\n")
    f.write("#         min: 0 \n")
    f.write("#         max: 100 \n")
    f.write("#     col12:\n")
    f.write("#         title: 'Q30 Bases in UMI'\n")
    f.write("#         description: 'Q30 Bases in UMI'\n")
    f.write("#         format: '{:.1f}'\n")
    f.write("#         suffix: '%'\n")
    f.write("#         min: 0 \n")
    f.write("#         max: 100 \n")
    f.write("#     col13:\n")
    f.write("#         title: 'Reads Mapped to Genome'\n")
    f.write("#         description: 'Reads Mapped to Genome'\n")
    f.write("#         format: '{:.1f}'\n")
    f.write("#         suffix: '%'\n")
    f.write("#         min: 0 \n")
    f.write("#         max: 100 \n")
    f.write("#     col14:\n")
    f.write("#         title: 'Reads Mapped Confidently to Genome'\n")
    f.write("#         description: 'Reads Mapped Confidently to Genome'\n")
    f.write("#         format: '{:.1f}'\n")
    f.write("#         suffix: '%'\n")
    f.write("#         min: 0 \n")
    f.write("#         max: 100 \n")
    f.write("#     col15:\n")
    f.write("#         title: 'Reads Mapped Confidently to Intergenic Regions'\n")
    f.write("#         description: 'Reads Mapped Confidently to Intergenic Regions'\n")
    f.write("#         format: '{:.1f}'\n")
    f.write("#         suffix: '%'\n")
    f.write("#         min: 0 \n")
    f.write("#         max: 100 \n")
    f.write("#     col16:\n")
    f.write("#         title: 'Reads Mapped Confidently to Intronic Regions'\n")
    f.write("#         description: 'Reads Mapped Confidently to Intronic Regions'\n")
    f.write("#         format: '{:.1f}'\n")
    f.write("#         suffix: '%'\n")
    f.write("#         min: 0 \n")
    f.write("#         max: 100 \n")
    f.write("#     col17:\n")
    f.write("#         title: 'Reads Mapped Confidently to Exonic Regions'\n")
    f.write("#         description: 'Reads Mapped Confidently to Exonic Regions'\n")
    f.write("#         format: '{:.1f}'\n")
    f.write("#         suffix: '%'\n")
    f.write("#         min: 0 \n")
    f.write("#         max: 100 \n")
    f.write("#     col18:\n")
    f.write("#         title: 'Reads Mapped Confidently to Transcriptome'\n")
    f.write("#         description: 'Reads Mapped Confidently to Transcriptome'\n")
    f.write("#         format: '{:.1f}'\n")
    f.write("#         suffix: '%'\n")
    f.write("#         min: 0 \n")
    f.write("#         max: 100 \n")
    f.write("#     col19:\n")
    f.write("#         title: 'Reads Mapped Antisense to Gene'\n")
    f.write("#         description: 'Reads Mapped Antisense to Gene'\n")
    f.write("#         format: '{:.1f}'\n")
    f.write("#         suffix: '%'\n")
    f.write("#         min: 0 \n")
    f.write("#         max: 100 \n")
    f.write("#     col20:\n")
    f.write("#         title: 'Percentage Reads in Cells'\n")
    f.write("#         description: 'Fraction Reads in Cells'\n")
    f.write("#         format: '{:.1f}'\n")
    f.write("#         suffix: '%'\n")
    f.write("#         min: 0 \n")
    f.write("#         max: 100 \n")
    mqdf.to_csv(f,sep="\t",index=False)
    f.close()
    
if __name__ == "__main__":
    main(sys.argv[1:])
