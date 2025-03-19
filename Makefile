MAKEFLAGS += --no-print-directory
SAMPLE = 

ZENODO-ID := 10884138

PREFIX := $(shell test -n "$(SAMPLE)" && echo -n "Sample")

Terms := *
SourceTermDir := Sources-TSV
Source := $(PREFIX)$(SourceTermDir)
DataDir := $(PREFIX)Data
DataSortedSourceDir := $(DataDir)/TsvSorted
DataTeiTextDir := $(DataDir)/TeiText

SampleFilter := $(shell test -n "$(SAMPLE)" && cat $(Source)/date_filter.txt | tr "\n" "|" )

download-terms-tsv:
	for t in `seq 1 8`;\
	  do wget -O $(SourceTermDir)/SK_term_$$t.tsv https://zenodo.org/records/$(ZENODO-ID)/files/SK_term_$$t.tsv?download=1 ; \
	done

sort-svk:
	mkdir -p $(DataSortedSourceDir)
	for f in `cd $(Source); ls SK_term*.tsv`;\
	  do sed -n '1s/^/svk_source\t/p' $(Source)/$$f > $(DataSortedSourceDir)/$$f; \
	  nl $(Source)/$$f| tail -n +2|sort -n|sed "s/^ *\([0-9]*\)\t/$$f-line\1\t/" >> $(DataSortedSourceDir)/$$f;\
	done

svk2tei-text:
	mkdir -p $(DataTeiTextDir)
	perl  -I Scripts Scripts/svk2tei-text.pl --out-dir $(DataTeiTextDir) --in-files $(DataSortedSourceDir)/SK_term_$(Terms).tsv


create-sample-source-data:
	test -n "$(PREFIX)"
	for f in `ls $(SourceTermDir)/SK_term*.tsv`;\
	  do head -n1 $$f > $(PREFIX)$$f;\
	  awk -F"\t" '$$4 ~ /^$(SampleFilter)$$/' $$f >> $(PREFIX)$$f;\
	done
	make sort-svk

skv-data:
	@tail -n +2 -q $(SourceTermDir)/SK_term*.tsv
skv-info-extent:
	cat $(SourceTermDir)/*.tsv | cut -f 25 | wc
skv-info-rows:
	head -1 -q $(SourceTermDir)/SK_term*.tsv | uniq | perl -pe 's/\t/\n/g'
skv-info-cnt-speeches:
	make skv-data | cut -f1 | wc -l
skv-info-fullname:
	make skv-data | cut -f9 | sort | uniq -c
skv-info-date-day:
	make skv-data | cut -f4 | sort | uniq -c
skv-info-date-month:
	make skv-data | cut -f4 |sed 's/..$$//' | sort | uniq -c
skv-info-date-year:
	make skv-data | cut -f4 |sed 's/....$$//' | sort | uniq -c
skv-info-type:
	make skv-data | cut -f 6,8 | sort | uniq -c