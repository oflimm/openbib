#!/bin/bash

for i in `grep -r verfstring *|cut -d: -f 1|xargs`;do cat $i | sed -e 's/verfstring/personstring/g' > $i.tmp; mv -f $i.tmp $i; done

for i in `grep -r korstring *|cut -d: -f 1|xargs`;do cat $i | sed -e 's/korstring/corporatebodystring/g' > $i.tmp; mv -f $i.tmp $i; done

for i in `grep -r swtstring *|cut -d: -f 1|xargs`;do cat $i | sed -e 's/swtstring/subjectstring/g' > $i.tmp; mv -f $i.tmp $i; done

for i in `grep -r sysstring *|cut -d: -f 1|xargs`;do cat $i | sed -e 's/sysstring/classificationstring/g' > $i.tmp; mv -f $i.tmp $i; done
