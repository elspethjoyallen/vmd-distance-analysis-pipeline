# Shared setup, validation, measurement, and output helpers.
# The distance-analysis approach builds on the `distance.tcl` example in
# Section 4.3, “Example of an analysis script,” of the Using VMD tutorial:
# https://www.ks.uiuc.edu/Training/Tutorials/vmd/tutorial-html/node5.html
# This implementation has been adapted and extended for the analysis pipeline.

proc load_analysis_config {} {
    if {[info exists ::env(ANALYSIS_CONFIG)] && $::env(ANALYSIS_CONFIG) ne ""} {
        set config_file $::env(ANALYSIS_CONFIG)
    } else {
        set config_file "config/pipeline_config.tcl"
    }
    if {![file exists $config_file]} {
        error "Configuration not found: $config_file. Run scripts/python/configure_pipeline.py first."
    }
    uplevel #0 [list source [file normalize $config_file]]
}

proc validate_analysis_config {} {
    global analysis_output_dir analysis_path_base_dir analysis_histogram_bins
    global analysis_write_replica_histograms analysis_progress_interval
    global analysis_systems analysis_signatures analysis_references

    foreach variable {
        analysis_output_dir analysis_histogram_bins
        analysis_write_replica_histograms analysis_progress_interval
        analysis_systems analysis_signatures analysis_references
    } {
        if {![uplevel #0 [list info exists ::$variable]]} {
            error "Required configuration value is missing: $variable"
        }
    }
    if {![info exists analysis_path_base_dir] || $analysis_path_base_dir eq ""} {
        set analysis_path_base_dir [pwd]
    }
    set analysis_path_base_dir [file normalize $analysis_path_base_dir]
    if {$analysis_output_dir eq ""} {
        error "analysis_output_dir cannot be empty"
    }
    if {![string is integer -strict $analysis_histogram_bins] || $analysis_histogram_bins < 2} {
        error "analysis_histogram_bins must be an integer of at least 2"
    }
    if {$analysis_write_replica_histograms ne "0" && $analysis_write_replica_histograms ne "1"} {
        error "analysis_write_replica_histograms must be 0 or 1"
    }
    if {![string is integer -strict $analysis_progress_interval] || $analysis_progress_interval < 1} {
        error "analysis_progress_interval must be a positive integer"
    }
    if {[llength $analysis_systems] == 0 || [llength $analysis_signatures] == 0} {
        error "Configure at least one system and one distance signature"
    }

    set system_ids {}
    foreach system $analysis_systems {
        if {[llength $system] != 10} {
            error "Each system entry must contain 10 fields: $system"
        }
        lassign $system system_id display_name system_dir prefix topology steps replicas parts stride template
        if {![regexp {^[A-Za-z0-9][A-Za-z0-9_]*$} $system_id]} {
            error "System IDs must contain only letters, numbers, and underscores: $system_id"
        }
        if {[lsearch -exact $system_ids $system_id] != -1} {
            error "Duplicate system ID: $system_id"
        }
        lappend system_ids $system_id
        if {$display_name eq "" || $system_dir eq "" || $prefix eq "" || $topology eq ""} {
            error "System display name, directory, prefix, and topology are required: $system_id"
        }
        if {[llength $steps] == 0 || [llength $replicas] == 0 || [llength $parts] == 0} {
            error "Each system needs at least one step, replicate, and trajectory suffix: $system_id"
        }
        foreach step $steps {
            if {![string is integer -strict $step]} {
                error "Step values must be whole numbers for $system_id: $step"
            }
        }
        foreach replica $replicas {
            if {![regexp {^[A-Za-z0-9_-]+$} $replica]} {
                error "Replica labels may contain letters, numbers, underscores, or hyphens: $replica"
            }
        }
        if {![string is integer -strict $stride] || $stride < 1} {
            error "Frame stride must be a positive integer for $system_id"
        }
        foreach token [list "{prefix}" "{step}" "{replica}" "{part}"] {
            if {[string first $token $template] == -1} {
                error "Trajectory pattern for $system_id must include $token"
            }
        }
    }

    set seen_signatures {}
    foreach signature $analysis_signatures {
        if {[llength $signature] != 6} {
            error "Each signature entry must contain 6 fields: $signature"
        }
        lassign $signature signature_id label mode selection_1 selection_2 scope
        if {![regexp {^[A-Za-z0-9][A-Za-z0-9_]*$} $signature_id]} {
            error "Signature IDs must contain only letters, numbers, and underscores: $signature_id"
        }
        if {[lsearch -exact $seen_signatures $signature_id] != -1} {
            error "Signature IDs must be unique: $signature_id"
        }
        lappend seen_signatures $signature_id
        if {$label eq "" || $selection_1 eq "" || $selection_2 eq ""} {
            error "Signature label and both VMD selections are required: $signature_id"
        }
        if {$mode ne "atom_distance" && $mode ne "com_distance"} {
            error "Signature $signature_id mode must be atom_distance or com_distance"
        }
        if {[llength $scope] == 0} {
            error "Signature $signature_id is not assigned to any system"
        }
        foreach system_id $scope {
            if {[lsearch -exact $system_ids $system_id] == -1} {
                error "Signature $signature_id refers to an unknown system: $system_id"
            }
        }
    }
    foreach system_id $system_ids {
        if {[llength [signatures_for_system $system_id]] == 0} {
            error "No signatures are assigned to system $system_id"
        }
    }

    foreach reference $analysis_references {
        if {[llength $reference] != 3} {
            error "Each reference entry must contain a label, path, and system list: $reference"
        }
        lassign $reference reference_label reference_path scope
        if {$reference_label eq "" || $reference_path eq "" || [llength $scope] == 0} {
            error "Reference label, path, and at least one system are required: $reference"
        }
        foreach system_id $scope {
            if {[lsearch -exact $system_ids $system_id] == -1} {
                error "Reference $reference_label refers to an unknown system: $system_id"
            }
        }
    }
}

proc signatures_for_system {system_id} {
    global analysis_signatures
    set selected {}
    foreach signature $analysis_signatures {
        lassign $signature signature_id label mode selection_1 selection_2 scope
        if {[lsearch -exact $scope $system_id] != -1} {
            lappend selected [list $signature_id $label $mode $selection_1 $selection_2]
        }
    }
    return $selected
}

proc resolve_system_path {system_dir path} {
    if {[file pathtype $path] eq "absolute"} {
        return [file normalize $path]
    }
    return [file normalize [file join $system_dir $path]]
}

proc resolve_config_path {path} {
    global analysis_path_base_dir
    if {[file pathtype $path] eq "absolute"} {
        return [file normalize $path]
    }
    return [file normalize [file join $analysis_path_base_dir $path]]
}

proc csv_quote {value} {
    set value [string map [list "\"" "\"\""] $value]
    return "\"$value\""
}

proc csv_row {values} {
    set quoted {}
    foreach value $values {
        lappend quoted [csv_quote $value]
    }
    return [join $quoted ","]
}

proc distance_from_selections {mode sel1 sel2} {
    if {$mode eq "atom_distance"} {
        set point1 [lindex [$sel1 get {x y z}] 0]
        set point2 [lindex [$sel2 get {x y z}] 0]
    } elseif {$mode eq "com_distance"} {
        set point1 [measure center $sel1 weight mass]
        set point2 [measure center $sel2 weight mass]
    } else {
        $sel1 delete
        $sel2 delete
        error "Unknown distance mode: $mode"
    }
    return [veclength [vecsub $point1 $point2]]
}

proc validate_selections {sel1 sel2 mode selection_1 selection_2} {
    set count_1 [$sel1 num]
    set count_2 [$sel2 num]
    if {$count_1 == 0} {
        error "Selection 1 matched no atoms: $selection_1"
    }
    if {$count_2 == 0} {
        error "Selection 2 matched no atoms: $selection_2"
    }
    if {$mode eq "atom_distance" && ($count_1 != 1 || $count_2 != 1)} {
        error "atom_distance requires exactly one atom in each selection (found $count_1 and $count_2): '$selection_1' / '$selection_2'"
    }
}

proc compute_distance {molid mode selection_1 selection_2 frame} {
    set sel1 [atomselect $molid $selection_1]
    set sel2 [atomselect $molid $selection_2]
    set status [catch {
        validate_selections $sel1 $sel2 $mode $selection_1 $selection_2
        $sel1 frame $frame
        $sel2 frame $frame
        distance_from_selections $mode $sel1 $sel2
    } result options]
    catch {$sel1 delete}
    catch {$sel2 delete}
    if {$status} {
        return -options $options $result
    }
    return $result
}

proc compute_distances {molid mode selection_1 selection_2 progress_interval} {
    set frame_count [molinfo $molid get numframes]
    if {$frame_count < 1} {
        error "The loaded molecule contains no frames"
    }
    set sel1 [atomselect $molid $selection_1]
    set sel2 [atomselect $molid $selection_2]
    set status [catch {
        validate_selections $sel1 $sel2 $mode $selection_1 $selection_2
        set distances {}
        for {set frame 0} {$frame < $frame_count} {incr frame} {
            if {$frame % $progress_interval == 0 || $frame == $frame_count - 1} {
                puts "  frame [expr {$frame + 1}] of $frame_count"
            }
            $sel1 frame $frame
            $sel2 frame $frame
            lappend distances [distance_from_selections $mode $sel1 $sel2]
        }
        set distances
    } result options]
    catch {$sel1 delete}
    catch {$sel2 delete}
    if {$status} {
        return -options $options $result
    }
    return $result
}

proc write_distance_file {distances outfile} {
    set handle [open $outfile w]
    for {set index 0} {$index < [llength $distances]} {incr index} {
        puts $handle "$index , [lindex $distances $index]"
    }
    close $handle
}

proc write_metadata_file {system_id signature_id distances frame_metadata outfile} {
    if {[llength $distances] != [llength $frame_metadata]} {
        error "Distance/frame metadata count mismatch for $system_id / $signature_id"
    }
    set handle [open $outfile w]
    puts $handle "system_name,signature_name,replica,distance_index,vmd_frame,source_nc,source_frame_0based,source_frame_1based,distance_angstrom"
    for {set index 0} {$index < [llength $distances]} {incr index} {
        lassign [lindex $frame_metadata $index] replica vmd_frame source_nc source_frame_0based source_frame_1based
        set row [list \
            $system_id $signature_id $replica $index $vmd_frame \
            $source_nc $source_frame_0based $source_frame_1based \
            [format "%.8f" [lindex $distances $index]]]
        puts $handle [csv_row $row]
    }
    close $handle
}

proc write_histogram_file {distances n_bins outfile} {
    if {[llength $distances] == 0} {
        error "No distances were provided for histogram output: $outfile"
    }
    set minimum [lindex $distances 0]
    set maximum $minimum
    foreach distance $distances {
        if {$distance < $minimum} { set minimum $distance }
        if {$distance > $maximum} { set maximum $distance }
    }

    set handle [open $outfile w]
    if {$maximum == $minimum} {
        puts $handle "$minimum , [llength $distances]"
        for {set bin 1} {$bin < $n_bins} {incr bin} {
            puts $handle "$minimum , 0"
        }
        close $handle
        return
    }

    set width [expr {($maximum - $minimum) / double($n_bins - 1)}]
    for {set bin 0} {$bin < $n_bins} {incr bin} {
        set count($bin) 0
    }
    foreach distance $distances {
        set bin [expr {int(($distance - $minimum) / $width)}]
        if {$bin >= $n_bins} { set bin [expr {$n_bins - 1}] }
        incr count($bin)
    }
    for {set bin 0} {$bin < $n_bins} {incr bin} {
        set coordinate [expr {$minimum + $bin * $width}]
        puts $handle "$coordinate , $count($bin)"
    }
    close $handle
}
