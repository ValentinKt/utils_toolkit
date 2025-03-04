# CSV Preview Script

This is a Zsh script (`csv_preview.sh`) designed to process CSV files in a directory, generating a Markdown, HTML, or PDF report that includes file metadata, headers, and a preview of the first few lines of each CSV file. The script is highly customizable, supporting features like custom delimiters, column filtering, table of contents, parallel processing, and more.

## Features

- **File Processing**: Processes all CSV files in a directory, with optional filtering by glob pattern.
- **Output Formats**: Generates reports in Markdown (`.md`), HTML (`.html`), or PDF (`.pdf`).
- **Metadata Display**: Displays file metadata such as size, last modified date, permissions, and owner.
- **Header Extraction**: Extracts and displays CSV headers.
- **Line Preview**: Previews the first N lines of each CSV file.
- **Custom Delimiters**: Supports single-character and multi-character delimiters.
- **Column Filtering**: Filters specific columns for preview (requires `csvkit`).
- **Table of Contents**: Optionally includes a table of contents in the output.
- **Pretty-Printing**: Uses `csvkit` for nicely formatted table output (optional).
- **Compressed Files**: Supports `.csv.gz` files by decompressing them on the fly.
- **Interactive Mode**: Allows interactive file selection using `fzf`.
- **Parallel Processing**: Processes files in parallel for improved performance on large directories (requires `parallel`).
- **Custom Styling**: Supports custom CSS for HTML output and LaTeX templates for PDF output.
- **Output Compression**: Optionally compresses the output file (e.g., `.md.gz`, `.html.gz`, `.pdf.gz`).
- **Error Logging**: Logs errors to a file instead of `stderr` (optional).

## Installation

### Prerequisites

The script requires Zsh (pre-installed on macOS) and several external tools for full functionality. Install the required tools using Homebrew:

```bash
# Install Homebrew (if not already installed)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install required tools
brew install csvkit  # For pretty-printing and column filtering
brew install pandoc  # For HTML and PDF output
brew install basictex  # For PDF output (LaTeX support)
brew install fzf  # For interactive file selection
brew install parallel  # For parallel processing
brew install coreutils  # For additional utilities (e.g., stat, gzip)
```

### Script Setup

1. Save the script as `csv_preview.sh` in your desired directory.
2. Make the script executable:

   ```bash
   chmod +x csv_preview.sh
   ```

3. (Optional) Place the script in a directory included in your `$PATH` (e.g., `/usr/local/bin`) for easy access:

   ```bash
   sudo mv csv_preview.sh /usr/local/bin/
   ```

## Usage

Run the script with various options to customize its behavior. The general syntax is:

```bash
./csv_preview.sh [options]
```

### Options

- `-d delimiter`: Specify the delimiter (default: `,`).
- `-l lines`: Number of lines to display (default: `10`).
- `-o output_file`: Output file (default: `csv_preview.md`).
- `-c`: Use `csvkit` for pretty-printing (requires `csvkit`).
- `-p pattern`: Glob pattern to filter CSV files (default: `*.csv`).
- `-f format`: Output format (`md`, `html`, or `pdf`; default: `md`).
- `-t`: Include a table of contents in the output.
- `-s css_file`: CSS file for HTML output (requires `-f html`).
- `-m template`: LaTeX template for PDF output (requires `-f pdf`).
- `-k columns`: Comma-separated list of column names to preview (requires `-c`).
- `-i`: Interactive mode for file selection (requires `fzf`).
- `-P`: Enable parallel processing of CSV files (requires `parallel`).
- `-e metadata_fields`: Comma-separated list of metadata fields to display (default: `size,modified`).
- `-z`: Compress the output file (e.g., `.md.gz`, `.html.gz`, `.pdf.gz`).
- `-L error_log`: Log errors to a file instead of `stderr`.

### Examples

Below are several examples demonstrating how to use the script with different options.

#### Example 1: Basic Usage (Markdown Output)

Generate a Markdown report for all CSV files in the current directory, showing the first 10 lines:

```bash
./csv_preview.sh
```

This will create `csv_preview.md` with file metadata, headers, and the first 10 lines of each CSV file.

#### Example 2: Custom Delimiter and Fewer Lines

Generate a Markdown report for CSV files using a semicolon (`;`) delimiter, showing only the first 5 lines:

```bash
./csv_preview.sh -d ";" -l 5
```

#### Example 3: HTML Output with Table of Contents

Generate an HTML report with a table of contents, using a custom CSS file:

```bash
./csv_preview.sh -f html -o report.html -t -s style.css
```

If `style.css` does not exist, the script will create a default one.

#### Example 4: PDF Output with Custom LaTeX Template

Generate a PDF report using a custom LaTeX template:

```bash
./csv_preview.sh -f pdf -o report.pdf -m custom_template.tex
```

If `custom_template.tex` does not exist, the script will create a default one.

#### Example 5: Pretty-Printing with `csvkit`

Generate a Markdown report with nicely formatted tables using `csvkit`:

```bash
./csv_preview.sh -c
```

#### Example 6: Filter Specific Columns

Generate a Markdown report showing only the `id` and `name` columns (requires `csvkit`):

```bash
./csv_preview.sh -c -k "id,name"
```

#### Example 7: Interactive File Selection

Interactively select CSV files to process using `fzf`:

```bash
./csv_preview.sh -i
```

Use the arrow keys to navigate, TAB to select multiple files, and ENTER to confirm.

#### Example 8: Process Compressed Files

Process only `.csv.gz` files in the current directory:

```bash
./csv_preview.sh -p "*.csv.gz"
```

#### Example 9: Parallel Processing

Process CSV files in parallel for improved performance (requires `parallel`):

```bash
./csv_preview.sh -P
```

#### Example 10: Custom Metadata Fields

Display additional metadata fields (e.g., permissions and owner) in the report:

```bash
./csv_preview.sh -e "size,modified,permissions,owner"
```

#### Example 11: Compress Output

Generate a compressed Markdown report:

```bash
./csv_preview.sh -z
```

This will create `csv_preview.md.gz`.

#### Example 12: Log Errors to a File

Generate a report and log errors to a file instead of `stderr`:

```bash
./csv_preview.sh -L errors.log
```

#### Example 13: Combine Multiple Options

Generate an HTML report with a table of contents, pretty-printing, column filtering, parallel processing, and compressed output:

```bash
./csv_preview.sh -f html -o report.html -t -c -k "id,name" -P -z
```

This will create `report.html.gz`.

#### Example 14:
- **Filter by Column Names**:

  ```bash
  ./csv_preview.sh -c -k "CityID,CityName"
  ```

- **Filter by Column Indices**:

  ```bash
  ./csv_preview.sh -c -k "1,2"
  ```

- **Display All Columns** (no filtering):

  ```bash
  ./csv_preview.sh -c
  ```


## Notes

- **Delimiter Handling**: Multi-character delimiters are supported but are converted to commas internally for `csvkit` processing. Raw output will show commas instead of the original delimiter.
- **Performance**: Parallel processing (`-P`) is useful for large directories but may consume significant system resources. Adjust the number of parallel jobs by modifying the `-j` option in the `parallel` command if needed.
- **Error Handling**: Errors are logged to `stderr` by default or to a file if `-L` is used. Check the error log for issues like unreadable files or parsing errors.
- **Dependencies**: Ensure all required tools are installed for full functionality. Missing tools will result in errors or warnings, and some features may be disabled.

## Troubleshooting

- **Pandoc Errors**: If PDF generation fails, ensure `basictex` is installed and configured correctly. You may need to run `sudo tlmgr update --self` and `sudo tlmgr install <package>` to install missing LaTeX packages.
- **Csvkit Errors**: If `csvkit` fails to parse a file, the script falls back to raw output. Check the CSV file for malformed data or incorrect delimiters.
- **Fzf Issues**: Ensure `fzf` is properly installed and configured. Run `$(brew --prefix)/opt/fzf/install` to set up key bindings if needed.
- **Parallel Issues**: Ensure `parallel` is installed and configured. Run `parallel --citation` to acknowledge the tool if prompted.

## Contributing

Feel free to contribute to this script by submitting pull requests or reporting issues. Suggestions for new features or improvements are welcome!
