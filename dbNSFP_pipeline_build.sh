#!/bin/bash
## small bash script to download and reformat dbNSFP for pipeline 
## Miles Benton
## created: 2018-01-13
## modified: 2019-08-21
## Fixed 2024-11-07 peter.juvan@gmail.com

# Set to dbNSFP version to download and build
version="4.9a"
MD5SUM=be89346ab3dc5c14a8a7b602f50c66fb
#TODO: check MD5 Sum before proceeding
#TODO: add an option to 'scrape' this from the url to always return latest version

# define thread number for parallel processing where able
THREADS=$(cat /proc/cpuinfo |grep processor | wc -l) # Note: autodetect threads
WORKINGDIR="/data/"


download() {
	# Download dbNSFP database using aria2c with 5 connections 
	# aria2c -o dbNSFP${version}.zip -x 5 "ftp://dbnsfp:dbnsfp@dbnsfp.softgenetics.com/dbNSFP${version}.zip" # Old FTP server location
	aria2c -o dbNSFP${version}.zip -x 5 "https://dbnsfp.s3.amazonaws.com/dbNSFP${version}.zip"
}

decompress() { 
	echo "Uncompressing...."
	unzip -n dbNSFP${version}.zip
	# Note: skip existing so it runs fast if re-run
}

extract_header() { 
	echo "Extracting header..."
	zcat dbNSFP${version}_variant.chr1.gz | head -n 1 | bgzip > header.gz
}

custom_build() {
	# Create a single file version
	# NOTE: bgzip parameter -@ X represents number of threads
	if [ -f dbNSFPv${version}_custom.gz ] ; then
		echo "Found custom version ${version}, skipping custom_build..."
	else
		echo "Building hg38 version..."
		cat dbNSFP${version}_variant.*.gz | zgrep -v '#chr' | bgzip -@ ${THREADS} > dbNSFPv${version}_custom.gz

		# add header back into file
		cat header.gz dbNSFPv${version}_custom.gz > dbNSFPv${version}_custombuild.gz

		# Create tabix index
		tabix -s 1 -b 2 -e 2 dbNSFPv${version}_custombuild.gz

		# test annotation
		# java -jar ~/install/snpEff/SnpSift.jar dbnsfp -v -db /mnt/dbNSFP/hg19/dbNSFPv${version}_custombuild.gz test/chr1_test.vcf > test/chr1_test_anno.vcf
		#TODO: provide actual unit test files for testing purposes, i.e. a section of public data with known annotation rates.
		#TODO: the above is currently a placeholder but it had it's intended purpose in terms of identifying incorrect genome build. 

		## this section will produce data for hg19 capable pipelines
		# for hg19 (coordinate data is located in columns 8 [chr] and 9 [position])
		# this takes output from above, filters out any variants with no hg19 coords and then sorts on hg19 chr and position, and then bgzips output
		# NOTE: bgzip parameter -@ X represents number of threads
		echo "Building hg19 version..."

		zcat dbNSFPv${version}_custombuild.gz | \
		  awk '$8 != "."' | \
		  awk 'BEGIN{FS=OFS="\t"} {$1=$8 && $2=$9; NF--}1'| \
		  LC_ALL=C sort --parallel=${THREADS} -n -S 4G -T . -k 1,1 -k 2,2 --compress-program=gzip | \
		  bgzip -@ ${THREADS} > dbNSFPv${version}.hg19.custombuild.gz
		# NOTE: removed target memory allocation  

		# Create tabix index
		tabix -s 1 -b 2 -e 2 dbNSFPv${version}.hg19.custombuild.gz

		# test hg19 annotation
		# java -jar ~/install/snpEff/SnpSift.jar dbnsfp -v -db /mnt/dbNSFP/hg19/dbNSFPv${version}.hg19.custombuild.gz test/chr1_test.vcf > test/chr1_test_anno.vcf
	fi 
}

# Check that working directory exists 
if [ -d ${WORKINGDIR} ] ; then 
	echo "Found outdir...we're going to need a lot of free space, does it have more than 100GB free?"
	cd ${WORKINGDIR}
else
	echo "Please create ${WORKINGDIR} before continuing" 
	exit 
fi

if [ -f ${WORKINGDIR}/dbNSFP${version}.zip ] ; then
	echo "Found dbNSFP${version}.zip, skipping download..." 	
else
	echo "Didn't find file, downloading, this could take awhile"
	download
fi

decompress
extract_header
custom_build

# clean up
#TODO: add clean up step to rm all intermediate files after testing confirmed working (i.e. correct annotation 'rates')
