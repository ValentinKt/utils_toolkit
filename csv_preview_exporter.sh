#!/bin/zsh
# CSV Preview Exporter
# Generates previews of one or more CSV files in Markdown, HTML, or PDF.
# Supports csvkit formatting, column selection, metadata display, TOC generation,
# interactive selection via fzf, optional parallel processing, and output compression.
# Run with -h for a full man-style reference and combined-option examples.

# Default values
DELIMITER=","
LINES=10
OUTPUT_FILE="csv_preview.md"
USE_CSVKIT=false
PATTERN="*.csv"
OUTPUT_FORMAT="md"  # md, html, or pdf
INCLUDE_TOC=false
PANDOC_CSS=""
PANDOC_TEMPLATE=""
COLUMNS=""
INTERACTIVE=false
PARALLEL=false # Requires GNU parallel (brew install parallel) for parallel processing of CSV files. It no longer seems necessary to parallelize with today's computers. ;)
METADATA_FIELDS="size,modified"
COMPRESS_OUTPUT=false
ERROR_LOG=""
SHOW_METADATA=true
SHOW_HEADERS=true
SHOW_LINES=true

man_page() {
    cat << 'EOF'
NAME
    csv_preview_exporter.sh

SYNOPSIS
    csv_preview_exporter.sh [options]

DESCRIPTION
    Creates a formatted preview of CSV files matching a glob pattern.
    Output can be Markdown, HTML, or PDF and optionally includes metadata,
    headers, and sample rows. Supports csvkit formatting, TOC generation,
    interactive selection via fzf, parallel processing, and compression.

OPTIONS
    -h  Show this man-style help and exit
    -d  Specify the delimiter (default: ',')
    -l  Number of lines to display (default: 10)
    -o  Output file (default: csv_preview.md)
    -c  Use csvkit for pretty-printing (if installed)
    -p  Glob pattern to filter CSV files (default: *.csv)
    -f  Output format: md, html, or pdf (default: md)
    -t  Include table of contents in output
    -s  CSS file for HTML output (requires -f html)
    -m  LaTeX template for PDF output (requires -f pdf)
    -k  Comma-separated list of column names to preview (requires -c)
    -i  Interactive mode for file selection (requires fzf)
    -P  Enable parallel processing of CSV files (requires GNU parallel)
    -e  Comma-separated list of metadata fields to display (default: size,modified)
    -z  Compress output file (e.g., .md.gz, .html.gz, .pdf.gz)
    -L  Log errors to a file instead of stderr
    -M  Disable display of file metadata
    -H  Disable display of CSV headers
    -N  Disable display of CSV lines

EXAMPLES
    csv_preview_exporter.sh -p "*.csv" -l 25 -c -k "name,amount" -t -f html -s style.css -o report.md
    csv_preview_exporter.sh -i -f pdf -m custom_template.tex -t -z -L errors.log
EOF
}

# Function to display usage
usage() {
    echo "Usage: $0 [-h] [-d delimiter] [-l lines] [-o output_file] [-c] [-p pattern] [-f format] [-t] [-s css_file] [-m template] [-k columns] [-i] [-P] [-e metadata_fields] [-z] [-L error_log] [-M] [-H] [-N]"
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
    echo "  -i: Interactive mode for file selection (requires fzf)" # Use fzf to select files interactively
    echo "  -P: Enable parallel processing of CSV files" # Not necessary with today's computers
    echo "  -e: Comma-separated list of metadata fields to display (default: size,modified)" # values : size, modified, permissions, owner
    echo "  -z: Compress output file (e.g., .md.gz, .html.gz, .pdf.gz)" # Compress the output file
    echo "  -L: Log errors to a file instead of stderr" # Allowing to log errors to a file
    echo "  -M: Disable display of file metadata" # Avoid displaying file metadata
    echo "  -H: Disable display of CSV headers" # Avoid displaying the first line of the CSV file
    echo "  -N: Disable display of CSV lines"  # Avoid displaying the first lines of the CSV file
    exit 1
}

# Parse command-line options
while getopts "hd:l:o:cp:f:ts:m:k:iPe:zL:MHN" opt; do
    case $opt in
        h) man_page; exit 0 ;;
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
        ?) usage ;;
    esac
done

# Redirect stderr to error log if specified
if [[ -n "$ERROR_LOG" ]]; then
    exec 2>> "$ERROR_LOG"
fi

# Validate output format
case "$OUTPUT_FORMAT" in
    md|html|pdf) ;;
    *) echo "Error: Invalid output format '$OUTPUT_FORMAT'. Use 'md', 'html', or 'pdf'." >&2; exit 1 ;;
esac

if [[ -z "$DELIMITER" ]]; then
    echo "Error: Delimiter cannot be empty." >&2
    exit 1
fi

if ! [[ "$LINES" =~ '^[0-9]+$' ]] || [[ "$LINES" -le 0 ]]; then
    echo "Error: Lines value must be a positive integer." >&2
    exit 1
fi

# Check if csvkit is installed only when -c or -k is explicitly used
if [[ "$USE_CSVKIT" == true || -n "$COLUMNS" ]]; then
    if ! command -v csvlook &> /dev/null; then
        echo "Error: csvkit is not installed. Install it with 'brew install csvkit' or run without -c or -k." >&2
        exit 1
    fi
fi

# Check if pandoc is installed when html or pdf output is requested
if [[ "$OUTPUT_FORMAT" != "md" ]]; then
    if ! command -v pandoc &> /dev/null; then
        echo "Error: pandoc is not installed. Install it with 'brew install pandoc' or use -f md." >&2
        exit 1
    fi
fi

# Check if fzf is installed when -i is used
if [[ "$INTERACTIVE" == true ]]; then
    if ! command -v fzf &> /dev/null; then
        echo "Error: fzf is not installed. Install it with 'brew install fzf' or run without -i." >&2
        exit 1
    fi
fi

# Check if parallel is installed when -P is used
if [[ "$PARALLEL" == true ]]; then
    if ! command -v parallel &> /dev/null; then
        echo "Error: parallel is not installed. Install it with 'brew install parallel' or run without -P." >&2
        exit 1
    fi
fi

# Validate CSS file if provided, or use default
if [[ -z "$PANDOC_CSS" && "$OUTPUT_FORMAT" == "html" ]]; then
    PANDOC_CSS="style.css"
    if [[ ! -f "$PANDOC_CSS" ]]; then
        echo "Warning: Default CSS file 'style.css' not found. Creating a default one." >&2
        cat > "$PANDOC_CSS" << 'EOF'
body {
    font-family: Arial, sans-serif;
    line-height: 1.6;
    margin: 0 auto;
    max-width: 800px;
    padding: 20px;
}
h1, h2, h3 {
    color: #333;
}
table {
    border-collapse: collapse;
    width: 100%;
    margin-bottom: 20px;
}
th, td {
    border: 1px solid #ddd;
    padding: 8px;
    text-align: left;
}
th {
    background-color: #f2f2f2;
}
pre {
    background-color: #f8f8f8;
    padding: 10px;
    border-radius: 5px;
    overflow-x: auto;
}
code {
    font-family: Consolas, Monaco, 'Andale Mono', monospace;
}
EOF
    fi
elif [[ -n "$PANDOC_CSS" && "$OUTPUT_FORMAT" != "html" ]]; then
    echo "Warning: CSS file specified but output format is not HTML. Ignoring -s." >&2
elif [[ -n "$PANDOC_CSS" && ! -f "$PANDOC_CSS" ]]; then
    echo "Error: CSS file '$PANDOC_CSS' does not exist." >&2
    exit 1
fi

# Validate LaTeX template if provided, or use default
if [[ -z "$PANDOC_TEMPLATE" && "$OUTPUT_FORMAT" == "pdf" ]]; then
    PANDOC_TEMPLATE="custom_template.tex"
    if [[ ! -f "$PANDOC_TEMPLATE" ]]; then
        echo "Warning: Default LaTeX template 'custom_template.tex' not found. Creating a default one." >&2
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
    echo "Warning: LaTeX template specified but output format is not PDF. Ignoring -m." >&2
elif [[ -n "$PANDOC_TEMPLATE" && ! -f "$PANDOC_TEMPLATE" ]]; then
    echo "Error: LaTeX template '$PANDOC_TEMPLATE' does not exist." >&2
    exit 1
fi

# Function to check if a file is empty or unreadable
check_file() {
    local file="$1"
    if [[ ! -f "$file" ]]; then
        echo "Error: File '$file' does not exist or is not a regular file." >&2
        return 1
    elif [[ ! -r "$file" ]]; then
        echo "Error: File '$file' is not readable." >&2
        return 1
    elif [[ ! -s "$file" ]]; then
        echo "Warning: File '$file' is empty." >&2
        return 1
    fi
    return 0
}

# Function to decompress .gz files
decompress_file() {
    local file="$1"
    local temp_file="$2"
    if [[ "$file" == *.gz ]]; then
        gunzip -c "$file" > "$temp_file" || {
            echo "Error: Failed to decompress '$file'." >&2
            return 1
        }
        echo "$temp_file"
    else
        echo "$file"
    fi
}

# Function to display file metadata
display_metadata() {
    local file="$1"
    echo "### File Metadata:"
    echo '```'
    for field in ${(s:,:)METADATA_FIELDS}; do
        case "$field" in
            size) echo "Size: $(stat -f %z "$file") bytes" ;;
            modified) echo "Last Modified: $(stat -f '%Sm' "$file")" ;;
            permissions) echo "Permissions: $(stat -f '%Sp' "$file")" ;;
            owner) echo "Owner: $(stat -f '%Su' "$file")" ;;
            *) echo "Warning: Unknown metadata field '$field'. Supported fields: size, modified, permissions, owner." >&2 ;;
        esac
    done
    echo '```'
}

# Function to display headers
display_headers() {
    local file="$1"
    if [[ "$USE_CSVKIT" == true ]]; then
        echo "### Headers (via csvkit):"
        echo '```'
        if [[ -n "$COLUMNS" ]]; then
            if ! error_message=$(csvcut -d "$DELIMITER" -c "$COLUMNS" "$file" 2>&1 >/dev/null); then
                echo "Error: Could not parse headers with csvkit for specified columns: $COLUMNS. Reason: $error_message" >&2
                echo "Available columns in $file:" >&2
                csvcut -d "$DELIMITER" -n "$file" >&2
                echo "Falling back to all headers." >&2
                csvcut -d "$DELIMITER" -n "$file" 2>/dev/null || {
                    echo "Error: Could not parse headers with csvkit. Falling back to raw output." >&2
                    head -n 1 "$file"
                }
            else
                csvcut -d "$DELIMITER" -c "$COLUMNS" "$file" | head -n 1
            fi
        else
            csvcut -d "$DELIMITER" -n "$file" 2>/dev/null || {
                echo "Error: Could not parse headers with csvkit. Falling back to raw output." >&2
                head -n 1 "$file"
            }
        fi
        echo '```'
    else
        echo "### Headers:"
        echo '```'
        head -n 1 "$file"
        echo '```'
    fi
}

# Function to display lines
display_lines() {
    local file="$1"
    local lines="$2"
    if [[ "$USE_CSVKIT" == true ]]; then
        echo "### First $lines Lines (via csvkit):"
        echo '```'
        if [[ -n "$COLUMNS" ]]; then
            csvcut -d "$DELIMITER" -c "$COLUMNS" "$file" 2>/dev/null | csvlook 2>/dev/null | head -n $((lines + 2)) || {
                echo "Error: Could not parse file with csvkit for specified columns. Falling back to all columns." >&2
                csvlook -d "$DELIMITER" "$file" 2>/dev/null | head -n $((lines + 2)) || {
                    echo "Error: Could not parse file with csvkit. Falling back to raw output." >&2
                    head -n "$lines" "$file"
                }
            }
        else
            csvlook -d "$DELIMITER" "$file" 2>/dev/null | head -n $((lines + 2)) || {
                echo "Error: Could not parse file with csvkit. Falling back to raw output." >&2
                head -n "$lines" "$file"
            }
        fi
        echo '```'
    else
        echo "### First $lines Lines:"
        echo '```'
        head -n "$lines" "$file"
        echo '```'
    fi
}

# Function to handle multi-character delimiters
handle_delimiter() {
    local file="$1"
    local temp_file="$2"
    if [[ ${#DELIMITER} -gt 1 ]]; then
        # Use awk to replace multi-character delimiter with a single character (e.g., comma)
        awk -F"$DELIMITER" '{$1=$1}1' OFS="," "$file" > "$temp_file"
        echo "$temp_file"
    else
        echo "$file"
    fi
}

# Function to process a single file (for parallel processing)
process_file() {
    local file="$1"
    local temp_decomp_file=$(mktemp)
    local temp_file=$(mktemp)
    trap 'rm -f $temp_decomp_file $temp_file' EXIT

    if ! check_file "$file"; then
        echo "## File: $file (Skipped due to errors)"
        echo ""
        return
    fi

    decompressed_file=$(decompress_file "$file" "$temp_decomp_file")
    processed_file=$(handle_delimiter "$decompressed_file" "$temp_file")

    if [[ "$INCLUDE_TOC" == true ]]; then
        echo "## File: $file {#file-${file//[^a-zA-Z0-9]/-}}"
    else
        echo "## File: $file"
    fi
    echo ""

    if [[ "$SHOW_METADATA" == true ]]; then
        display_metadata "$file"
        echo ""
    fi

    if [[ "$SHOW_HEADERS" == true ]]; then
        display_headers "$processed_file"
        echo ""
    fi

    if [[ "$SHOW_LINES" == true ]]; then
        display_lines "$processed_file" "$LINES"
        echo ""
    fi
}

# Temporary files for decompression and delimiter handling
TEMP_FILE=$(mktemp)
TEMP_DECOMP_FILE=$(mktemp)

# Trap to clean up temporary files on exit
trap 'rm -f $TEMP_FILE $TEMP_DECOMP_FILE' EXIT

# Determine final output file based on format
case "$OUTPUT_FORMAT" in
    md) FINAL_OUTPUT_FILE="$OUTPUT_FILE" ;;
    html) FINAL_OUTPUT_FILE="${OUTPUT_FILE:r}.html" ;;
    pdf) FINAL_OUTPUT_FILE="${OUTPUT_FILE:r}.pdf" ;;
esac

# Redirect output to a temporary Markdown file if converting to HTML or PDF
if [[ "$OUTPUT_FORMAT" != "md" ]]; then
    TEMP_MD_FILE=$(mktemp)
    exec > "$TEMP_MD_FILE"
else
    exec > "$OUTPUT_FILE"
fi

# Print Markdown header
# echo "# CSV Preview"
# echo "Generated on: $(date)"
# echo ""

# Include table of contents if requested
if [[ "$INCLUDE_TOC" == true ]]; then
    echo "## Table of Contents"
    echo ""
    echo "<!-- TOC will be inserted here -->"
    echo ""
fi

# Count total CSV files for progress feedback
if [[ "$INTERACTIVE" == true ]]; then
    csv_files=($(ls ${~PATTERN}(N) | fzf -m --prompt="Select CSV files (use TAB to select multiple): "))
    if [[ ${#csv_files[@]} -eq 0 ]]; then
        echo "No files selected." >&2
        exit 1
    fi
else
    csv_files=(${~PATTERN}(N))
fi

total_files=${#csv_files[@]}
if [[ $total_files -eq 0 ]]; then
    echo "No CSV files found matching pattern '$PATTERN' in the current directory."
    exit 1
fi

# Sort CSV files alphabetically
csv_files=(${(o)csv_files})

# Store TOC entries
TOC_ENTRIES=()
if [[ "$INCLUDE_TOC" == true ]]; then
    for file in "${csv_files[@]}"; do
        TOC_ENTRIES+=("- [$file](#file-${file//[^a-zA-Z0-9]/-})")
    done
fi

# Process files (sequentially or in parallel)
if [[ "$PARALLEL" == true ]]; then
    export -f process_file check_file decompress_file display_metadata display_headers display_lines handle_delimiter
    export DELIMITER LINES USE_CSVKIT COLUMNS INCLUDE_TOC METADATA_FIELDS
    echo "Processing $total_files files in parallel..." >&2
    printf "%s\n" "${csv_files[@]}" | parallel -j $(sysctl -n hw.ncpu) process_file
else
    current_file=0
    for file in "${csv_files[@]}"; do
        ((current_file++))
        echo "Processing file $current_file of $total_files: $file" >&2

        process_file "$file"
    done
fi

echo "Processing complete." >&2

# Insert TOC if requested
if [[ "$INCLUDE_TOC" == true ]]; then
    if [[ "$OUTPUT_FORMAT" != "md" ]]; then
        sed -i '' "/<!-- TOC will be inserted here -->/r /dev/stdin" "$TEMP_MD_FILE" <<< ${(F)TOC_ENTRIES}
    else
        sed -i '' "/<!-- TOC will be inserted here -->/r /dev/stdin" "$OUTPUT_FILE" <<< ${(F)TOC_ENTRIES}
    fi
fi

# Convert to HTML or PDF if requested
if [[ "$OUTPUT_FORMAT" != "md" ]]; then
    pandoc_cmd=(pandoc "$TEMP_MD_FILE" -o "$FINAL_OUTPUT_FILE")
    if [[ "$INCLUDE_TOC" == true ]]; then
        pandoc_cmd+=(--toc)
    fi
    if [[ "$OUTPUT_FORMAT" == "html" && -n "$PANDOC_CSS" ]]; then
        pandoc_cmd+=(-c "$PANDOC_CSS")
    fi
    if [[ "$OUTPUT_FORMAT" == "pdf" && -n "$PANDOC_TEMPLATE" ]]; then
        pandoc_cmd+=(--template "$PANDOC_TEMPLATE")
    fi
    "${pandoc_cmd[@]}"
    if [[ $? -eq 0 ]]; then
        if [[ "$OUTPUT_FORMAT" == "html" ]]; then
            echo "HTML output written to $FINAL_OUTPUT_FILE" >&2
        else
            echo "PDF output written to $FINAL_OUTPUT_FILE" >&2
        fi
    else
        echo "Error: Failed to convert Markdown to $OUTPUT_FORMAT using pandoc." >&2
        exit 1
    fi
    rm -f "$TEMP_MD_FILE"
else
    echo "Markdown output written to $FINAL_OUTPUT_FILE" >&2
fi

# Compress output file if requested
if [[ "$COMPRESS_OUTPUT" == true ]]; then
    if command -v gzip &> /dev/null; then
        gzip -f "$FINAL_OUTPUT_FILE"
        if [[ $? -eq 0 ]]; then
            FINAL_OUTPUT_FILE="$FINAL_OUTPUT_FILE.gz"
            echo "Compressed output written to $FINAL_OUTPUT_FILE" >&2
        else
            echo "Error: Failed to compress output file." >&2
            exit 1
        fi
    else
        echo "Warning: gzip not found. Output file not compressed." >&2
    fi
fi
