# Measure each configured starting/reference structure using the same signatures.

if {![info exists ::env(ANALYSIS_PROJECT_ROOT)] || $::env(ANALYSIS_PROJECT_ROOT) eq ""} {
    puts stderr "ERROR: Export ANALYSIS_PROJECT_ROOT to the repository directory before starting VMD; see the README quick-start commands."
    quit
}
source [file join $::env(ANALYSIS_PROJECT_ROOT) scripts vmd distance_core.tcl]
if {[catch {
    load_analysis_config
    validate_analysis_config
} config_error]} {
    puts stderr "ERROR: $config_error"
    quit
}

if {[llength $analysis_references] == 0} {
    puts "No reference structures are configured; nothing to measure."
    quit
}

# Check every configured structure before opening the output file.
foreach reference $analysis_references {
    lassign $reference reference_label reference_path systems
    set reference_path [resolve_config_path $reference_path]
    if {![file exists $reference_path]} {
        puts stderr "ERROR: Missing reference structure: $reference_path"
        quit
    }
}

set output_dir [resolve_config_path $analysis_output_dir]
file mkdir $output_dir
set output_file [file join $output_dir "reference_distances.csv"]
set handle [open $output_file w]
puts $handle "system_name,reference_name,signature_name,reference_file,distance_angstrom"

foreach reference $analysis_references {
    lassign $reference reference_label reference_path systems
    set reference_path [resolve_config_path $reference_path]
    if {![file exists $reference_path]} {
        close $handle
        error "Missing reference structure: $reference_path"
    }

    foreach system_id $systems {
        set system_signatures [signatures_for_system $system_id]
        if {[llength $system_signatures] == 0} {
            puts "WARNING: No signatures are configured for system $system_id"
            continue
        }

        puts "Loading reference $reference_label for $system_id: $reference_path"
        set molid [mol new $reference_path waitfor all]
        foreach signature $system_signatures {
            lassign $signature signature_id label mode selection_1 selection_2
            if {[catch {
                set distance [compute_distance \
                    $molid $mode $selection_1 $selection_2 0]
            } distance_error]} {
                mol delete $molid
                close $handle
                puts stderr "ERROR: Could not measure $signature_id for reference $reference_label / $system_id: $distance_error"
                quit
            }
            set row [list \
                $system_id $reference_label $signature_id $reference_path \
                [format "%.8f" $distance]]
            puts $handle [csv_row $row]
            puts "  $system_id / $reference_label / $signature_id = $distance A"
        }
        mol delete $molid
    }
}

close $handle
puts "Wrote reference measurements to $output_file"
quit
