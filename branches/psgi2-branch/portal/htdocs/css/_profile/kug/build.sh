#!/bin/bash
cat /var/www/yaml/core/base.min.css /var/www/yaml/navigation/hlist.css /var/www/yaml/print/print.css /var/www/yaml/screen/typography.css typography.css layout.css hlist.css vlist.css  screen.css forms.css buttons.css jquery-ui-1.8.14.custom.css jquery.autocomplete.css local.css print.css  > openbib-merged.css
java -jar /opt/svn/openbib-current/portal/htdocs/css/yuicompressor-2.4.7/build/yuicompressor-2.4.7.jar openbib-merged.css -o openbib.css
