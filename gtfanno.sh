#!/bin/bash


info(){
	printf "\e[44m$*\e[0m\n"
}
ok(){
	printf "\e[42m$*\e[0m\n"
}
warn(){
	printf "\e[33m$*\e[0m\n"
}

usage() {
	cat <<\END_HELP
   _____ _______ ______                      
  / ____|__   __|  ____|                     
 | |  __   | |  | |__ __ _ _ __  _ __   ___  
 | | |_ |  | |  |  __/ _` | '_ \| '_ \ / _ \ 
 | |__| |  | |  | | | (_| | | | | | | | (_) |
  \_____|  |_|  |_|  \__,_|_| |_|_| |_|\___/  
                                             
This script is for generating TSS, exon, intron, intergenic region annotations from GTF file.
The input GTF file requires chromosome name with "chr" prefix.

Usage:
	bash gtfanno.sh -f <GTF file>			# Output file to current working directory
	bash gtfanno.sh -f <GTF file> -o <output directory> -k   # Includes scaffolds
	
Parameters:
	-f	Required. Path to GTF file. Either gzipped or plain file is accepted.
	-p	Optional. Prefix to output files. Default the same as the prefix of GTF file name.
	-o	Optional. Output directory. Default the current working directory.
	-k	Optional. Also include scaffolds.
	-r	Optional. The radius upstream and downstream the TSS. Default to 300.
	-s	Optional. The local chromosome size file for calculating intergenic area. If left empty, it will be automatically downloaded from https://github.com/igvteam/igv/tree/maaster/genomes/sizes
	-h	Print this help message.

END_HELP
	exit $1;
}

check_cmd() {
	local uninstalled=()
	for c in bedtools; do
		if ! command -v $c > /dev/null; then
			uninstalled+=($c)
		fi
	done
	if [[ ${#uninstalled[@]} -gt 0 ]]; then
		warn "Required command[s] not found: ${uninstalled[@]}"
		exit 1
	fi
}
check_cmd

include_scaffold=false
outdir=$(pwd)
tss_radius=300

while getopts f:p:o:kr:s:h opt
do
case ${opt} in
f) gtf_file=${OPTARG};;
p) prefix=${OPTARG};;
o) outdir=${OPTARG};;
k) include_scaffold=true;;
r) tss_radius=${OPTARG};;
s) size_file=${OPTARG};;
h) usage 0;;
esac
done

if [[ -z $gtf_file ]];then
	usage 1
fi

tmpdir=$outdir/.tmp
mkdir -p $tmpdir

if [[ -z $prefix ]];then
	prefix=$(echo "$(basename $gtf_file)" | awk -F '.gtf' '{print $1}')
fi

load_gtf() {
	if [[ $(file -b ${gtf_file}) == *gzip* ]];then
		zcat ${gtf_file}
	else
		cat ${gtf_file}
	fi
}

if load_gtf | head | grep -E "GRCh38|hg38" > /dev/null; then
	genome=hg38
elif load_gtf | head | grep -E "GRCh37|hg19" > /dev/null; then
	genome=hg19
elif load_gtf | head | grep -E "GRCm39|mm39" > /dev/null; then
	genome=mm39
elif load_gtf | head | grep -E "GRCh38|mm10" > /dev/null; then
	genome=mm10
fi

genome_size_url="https://raw.githubusercontent.com/igvteam/igv/master/genomes/sizes/$genome.chrom.sizes"

chr_file=$outdir/$prefix.chr.bed
tss_file=$outdir/$prefix.tss$tss_radius.bed
exon_file=$outdir/$prefix.exon_no_tss.bed
intron_file=$outdir/$prefix.intron.bed
intergenic_file=$outdir/$prefix.intergenic.bed

#####################################################
#													#
#			1) GTF to BED conversion				#
#													#
#####################################################

info "Start converting GTF to BED: $(warn $chr_file)"

# row example
# 1	2	3	4	5	6	7	8	9
# chr1	HAVANA	gene	11869	14409	.	+	.	gene_id "ENSG00000223972.5"; gene_type "transcribed_unprocessed_pseudogene"; gene_name "DDX11L1"; level 2; hgnc_id "HGNC:37102"; havana_gene "OTTHUMG00000000961.1";
gtf_to_bed() {
	 awk -F '\t' -v OFS='\t' '{
		split($9, attr, ";")
		for (i = 1; i <= length(attr); i++) {
			if (attr[i] ~ /gene_name/) {
				split(attr[i], gene_name, " ")
				gsub("\"", "", gene_name[2])
				print $1, $4-1, $5, $1":"$3":"gene_name[2]":"$4-1"-"$5":"$7, "0", $7
				break
			}
		}
	}'
}

filter_scaffold() {
	if $include_scaffold
	then
		grep ""
	else
		grep -E '^(chr[0-9]+|[0-9]+|chr[XYM])'
	fi
}

sort_bed() {
	awk -F '\t' -v OFS='\t' '{
		if ($1 == "chrM")
			print $0, "chrZ"
		else
			print $0, $1
	}' | sort -k7,7V -k2,2n -k3,3n | awk -F '\t' -v OFS='\t' '{
		$NF=""
		sub(/\t$/, "")
		print $0
	}'
}

load_gtf $gtf_file | gtf_to_bed | filter_scaffold | sort_bed | uniq > $chr_file
ok "Job finished"

#####################################################
#													#
#				2) TSS annotation					#
#													#
#####################################################

info "Start generate TSS $tss_radius annotation: $(warn $tss_file)"

get_tss_from_chr() {
	awk -F '\t' -v r="$tss_radius" -v OFS='\t' '{
		if ($6 == "+") {
			print $1, $2-r, $2+r, $4, $5, $6
		} else {
			print $1, $3-r, $3+r, $4, $5, $6
		}
	}' $1
}

bedtools_merge_with_genename() {
    awk -F '\t' -v OFS='\t' '{
        split($4, attr, ":")
        print $1, $2, $3, attr[3], $5, $6
    }' | sort_bed | \
	bedtools merge -s -c 4,6 -o distinct,distinct -i stdin | \
	awk -F '\t' -v OFS='\t' -v region="$1" '{
        print $1, $2, $3, $1":"region":"$4":"$2"-"$3":"$5, "0", $5
    }' | sort_bed
}

bedtools_merge_simple() {
    sort_bed | bedtools merge -s -c 6 -o distinct -i stdin | \
	awk -F '\t' -v OFS='\t' -v region="$1" '{
        print $1, $2, $3, $1":"region":"$2"-"$3":"$4, "0", $4
    }' | sort_bed
}


get_tss_from_chr $chr_file | bedtools_merge_simple tss > $tss_file

ok "Job finished."

#####################################################
#													#
#				3) exon annotation					#
#													#
#####################################################

info "Start generate exon (without TSS $tss_radius) annotation: $(warn $exon_file)"

exon_tmp=$tmpdir/exon.tmp
grep "exon" $chr_file > $exon_tmp
bedtools subtract -s -a $exon_tmp -b $tss_file | bedtools_merge_simple exon > $exon_file

ok "Job finished."

#####################################################
#													#
#				4) intron annotation				#
#													#
#####################################################

info "Start generate intron (without TSS $tss_radius) annotation: $(warn $intron_file)"

exon_tss_tmp=$tmpdir/exon_tss.tmp
gene_tmp=$tmpdir/gene.tmp

grep "gene" $chr_file > $gene_tmp
cat $exon_tmp $tss_file | bedtools_merge_simple intron > $exon_tss_tmp

bedtools subtract -s -a $gene_tmp -b $exon_tss_tmp | bedtools_merge_simple intron > $intron_file

ok "Job finished."

#####################################################
#													#
#			5) intergenic annotation				#
#													#
#####################################################

info "Start generate intergenic annotation: $(warn $intergenic_file)"

gene_tss_fwd_tmp=$tmpdir/gene_tss_fwd.tmp
gene_tss_rev_tmp=$tmpdir/gene_tss_rev.tmp
intergenic_fwd_tmp=$tmpdir/intergenic_fwd.tmp
intergenic_rev_tmp=$tmpdir/intergenic_rev.tmp
genome_size_tmp=$tmpdir/genome_size.tmp

if [[ -z $size_file ]] || [[ -f $size_file ]]; then
	warn "Local genome size file not found. Start downloading from $genome_size_url"
	curl $genome_size_url > $genome_size_tmp
	ok "$genome size file is downloaded to $genome_size_tmp"
else
	cat $size_file > genome_size_tmp
fi


cat $gene_tmp $tss_file | awk -F '\t' -v OFS='\t' '{if ($6 == "+") {print $0}}' | \
	bedtools_merge_simple > $gene_tss_fwd_tmp
cat $gene_tmp $tss_file | awk -F '\t' -v OFS='\t' '{if ($6 == "-") {print $0}}' | \
	bedtools_merge_simple > $gene_tss_rev_tmp

bedtools complement -i $gene_tss_fwd_tmp -g $genome_size_tmp | \
	awk -F '\t' -v OFS='\t' '{print $1, $2, $3, $1":"$2":"$3":+", "0", "+"}' > $intergenic_fwd_tmp
bedtools complement -i $gene_tss_rev_tmp -g $genome_size_tmp | \
	awk -F '\t' -v OFS='\t' '{print $1, $2, $3, $1":"$2":"$3":-", "0", "-"}' > $intergenic_rev_tmp

cat $intergenic_fwd_tmp $intergenic_rev_tmp | bedtools_merge_simple intergenic > $intergenic_file

ok "Job finished."

#####################################################
#													#
#					6) clean						#
#													#
#####################################################

rm -rf $tmpdir
