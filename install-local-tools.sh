#!/usr/bin/env bash
# Shared local document/science tools; no hosted AI services or external accounts.
set -Eeuo pipefail
if (( EUID == 0 )); then echo 'Run as the desktop user.' >&2; exit 1; fi
export PATH="$HOME/.local/bin:$HOME/.bun/bin:$PATH"
command -v uv >/dev/null || { echo 'Install uv first.' >&2; exit 1; }
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y latexmk texlive-latex-extra texlive-fonts-recommended texlive-pictures bibtex2html poppler-utils ghostscript pandoc libreoffice ffmpeg tesseract-ocr nodejs npm
venv="$HOME/.local/share/omp-scientific-tools/venv"
mkdir -p "$(dirname "$venv")"
if [[ ! -x $venv/bin/python ]]; then uv venv --python 3.12 "$venv"; fi
uv pip install --python "$venv/bin/python" numpy scipy pandas matplotlib seaborn sympy statsmodels scikit-learn pillow pymupdf pypdf pdfplumber pdf2image reportlab python-docx python-pptx openpyxl lxml defusedxml biopython rdkit networkx
"$venv/bin/python" -c 'import numpy, scipy, pandas, matplotlib, pymupdf, docx, pptx, openpyxl, Bio, rdkit; print("Local science/document imports passed")'
js="$HOME/.local/share/omp-scientific-tools/js"
mkdir -p "$js"
npm install --prefix "$js" docx pptxgenjs react react-dom react-icons sharp
echo "Node modules: $js/node_modules (use NODE_PATH=$js/node_modules)"
echo "Local Python environment: $venv; use $venv/bin/python or uv run."
