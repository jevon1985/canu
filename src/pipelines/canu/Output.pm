
###############################################################################
 #
 #  This file is part of canu, a software program that assembles whole-genome
 #  sequencing reads into contigs.
 #
 #  This software is based on:
 #    'Celera Assembler' (http://wgs-assembler.sourceforge.net)
 #    the 'kmer package' (http://kmer.sourceforge.net)
 #  both originally distributed by Applera Corporation under the GNU General
 #  Public License, version 2.
 #
 #  Canu branched from Celera Assembler at its revision 4587.
 #  Canu branched from the kmer project at its revision 1994.
 #
 #  This file is derived from:
 #
 #    src/pipelines/ca3g/Output.pm
 #
 #  Modifications by:
 #
 #    Brian P. Walenz from 2015-MAR-16 to 2015-AUG-25
 #      are Copyright 2015 Battelle National Biodefense Institute, and
 #      are subject to the BSD 3-Clause License
 #
 #    Brian P. Walenz beginning on 2015-NOV-02
 #      are a 'United States Government Work', and
 #      are released in the public domain
 #
 #  File 'README.licenses' in the root directory of this distribution contains
 #  full conditions and disclaimers for each license.
 ##

package canu::Output;

require Exporter;

@ISA    = qw(Exporter);
@EXPORT = qw(outputLayout outputGraph outputSequence outputSummary);

use strict;

use POSIX qw(UINT_MAX);

use canu::Defaults;
use canu::Execution;
use canu::HTML;


#  In this module, the inputs are read from $wrk (the local work directory), and the output are
#  written to $WRK (the root work directory).  This is a change from CA8 where outputs
#  were written to the 9-terminator directory.


sub outputLayout ($$) {
    my $WRK     = shift @_;           #  Root work directory (the -d option to canu)
    my $wrk     = "$WRK/unitigging";  #  Local work directory
    my $asm     = shift @_;
    my $bin     = getBinDirectory();
    my $cmd;

    goto allDone   if (skipStage($WRK, $asm, "outputLayout") == 1);
    goto allDone   if (-e "$WRK/$asm.layout");

    $cmd  = "$bin/tgStoreDump \\\n";
    $cmd .= "  -G $wrk/$asm.gkpStore \\\n";
    $cmd .= "  -T $wrk/$asm.tigStore 2 \\\n";
    $cmd .= "  -o $WRK/$asm \\\n";
    $cmd .= "  -layout \\\n";
    $cmd .= "> $WRK/$asm.layout.err 2>&1";

    if (runCommand($wrk, $cmd)) {
        caExit("failed to output layouts", "$WRK/$asm.layout.err");
    }

    unlink "$WRK/$asm.layout.err";

  finishStage:
    emitStage($WRK, $asm, "outputLayout");
    buildHTML($WRK, $asm, "utg");

  allDone:
    print STDERR "-- Unitig layouts saved in '$WRK/$asm.layout'.\n";
}




sub outputGraph ($$) {
    my $WRK     = shift @_;           #  Root work directory (the -d option to canu)
    my $wrk     = "$WRK/unitigging";  #  Local work directory
    my $asm     = shift @_;
    my $bin     = getBinDirectory();
    my $cmd;

    goto allDone   if (skipStage($WRK, $asm, "outputGraph") == 1);
    goto allDone   if (-e "$WRK/$asm.graph");

    #
    #  Stuff here.
    #

    if (runCommand($wrk, $cmd)) {
        caExit("failed to output consensus", "$WRK/$asm.graph.err");
    }

    unlink "$WRK/$asm.graph.err";

  finishStage:
    emitStage($WRK, $asm, "outputGraph");
    buildHTML($WRK, $asm, "utg");

  allDone:
    print STDERR "-- Unitig graph saved in (nowhere, yet).\n";
}




sub outputSequence ($$) {
    my $WRK     = shift @_;           #  Root work directory (the -d option to canu)
    my $wrk     = "$WRK/unitigging";  #  Local work directory
    my $asm     = shift @_;
    my $bin     = getBinDirectory();
    my $cmd;

    my $type = "fasta";  #  Should probably be an option.

    goto allDone   if (skipStage($WRK, $asm, "outputSequence") == 1);
    goto allDone   if (-e "$WRK/$asm.consensus.$type");

    $cmd  = "$bin/tgStoreDump \\\n";
    $cmd .= "  -G $wrk/$asm.gkpStore \\\n";
    $cmd .= "  -T $wrk/$asm.tigStore 2 \\\n";
    $cmd .= "  -consensus -$type \\\n";
    $cmd .= "  -nreads 2 " . (UINT_MAX-1) . " \\\n";
    $cmd .= "> $WRK/$asm.consensus.$type\n";
    $cmd .= "2> $WRK/$asm.consensus.err";

    if (runCommand($WRK, $cmd)) {
        caExit("failed to output consensus", "$WRK/$asm.consensus.err");
    }

    unlink "$WRK/$asm.consensus.err";

  finishStage:
    emitStage($WRK, $asm, "outputSequence");
    buildHTML($WRK, $asm, "utg");

  allDone:
    print STDERR "-- Unitig sequences saved in '$WRK/$asm.consensus.$type'.\n";
}



sub outputSummary ($$) {
    my $WRK     = shift @_;           #  Root work directory (the -d option to canu)
    my $wrk     = "$WRK/unitigging";  #  Local work directory
    my $asm     = shift @_;
    my $bin     = getBinDirectory();
    my $cmd;

    goto allDone   if (skipStage($WRK, $asm, "outputSummary") == 1);
    goto allDone   if (-e "$WRK/$asm.html");

    #  Write a basic html file with all the summary statistics we can find, links to images, and links to outputs.


  finishStage:
    emitStage($WRK, $asm, "outputSummary");
    buildHTML($WRK, $asm, "utg");

  allDone:
    print STDERR "-- Summary saved in '$WRK/$asm.html'.\n";
}