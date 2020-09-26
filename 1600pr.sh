#!/bin/sh
#
# Simple static photoblog generator.
# Requires ImageMagick for creation of thumbnails/alternative sizes, but you can
# turn that off.
#
# Example usage:
#
# ./1600pr.sh ~/blargh.jpg
#
# Anders Jensen-Urstad <anders@unix.se>
# License: MIT

site_title=${_1600PR_SITE_TITLE:-"J. Random Photoblogger"} # <title> in HTML and RSS
site_url=${_1600PR_SITE_URL:-"https://example.com/"}       # Absolute URL to photoblog; used for RSS
email=${_1600PR_EMAIL:-"foobar@example.com"}               # Email used in default menu HTML
archive_page=${_1600PR_ARCHIVE_PAGE:-true}                 # If true, create archive page + thumbs.
sizes=${_1600PR_SIZES:-"1920 1600 1280 800"}  # Image sizes to create (widths). Set to "" to disable.
rss_items=${_1600PR_RSS_ITEMS:-10}            # Max number of items in RSS file
web_root_path=${_1600PR_WEB_ROOT_PATH:-"/"}   # Relative URL to site, e.g. / or /photoblog/; this affects links
db_file=${_1600PR_DB_FILE:-"./_1600pr.dat"}   # Path to the data file
image_dir=${_1600PR_IMAGE_DIR:-"./images"}    # Directory where original images should be stored
output_dir=${_1600PR_OUTPUT_DIR:-"./public"}  # Where to build the site

default_menu="<a href=\"${web_root_path}\">home</a> <a href=\"${web_root_path}photo\">archive</a> <a href=\"mailto:${email}\">contact</a>"
menu=${_1600PR_MENU:-"${default_menu}"} # Menu HTML

###########################################################################

rebuild=false
post_date=$(date "+%a, %d %b %Y %H:%M:%S %z")

usage() {
  echo "Usage:"
  echo "  $0 [-d <date>] [-t <title>] [-n] <image to add>"
  echo "  $0 -r <id to remove>"
  echo "  $0 [-h] [-b]"
  echo ""
  echo " -d <date>   Publication date (for RSS) formatted as RFC 822 datetime,"
  echo "             e.g. Sat, 07 Sep 2002 0:00:01 GMT."
  echo "             If not specified, current date will be used."
  echo " -t <title>  Image title. If not specified, publication date will be used as"
  echo "             title in RSS feed."
  echo " -b          Rebuild everything to ${output_dir} (image versions, pages)."
  echo " -r <id>     Remove post with specified ID from database and rebuild."
  echo "             Doesn't remove image from [non-public] ${image_dir} or from"
  echo "             ${output_dir}."
  echo " -h          Show help message and exit."
}

while getopts "hbd:t:r:" opt; do
  case $opt in
    h) usage; exit;;
    b) rebuild=true ;;
    d) post_date="${OPTARG}" ;;
    t) post_title="${OPTARG}" ;;
    r) id_to_remove="${OPTARG}" ;;
    *) usage; exit;; 
  esac
done

get_num_posts () { sed '/^\s*$/d' "${db_file}" | wc -l ; }
get_latest_id () { tail -n1 "${db_file}" | awk '{print $1}' ; }
get_new_id () {
  highest_id=$(awk '{print $1}' "${db_file}" | sort -n | tail -n1)
  echo $((highest_id + 1))
}
# $1: post id
get_title () {
  title=$(grep "^${post_id}[[:blank:]]" "${db_file}" \
    | awk 'BEGIN {FS="\t"}; {print $4}' \
    | sed 's/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g; s/'"'"'/\&#39;/g'
    )
  date=$(grep "^${post_id}[[:blank:]]" "${db_file}" | awk 'BEGIN {FS="\t"}; {print $2}')
  if [ -n "${title}" ]; then
    echo "${title}"
  else
    echo "${date}"
  fi
}

# $1: image filename, $2: post id
gen_thumb () {
  if [ ! -f "${output_dir}/images/${2}/thumb_${1}" ]; then
    echo "Generating thumbnail for ${1}"
    convert -define jpeg:size=100x65 "${image_dir}/${1}" -thumbnail 100x65^ -gravity center -extent 100x65 "${output_dir}/images/${2}/thumb_${1}"
    mogrify -unsharp 0.25x0.08+8.3+0.045 "${output_dir}/images/${2}/thumb_${1}"
  fi
}

# $1: image filename, $2: post id
gen_image_versions () {
  # unsharp values from https://www.smashingmagazine.com/2015/06/efficient-image-resizing-with-imagemagick/
  for size in ${sizes}; do
    if [ ! -f "${output_dir}/images/${2}/${size}_${1}" ]; then
      echo "Generating ${size}x version of ${1}"
      convert -resize "${size}x" -quality 85 "${image_dir}/${1}" "${output_dir}/images/${2}/${size}_${1}"
      mogrify -unsharp 0.25x0.08+8.3+0.045 "${output_dir}/images/${2}/${size}_${1}"
    fi
  done
}

# $1: image filename, $2: post id
gen_images () {
  mkdir -p "${output_dir}/images/${2}"
  if [ -n "${sizes}" ]; then
    gen_image_versions "${1}" "${2}"
  else
    cp "${image_dir}/${1}" "${output_dir}/images/${2}"
  fi
  if [ "${archive_page}" = true ]; then
    gen_thumb "${1}" "${2}"
  fi
}

# $1: path, $2: RFC 822 datetime, $3: optional title
add_image () {
  orig_file_path=$1
  orig_file_basename=$(basename "${orig_file_path}")
  post_date=$2
  post_title=$3
  echo "Adding ${orig_file_basename}"

  if [ ! -f "${orig_file_path}" ]; then
    echo "Error: File ${orig_file_path} does not exist."
    exit 1
  fi

  # If filename already exists, prepend timestamp to the new one
  if [ -f "${image_dir}/${orig_file_basename}" ]; then
    timestamp=$(date "+%s")
    file_basename="${timestamp}_${orig_file_basename}"
    echo "${orig_file_basename} already exists; using ${file_basename} instead"
  else
    file_basename="${orig_file_basename}"
  fi

  # Figure out what ID to use
  prev_id=$(get_latest_id)
  if [ -z "${prev_id}" ]; then
    new_id=1
  else
    new_id=$(get_new_id)
  fi

  # Write to db
  printf "%s\t%s\t%s\t%s\n" "${new_id}" "${post_date}" "${file_basename}" "${post_title}" >> "${db_file}"
  # Copy original to (non-public) image directory
  cp -p "${orig_file_path}" "${image_dir}/${file_basename}"
  # Create different sizes/thumb
  gen_images "${file_basename}" "${new_id}"
}

# $1: filename, $2: post id
gen_img_src () {
  title=$(get_title "${2}")
  if [ -n "${sizes}" ]; then
    for size in $sizes; do
      srcset="${srcset}${web_root_path}images/${2}/${size}_${1} ${size}w, "
    done
    srcset=${srcset%, } # remove trailing ", "
    largest=${sizes%% *}
    echo "<img src=\"${web_root_path}images/${2}/${largest}_${1}\" srcset=\"${srcset}\" sizes=\"100vw\" class=\"image-inner\" alt=\"${title}\">"
  else
    echo "<img src=\"${web_root_path}images/${2}/${1}\" class=\"image-inner\" alt=\"${title}\">"
  fi
}

# $1: post id
gen_post_html () {
  unset prev_html next_html

  post_id=${1}
  prev_id=$(grep -B1 "^${post_id}[[:blank:]]" "${db_file}" | head -n1 | grep -v "^${post_id}[[:blank:]]" | awk '{print $1}')
  next_id=$(grep -A1 "^${post_id}[[:blank:]]" "${db_file}" | tail -n1 | grep -v "^${post_id}[[:blank:]]" | awk '{print $1}')
  filename=$(grep "^${post_id}[[:blank:]]" "${db_file}" | awk 'BEGIN {FS="\t"}; {print $3}')

  if [ -n "${prev_id}" ]; then
    image_before="<a href=\"${web_root_path}photo/${prev_id}/\">"
    image_after="</a>"
    prev_html="<a class=\"bold\" href=\"${web_root_path}photo/${prev_id}/\">← older</a> " 
  fi

  if [ -n "${next_id}" ]; then
    next_html=" <a class=\"bold\" href=\"${web_root_path}photo/${next_id}/\">newer →</a>" 
  fi

  mkdir -p "${output_dir}/photo/${post_id}"

  cat <<EOF > "${output_dir}/photo/${post_id}/index.html"
<!DOCTYPE html>
<html lang="en-US">
  <head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta name="referrer" content="no-referrer">
    <title>${site_title}</title>
    <link rel="stylesheet" href="${web_root_path}style.css">
    <link href="${web_root_path}index.xml" rel="alternate" type="application/rss+xml" title="${site_title}">
  </head>
  <body>

  ${image_before}
    <div class="image-outer">$(gen_img_src "${filename}" "${post_id}")</div>
  ${image_after}
  ${prev_html}
  ${menu}
  ${next_html}
  </body>
</html>
EOF
}

gen_archive_html () {
  echo "Creating archive page"
  thumb_html=$(sed '1!G;h;$!d' "${db_file}" \
    | awk -v web_root="${web_root_path}" \
      'BEGIN { FS="\t" }; {
        printf "<a href=\"%sphoto/%s/\"><img src=\"%simages/%s/thumb_%s\" alt=\"%s\"></a>\n",
        web_root, $1, web_root, $1, $3, $2
      }'
    )

  cat <<EOF > "${output_dir}/photo/index.html"
<!DOCTYPE html>
<html lang="en-US">
  <head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta name="referrer" content="no-referrer">
    <title>${site_title}</title>
    <link rel="stylesheet" href="${web_root_path}style.css">
    <link href="${web_root_path}index.xml" rel="alternate" type="application/rss+xml" title="${site_title}">
  </head>
  <body>
    <div class="list">
      ${thumb_html}
    </div>
    ${menu}
  </body>
</html>
EOF
}

gen_css () {
  cat <<EOF > "${output_dir}/style.css"
* {
  margin: 0;
  padding: 0;
}

body {
  background: black;
  color: #868e96;
  font-family: sans-serif;
  font-size: 0.8em;
  text-align: center;
}

.bold {
  font-weight: bold;
}

a {
  color: #868e96;
}

.image-outer {
  display: grid;
  height: 100%;
}

.image-inner {
  max-width: 100%;
  max-height: 100vh;
  margin: auto;
}
EOF
}

gen_rss() {
  last_build_date=$(date "+%a, %d %b %Y %H:%M:%S %z")
  rss_items=$(sed '1!G;h;$!d' "${db_file}" \
    | head -n "${rss_items}" \
    | awk -v site_url="${site_url}" -v largest="${sizes%% *}" \
      'BEGIN { FS="\t" }; {
        printf "<item>\n"
        if (length($4) > 0) {
          printf "<title>%s</title>\n", $4
        } else {
          printf "<title>%s</title>\n", $2
        }
        printf "<link>%sphoto/%s/</link>\n", site_url, $1
        printf "<pubDate>%s</pubDate>\n", $2
        printf "<guid>%sphoto/%s/</guid>\n", site_url, $1
        printf "<description><![CDATA[<img src=\"%simages/%s/%s_%s\" />]]></description>\n", site_url, $1, largest, $3
        printf "</item>\n"
      }'
    )

  cat <<EOF > "${output_dir}/index.xml"
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom">
  <channel>
    <title>${site_title}</title>
    <link>${site_url}</link>
    <description>Recent photos from ${site_title}</description>
    <lastBuildDate>${last_build_date}</lastBuildDate>
    <atom:link href="${site_url}index.xml" rel="self" type="application/rss+xml" />
    ${rss_items}
  </channel>
</rss>
EOF
}

rebuild_all () {
  echo "Rebuilding everything"
  num_posts=$(get_num_posts)
  if [ "${num_posts}" -lt "1" ]; then
    echo "No posts in ${db_file}. Exiting."
    exit
  fi

  while IFS= read -r line; do
    if [ -n "${line}" ]; then
      post_id=$(echo "${line}" | awk '{print $1}')
      filename=$(echo "${line}" | awk 'BEGIN {FS="\t"}; {print $3}')
      echo "Processing ${filename} (ID ${post_id})"
      gen_images "${filename}" "${post_id}"
      gen_post_html "${post_id}"
    fi
  done < "${db_file}"

  if [ "${archive_page}" = true ]; then
    gen_archive_html
  fi
  echo "Copying latest post to ${output_dir}/index.html"
  cp "${output_dir}/photo/$(get_latest_id)/index.html" "${output_dir}/index.html"
  gen_css
  gen_rss
}

# $1: ID to remove
remove_post () {
  echo "Removing ID ${1}"
  if grep -q "^${1}[[:blank:]]" "${db_file}"; then
    grep -v "^${1}[[:blank:]]" "${db_file}" > "${db_file}.tmp" && mv "${db_file}.tmp" "${db_file}" 
  else
    echo "ID ${1} not found in db. Exiting."
    exit 1
  fi
}

# Make sure necessary files/directories exist
touch "${db_file}"
mkdir -p "${image_dir}" "${output_dir}" "${output_dir}/images" "${output_dir}/photo"
if ! [ -f "${output_dir}/style.css" ]; then
  echo "${output_dir}/style.css missing. Generating"
  gen_css
fi

# Make sure ImageMagick's convert/mogrify are available if image generation is needed
if [ "${archive_page}" = true ] || [ -n "${sizes}" ] ; then
  command -v convert >/dev/null 2>&1 || { echo >&2 "Error: ImageMagick convert command not found"; exit 1; }
  command -v mogrify >/dev/null 2>&1 || { echo >&2 "Error: ImageMagick mogrify command not found"; exit 1; }
fi

if [ "${rebuild}" = true ]; then
  rebuild_all
elif [ -n "${id_to_remove}" ]; then
  if [ -z "${id_to_remove##*[!0-9]*}" ]; then
    echo "Specified ID not positive integer."
    exit 1
  else
    remove_post "${id_to_remove}"
    rebuild_all
  fi
else
  shift $((OPTIND - 1))
  if [ -z "$1" ]; then
    usage
    exit 1
  fi

  add_image "${1}" "${post_date}" "${post_title}"
  new_id=$(get_latest_id)
  gen_post_html "${new_id}"
  # New post also becomes the new index.html
  cp "${output_dir}/photo/${new_id}/index.html" "${output_dir}/index.html"

  # If there's more than one post, update the previous one's HTML so it gets a "Next" link to the new post
  num_posts=$(get_num_posts)
  if [ "${num_posts}" -gt "1" ]; then
    prev_id=$(tail -n2 "${db_file}" | head -n1 | awk '{print $1}')
    gen_post_html "${prev_id}"
  fi

  if [ "${archive_page}" = true ]; then
    gen_archive_html
  fi

  gen_rss
fi

echo "All done! Your photoblog is in ${output_dir}"
