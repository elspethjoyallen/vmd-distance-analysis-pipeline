# Calculate configured distances across all systems, steps, and replicates.

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

set output_dir [resolve_config_path $analysis_output_dir]
file mkdir $output_dir
set analysis_success 0

foreach system $analysis_systems {
    lassign $system system_id display_name system_dir prefix topology steps replicas parts stride trajectory_template
    set system_dir [resolve_config_path $system_dir]
    set topology_path [resolve_system_path $system_dir $topology]
    if {![file exists $topology_path]} {
        error "Missing topology file for $system_id: $topology_path"
    }
    set system_signatures [signatures_for_system $system_id]
    set first_step [lindex $steps 0]
    set last_step [lindex $steps end]

    puts "============================================================"
    puts "System: $display_name ($system_id)"
    puts "Topology: $topology_path"
    puts "Trajectory directory: $system_dir"
    puts "============================================================"

    array unset all_distances
    array set all_distances {}
    array unset all_metadata
    array set all_metadata {}
    foreach signature $system_signatures {
        set signature_id [lindex $signature 0]
        set all_distances($signature_id) {}
        set all_metadata($signature_id) {}
    }

    foreach replica $replicas {
        puts "Processing replica $replica"
        set molid [mol new $topology_path waitfor all]
        set frame_metadata {}
        set loaded_files 0

        foreach step $steps {
            foreach part $parts {
                set substitutions [list \
                    "{prefix}" $prefix \
                    "{step}" $step \
                    "{replica}" $replica \
                    "{part}" $part]
                set trajectory_name [string map $substitutions $trajectory_template]
                set trajectory_path [file normalize [file join $system_dir $trajectory_name]]

                if {![file exists $trajectory_path]} {
                    puts "WARNING: Missing $trajectory_path; skipping"
                    continue
                }

                puts "Loading $trajectory_path"
                set frames_before [molinfo $molid get numframes]
                mol addfile $trajectory_path start 0 last -1 step $stride waitfor all molid $molid
                set frames_after [molinfo $molid get numframes]
                set frames_added [expr {$frames_after - $frames_before}]
                if {$frames_added < 0} {
                    mol delete $molid
                    error "VMD reported a negative frame count after loading $trajectory_path"
                }
                for {set index 0} {$index < $frames_added} {incr index} {
                    set source_frame_0based [expr {$index * $stride}]
                    lappend frame_metadata [list \
                        $replica [expr {$frames_before + $index}] \
                        $trajectory_path $source_frame_0based \
                        [expr {$source_frame_0based + 1}]]
                }
                incr loaded_files
            }
        }

        if {$loaded_files == 0 || [llength $frame_metadata] == 0} {
            puts "WARNING: No trajectory frames were loaded for $system_id replica $replica"
            mol delete $molid
            continue
        }

        foreach signature $system_signatures {
            lassign $signature signature_id label mode selection_1 selection_2
            puts "Measuring $signature_id for $system_id replica $replica ($mode)"
            if {[catch {
                set distances [compute_distances \
                    $molid $mode $selection_1 $selection_2 $analysis_progress_interval]
            } distance_error]} {
                mol delete $molid
                puts stderr "ERROR: Could not measure $signature_id for $system_id replica $replica: $distance_error"
                quit
            }

            set base [format "%s_%s_steps%s-%s" $system_id $signature_id $first_step $last_step]
            set dist_file [file join $output_dir [format "%s_rep%s_dist.dat" $base $replica]]
            set metadata_file [file join $output_dir [format "%s_rep%s_frame_metadata.csv" $base $replica]]
            write_distance_file $distances $dist_file
            write_metadata_file $system_id $signature_id $distances $frame_metadata $metadata_file

            if {$analysis_write_replica_histograms} {
                set histogram_file [file join $output_dir [format "%s_rep%s_stats.dat" $base $replica]]
                write_histogram_file $distances $analysis_histogram_bins $histogram_file
            }
            set all_distances($signature_id) [concat $all_distances($signature_id) $distances]
            set all_metadata($signature_id) [concat $all_metadata($signature_id) $frame_metadata]
        }
        mol delete $molid
    }

    foreach signature $system_signatures {
        set signature_id [lindex $signature 0]
        if {[llength $all_distances($signature_id)] == 0} {
            puts "WARNING: No distances were collected for $system_id / $signature_id"
            continue
        }
        set base [format "%s_%s_all" $system_id $signature_id]
        write_distance_file \
            $all_distances($signature_id) \
            [file join $output_dir [format "%s_dist.dat" $base]]
        write_metadata_file \
            $system_id $signature_id $all_distances($signature_id) \
            $all_metadata($signature_id) \
            [file join $output_dir [format "%s_frame_metadata.csv" $base]]
        set analysis_success 1
        write_histogram_file \
            $all_distances($signature_id) $analysis_histogram_bins \
            [file join $output_dir [format "%s_stats.dat" $base]]
    }
}

if {!$analysis_success} {
    puts stderr "ERROR: No distance data were produced. Check the configured system paths and trajectory filenames."
    quit
}

puts "Done. Distance and frame-metadata files were written to $output_dir"
quit
