#!/bin/bash
##
## Apply Google guetzli to JPEG files under the specified directory
## Copyright (c) 2017 SATOH Fumiyasu @ OSS Technology Corp., Japan
##
## License: GNU General Public License version 3
##
## Requirements:
##   Google guetzli
##   ImageMagick identify(1), convert(1)
##   and others...
##

set -u
set -o pipefail

mark="guetzli-ed"

if [[ $# -eq 0 ]]; then
  echo "Usage $0 DIR [...]"
  exit 1
fi

file2size() {
  ls -l -- "$1" |sed -n 's/^[^ ]* [^ ]* [^ ]* [^ ]* \([0-9][0-9]*\).*/\1/p'
}

if type identify >&/dev/null; then
  ## ImageMagick identify(1)
  jpg2comment() {
    identify -format '%c' -- "$1"
  }
elif type exifprobe >&/dev/null; then
  ## Exifprobe exifprobe(1)
  jpg2comment() {
    exifprobe -R -c -- "$1" \
    |sed -n "s/^ *<JPEG_COM> length [0-9]*: ''\(.*\)''$/\1/p" \
    ;
  }
else
  ## Darwin's file(1)
  jpg2comment() {
    file -- "$1" |sed -n 's/.*, comment: "\([^"]*\)".*/\1/p'
  }
fi

sigint_handler() {
  rm -f -- ${jpg_tmp1+"$jpeg_tmp1"} ${jpg_tmp2+"$jpeg_tmp2"}
  trap - INT
  kill -INT $$
}

trap sigint_handler INT

find "$@" -type f \( -iname "*.jpg" -o -iname "*.jpeg" \) ! -name "*.tmp.jpg" \
|while IFS= read -r jpg_in; do
  echo "$jpg_in ..."
  jpg_comment=$(jpg2comment "$jpg_in") || continue
  if [[ $jpg_comment == "$mark" ]]; then
    echo "$jpg_in: Skipped: Already guetzli-ed: $jpg_comment"
    continue
  fi

  jpg_in_size=$(file2size "$jpg_in") || continue

  jpg_tmp1="${jpg_in%.*}.$$.1.tmp.jpg"
  jpg_tmp2="${jpg_in%.*}.$$.2.tmp.jpg"
  (
    set -e
    ## NOTE: Only YUV color space input jpeg is supported by guetzli
    ## NOTE: Applying ImageMagick mogrify(1) (or convert(1)) with
    ##       only '-comment' option to a guetzli-ed JPEG file grows
    ##       the file size. Why?
    convert -colorspace yuv -comment "$mark" "$jpg_in" "$jpg_tmp1"
    time_start="$SECONDS"
    guetzli "$jpg_tmp1" "$jpg_tmp2"
    time_end=$((SECONDS - time_start))
    time=$(printf '%d:%02d' $((time_end / 60)) $((time_end % 60)))
    rm "$jpg_tmp1"
    jpg_out_size=$(file2size "$jpg_tmp2")
    jpg_size_ratio=$((jpg_out_size * 100 / jpg_in_size))
    jpg_size_report="$jpg_in_size -> $jpg_out_size ($jpg_size_ratio %, $time)"
    if [[ $jpg_out_size -ge $jpg_in_size ]]; then
      echo "$jpg_in: Skipped: Not compressed: $jpg_size_report"
      exit 1
    fi
    mv "$jpg_tmp2" "$jpg_in"
    echo "$jpg_in: Compressed: $jpg_size_report"
  ) || { rm -f "$jpg_tmp1" "$jpg_tmp2"; }
done
