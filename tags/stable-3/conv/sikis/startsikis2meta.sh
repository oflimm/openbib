#!/bin/bash

#####################################################################
#
#  startsikis2meta.sh
#
#  BCP-Export relevanter Tabellen aus einer Sybase-Datenbank,
#  Konvertierung in das Meta-Format und Ablage in einem
#  Web-Verzeichnis zur Abholung von OpenBib-Rechner(n)
#
#  Copyright 2003-2012 Oliver Flimm <flimm@openbib.org>
#
#  Dieses Programm ist freie Software. Sie koennen es unter
#  den Bedingungen der GNU General Public License, wie von der
#  Free Software Foundation herausgegeben, weitergeben und/oder
#  modifizieren, entweder unter Version 2 der Lizenz oder (wenn
#  Sie es wuenschen) jeder spaeteren Version.
#
#  Die Veroeffentlichung dieses Programms erfolgt in der
#  Hoffnung, dass es Ihnen von Nutzen sein wird, aber OHNE JEDE
#  GEWAEHRLEISTUNG - sogar ohne die implizite Gewaehrleistung
#  der MARKTREIFE oder der EIGNUNG FUER EINEN BESTIMMTEN ZWECK.
#  Details finden Sie in der GNU General Public License.
#
#  Sie sollten eine Kopie der GNU General Public License zusammen
#  mit diesem Programm erhalten haben. Falls nicht, schreiben Sie
#  an die Free Software Foundation, Inc., 675 Mass Ave, Cambridge,
#  MA 02139, USA.
#
#####################################################################

echo "Start des Entladens: "
date

# Uebergabe des Datenbank/Pool-Namens als Parameter

pool=$1

# Einladen, Setzen und Entfernen diverser Umgebungsvariablen

. /etc/profile
. ~/.bash_profile

export SYBPATH="/opt/sybase"

export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/opt/sybase/OCS-15_0/lib
export PATH=$PATH:/opt/sybase/OCS-15_0/bin

unset LANG LC_CTYPE

# Basis-Verzeichnis im Web-Baum, in dem das Export-Verzeichnis mit den
# konvertierten Dateien erzeugt wird

IMXBASEPATH="/pfad/zu/verzeichnis/im/webbaum"

# Verzeichnis, in das die BCP-Dateien temporaer abgelegt werden

BCPPATH="/tmp"

# Benutzernamen, Passwort und Servername in/von Sybase

SYBASEUSER="username"
SYBASEPASS="Geheim"
SYBASESERVER="fooSYB"

# Check, ob Ausgabeverzeichnis existiert

if [ ! -d $IMXBASEPATH/$pool ]
then
  mkdir $IMXBASEPATH/$pool
fi

# Bereits existierende bcp-Dumps loeschen

rm $BCPPATH/sik_fstab.bcp
rm $BCPPATH/per_daten.bcp
rm $BCPPATH/koe_daten.bcp
rm $BCPPATH/swd_daten.bcp
rm $BCPPATH/sys_daten.bcp
rm $BCPPATH/titel_daten.bcp
rm $BCPPATH/titel_exclude.bcp
rm $BCPPATH/titel_buch_key.bcp
rm $BCPPATH/d01buch.bcp
rm $BCPPATH/d50zweig.bcp
rm $BCPPATH/d60abteil.bcp

# Entladen der sik_fstab plus Normdateien mit bcp

$SYBPATH/OCS-15_0/bin/bcp $pool.sisis.sik_fstab out $BCPPATH/sik_fstab.bcp -b 10000 -c -t"" -U $SYBASEUSER -P $SYBASEPASS -S $SYBASESERVER -N
$SYBPATH/OCS-15_0/bin/bcp $pool.sisis.titel_exclude out $BCPPATH/titel_exclude.bcp -b 10000 -c -t"" -U $SYBASEUSER -P $SYBASEPASS -S $SYBASESERVER -N
$SYBPATH/OCS-15_0/bin/bcp $pool.sisis.titel_daten out $BCPPATH/titel_daten.bcp -b 10000 -c -t"" -U $SYBASEUSER -P $SYBASEPASS -S $SYBASESERVER -N
$SYBPATH/OCS-15_0/bin/bcp $pool.sisis.per_daten out $BCPPATH/per_daten.bcp -b 10000 -c -t"" -U $SYBASEUSER -P $SYBASEPASS -S $SYBASESERVER -N
$SYBPATH/OCS-15_0/bin/bcp $pool.sisis.koe_daten out $BCPPATH/koe_daten.bcp -b 10000 -c -t"" -U $SYBASEUSER -P $SYBASEPASS -S $SYBASESERVER -N
$SYBPATH/OCS-15_0/bin/bcp $pool.sisis.swd_daten out $BCPPATH/swd_daten.bcp -b 10000 -c -t"" -U $SYBASEUSER -P $SYBASEPASS -S $SYBASESERVER -N
$SYBPATH/OCS-15_0/bin/bcp $pool.sisis.sys_daten out $BCPPATH/sys_daten.bcp -b 10000 -c -t"" -U $SYBASEUSER -P $SYBASEPASS -S $SYBASESERVER -N
$SYBPATH/OCS-15_0/bin/bcp $pool.sisis.d01buch out $BCPPATH/d01buch.bcp -b 10000 -c -t"" -U $SYBASEUSER -P $SYBASEPASS -S $SYBASESERVER -N
$SYBPATH/OCS-15_0/bin/bcp $pool.sisis.d50zweig out $BCPPATH/d50zweig.bcp -b 10000 -c -t"" -U $SYBASEUSER -P $SYBASEPASS -S $SYBASESERVER -N
$SYBPATH/OCS-15_0/bin/bcp $pool.sisis.d60abteil out $BCPPATH/d60abteil.bcp -b 10000 -c -t"" -U $SYBASEUSER -P $SYBASEPASS -S $SYBASESERVER -N
$SYBPATH/OCS-15_0/bin/bcp $pool.sisis.titel_buch_key out $BCPPATH/titel_buch_key.bcp -b 10000 -c -t"" -U $SYBASEUSER -P $SYBASEPASS -S $SYBASESERVER -N
echo "Ende des Entladens: "
date

echo Titelsaetze entladen: `cat $BCPPATH/titel_daten.bcp | grep "^[0-9]*0" | wc -l`
echo Davon excluded      : `wc -l $BCPPATH/titel_exclude.bcp`

# Blobs extrahieren und in das Meta-Format konvertieren

cd $IMXBASEPATH/$pool/

echo "Start der Konvertierung: "
date

# Verschiedene Options-Varianten
# 1) Institute ohne Buchdaten oder mit unvollstaendigen Buchdaten in der d01buch
#    bcp2meta.pl
#    d.h. Holdings werden generell aus den bibliographischen Daten der titel_daten (0005,0014,0016,1204) generiert
# 2) Ausleihinstitute mit vollstaendigen Buchdaten in der d01buch
#    bcp2meta.pl -use-d01buch -use-d01buch-standort -use-mcopynum
#    d.h. Holdings werden aus der d01buch generiert, der Standort wird jedoch ueber das Standortfeld in
#    der d01buch realisiert (und nicht via d50zweig/d60abteil). Ebenso wird entsprechend dem Bindeeinheitenkonzept mit
#    mcopynum ueber titel_buch_key gegangen
# 3) USB mit vollstaendigen Buchdaten in der d01buch
#    bcp2meta.pl -use-d01buch -use-mcopynum
#    d.h. Holdings werden aus der d01buch generiert, der Standort dabei via d50zweig/d60abteil. Ebenso wird entsprechend dem Bindeeinheitenkonzept mit
#    mcopynum ueber titel_buch_key gegangen
#
# Bei 1)-3) werden Zeitschriften-Holdings jeweils via 1204 aus den bibliograph. Daten in titel_daten erzeugt.

/pfad/zu/bcp2meta.pl 2> /dev/null

echo "Ende der Konvertierung: "
date

# Und hinterher wieder aufraeumen

rm $BCPPATH/sik_fstab.bcp
rm $BCPPATH/per_daten.bcp
rm $BCPPATH/koe_daten.bcp
rm $BCPPATH/swd_daten.bcp
rm $BCPPATH/sys_daten.bcp
rm $BCPPATH/titel_daten.bcp
rm $BCPPATH/titel_exclude.bcp
rm $BCPPATH/titel_buch_key.bcp
rm $BCPPATH/d01buch.bcp
rm $BCPPATH/d50zweig.bcp
rm $BCPPATH/d60abteil.bcp



