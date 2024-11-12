##############################
# STAGE 1 - download databases
##############################
FROM alpine/git as intermediate
#RUN git clone https://github.com/konradjk/loftee.git /loftee
RUN git clone --single-branch --branch grch38 https://github.com/konradjk/loftee.git /loftee

#### TODO FIX
# [cmg@vglogin0002 vcfNormFilterMerge]$ cat d081e13a-dc8c-40b9-8cd7-68f4a23bc19e/call-RunVEP/shard-3109/attempt-3/execution/chrX__142929403_143929403.SGP9427_nrmFlt0.1Mrgd_ClinVar_vep.vcf.gz_warnings.txt 
# WARNING: 590533 : WARNING: Plugin 'LoF' went wrong: tabix /vep/loftee/GERP_scores.final.sorted.txt.gz does not exist at /opt/vep/.vep/Plugins/loftee/gerp_dist.pl line 72.
# WARNING: Plugin 'LoF' went wrong: tabix /vep/loftee/GERP_scores.final.sorted.txt.gz does not exist at /opt/vep/.vep/Plugins/loftee/gerp_dist.pl line 72.


##############################
# STAGE 2 - Download loftee DBs
##############################
FROM alpine as download_loftee
RUN wget https://personal.broadinstitute.org/konradk/loftee_data/GRCh38/human_ancestor.fa.gz -Y off
RUN wget https://personal.broadinstitute.org/konradk/loftee_data/GRCh38/human_ancestor.fa.gz.fai -Y off
RUN wget https://personal.broadinstitute.org/konradk/loftee_data/GRCh38/human_ancestor.fa.gz.gzi -Y off
RUN wget https://personal.broadinstitute.org/konradk/loftee_data/GRCh38/gerp_conservation_scores.homo_sapiens.GRCh38.bw -Y off
RUN wget https://personal.broadinstitute.org/konradk/loftee_data/GRCh38/loftee.sql.gz -Y off
RUN gunzip loftee.sql.gz
RUN wget https://personal.broadinstitute.org/konradk/loftee_data/GRCh37/phylocsf_gerp.sql.gz -Y off

##############################
# STAGE 3 - build dbNSFP recent version
# Code for script obtained from https://github.com/GenomicsAotearoa/dbNSFP_build
# Need to update version @ dbNSFP_pipeline_build.sh
##############################
FROM debian as dbnsfp_build

RUN apt-get update && \
	apt-get install -y wget tabix samtools unzip aria2

# Put shell script inside container
RUN mkdir /opt/scripts
COPY dbNSFP_pipeline_build.sh /opt/scripts/

WORKDIR /data

RUN /opt/scripts/dbNSFP_pipeline_build.sh

##############################
# STAGE 4 - Prepare AlphaMissense DB
# Prepared by Aleksander
##############################
FROM alpine as download_AlphaMissense

#Download tabix so we can index the AM dataset
#Installs dependencies (and removes some unnecessary tar files later)
RUN apk add --no-cache \
    gcc \
    g++ \
    make \
    zlib-dev \
    curl \
    curl-dev \
    tar \
    bzip2 \
    bzip2-dev \
    xz \
    xz-dev

# Download and extract HTSlib (version 1.20, newest as of 28.8.2024)
RUN curl -L https://github.com/samtools/htslib/releases/download/1.20/htslib-1.20.tar.bz2 -o htslib.tar.bz2 \
    && tar -xjf htslib.tar.bz2
# Check installation
RUN ls -la htslib-1.20
# Build and install HTSlib
RUN cd htslib-1.20 \
    && make install

# Clean up unnecessary dependencies to save space
RUN rm -rf htslib-1.20 htslib.tar.bz2 \
    && apk del \
    gcc \
    g++ \
    make 

# Add the PATH environmental variable
ENV PATH="/usr/local/bin:${PATH}"

# Verify installation
RUN tabix --version
#Download the Alpha Missense hg38 data file and index it
RUN wget https://storage.googleapis.com/dm_alphamissense/AlphaMissense_hg38.tsv.gz -Y off
RUN tabix -s 1 -b 2 -e 2 -f -S 1 AlphaMissense_hg38.tsv.gz

##############################
# STAGE 5 - Create VEP docker, copy relevant datasets to the image
# VEP should at least release 112 to support AlphaMissense (Aleksander) # FROM ensemblorg/ensembl-vep:release_112.0
##############################

# Image history
# FROM ensemblorg/ensembl-vep:release_110.1
# FROM ensemblorg/ensembl-vep:release_112.0

## Enforce rebuild ##
ARG CACHEBUST=1

FROM ensemblorg/ensembl-vep:latest

# Needs to be root to allow image modifications
USER root

RUN apt-get update && apt-get install -y samtools

# Change user to vep
USER vep

RUN perl /opt/vep/src/ensembl-vep/INSTALL.pl \
        --AUTO fcp \
        --NO_UPDATE \
        --ASSEMBLY GRCh38 \
        --PLUGINSDIR /opt/vep/.vep/Plugins/ \
        --CACHEDIR /opt/vep/.vep/ \
        --PLUGINS all \
        --SPECIES homo_sapiens_merged

RUN vep -id rs699 \
      --cache --merged \
      --nearest symbol \
      -o 'STDOUT' \
      --no_stats \
      > /dev/null

COPY --from=intermediate /loftee /opt/vep/.vep/Plugins/loftee
COPY --from=download_loftee /human_ancestor.fa* /opt/vep/.vep/Plugins/loftee/data/
COPY --from=download_loftee /gerp* /opt/vep/.vep/Plugins/loftee/data/
COPY --from=download_loftee /loftee* /opt/vep/.vep/Plugins/loftee/data/

RUN mkdir -p /opt/vep/.vep/dbNSFP
COPY --from=dbnsfp_build /data/dbNSFPv4.9a_custombuild.gz /opt/vep/.vep/dbNSFP/
COPY --from=dbnsfp_build /data/dbNSFPv4.9a_custombuild.gz.tbi /opt/vep/.vep/dbNSFP/

COPY --from=download_AlphaMissense /AlphaMissense* /opt/vep/.vep/Plugins/AlphaMissense/

