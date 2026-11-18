# VMD Protein Distance Analysis and MATLAB Figures

This repository provides a configurable workflow for calculating protein distances from molecular-dynamics trajectories in VMD and plotting the results in MATLAB. It supports multiple systems, replicates, step ranges, and activation signatures in one analysis.

The Tcl scripts also measure optional starting or reference structures. MATLAB can overlay those reference distances on trajectory and histogram panels. The workflow records which input trajectory file and source frame produced each value.

## What the workflow does

1. A short Python setup program collects system paths, trajectory naming, replicate and step ranges, atom selections, optional reference structures, and figure layouts.
2. VMD measures atom-to-atom distances or mass-weighted center-of-mass distances for every configured system, replicate, step, and signature.
3. VMD writes per-replicate distance files and frame metadata that maps sampled values back to the source trajectory files and frames.
4. MATLAB reads the generated configuration and metadata, then creates the requested figures and panels.

This repository analyzes distances only. It does not run molecular-dynamics simulations or calculate MM/PBSA energies.

## Requirements

- VMD with support for the topology and trajectory formats used by your simulations. The included example uses AMBER topology files (.prmtop) and NetCDF trajectory files (.nc).
- A shell where VMD is available. On an HPC system, load the site's VMD module before starting VMD.
- Python 3.10 or later for the interactive configuration program. It uses only the Python standard library.
- MATLAB with jsondecode, tiledlayout, histogram, and exportgraphics for figure generation.

No trajectory, topology, or reference-structure data are included. Replace the illustrative paths in the example configuration with paths to your own files.

## Quick start

Start the configuration prompts while your shell is in the directory that should be used as the base for relative system, reference, and output paths. You can call the Python script by its full path, so you do not have to change directories to reach the repository:

~~~bash
python3 /path/to/vmd-distance-analysis-pipeline/scripts/python/configure_pipeline.py
~~~

The setup records that starting directory as `path_base_dir`. Relative paths entered in the prompts will keep resolving from that directory, even when you launch VMD or MATLAB from elsewhere. The program asks for each system's name, display label, trajectory directory, topology, filename template, replicate range, step range, and sampling stride. It then asks for distance signatures, optional reference structures, and the MATLAB figures to create. It writes:

- config/pipeline_config.json for MATLAB and future edits
- config/pipeline_config.tcl for the VMD scripts

Load your site's VMD module first if needed. Then, from the directory saved as `path_base_dir`, export the repository and config paths and run VMD directly. This keeps VMD in your current shell environment and leaves the working directory unchanged:

~~~bash
export ANALYSIS_PROJECT_ROOT=/path/to/vmd-distance-analysis-pipeline
export ANALYSIS_CONFIG=/path/to/vmd-distance-analysis-pipeline/config/pipeline_config.tcl
vmd -dispdev text -e "$ANALYSIS_PROJECT_ROOT/scripts/vmd/run_distance_analysis.tcl"
~~~

If you configured starting/reference structures, calculate their distances with:

~~~bash
vmd -dispdev text -e "$ANALYSIS_PROJECT_ROOT/scripts/vmd/run_starting_references.tcl"
~~~

Create the MATLAB figures (the function finds the repository config by default):

~~~matlab
addpath('/path/to/vmd-distance-analysis-pipeline/scripts/matlab')
plot_distance_figures
~~~

The MATLAB function writes .fig and .png files under the configured output directory's `figures` subfolder.

## Run MATLAB on a separate Windows computer

The VMD analysis can run on a cluster while MATLAB creates figures on a Windows computer. MATLAB needs the configuration JSON and VMD's output files; it does not need the topology, trajectory, or reference-structure inputs.

Copy these items from the cluster to the Windows computer:

- `config/pipeline_config.json`
- `scripts/matlab/plot_distance_figures.m`
- The configured VMD output directory. Copy the whole directory to include all `*_all_frame_metadata.csv` files and, if you want reference overlays, `reference_distances.csv`.

In the Windows copy of `pipeline_config.json`, point `output_dir` to the folder where you copied the VMD output files. The simplest option is to use the full Windows path. For example, if the output files are in `C:/Users/YourName/Documents/vmd-distance-analysis-pipeline/results`, set:

~~~json
"path_base_dir": "C:/Users/YourName/Documents/vmd-distance-analysis-pipeline",
"output_dir": "C:/Users/YourName/Documents/vmd-distance-analysis-pipeline/results"
~~~

Here, `output_dir` is an absolute path, so MATLAB uses it directly. If instead `output_dir` is just `results`, it is relative: MATLAB joins it to `path_base_dir`, giving `C:/Users/YourName/Documents/vmd-distance-analysis-pipeline/results`. Forward slashes are valid in JSON Windows paths.

If your VMD output files are directly in the project folder, you do not need to create a `results` subfolder. For example, if you copy the project to `C:/Users/YourName/Documents/github_distance_matlab`, set both paths to that folder:

~~~json
"path_base_dir": "C:/Users/YourName/Documents/github_distance_matlab",
"output_dir": "C:/Users/YourName/Documents/github_distance_matlab"
~~~

Make these edits only in the Windows copy of the JSON; keep the cluster configuration unchanged for VMD runs. The Linux paths for topologies and trajectories can remain as they are because MATLAB uses the system labels and frame intervals from those entries, not the input files.

In MATLAB, add the copied script folder to the path and pass the copied JSON file:

~~~matlab
addpath('C:/Users/YourName/Documents/vmd-distance-analysis-pipeline/scripts/matlab')
plot_distance_figures('C:/Users/YourName/Documents/vmd-distance-analysis-pipeline/config/pipeline_config.json')
~~~

MATLAB saves the figures in a `figures` subfolder under the Windows output directory.

## Systems and trajectory files

Each system has its own directory, topology file, trajectory prefix, step list, replicate list, suffix list, and stride. Paths can be absolute or relative to the directory where you started the configuration program. The config saves that directory so you can run the pipeline without changing your shell's working directory.

The trajectory filename template is applied to every combination of the configured steps, replicates, and suffixes. Press Enter at the prompt to keep the displayed default:

~~~text
{prefix}_step{step}{replica}{part}.nc
~~~

For example, with prefix `receptor_active`, steps 7–10, replicas a–d, and suffixes none and 2, the pipeline checks each combination, including:

~~~text
receptor_active_step7a.nc
receptor_active_step7a2.nc
receptor_active_step7b.nc
receptor_active_step7b2.nc
receptor_active_step8a.nc
~~~

The setup accepts ranges such as a-d and 7-10, or comma-separated values such as a,c,d and 7,9,10. For trajectory suffixes, enter none for a file without a suffix, or provide suffixes such as 2 or 2,3. The default stride loads every 100th source frame from each trajectory file. Change it to match the sampling resolution you need.

The topology filename may be given as a filename relative to that system's trajectory directory or as an absolute path. Systems can use different steps, replicates, and trajectory directories.

## Distance signatures and VMD selections

Every signature has a unique ID, a display label, two VMD atom selections, and a measurement mode:

- `atom_distance` measures the distance between one atom selected on each side. For example, select one C-beta atom from each of two residues to measure a C-beta–C-beta distance. It also supports C-alpha or other single-atom pairs; each selection must match exactly one atom.
- `com_distance` measures the distance between the mass-weighted centers of the selected atoms. Each selection can contain multiple atoms from one residue or from several residues; use it for sidechain groups or other atom groups.

For example, a C-beta distance between residues 147 and 309 is:

~~~text
Selection 1: protein and resid 147 and name CB
Selection 2: protein and resid 309 and name CB
Mode: atom_distance
~~~

A mass-weighted distance between the sidechains of those residues is:

~~~text
Selection 1: protein and resid 147 and sidechain
Selection 2: protein and resid 309 and sidechain
Mode: com_distance
~~~

Although each selection above names one residue, `com_distance` is appropriate because each residue's sidechain selection includes multiple atoms. The choice between the two modes depends on how many atoms each selection matches, not how many residues it names.

The same signature can be assigned to several systems when residue numbering and atom names match. If numbering differs, define separate signatures and assign each to the appropriate systems. More selection examples and guidance are in [docs/vmd-selection-examples.md](docs/vmd-selection-examples.md).

## Reference structures

Reference structures are optional. Add one or more PDB or other VMD-readable structure paths in the setup prompts. Each reference is assigned a label, such as active or inactive, and one or more systems. For each selected system, the reference script measures every activation signature assigned to that system; you do not select signatures separately for a reference. It writes one row per reference, system, and signature to results/reference_distances.csv. MATLAB overlays the reference distance matching each panel's system and signature.

When a figure panel has reference overlays enabled, MATLAB draws the matching reference distances as horizontal lines on trajectory panels and vertical lines on histogram panels.

## MATLAB figure panels

The setup prompts for the number of figures and panels in each figure. For every panel, choose one system, one signature, and one view:

- trajectory plots each replicate as a separate line.
- histogram plots the pooled distance distribution for the configured replicates of that system and signature.

The prompt asks for a column count and arranges the requested panels in a grid. To make both views for the same system and signature, add two panels. Enter the interval between frames after the VMD stride, in nanoseconds. For example, if a 1-μs trajectory has 10,000 saved frames and VMD loads every 100th frame, each loaded frame represents 10 ns. Trajectory plots show time in microseconds when this interval is supplied; leave it blank to use the loaded-frame index.

The distribution panels are horizontal histograms: distance (Å) is on the vertical axis, and observed time (μs) for each distance bin is on the horizontal axis. The time is calculated from the number of loaded frames in each bin multiplied by the loaded-frame interval, then pooled across the selected replicates. When a loaded-frame interval is supplied, the time axis uses ticks every 0.5 μs; otherwise, the horizontal axis shows frame count. All plots for the same signature share y-axis limits and tick marks, calculated across the configured systems and reference values. Reference lines are solid; labels containing “inactive” are red and labels containing “active” are blue. Trajectory traces use a separate color palette that avoids those reference colors.

You can change the figure titles, panel assignments, and layout later in config/pipeline_config.json. After editing that JSON file, regenerate its VMD companion with:

~~~bash
python3 /path/to/vmd-distance-analysis-pipeline/scripts/python/configure_pipeline.py --from-json /path/to/vmd-distance-analysis-pipeline/config/pipeline_config.json
~~~

Run that command from the directory that should be the base for relative paths. For a configuration created by an older draft, the command asks before adding the current directory as `path_base_dir` to the JSON and regenerating the Tcl file. This preserves the paths you have already entered without making you re-enter the prompts. The JSON file is the MATLAB configuration source. The matching Tcl file is generated from it for VMD.

## Output files

VMD writes results to the configured output directory:

- *_rep*_dist.dat: numeric loaded-frame index and distance for one replicate.
- *_rep*_frame_metadata.csv: one record per sampled distance, including replicate, VMD frame, source trajectory path, and source frame numbers.
- *_all_dist.dat: distance values pooled across available replicates.
- *_all_frame_metadata.csv: pooled frame metadata consumed by MATLAB.
- *_all_stats.dat: pooled distance-count histogram.
- reference_distances.csv: optional measurements from configured starting/reference structures.

Distances are in angstroms. Missing trajectory parts are reported and skipped. A missing topology, an empty selection, or an invalid atom-distance selection stops the analysis with an error.

## Example configuration

config/example_config.json demonstrates four 5-HT1B system labels, steps 7–10, replicas a–d, a C-beta distance, a sidechain center-of-mass distance, reference structures, and a four-panel MATLAB figure. Its file paths are examples; it is not a runnable dataset.

## Authors, contributions, and citations

- **Elspeth Allen:** software implementation, testing, and documentation.
- **Ravinder Abrol:** conceptualization and methodology; provided the initial MATLAB figure format, suggested reference lines, and recommended atom selections for activation signatures.

The distance-analysis approach builds on the `distance.tcl` example in Section 4.3, “Example of an analysis script,” of the [Using VMD tutorial](https://www.ks.uiuc.edu/Training/Tutorials/vmd/tutorial-html/node5.html), from the Theoretical and Computational Biophysics Group at the University of Illinois at Urbana-Champaign. The pipeline implementation has been adapted and extended from that example.

For published analyses using VMD, cite: Humphrey, W., Dalke, A., and Schulten, K. “VMD - Visual Molecular Dynamics.” *Journal of Molecular Graphics*, 14, 33–38 (1996). Include a link to the [official VMD site](https://www.ks.uiuc.edu/Research/vmd/).

## Notes for reproducible analysis

- Check that every VMD selection matches the intended atoms in every assigned topology.
- The residue numbering in VMD selections must match the numbering in the loaded topology or structure.
- Keep topology, trajectory, and reference structures consistent with the systems being analyzed.
- The frame metadata are intended to preserve the mapping from sampled distance values to source trajectory frames.
- Use an appropriate stride and frame-time conversion for your trajectory output frequency.
