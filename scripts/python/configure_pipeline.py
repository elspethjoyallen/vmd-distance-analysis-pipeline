#!/usr/bin/env python3
"""Create the JSON and Tcl configuration files for the VMD/MATLAB pipeline."""

from __future__ import annotations

import argparse
import json
import math
import re
import string
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[2]
CONFIG_DIR = PROJECT_ROOT / "config"
ID_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_]*$")


def ask(prompt: str, default: str | None = None) -> str:
    suffix = f" [{default}]" if default is not None else ""
    while True:
        value = input(f"{prompt}{suffix}: ").strip()
        if value:
            return value
        if default is not None:
            return default
        print("Please enter a value.")


def ask_int(prompt: str, default: int, minimum: int = 1) -> int:
    while True:
        raw = ask(prompt, str(default))
        try:
            value = int(raw)
        except ValueError:
            print("Enter a whole number.")
            continue
        if value < minimum:
            print(f"Enter a number of at least {minimum}.")
            continue
        return value


def ask_yes_no(prompt: str, default: bool = True) -> bool:
    default_text = "Y/n" if default else "y/N"
    while True:
        raw = input(f"{prompt} [{default_text}]: ").strip().lower()
        if not raw:
            return default
        if raw in {"y", "yes"}:
            return True
        if raw in {"n", "no"}:
            return False
        print("Enter y or n.")


def expand_range(raw: str, label: str, numeric_only: bool = False) -> list[str]:
    """Expand a range such as a-d or 7-10, or a comma-separated list."""
    raw = raw.strip().replace(" ", "")
    if not raw:
        raise ValueError(f"{label} cannot be empty")

    if "," in raw:
        values = raw.split(",")
    elif "-" in raw:
        first, last = raw.split("-", 1)
        if first.isdigit() and last.isdigit():
            start, end = int(first), int(last)
            if end < start:
                raise ValueError(f"{label} range must go from low to high")
            values = [str(value) for value in range(start, end + 1)]
        elif (
            not numeric_only
            and len(first) == 1
            and len(last) == 1
            and first.isalpha()
            and last.isalpha()
            and first.islower() == last.islower()
        ):
            start, end = ord(first), ord(last)
            if end < start:
                raise ValueError(f"{label} range must go from low to high")
            values = [chr(value) for value in range(start, end + 1)]
        else:
            raise ValueError(
                f"Use a numeric range, a letter range, or comma-separated values for {label}"
            )
    else:
        values = [raw]

    if any(not value for value in values):
        raise ValueError(f"{label} contains an empty value")
    if numeric_only and any(not value.isdigit() for value in values):
        raise ValueError(f"{label} must contain whole numbers")
    if len(set(values)) != len(values):
        raise ValueError(f"{label} contains repeated values")
    return values


def ask_range(prompt: str, default: str, label: str, numeric_only: bool = False) -> list[str]:
    while True:
        raw = ask(prompt, default)
        try:
            return expand_range(raw, label, numeric_only)
        except ValueError as exc:
            print(exc)


def ask_parts() -> list[str]:
    while True:
        raw = ask(
            "Trajectory filename suffixes after the replica label (none means no suffix)",
            "none,2",
        )
        values = [value.strip() for value in raw.split(",")]
        if values and all(value for value in values):
            parts = ["" if value.lower() == "none" else value for value in values]
            if len(set(parts)) == len(parts):
                return parts
            print("Enter each suffix only once.")
            continue
        print("Use comma-separated suffixes such as none,2 or just none.")


def ask_template() -> str:
    default = "{prefix}_step{step}{replica}{part}.nc"
    print(
        "This template is applied to every configured step, replicate, and suffix. "
        "Press Enter to keep the default."
    )
    while True:
        template = ask(
            "Trajectory filename template using {prefix}, {step}, {replica}, and {part}",
            default,
        )
        try:
            fields = [
                field
                for _, field, _, _ in string.Formatter().parse(template)
                if field is not None
            ]
        except ValueError as exc:
            print(f"Invalid pattern: {exc}")
            continue
        allowed = {"prefix", "step", "replica", "part"}
        if set(fields) == allowed:
            return template
        print("The pattern must include only these four placeholders: {prefix}, {step}, {replica}, and {part}.")


def ask_scope(system_ids: list[str], prompt: str) -> list[str]:
    print("Available system IDs: " + ", ".join(system_ids))
    while True:
        raw = ask(prompt, "all").strip()
        if raw.lower() == "all":
            return list(system_ids)
        selected = [part.strip() for part in raw.split(",") if part.strip()]
        unknown = sorted(set(selected) - set(system_ids))
        if unknown:
            print("Unknown system ID(s): " + ", ".join(unknown))
            continue
        if len(set(selected)) != len(selected):
            print("Enter each system ID only once.")
            continue
        if not selected:
            print("Select at least one system.")
            continue
        return selected


def ask_systems() -> list[dict]:
    systems: list[dict] = []
    count = ask_int("How many systems should this analysis include?", 2)
    for index in range(count):
        print(f"\nSystem {index + 1} of {count}")
        while True:
            system_id = ask("System name")
            if not ID_PATTERN.fullmatch(system_id):
                print("Use a name that starts with a letter or number and contains only letters, numbers, and underscores.")
                continue
            if any(item["id"] == system_id for item in systems):
                print("That system ID is already in use.")
                continue
            break

        display_name = ask("Display name for figures", system_id.replace("_", " "))
        directory = ask("Directory containing this system's topology and trajectories")
        prefix = ask("Trajectory filename prefix", system_id)
        topology = ask(
            "Topology filename or path relative to the system directory",
            f"{prefix}_md.prmtop",
        )
        steps = ask_range("Steps to include, such as 7-10", "7-10", "steps", numeric_only=True)
        replicas = ask_range("Replicates to include, such as a-d", "a-d", "replicates")
        parts = ask_parts()
        stride = ask_int("Load every Nth frame from each trajectory file", 100)
        while True:
            print("Enter the time spacing between loaded frames after applying the stride.")
            print("Example: a 1-microsecond file with 10,000 saved frames and stride 100 gives 10 ns per loaded frame.")
            raw_interval = input(
                "Loaded-frame interval in ns (blank uses sample index): "
            ).strip()
            if not raw_interval:
                frame_interval_ns = 0.0
                break
            try:
                frame_interval_ns = float(raw_interval)
                if frame_interval_ns <= 0:
                    raise ValueError
                break
            except ValueError:
                print("Enter a positive number or leave blank.")

        systems.append(
            {
                "id": system_id,
                "display_name": display_name,
                "directory": directory,
                "prefix": prefix,
                "topology": topology,
                "steps": steps,
                "replicas": replicas,
                "parts": parts,
                "stride": stride,
                "template": ask_template(),
                "frame_interval_ns": frame_interval_ns,
            }
        )
    return systems


def ask_signatures(systems: list[dict]) -> list[dict]:
    system_ids = [system["id"] for system in systems]
    signatures: list[dict] = []
    count = ask_int("\nHow many distance signatures should be analyzed?", 1)
    for index in range(count):
        print(f"\nSignature {index + 1} of {count}")
        while True:
            signature_id = ask("Short signature ID (letters, numbers, underscores)")
            if not ID_PATTERN.fullmatch(signature_id):
                print("Use a name that starts with a letter or number and contains only letters, numbers, and underscores.")
                continue
            if any(item["id"] == signature_id for item in signatures):
                print("That signature ID is already in use.")
                continue
            break

        label = ask("Figure label for this signature", signature_id.replace("_", " "))
        scope = ask_scope(
            system_ids,
            "Apply this selection to which systems? (all or comma-separated IDs)",
        )
        print(
            "Measurement types: atom_distance measures between one atom in each selection "
            "(for example, C-beta to C-beta between two residues). "
            "com_distance measures the mass-weighted centers of the selected atoms; each selection "
            "can contain multiple atoms from one residue or several residues."
        )
        while True:
            mode = ask("Measurement type (atom_distance or com_distance)", "atom_distance").lower()
            if mode in {"atom_distance", "com_distance"}:
                break
            print("Choose atom_distance or com_distance.")
        if mode == "atom_distance":
            example_1 = "protein and resid 147 and name CB"
            example_2 = "protein and resid 309 and name CB"
        else:
            example_1 = "protein and resid 147 and sidechain"
            example_2 = "protein and resid 309 and sidechain"
        selection_1 = ask(f"VMD selection 1 (example: {example_1})")
        selection_2 = ask(f"VMD selection 2 (example: {example_2})")
        signatures.append(
            {
                "id": signature_id,
                "label": label,
                "mode": mode,
                "selection_1": selection_1,
                "selection_2": selection_2,
                "systems": scope,
            }
        )
    return signatures


def ask_references(system_ids: list[str]) -> list[dict]:
    references: list[dict] = []
    count = ask_int(
        "\nHow many starting/reference structures should be measured? (0 to skip)",
        0,
        minimum=0,
    )
    for index in range(count):
        print(f"\nReference structure {index + 1} of {count}")
        label = ask("Reference label, such as active or inactive")
        path = ask("Path to the starting PDB or other structure file")
        print("This reference will be measured for every activation signature assigned to each selected system.")
        scope = ask_scope(
            system_ids,
            "Use this reference with which systems? (all or comma-separated IDs)",
        )
        references.append({"label": label, "path": path, "systems": scope})
    return references


def choose_numbered(prompt: str, choices: list[dict], label_key: str) -> dict:
    for index, choice in enumerate(choices, start=1):
        print(f"  {index}. {choice[label_key]}")
    while True:
        raw = ask(prompt)
        try:
            selected = int(raw)
        except ValueError:
            print("Enter the number beside your choice.")
            continue
        if 1 <= selected <= len(choices):
            return choices[selected - 1]
        print(f"Choose a number from 1 to {len(choices)}.")


def ask_figures(systems: list[dict], signatures: list[dict], references: list[dict]) -> list[dict]:
    count = ask_int("\nHow many MATLAB figures should the setup include?", 1)
    figures: list[dict] = []
    for figure_index in range(count):
        print(f"\nFigure {figure_index + 1} of {count}")
        title = ask("Figure title", f"Distance analysis figure {figure_index + 1}")
        panel_count = ask_int("Number of panels in this figure", 4)
        default_columns = max(1, math.ceil(math.sqrt(panel_count)))
        columns = ask_int("Number of columns", default_columns)
        rows = math.ceil(panel_count / columns)
        panels: list[dict] = []

        for panel_index in range(panel_count):
            print(f"\nPanel {panel_index + 1} of {panel_count}")
            while True:
                system = choose_numbered("System number", systems, "display_name")
                valid_signatures = [
                    signature
                    for signature in signatures
                    if system["id"] in signature["systems"]
                ]
                if valid_signatures:
                    break
                print(f"No signature is assigned to {system['id']}. Choose another system.")

            signature = choose_numbered("Signature number", valid_signatures, "label")
            print("  1. trajectory trace")
            print("  2. distance histogram")
            while True:
                kind_raw = ask("Panel type", "1").lower()
                if kind_raw in {"1", "trajectory", "trace"}:
                    kind = "trajectory"
                    break
                if kind_raw in {"2", "histogram", "distribution"}:
                    kind = "histogram"
                    break
                print("Choose 1 for a trajectory trace or 2 for a distance histogram.")
            show_refs = ask_yes_no(
                "Overlay matching reference distances?",
                bool(references),
            )
            panels.append(
                {
                    "system_id": system["id"],
                    "signature_id": signature["id"],
                    "kind": kind,
                    "show_references": show_refs,
                }
            )

        figures.append(
            {"title": title, "rows": rows, "columns": columns, "panels": panels}
        )
    return figures


def tcl_quote(value: object) -> str:
    """Quote a Tcl word while protecting substitutions and list separators."""
    text = str(value)
    escapes = {
        "\\": "\\\\",
        '"': '\\"',
        "$": "\\$",
        "[": "\\[",
        "]": "\\]",
        ";": "\\;",
    }
    return '"' + "".join(escapes.get(char, char) for char in text) + '"'


def tcl_list(values: list[object]) -> str:
    return "[list " + " ".join(tcl_quote(value) for value in values) + "]"


def render_tcl_config(config: dict) -> str:
    lines = [
        "# Generated by scripts/python/configure_pipeline.py.",
        "# Edit the JSON config and regenerate this file; do not edit it by hand.",
        f"set analysis_output_dir {tcl_quote(config['output_dir'])}",
        f"set analysis_path_base_dir {tcl_quote(config.get('path_base_dir') or Path.cwd().resolve())}",
        f"set analysis_histogram_bins {int(config['histogram_bins'])}",
        f"set analysis_write_replica_histograms {1 if config['write_replica_histograms'] else 0}",
        f"set analysis_progress_interval {int(config['progress_interval'])}",
        "set analysis_systems [list \\",
    ]

    for system in config["systems"]:
        values = [
            system["id"],
            system["display_name"],
            system["directory"],
            system["prefix"],
            system["topology"],
        ]
        row = "[list " + " ".join(tcl_quote(value) for value in values)
        row += " " + tcl_list(system["steps"])
        row += " " + tcl_list(system["replicas"])
        row += " " + tcl_list(system["parts"])
        row += " " + tcl_quote(system["stride"])
        row += " " + tcl_quote(system["template"]) + "]"
        lines.append("    " + row + " " + chr(92))

    lines.extend(["]", "set analysis_signatures [list \\"])
    for signature in config["signatures"]:
        values = [
            signature["id"],
            signature["label"],
            signature["mode"],
            signature["selection_1"],
            signature["selection_2"],
        ]
        row = "[list " + " ".join(tcl_quote(value) for value in values)
        row += " " + tcl_list(signature["systems"]) + "]"
        lines.append("    " + row + " " + chr(92))

    lines.extend(["]", "set analysis_references [list \\"])
    for reference in config["references"]:
        row = "[list " + " ".join(
            tcl_quote(value) for value in [reference["label"], reference["path"]]
        )
        row += " " + tcl_list(reference["systems"]) + "]"
        lines.append("    " + row + " " + chr(92))
    lines.append("]")
    return "\n".join(lines) + "\n"


def write_config(config: dict, json_path: Path) -> None:
    tcl_path = json_path.with_suffix(".tcl")
    existing = [path for path in (json_path, tcl_path) if path.exists()]
    if existing:
        paths = ", ".join(str(path.relative_to(PROJECT_ROOT)) for path in existing)
        if not ask_yes_no(f"Replace existing configuration file(s): {paths}?", False):
            print("No files were changed.")
            return

    json_path.parent.mkdir(parents=True, exist_ok=True)
    json_path.write_text(json.dumps(config, indent=2) + "\n", encoding="utf-8")
    tcl_path.write_text(render_tcl_config(config), encoding="utf-8")
    print(f"\nWrote {json_path.relative_to(PROJECT_ROOT)}")
    print(f"Wrote {tcl_path.relative_to(PROJECT_ROOT)}")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Create the JSON and VMD Tcl configuration for distance analysis."
    )
    parser.add_argument(
        "--from-json",
        type=Path,
        help="Generate the matching Tcl file from an edited JSON configuration.",
    )
    args = parser.parse_args()

    if args.from_json:
        json_path = args.from_json
        if not json_path.is_absolute():
            json_path = PROJECT_ROOT / json_path
        if not json_path.is_file():
            parser.error(f"Configuration file not found: {json_path}")
        config = json.loads(json_path.read_text(encoding="utf-8"))
        added_path_base = False
        if not config.get("path_base_dir"):
            config["path_base_dir"] = str(Path.cwd().resolve())
            added_path_base = True
        tcl_path = json_path.with_suffix(".tcl")
        replace_prompt = f"Replace {tcl_path.name}"
        if added_path_base:
            replace_prompt += f" and save the current directory as path_base_dir in {json_path.name}"
        if tcl_path.exists() and not ask_yes_no(replace_prompt + "?", False):
            print("No files were changed.")
            return 0
        if added_path_base:
            json_path.write_text(json.dumps(config, indent=2) + "\n", encoding="utf-8")
            print(
                "Added path_base_dir to the JSON config using the current directory. "
                "Relative paths will resolve from here."
            )
        tcl_path.write_text(render_tcl_config(config), encoding="utf-8")
        print(f"Wrote {tcl_path}")
        return 0

    print("VMD and MATLAB distance-analysis setup")
    print("Enter paths relative to the directory where you start this setup, or use absolute paths.")
    print("That directory is saved in the config so relative paths keep working when you launch the analysis later.")
    systems = ask_systems()
    signatures = ask_signatures(systems)
    references = ask_references([system["id"] for system in systems])
    figures = ask_figures(systems, signatures, references)

    config = {
        "path_base_dir": str(Path.cwd().resolve()),
        "output_dir": ask("\nDirectory for VMD results and MATLAB figures", "results"),
        "histogram_bins": ask_int("Number of bins for VMD distance-count histograms", 100, minimum=2),
        "write_replica_histograms": ask_yes_no("Also write one histogram file per replicate?", False),
        "progress_interval": ask_int("Print VMD progress every N frames", 500),
        "systems": systems,
        "signatures": signatures,
        "references": references,
        "figures": figures,
    }
    write_config(config, CONFIG_DIR / "pipeline_config.json")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (KeyboardInterrupt, EOFError):
        print("\nSetup cancelled.")
        raise SystemExit(1)
