# VMD selection examples for distance measurements

Enter two VMD selection expressions for each distance signature. The script measures the distance between the selected atoms or groups in every loaded trajectory frame.

## One atom to one atom

Use atom_distance when each selection returns exactly one atom.

| Distance | Selection 1 | Selection 2 |
|---|---|---|
| C-beta to C-beta | protein and resid 147 and name CB | protein and resid 309 and name CB |
| C-alpha to C-alpha | protein and resid 147 and name CA | protein and resid 309 and name CA |
| Named atom on two residues | protein and resid 50 and name NZ | protein and resid 120 and name OE1 |
| Chain-specific atom | chain A and resid 42 and name CA | chain B and resid 90 and name CA |

If either selection contains zero atoms or more than one atom, VMD stops with an explanatory error. Add a chain, segment, atom-name, or other selection condition until each side selects exactly one atom.

## Center of mass between atom groups

Use com_distance to calculate the mass-weighted center of each selection and measure between those centers.

| Distance | Selection 1 | Selection 2 |
|---|---|---|
| Sidechain COM to sidechain COM | protein and resid 147 and sidechain | protein and resid 309 and sidechain |
| Backbone group COMs | protein and resid 10 to 14 and backbone | protein and resid 45 to 49 and backbone |
| Sidechain group in a specific chain | chain A and resid 42 and sidechain | chain A and resid 90 and sidechain |

For center-of-mass measurements, each selection can contain any number of atoms. VMD uses the atom masses supplied by the loaded topology or structure.

## Selection terms

- protein limits the selection to protein atoms.
- resid 147 selects the residue whose VMD residue identifier is 147.
- resid 10 to 14 selects an inclusive residue range.
- name CB or name CA selects atoms by atom name.
- sidechain and backbone are VMD selection keywords.
- chain A selects atoms assigned to chain A when the structure contains chain identifiers.

## Check selections before a long run

Load the matching topology in VMD and test the selection in the VMD command window. For example:

~~~tcl
set test_selection [atomselect top "protein and resid 147 and name CB"]
$test_selection num
$test_selection get {resid resname name}
$test_selection delete
~~~

For atom_distance, the num result should be 1 for both selections. For com_distance, it should be greater than 0. Residue identifiers can differ between a PDB reference and a simulation topology, so check selections on both kinds of input.
