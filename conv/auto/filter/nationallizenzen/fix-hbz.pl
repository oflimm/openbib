#!/usr/bin/perl

# Korrektur von invaliden Daten mit Schmutzzeichen aus dem hbz, die eine Verarbeitung verhindern wuerden

while (<>){
    s/Ê//g;
    print;
}
