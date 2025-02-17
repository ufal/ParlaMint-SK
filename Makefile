

ZENODO-ID := 10884138

SourceTermDir := Sources-TSV

download-terms-tsv:
	for t in `seq 1 8`;\
	  do wget -O $(SourceTermDir)/SK_term_$$t.tsv https://zenodo.org/records/$(ZENODO-ID)/files/SK_term_$$t.tsv?download=1 ; \
	done

