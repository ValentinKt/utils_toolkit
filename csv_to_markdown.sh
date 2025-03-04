#!/bin/zsh

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

# Function to display usage
usage() {
    echo "Usage: $0 [-d delimiter] [-l lines] [-o output_file] [-c] [-p pattern] [-f format] [-t] [-s css_file] [-m template] [-k columns]"
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
    exit 1
}

# Parse command-line options
while getopts "d:l:o:cp:f:ts:m:k:" opt; do
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
        ?) usage ;;
    esac
done

# Validate output format
case "$OUTPUT_FORMAT" in
    md|html|pdf) ;;
    *) echo "Error: Invalid output format '$OUTPUT_FORMAT'. Use 'md', 'html', or 'pdf'." >&2; exit 1 ;;
esac

# Check if csvkit is installed when -c is used or -k is specified
if [[ "$USE_CSVKIT" == true || -n "$COLUMNS" ]]; then
    if ! command -v csvlook &> /dev/null; then
        echo "Error: csvkit is not installed. Install it with 'brew install csvkit' or run without -c or -k." >&2
        exit 1
    fi
    USE_CSVKIT=true  # Force USE_CSVKIT if -k is used
fi

# Check if pandoc is installed when html or pdf output is requested
if [[ "$OUTPUT_FORMAT" != "md" ]]; then
    if ! command -v pandoc &> /dev/null; then
        echo "Error: pandoc is not installed. Install it with 'brew install pandoc' or use -f md." >&2
        exit 1
    fi
fi

# Validate CSS file if provided
if [[ -n "$PANDOC_CSS" && "$OUTPUT_FORMAT" != "html" ]]; then
    echo "Warning: CSS file specified but output format is not HTML. Ignoring -s." >&2
elif [[ -n "$PANDOC_CSS" && ! -f "$PANDOC_CSS" ]]; then
    echo "Error: CSS file '$PANDOC_CSS' does not exist." >&2
    exit 1
fi

# Validate LaTeX template if provided
if [[ -n "$PANDOC_TEMPLATE" && "$OUTPUT_FORMAT" != "pdf" ]]; then
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
    echo "Size: $(stat -f %z "$file") bytes"
    echo "Last Modified: $(stat -f '%Sm' "$file")"
    echo '```'
}

# Function to display headers
display_headers() {
    local file="$1"
    if [[ "$USE_CSVKIT" == true ]]; then
        echo "### Headers (via csvkit):"
        echo '```'
        if [[ -n "$COLUMNS" ]]; then
            csvcut -d "$DELIMITER" -c "$COLUMNS" "$file" 2>/dev/null | csvcut -n 2>/dev/null || {
                echo "Error: Could not parse headers with csvkit for specified columns. Falling back to all headers."
                csvcut -d "$DELIMITER" -n "$file" 2>/dev/null || {
                    echo "Error: Could not parse headers with csvkit. Falling back to raw output."
                    head -n 1 "$file"
                }
            }
        else
            csvcut -d "$DELIMITER" -n "$file" 2>/dev/null || {
                echo "Error: Could not parse headers with csvkit. Falling back to raw output."
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
                echo "Error: Could not parse file with csvkit for specified columns. Falling back to all columns."
                csvlook -d "$DELIMITER" "$file" 2>/dev/null | head -n $((lines + 2)) || {
                    echo "Error: Could not parse file with csvkit. Falling back to raw output."
                    head -n "$lines" "$file"
                }
            }
        else
            csvlook -d "$DELIMITER" "$file" 2>/dev/null | head -n $((lines + 2)) || {
                echo "Error: Could not parse file with csvkit. Falling back to raw output."
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
echo "# CSV Preview"
echo "Generated on: $(date)"
echo ""

# Include table of contents if requested
if [[ "$INCLUDE_TOC" == true ]]; then
    echo "## Table of Contents"
    echo ""
    # Generate TOC entries for each file (will be updated later)
    echo "<!-- TOC will be inserted here -->"
    echo ""
fi

# Count total CSV files for progress feedback
csv_files=(${~PATTERN}(N))  # Use (N) to handle no-match gracefully, ~ to expand pattern
total_files=${#csv_files[@]}
if [[ $total_files -eq 0 ]]; then
    echo "No CSV files found matching pattern '$PATTERN' in the current directory."
    exit 1
fi

# Sort CSV files alphabetically
csv_files=(${(o)csv_files})

# Store TOC entries
TOC_ENTRIES=()

# Process each CSV file
current_file=0
for file in "${csv_files[@]}"; do
    ((current_file++))
    echo "Processing file $current_file of $total_files: $file" >&2  # Progress feedback to stderr

    # Check file validity
    if ! check_file "$file"; then
        echo "## File: $file (Skipped due to errors)"
        echo ""
        continue
    fi

    # Decompress .gz files if necessary
    decompressed_file=$(decompress_file "$file" "$TEMP_DECOMP_FILE")

    # Handle multi-character delimiters
    processed_file=$(handle_delimiter "$decompressed_file" "$TEMP_FILE")

    # Add TOC entry
    if [[ "$INCLUDE_TOC" == true ]]; then
        TOC_ENTRIES+=("- [$file](#file-${file//[^a-zA-Z0-9]/-})")
    fi

    # Print file name as a Markdown header with anchor
    echo "## File: $file {#file-${file//[^a-zA-Z0-9]/-}}"
    echo ""

    # Display file metadata
    display_metadata "$file"
    echo ""

    # Display headers
    display_headers "$processed_file"
    echo ""

    # Display first N lines
    display_lines "$processed_file" "$LINES"
    echo ""
done

echo "Processing complete." >&2

# Insert TOC if requested
if [[ "$INCLUDE_TOC" == true ]]; then
    # Read the temporary Markdown file, insert TOC, and write back
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
    if [[ "$OUTPUT_FORMAT" == "html" ]]; then
        echo "HTML output written to $FINAL_OUTPUT_FILE" >&2
    else
        echo "PDF output written to $FINAL_OUTPUT_FILE" >&2
    fi
    rm -f "$TEMP_MD_FILE"
else
    echo "Markdown output written to $OUTPUT_FILE" >&2
fi

