#!/bin/zsh

# Default values
DELIMITER=","
LINES=10
OUTPUT_FILE="csv_preview.md"
USE_CSVKIT=false

# Function to display usage
usage() {
    echo "Usage: $0 [-d delimiter] [-l lines] [-o output_file] [-c]"
    echo "  -d: Specify the delimiter (default: ',')"
    echo "  -l: Number of lines to display (default: 10)"
    echo "  -o: Output Markdown file (default: csv_preview.md)"
    echo "  -c: Use csvkit for pretty-printing (if installed)"
    exit 1
}

# Parse command-line options
while getopts "d:l:o:c" opt; do
    case $opt in
        d) DELIMITER="$OPTARG" ;;
        l) LINES="$OPTARG" ;;
        o) OUTPUT_FILE="$OPTARG" ;;
        c) USE_CSVKIT=true ;;
        ?) usage ;;
    esac
done

# Check if csvkit is installed when -c is used
if [[ "$USE_CSVKIT" == true ]]; then
    if ! command -v csvlook &> /dev/null; then
        echo "Error: csvkit is not installed. Install it with 'brew install csvkit' or run without -c."
        exit 1
    fi
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

# Function to display headers
display_headers() {
    local file="$1"
    if [[ "$USE_CSVKIT" == true ]]; then
        # echo "### Headers (via csvkit):"
        echo '```'
        csvcut -d "$DELIMITER" -n "$file" 2>/dev/null || {
            echo "Error: Could not parse headers with csvkit. Falling back to raw output."
            head -n 1 "$file"
        }
        echo '```'
    else
        # echo "### Headers:"
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
        # echo "### First $lines Lines (via csvkit):"
        echo '```'
        csvlook -d "$DELIMITER" "$file" 2>/dev/null | head -n $((lines + 2)) || {
            echo "Error: Could not parse file with csvkit. Falling back to raw output."
            head -n "$lines" "$file"
        }
        echo '```'
    else
        # echo "### First $lines Lines:"
        echo '```'
        head -n "$lines" "$file"
        echo '```'
    fi
}

# Redirect output to the specified file
exec > "$OUTPUT_FILE"

# Print Markdown header
echo "# CSV Preview"
echo "Generated on: $(date)"
echo ""

# Count total CSV files for progress feedback
csv_files=(*.csv(N))  # Use (N) to handle no-match gracefully
total_files=${#csv_files[@]}
if [[ $total_files -eq 0 ]]; then
    echo "No CSV files found in the current directory."
    exit 1
fi

# Sort CSV files alphabetically
csv_files=(${(o)csv_files})

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

    # Print file name as a Markdown header
    echo "## File: $file"
    echo ""

    # Display headers
    display_headers "$file"
    echo ""

    # Display first N lines
    display_lines "$file" "$LINES"
    echo ""
done

echo "Processing complete. Output written to $OUTPUT_FILE" >&2


Loop through all CSV files in the current directory
for file in *.csv; do
    # Check if there are any CSV files
    if [[ ! -f "$file" ]]; then
        echo "No CSV files found in the current directory."
        exit 1
    fi

    # Print the file name as a Markdown header
    echo "## File: $file"
    echo ""

    # Extract and print the headers (first line of the CSV)
    echo "### Headers:"
    echo '```'
    head -n 1 "$file"
    echo '```'
    echo ""

    # Print the first 10 lines of the CSV (including headers)
    echo "### First 10 Lines:"
    echo '```'
    head -n 10 "$file"
    echo '```'
    echo ""
done
