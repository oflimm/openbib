#!/usr/bin/perl

while (<>){
    # 'Normale' Schlagworte ignorieren
    next if (/^09[01234][27]/);

    # 'Eigene' Schlagworte stattdessen verwenden
    if (/^19[01234][27]/){
        substr($_,0,1)="0";
    }
    print;
}
