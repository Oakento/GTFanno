# GTFanno
This script is for generating TSS, exon, intron, intergenic region annotations from GTF file.
The input GTF file requires chromosome name with "chr" prefix.

## Usage:
`bash gtfanno.sh -f <GTF file>`			# Output file to current working directory

`bash gtfanno.sh -f <GTF file> -o <output directory> -k`   # Includes scaffolds

## Parameters:
+ `-f`	Required. Path to GTF file. Either gzipped or plain file is accepted.
+ `-p`	Optional. Prefix to output files. Default the same as the prefix of GTF file name.
+	`-o`	Optional. Output directory. Default the current working directory.
+ `-k`	Optional. Also include scaffolds.
+	`-r`	Optional. The radius upstream and downstream the TSS. Default to 300.
+ `-s`	Optional. The local chromosome size file for calculating intergenic area. If left empty, it will be automatically downloaded from https://github.com/igvteam/igv/tree/maaster/genomes/sizes
+ `-h`	Print this help message.
