package ca3g::OverlapStore;

require Exporter;

@ISA    = qw(Exporter);
@EXPORT = qw(createOverlapStore);

use strict;

use ca3g::Defaults;
use ca3g::Execution;


#  Parallel documentation:
#
#  Each overlap job is converted into a single bucket of overlaps.  Within each bucket, the overlaps
#  are distributed into many slices, one per sort job.  The sort jobs then load the same slice from
#  each bucket.
#
#  E.g., Overlap job 13 will create bucket 13 with slices 4-15.  Sort job 13 will load slice 13 from
#  any bucket that it exists in.
#
#  The terminology isn't consistent however, espeically in the C++ code.



#  NOT FILTERING overlaps by error rate when building the parallel store.
#  NOT able to change the delete flag.
#  Using ovlStoreMemory for sorting.



sub createOverlapStoreSequential ($$@) {
    my $wrk          = shift @_;
    my $asm          = shift @_;
    my $files        = shift @_;
    my $bin          = getBinDirectory();
    my $cmd;

    $cmd  = "$bin/ovStoreBuild \\\n";
    $cmd .= " -o $wrk/$asm.ovlStore.BUILDING \\\n";
    $cmd .= " -g $wrk/$asm.gkpStore \\\n";
    $cmd .= " -M " . getGlobal("ovlStoreMemory") . " \\\n";
    $cmd .= " -L $files \\\n";
    $cmd .= " > $wrk/$asm.ovlStore.err 2>&1";

    if (runCommand($wrk, $cmd)) {
        caFailure("failed to create the overlap store", "$wrk/$asm.ovlStore.err");
    }

    rename "$wrk/$asm.ovlStore.BUILDING", "$wrk/$asm.ovlStore";
}




#  Count the number of inputs.  We don't expect any to be missing (they were just checked
#  by overlapCheck()) but feel silly not checking again.

sub countOverlapStoreInputs ($) {
    my $inputs    = shift @_;
    my $numInputs = 0;

    open(F, "< $inputs") or die "Failed to open overlap store input file '$inputs': $0\n";
    while (<F>) {
        chomp;
        die "overlapper output '$_' not found\n"  if (! -e $_);
        $numInputs++;
    }
    close(F);

    return($numInputs);
}





sub overlapStoreBucketizerCheck ($$$$) {
    my $wrk          = shift @_;
    my $asm          = shift @_;
    my $files        = shift @_;
    my $attempt      = shift @_;

    return  if (-d "$wrk/$asm.ovlStore");

    my $numInputs      = countOverlapStoreInputs($files);
    my $currentJobID   = 1;
    my @successJobs;
    my @failedJobs;
    my $failureMessage = "";

    my $bucketID       = "0001";

    #  Two ways to check for completeness, either 'sliceSizes' exists, or the 'bucket' directory
    #  exists.  The compute is done in a 'create' directory, which is renamed to 'bucket' just
    #  before the job completes.

    open(F, "< $files") or caFailure("failed to open '$files': $0\n", undef);

    while (<F>) {
        chomp;

        if (! -e "$wrk/$asm.ovlStore.BUILDING/bucket$bucketID") {
            $failureMessage .= "  job $wrk/$asm.ovlStore.BUILDING/bucket$bucketID FAILED.\n";
            push @failedJobs, $currentJobID;
        } else {
            push @successJobs, $currentJobID;
        }

        $currentJobID++;
        $bucketID++;
    }

    close(F);

    if (scalar(@failedJobs) == 0) {
        print STDERR "overlap store bucketizer finished.\n";
        return;
    }

    if ($attempt > 0) {
        print STDERR "\n";
        print STDERR scalar(@failedJobs), " overlapStoreBucketizer jobs failed:\n";
        print STDERR $failureMessage;
        print STDERR "\n";
    }

    print STDERR "overlapStoreBucketizerCheck() -- attempt $attempt begins with ", scalar(@successJobs), " finished, and ", scalar(@failedJobs), " to compute.\n";

    if ($attempt < 2) {
        submitOrRunParallelJob($wrk, $asm, "ovB", "$wrk/$asm.ovlStore.BUILDING", "scripts/1-bucketize", getGlobal("osbConcurrency"), @failedJobs);
    } else {
        caFailure("failed to overlapStoreBucketize.  Made $attempt attempts, jobs still failed.\n", undef);
    }
}





sub overlapStoreSorterCheck ($$$$) {
    my $wrk          = shift @_;
    my $asm          = shift @_;
    my $files        = shift @_;
    my $attempt      = shift @_;

    return  if (-d "$wrk/$asm.ovlStore");

    my $numSlices      = getGlobal("ovlStoreSlices");
    my $currentJobID   = 1;
    my @successJobs;
    my @failedJobs;
    my $failureMessage = "";

    my $sortID       = "0001";

    open(F, "< $files") or caFailure("failed to open '$files': $0\n", undef);

    #  A valid result has three files:
    #    $wrk/$asm.ovlStore.BUILDING/$sortID
    #    $wrk/$asm.ovlStore.BUILDING/$sortID.index
    #    $wrk/$asm.ovlStore.BUILDING/$sortID.info
    #
    #  A crashed result has one file, if it crashes before output
    #    $wrk/$asm.ovlStore.BUILDING/$sortID.ovs
    #
    #  On out of disk, the .info is missing.  It's the last thing created.
    #
    while ($currentJobID <= $numSlices) {

        if ((! -e "$wrk/$asm.ovlStore.BUILDING/$sortID") ||
            (! -e "$wrk/$asm.ovlStore.BUILDING/$sortID.info") ||
            (  -e "$wrk/$asm.ovlStore.BUILDING/$sortID.ovs")) {
            $failureMessage .= "  job $wrk/$asm.ovlStore.BUILDING/$sortID FAILED.\n";
            unlink "$wrk/$asm.ovlStore.BUILDING/$sortID.ovs";
            push @failedJobs, $currentJobID;
        } else {
            push @successJobs, $currentJobID;
        }

        $currentJobID++;
        $sortID++;
    }

    close(F);


    if (scalar(@failedJobs) == 0) {
        print STDERR "overlap store sorter finished.\n";
        return;
    }

    if ($attempt > 0) {
        print STDERR "\n";
        print STDERR scalar(@failedJobs), " overlapStoreSorter jobs failed:\n";
        print STDERR $failureMessage;
        print STDERR "\n";
    }

    print STDERR "overlapStoreSorterCheck() -- attempt $attempt begins with ", scalar(@successJobs), " finished, and ", scalar(@failedJobs), " to compute.\n";

    if ($attempt < 2) {
        submitOrRunParallelJob($wrk, $asm, "ovS", "$wrk/$asm.ovlStore.BUILDING", "scripts/2-sort", getGlobal("ossConcurrency"), @failedJobs);
    } else {
        caFailure("failed to overlapStoreSorter.  Made $attempt attempts, jobs still failed.\n", undef);
    }
}




sub createOverlapStoreParallel ($$@) {
    my $wrk          = shift @_;
    my $asm          = shift @_;
    my $files        = shift @_;
    my $bin          = getBinDirectory();
    my $cmd;

    my $numInputs  = countOverlapStoreInputs($files);
    my $numSlices  = getGlobal("ovlStoreSlices");

    #  Create an output directory, and populate it with more directories and scripts

    system("mkdir -p $wrk/$asm.ovlStore.BUILDING")                   if (! -d "$wrk/$asm.ovlStore.BUILDING");
    system("mkdir -p $wrk/$asm.ovlStore.BUILDING/scripts")           if (! -d "$wrk/$asm.ovlStore.BUILDING/scripts");
    system("mkdir -p $wrk/$asm.ovlStore.BUILDING/logs")              if (! -d "$wrk/$asm.ovlStore.BUILDING/logs");

    #  Parallel jobs for bucketizing.  This should really be part of overlap computation itself.

    if (! -e "$wrk/$asm.ovlStore.BUILDING/scripts/1-bucketize.sh") {
        open(F, "> $wrk/$asm.ovlStore.BUILDING/scripts/1-bucketize.sh") or die;
        print F "#!/bin/sh\n";
        print F "\n";
        print F "jobid=\$SGE_TASK_ID\n";
        print F "if [ x\$jobid = x -o x\$jobid = xundefined ]; then\n";
        print F "  jobid=\$1\n";
        print F "fi\n";
        print F "if [ x\$jobid = x ]; then\n";
        print F "  echo Error: I need SGE_TASK_ID set, or a job index on the command line.\n";
        print F "  exit 1\n";
        print F "fi\n";
        print F "\n";
        print F "bn=`printf %04d \$jobid`\n";
        print F "jn=\"undefined\"\n";
        print F "\n";
        
        my $tstid = 1;

        open(I, "< $files") or die "Failed to open '$files': $0\n";

        while (<I>) {
            chomp;

            print F "if [ \"\$jobid\" -eq \"$tstid\" ] ; then jn=\"$_\"; fi\n";
            $tstid++;
        }

        close(I);

        print F "\n";
        print F "if [ \$jn = \"undefined\" ] ; then\n";
        print F "  echo \"Job out of range.\"\n";
        print F "  exit\n";
        print F "fi\n";
        print F "\n";
        print F "if [ -e \"$wrk/$asm.ovlStore.BUILDING/bucket\$bn/sliceSizes\" ] ; then\n";
        print F "  echo \"Bucket $wrk/$asm.ovlStore.BUILDING/bucket\$bn finished successfully.\"\n";
        print F "  exit\n";
        print F "fi\n";
        print F "\n";
        print F "if [ -e \"$wrk/$asm.ovlStore.BUILDING/create\$bn\" ] ; then\n";
        print F "  echo \"Removing incomplete bucket $wrk/$asm.ovlStore.BUILDING/create\$bn\"\n";
        print F "  rm -rf \"$wrk/$asm.ovlStore.BUILDING/create\$bn\"\n";
        print F "fi\n";
        print F "\n";
        print F getBinDirectoryShellCode();
        print F "\n";
        print F "\$bin/ovStoreBucketizer \\\n";
        print F "  -o $wrk/$asm.ovlStore.BUILDING \\\n";
        print F "  -g $wrk/$asm.gkpStore \\\n";
        print F "  -F $numSlices \\\n";
        #print F "  -e " . getGlobal("") . " \\\n"  if (defined(getGlobal("")));
        print F "  -job \$jobid \\\n";
        print F "  -i   \$jn\n";
        close(F);
    }

    #  Parallel jobs for sorting each bucket

    if (! -e "$wrk/$asm.ovlStore.BUILDING/scripts/2-sort.sh") {
        open(F, "> $wrk/$asm.ovlStore.BUILDING/scripts/2-sort.sh") or die;
        print F "#!/bin/sh\n";
        print F "\n";
        print F "jobid=\$SGE_TASK_ID\n";
        print F "if [ x\$jobid = x -o x\$jobid = xundefined ]; then\n";
        print F "  jobid=\$1\n";
        print F "fi\n";
        print F "if [ x\$jobid = x ]; then\n";
        print F "  echo Error: I need SGE_TASK_ID set, or a job index on the command line.\n";
        print F "  exit 1\n";
        print F "fi\n";
        print F "\n";
        print F getBinDirectoryShellCode();
        print F "\n";
        print F "\$bin/ovStoreSorter \\\n";
        print F "  -deletelate \\\n";  #  Choices -deleteearly -deletelate or nothing
        print F "  -M " . getGlobal("ovlStoreMemory") . " \\\n";
        print F "  -o $wrk/$asm.ovlStore.BUILDING \\\n";
        print F "  -g $wrk/$asm.gkpStore \\\n";
        print F "  -F $numSlices \\\n";
        print F "  -job \$jobid $numInputs\n";
        print F "\n";
        print F "if [ \$? = 0 ] ; then\n";
        print F "  echo Success.\n";
        print F "else\n";
        print F "  echo Failure.\n";
        print F "fi\n";
        close(F);
    }

    #  A final job to merge the indices.

    if (! -e "$wrk/$asm.ovlStore.BUILDING/scripts/3-index.sh") {
        open(F, "> $wrk/$asm.ovlStore.BUILDING/scripts/3-index.sh") or die;
        print F "#!/bin/sh\n";
        print F "\n";
        print F getBinDirectoryShellCode();
        print F "\n";
        print F "\$bin/ovStoreIndexer \\\n";
        #print F "  -nodelete \\\n";  #  Choices -nodelete or nothing
        print F "  -o $wrk/$asm.ovlStore.BUILDING \\\n";
        print F "  -F $numSlices\n";
        print F "\n";
        print F "if [ \$? = 0 ] ; then\n";
        print F "  echo Success.\n";
        print F "else\n";
        print F "  echo Failure.\n";
        print F "fi\n";
        close(F);
    }

    system("chmod +x $wrk/$asm.ovlStore.BUILDING/scripts/1-bucketize.sh");
    system("chmod +x $wrk/$asm.ovlStore.BUILDING/scripts/2-sort.sh");
    system("chmod +x $wrk/$asm.ovlStore.BUILDING/scripts/3-index.sh");

    overlapStoreBucketizerCheck($wrk, $asm, $files, 0);  #  Compute
    overlapStoreBucketizerCheck($wrk, $asm, $files, 1);  #  Compute again, if needed
    overlapStoreBucketizerCheck($wrk, $asm, $files, 2);  #  Fail, if needed

    overlapStoreSorterCheck($wrk, $asm, $files, 0);
    overlapStoreSorterCheck($wrk, $asm, $files, 1);
    overlapStoreSorterCheck($wrk, $asm, $files, 2);

    if (runCommand("$wrk/$asm.ovlStore.BUILDING", "scripts/3-index.sh")) {
        caFailure("failed to build index for overlap store", "");
    }

    #  All done!

    rename "$wrk/$asm.ovlStore.BUILDING", "$wrk/$asm.ovlStore";
}



sub createOverlapStore ($$$) {
    my $wrk          = shift @_;
    my $asm          = shift @_;
    my $seq          = shift @_;
    my $path         = "$wrk/1-overlapper";

    goto alldone if (-d "$wrk/$asm.ovlStore");
    goto alldone if (-d "$wrk/$asm.tigStore");

    #  Did we _really_ complete?

    caFailure("overlapper claims to be finished, but no job list found in '$path/ovljob.files'", undef)  if (! -e "$path/ovljob.files");

    #  Then just build the store!  Simple!

    createOverlapStoreSequential($wrk, $asm, "$path/ovljob.files")  if ($seq eq "sequential");
    createOverlapStoreParallel  ($wrk, $asm, "$path/ovljob.files")  if ($seq eq "parallel");

    goto alldone  if (getGlobal("saveOverlaps"));

    #  Delete the inputs and directories.

    my %directories;

    open(F, "< $path/ovljob.files");
    while (<F>) {
        chomp;
        unlink "$path/$_";

        my @components = split '/', $_;
        pop @components;
        my $dir = join '/', @components;
        
        $directories{$dir}++;
    }
    close(F);
    
    foreach my $dir (keys %directories) {
        rmdir "$path/$dir";
    }
    
    unlink "$path/ovljob.files";

    #  Now all done!
  alldone:
    stopAfter("overlapper");
}

1;
