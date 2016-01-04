#!/bin/bash

/opt/openbib/bin/ugc-migrations-korrektur.pl --source-database=inst103 --target-database=inst001 --master-database=inst103master --target-location="Fachbibliothek VWL" -migrate-litlists
/opt/openbib/bin/ugc-migrations-korrektur.pl --source-database=inst105 --target-database=inst001 --master-database=inst105master --target-location="Fachbibliothek VWL" -migrate-litlists
/opt/openbib/bin/ugc-migrations-korrektur.pl --source-database=inst128 --target-database=inst001 --master-database=inst128master --target-location="Fachbibliothek VWL" -migrate-litlists
/opt/openbib/bin/ugc-migrations-korrektur.pl --source-database=inst132 --target-database=inst001 --master-database=inst132master --target-location="Fachbibliothek Soziologie" -migrate-litlists
/opt/openbib/bin/ugc-migrations-korrektur.pl --source-database=inst157 --target-database=inst001 --master-database=inst157master --target-location="Fachbibliothek VWL" -migrate-litlists
/opt/openbib/bin/ugc-migrations-korrektur.pl --source-database=inst166 --target-database=inst001 --master-database=inst166master --target-location="Fachbibliothek VWL" -migrate-litlists
/opt/openbib/bin/ugc-migrations-korrektur.pl --source-database=inst418 --target-database=inst001 --master-database=inst418master --target-location="Fachbibliothek Slavistik" -migrate-litlists
/opt/openbib/bin/ugc-migrations-korrektur.pl --source-database=inst427 --target-database=inst001 --master-database=inst427master --target-location="Fachbibliothek Archäologien / Archäologisches Institut" -migrate-litlists
/opt/openbib/bin/ugc-migrations-korrektur.pl --source-database=inst429 --target-database=inst001 --master-database=inst429master --target-location="Fachbibl. Medienkultur und Theater . Theaterwiss. Sammlung" -migrate-litlists
/opt/openbib/bin/ugc-migrations-korrektur.pl --source-database=inst448 --target-database=inst001 --master-database=inst448master --target-location="Fachbibl. Medienkultur und Theater . Inst. f..r Medienkultur u. Theater" -migrate-litlists
/opt/openbib/bin/ugc-migrations-korrektur.pl --source-database=inst622 --target-database=inst001 --master-database=inst622master --target-location="inst622" -migrate-litlists

