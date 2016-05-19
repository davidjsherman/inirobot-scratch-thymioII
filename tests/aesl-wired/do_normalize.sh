#!/bin/bash

# normalize times to start at 0.000
for i in {sw,rec}.*.txt; do
    perl ./normalize_rec.perl 1 < $i > n.$i
done

# extract movement events and renormalize
for i in rec.*.txt; do
    egrep '(44 01)|(ec ff)' $i | perl ./normalize_rec.perl 1 > loop.${i#rec.}
done
