#!/bin/bash
set -euo pipefail

# Define color variables.
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

#############################
# Default Values
#############################
DELIMITER=","
LINES=20
OUTPUT_FILE="csv_preview.html"
USE_CSVKIT=true
PATTERN="*.csv"
OUTPUT_FORMAT="html"   # Options: md, html, or pdf
INCLUDE_TOC=true
PANDOC_CSS=""
PANDOC_TEMPLATE=""
COLUMNS=""
INTERACTIVE=false
PARALLEL=false    # Requires GNU parallel for parallel processing
METADATA_FIELDS="size,modified"
COMPRESS_OUTPUT=false
ERROR_LOG=""
SHOW_METADATA=false    # Enabled by default; disable with -M
SHOW_HEADERS=false     # Enabled by default; disable with -H
SHOW_LINES=true

#############################
# OS Detection for sed In‑place & CPU Count
#############################
# Set the sed in‑place option depending on the platform.
if sed --version &>/dev/null; then
    # GNU sed (Linux)
    SED_INPLACE=(-i)
else
    # BSD sed (macOS)
    SED_INPLACE=(-i '')
fi

if [[ "$(uname)" == "Darwin" ]]; then
    CPU_COUNT=$(sysctl -n hw.ncpu)
else
    CPU_COUNT=$(nproc)
fi

#############################
# Enable nullglob for bash (so that unmatched globs produce an empty array)
#############################
shopt -s nullglob

#############################
# Usage Function
#############################
usage() {
    echo -e "${CYAN}Usage:${NC} $0 [-d delimiter] [-l lines] [-o output_file] [-c] [-p pattern] [-f format] [-t] [-s css_file] [-m template] [-k columns] [-i] [-P] [-e metadata_fields] [-z] [-L error_log] [-M] [-H] [-N]"
    echo "  -d: Specify the delimiter (default: ',')"
    echo "  -l: Number of lines to display (default: 10)"
    echo "  -o: Output file (default: csv_preview.md)"
    echo "  -c: Use csvkit for pretty-printing (if installed)"
    echo "  -p: Glob pattern to filter CSV files (default: *.csv)"
    echo "  -f: Output format (md, html, or pdf; default: md)"
    echo "  -t: Include table of contents in output"
    echo "  -s: CSS file for HTML output (requires -f html)"
    echo "  -m: LaTeX template for PDF output (requires -f pdf)"
    echo "  -k: Comma-separated list of column names to preview (requires -c)"
    echo "  -i: Interactive mode for file selection (requires fzf)"
    echo "  -P: Enable parallel processing of CSV files"
    echo "  -e: Comma-separated list of metadata fields to display (default: size,modified)"
    echo "  -z: Compress output file (e.g., .md.gz, .html.gz, .pdf.gz)"
    echo "  -L: Log errors to a file instead of stderr"
    echo "  -M: Disable display of file metadata"
    echo "  -H: Disable display of CSV headers"
    echo "  -N: Disable display of CSV lines"
    exit 1
}

#############################
# Parse Command-Line Options
#############################
while getopts "d:l:o:cp:f:ts:m:k:iPe:zL:MHN" opt; do
    case $opt in
        d) DELIMITER="$OPTARG" ;;
        l) LINES="$OPTARG" ;;
        o) OUTPUT_FILE="$OPTARG" ;;
        c) USE_CSVKIT=true ;;
        p) PATTERN="$OPTARG" ;;
        f) OUTPUT_FORMAT="$OPTARG" ;;
        t) INCLUDE_TOC=true ;;
        s) PANDOC_CSS="$OPTARG" ;;
        m) PANDOC_TEMPLATE="$OPTARG" ;;
        k) COLUMNS="$OPTARG" ;;
        i) INTERACTIVE=true ;;
        P) PARALLEL=true ;;
        e) METADATA_FIELDS="$OPTARG" ;;
        z) COMPRESS_OUTPUT=true ;;
        L) ERROR_LOG="$OPTARG" ;;
        M) SHOW_METADATA=false ;;
        H) SHOW_HEADERS=false ;;
        N) SHOW_LINES=false ;;
        *) usage ;;
    esac
done

# Redirect stderr to error log if specified.
if [[ -n "$ERROR_LOG" ]]; then
    exec 2>> "$ERROR_LOG"
fi

#############################
# Validate Output Format & Dependencies
#############################
case "$OUTPUT_FORMAT" in
    md|html|pdf) ;;
    *) echo -e "${RED}Error:${NC} Invalid output format '$OUTPUT_FORMAT'. Use 'md', 'html', or 'pdf'." >&2; exit 1 ;;
esac

if [[ "$USE_CSVKIT" == true || -n "$COLUMNS" ]]; then
    if ! command -v csvlook -I &>/dev/null; then
        echo -e "${RED}Error:${NC} csvkit is not installed. Install it or run without -c or -k." >&2
        exit 1
    fi
fi

if [[ "$OUTPUT_FORMAT" != "md" ]]; then
    if ! command -v pandoc &>/dev/null; then
        echo -e "${RED}Error:${NC} pandoc is not installed. Install it or use -f md." >&2
        exit 1
    fi
fi

if [[ "$INTERACTIVE" == true ]]; then
    if ! command -v fzf &>/dev/null; then
        echo -e "${RED}Error:${NC} fzf is not installed. Install it or run without -i." >&2
        exit 1
    fi
fi

if [[ "$PARALLEL" == true ]]; then
    if ! command -v parallel &>/dev/null; then
        echo -e "${RED}Error:${NC} parallel is not installed. Install it or run without -P." >&2
        exit 1
    fi
fi

#############################
# Validate CSS & LaTeX Template
#############################
echo -e "${BLUE}Validating CSS and LaTeX template files...${NC}" >&2
if [[ -z "$PANDOC_CSS" ]]; then
    echo "empty";
else
    echo "not empty";
fi
echo "PANDOC_CSS: $PANDOC_CSS"
if [[ -z "$PANDOC_CSS" && "$OUTPUT_FORMAT" == "html" ]]; then
    PANDOC_CSS="style.css"
    if [[ ! -f "$PANDOC_CSS" ]]; then
        echo -e "${YELLOW}Warning:${NC} Default CSS file 'style.css' not found. Creating a default one." >&2
        cat > "$PANDOC_CSS" << 'EOF'
        body {
            font-family: 'Segoe UI', Arial, sans-serif;
            line-height: 1.6;
            margin: 40px;
            max-width: 800px;
            margin: 0 auto;
        }
        h1, h2, h3, h4, h5, h6 {
            color: #2c3e50;
            margin-bottom: 20px;
        }
        h1 { font-size: 2.5em; }
        h2 { font-size: 2em; }
        h3 { font-size: 1.75em; }
        h4 { font-size: 1.5em; }
        h5 { font-size: 1.25em; }
        h6 { font-size: 1em; }
        p {
            font-size: 1em;
            margin-bottom: 20px;
        }
        ul, ol {
            padding-left: 40px;
            margin-bottom: 20px;
        }
        li {
            margin-bottom: 8px;
        }
        a {
            color: #3498db;
            text-decoration: none;
        }
        a:hover {
            text-decoration: underline;
        }
        img {
            max-width: 100%;
            height: auto;
            margin: 20px 0;
            border-radius: 5px;
        }
        blockquote {
            border-left: 4px solid #e74c3c;
            margin-left: 0;
            padding: 15px 20px;
            color: #7f8c8d;
            font-style: italic;
        }
        code {
            background-color: #f3f3f3;
            border-radius: 3px;
            padding: 2px 4px;
            font-family: 'Courier New', monospace;
            font-size: 0.9em;
        }
        pre {
            background-color: #f3f3f3;
            padding: 20px;
            border-radius: 8px;
            overflow-x: auto;
        }
        strong {
            font-weight: bold;
        }
        em {
            font-style: italic;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            margin: 20px 0;
        }
        th, td {
            border: 1px solid #ddd;
            padding: 12px;
            text-align: left;
        }
        th {
            background-color: #f2f2f2;
            font-weight: bold;
        }
        tr:nth-child(even) {
            background-color: #f9f9f9;
        }
EOF
    fi
elif [[ -n "$PANDOC_CSS" && "$OUTPUT_FORMAT" != "html" ]]; then
    echo -e "${YELLOW}Warning:${NC} CSS file specified but output format is not HTML. Ignoring -s." >&2
elif [[ -n "$PANDOC_CSS" && ! -f "$PANDOC_CSS" ]]; then
    echo -e "${RED}Error:${NC} CSS file '$PANDOC_CSS' does not exist." >&2
    exit 1
fi

if [[ -z "$PANDOC_TEMPLATE" && "$OUTPUT_FORMAT" == "pdf" ]]; then
    PANDOC_TEMPLATE="custom_template.tex"
    if [[ ! -f "$PANDOC_TEMPLATE" ]]; then
        echo -e "${YELLOW}Warning:${NC} Default LaTeX template 'custom_template.tex' not found. Creating a default one." >&2
        cat > "$PANDOC_TEMPLATE" << 'EOF'
\documentclass[a4paper,12pt]{article}
\usepackage[utf8]{inputenc}
\usepackage[T1]{fontenc}
\usepackage{lmodern}
\usepackage{geometry}
\geometry{margin=1in}
\usepackage{fancyhdr}
\pagestyle{fancy}
\fancyhf{}
\fancyhead[C]{CSV Preview}
\fancyfoot[C]{\thepage}
\usepackage{longtable}
\usepackage{booktabs}
\usepackage{hyperref}
\hypersetup{colorlinks=true,linkcolor=blue}
\begin{document}
$if(toc)$
\tableofcontents
\newpage
$endif$
$body$
\end{document}
EOF
    fi
elif [[ -n "$PANDOC_TEMPLATE" && "$OUTPUT_FORMAT" != "pdf" ]]; then
    echo -e "${YELLOW}Warning:${NC} LaTeX template specified but output format is not PDF. Ignoring -m." >&2
elif [[ -n "$PANDOC_TEMPLATE" && ! -f "$PANDOC_TEMPLATE" ]]; then
    echo -e "${RED}Error:${NC} LaTeX template '$PANDOC_TEMPLATE' does not exist." >&2
    exit 1
fi

#############################
# Utility Functions
#############################

# check_file: verifies that the file exists, is readable, and is not empty.
check_file() {
    local file="$1"
    if [[ ! -f "$file" ]]; then
        echo -e "${RED}Error:${NC} File '$file' does not exist or is not a regular file." >&2
        return 1
    elif [[ ! -r "$file" ]]; then
        echo -e "${RED}Error:${NC} File '$file' is not readable." >&2
        return 1
    elif [[ ! -s "$file" ]]; then
        echo -e "${YELLOW}Warning:${NC} File '$file' is empty." >&2
        return 1
    fi
    return 0
}

# decompress_file: if the file is a .gz, decompress it to a temporary file.
decompress_file() {
    local file="$1"
    local temp_file="$2"
    if [[ "$file" == *.gz ]]; then
        if ! gunzip -c "$file" > "$temp_file"; then
            echo -e "${RED}Error:${NC} Failed to decompress '$file'." >&2
            return 1
        fi
        echo "$temp_file"
    else
        echo "$file"
    fi
}

# display_metadata: outputs file metadata based on METADATA_FIELDS.
display_metadata() {
    local file="$1"
    echo "### File Metadata:"
    echo '```'
    OLDIFS=${IFS:-$' \t\n'}
    IFS=','
    for field in $METADATA_FIELDS; do
        case "$field" in
            size) echo "Size: $(stat -f %z "$file") bytes" ;;
            modified) echo "Last Modified: $(stat -f '%Sm' "$file")" ;;
            permissions) echo "Permissions: $(stat -f '%Sp' "$file")" ;;
            owner) echo "Owner: $(stat -f '%Su' "$file")" ;;
            *) echo "Warning: Unknown metadata field '$field'. Supported: size, modified, permissions, owner." >&2 ;;
        esac
    done
    IFS="$OLDIFS"
    echo '```'
}

# display_headers: outputs CSV headers.
# Optimization: only read the first line (using head) instead of scanning the whole file.
display_headers() {
    local file="$1"
    echo "### Headers:"
    echo '```'
    if $USE_CSVKIT; then
        if [[ -n "$COLUMNS" ]]; then
            head -n 1 "$file" | csvcut -d "$DELIMITER" -c "$COLUMNS" 2>/dev/null | csvcut -n
        else
            head -n 1 "$file" | csvcut -d "$DELIMITER" -n 2>/dev/null || head -n 1 "$file"
        fi
    else
        head -n 1 "$file"
    fi
    echo '```'
}

# display_lines: outputs the first N lines of the CSV.
# Optimization: use head to limit reading to just the header and the preview lines.
display_lines() {
    local file="$1"
    local lines="$2"
    echo "### First $lines Lines:"
    echo '```'
    if $USE_CSVKIT; then
        if [[ -n "$COLUMNS" ]]; then
            if ! head -n $((lines+1)) "$file" | csvcut -d "$DELIMITER" -c "$COLUMNS" 2>/dev/null | csvlook -I 2>/dev/null | head -n $((lines+2)); then
                echo -e "${RED}Error:${NC} Could not parse file with csvkit for columns. Falling back." >&2
                if ! head -n $((lines+1)) "$file" | csvlook -I 2>/dev/null | head -n $((lines+2)); then
                    head -n "$lines" "$file"
                fi
            fi
        else
            if ! head -n $((lines+1)) "$file" | csvlook -I -d "$DELIMITER" 2>/dev/null | head -n $((lines+2)); then
                echo -e "${RED}Error:${NC} Could not parse file with csvkit. Falling back." >&2
                head -n "$lines" "$file"
            fi
        fi
    else
        head -n "$lines" "$file"
        echo "...."
    fi
    echo '```'
}

# handle_delimiter: if DELIMITER is more than one character, replace it with a single comma.
handle_delimiter() {
    local file="$1"
    local temp_file="$2"
    if [[ ${#DELIMITER} -gt 1 ]]; then
        awk -F"$DELIMITER" '{$1=$1}1' OFS="," "$file" > "$temp_file"
        echo "$temp_file"
    else
        echo "$file"
    fi
}

# process_file: process a single CSV file and output Markdown.
process_file() {
    local file="$1"
    local temp_decomp_file temp_file
    temp_decomp_file=$(mktemp)
    temp_file=$(mktemp)
    trap 'rm -f "$temp_decomp_file" "$temp_file"' RETURN

    if ! check_file "$file"; then
        echo "## File: $file (Skipped due to errors)"
        echo ""
        return
    fi

    local decompressed_file processed_file
    decompressed_file=$(decompress_file "$file" "$temp_decomp_file")
    processed_file=$(handle_delimiter "$decompressed_file" "$temp_file")

    if $INCLUDE_TOC; then
        local anchor
        anchor=$(echo "$file" | sed 's/[^a-zA-Z0-9]/-/g')
        echo "## File: $file {#file-$anchor}"
    else
        echo "## File: $file"
    fi
    echo ""

    if $SHOW_METADATA; then
        display_metadata "$file"
        echo ""
    fi

    if $SHOW_HEADERS; then
        display_headers "$processed_file"
        echo ""
    fi

    if $SHOW_LINES; then
        display_lines "$processed_file" "$LINES"
        echo ""
    fi
}

#############################
# Main Script Logic
#############################

echo -e "${GREEN}Starting CSV to Markdown conversion...${NC}"

# Create a temporary Markdown file.
TEMP_MD_FILE=$(mktemp)

# Determine final output file based on OUTPUT_FORMAT.
case "$OUTPUT_FORMAT" in
    md) FINAL_OUTPUT_FILE="$OUTPUT_FILE" ;;
    html) FINAL_OUTPUT_FILE="${OUTPUT_FILE%.*}.html" ;;
    pdf) FINAL_OUTPUT_FILE="${OUTPUT_FILE%.*}.pdf" ;;
esac

echo -e "${BLUE}Output will be written to:${NC} ${CYAN}$FINAL_OUTPUT_FILE${NC}"

# Write initial Markdown header.
{
    if $INCLUDE_TOC; then
        echo "## Table of Contents"
        echo ""
        echo "<!-- TOC will be inserted here -->"
        echo ""
    fi
} >> "$TEMP_MD_FILE"

# File selection.
if $INTERACTIVE; then
    csv_files=( $(ls $PATTERN 2>/dev/null | fzf -m --prompt="Select CSV files (use TAB for multiple): ") )
    if [ ${#csv_files[@]} -eq 0 ]; then
        echo -e "${RED}No files selected.${NC}" >&2
        exit 1
    fi
else
    csv_files=( $PATTERN )
fi

total_files=${#csv_files[@]}
if [ $total_files -eq 0 ]; then
    echo -e "${RED}No CSV files found matching pattern '$PATTERN'.${NC}" >&2
    exit 1
fi

echo -e "${GREEN}Found ${total_files} CSV file(s).${NC}"

# Sort CSV files alphabetically.
IFS=$'\n' sorted=($(sort <<<"${csv_files[*]}"))
csv_files=("${sorted[@]}")
unset IFS

# TOC entries array.
declare -a TOC_ENTRIES

# Process CSV files.
if $PARALLEL; then
    echo -e "${YELLOW}Processing ${total_files} files in parallel...${NC}" >&2
    export -f process_file check_file decompress_file display_metadata display_headers display_lines handle_delimiter
    export DELIMITER LINES USE_CSVKIT COLUMNS INCLUDE_TOC METADATA_FIELDS SHOW_METADATA SHOW_HEADERS SHOW_LINES
    # Using GNU Parallel's built-in --bar for progress.
    printf "%s\n" "${csv_files[@]}" | parallel --bar -j "$CPU_COUNT" process_file >> "$TEMP_MD_FILE" 2>/dev/null
else
    current_file=0
    for file in "${csv_files[@]}"; do
        ((current_file++))
        percent=$(( 100 * current_file / total_files ))
        echo -ne "${YELLOW}Processing file $current_file of $total_files ($percent%)...${NC}\r" >&2
        if $INCLUDE_TOC; then
            anchor=$(echo "$file" | sed 's/[^a-zA-Z0-9]/-/g')
            TOC_ENTRIES+=( "- [$file](#file-$anchor)" )
        fi
        process_file "$file" >> "$TEMP_MD_FILE"
    done
    echo "" >&2  # Newline after progress.
fi

echo -e "${GREEN}File processing complete.${NC}" >&2

# Insert TOC if requested.
if $INCLUDE_TOC; then
    TOC_BLOCK=$(printf "%s\n" "${TOC_ENTRIES[@]}")
    sed "${SED_INPLACE[@]}" "/<!-- TOC will be inserted here -->/r /dev/stdin" "$TEMP_MD_FILE" <<< "$TOC_BLOCK"
fi

#############################
# Output Conversion
#############################
if [ "$OUTPUT_FORMAT" != "md" ]; then
    echo -e "${BLUE}Converting Markdown to $OUTPUT_FORMAT...${NC}" >&2
    pandoc_cmd=(pandoc "$TEMP_MD_FILE" -o "$FINAL_OUTPUT_FILE")
    if $INCLUDE_TOC; then
        pandoc_cmd+=(--toc)
    fi
    if [ "$OUTPUT_FORMAT" == "html" ] && [ -n "$PANDOC_CSS" ]; then
        pandoc_cmd+=(-c "$PANDOC_CSS")
    fi
    if [ "$OUTPUT_FORMAT" == "pdf" ] && [ -n "$PANDOC_TEMPLATE" ]; then
        pandoc_cmd+=(--template "$PANDOC_TEMPLATE")
    fi
    "${pandoc_cmd[@]}"
    if [ $? -eq 0 ]; then
        if [ "$OUTPUT_FORMAT" == "html" ]; then
            echo -e "${GREEN}HTML output written to ${CYAN}$FINAL_OUTPUT_FILE${NC}" >&2
        else
            echo -e "${GREEN}PDF output written to ${CYAN}$FINAL_OUTPUT_FILE${NC}" >&2
        fi
    else
        echo -e "${RED}Error: pandoc conversion failed.${NC}" >&2
        exit 1
    fi
    rm -f "$TEMP_MD_FILE"
else
    mv "$TEMP_MD_FILE" "$FINAL_OUTPUT_FILE"
    echo -e "${GREEN}Markdown output written to ${CYAN}$FINAL_OUTPUT_FILE${NC}" >&2
fi

if $COMPRESS_OUTPUT; then
    if command -v gzip &>/dev/null; then
        gzip -f "$FINAL_OUTPUT_FILE"
        if [ $? -eq 0 ]; then
            FINAL_OUTPUT_FILE="$FINAL_OUTPUT_FILE.gz"
            echo -e "${GREEN}Compressed output written to ${CYAN}$FINAL_OUTPUT_FILE${NC}" >&2
        else
            echo -e "${RED}Error: Compression failed.${NC}" >&2
            exit 1
        fi
    else
        echo -e "${YELLOW}Warning:${NC} gzip not found. Output file not compressed." >&2
    fi
fi

echo -e "${GREEN}Done. Check the file: ${CYAN}$FINAL_OUTPUT_FILE${NC}"
