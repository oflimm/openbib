#!/bin/bash

/opt/git/openbib-current/conv/enrichmnt/bvb2enrich.pl -init-rvk --json-importfile=rvk_2018_05.json
/opt/git/openbib-current/conv/enrichmnt/bvb2enrich.pl -init-ddc --json-importfile=ddc_2018_05.json
/opt/git/openbib-current/conv/enrichmnt/bvb2enrich.pl -init-lang --json-importfile=lang_2018_05.json
/opt/git/openbib-current/conv/enrichmnt/bvb2enrich.pl -init-tocurls --json-importfile=tocurls_2018_05.json
/opt/git/openbib-current/conv/enrichmnt/bvb2enrich.pl -init-subjects --json-importfile=subjects_2018_05.json
