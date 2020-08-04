1600pr.sh: simple static photoblog generator
============================================
1600pr.sh is a minimalist static photoblog generator made up of a single
POSIX-compliant shell script. It should work on most Unix-like systems. It passes
[ShellCheck](https://github.com/koalaman/shellcheck) and some effort has been
made to ensure external tools (grep, sed, awk, etc.) are used in a portable way.

The only external dependency is [ImageMagick](https://imagemagick.org)
for creation of thumbnails and alternative sizes (for responsive images),
however this can be disabled if you don't want those things.

You can see it in action on [minorshadows.net](https://minorshadows.net/).

Named after Fujifilm Neopan 1600 Professional (RIP). Inspired by (but not based
on) [Expose](https://github.com/Jack000/Expose).

Installation and usage
----------------------
```sh
# Download script
curl -O https://github.com/andersju/1600pr.sh/raw/master/1600pr.sh
# Make it executable
chmod +x 1600pr.sh
# Add first photo
./1600pr.sh ~/some-photo.jpg
```
Boom, you now have a photoblog built in `public/`.

You probably have Python installed, so fire up a local web server and look around:

    cd public/ && python3 -m http.server

### Deploy

rsync or scp the files in `public/` to somewhere:

    rsync -av -e ssh public/* user@example.com:public_html

You probably want to change a few variables (title, absolute url, menu) in
the script, though, or set environment variables (`_1600PR_SITE_TITLE`,
`_1600PR_SITE_URL`, `_1600PR_EMAIL`, etc).

### More things you can do

Add photo with title:

    ./1600pr.sh -t "My cat." ~/my-cat.jpg

Title is only used in the RSS feed, and for the image's `alt` attribute. If no
title is set, current date will be used instead.

Add photo with title and custom date (should be RFC 822 datetime):

    ./1600pr.sh -t "My cat." -d "Sun, 31 May 2020 19:22:17 +0200" ~/my-cat.jpg

If you nuked your `public/`, or changed some setting (e.g. what sizes to generate),
you can rebuild everything with -b:

    ./1600pr.sh -b

Remove post with ID 23 from the "database" and rebuild:

    ./1600pr.sh -r 23

(This doesn't *remove* anything from `public/`, nor does it remove the
original photo stored in `images/`.)

ImageMagick is required, unless you set `sizes` to `""` and `archive_page` to false,
disabling creation of alternative sizes and archive page with thumbnails.

How it works
------------
Information about each post is stored in `_1600pr.dat`. It's a plaintext file
where each line represents one post, in ascending order from oldest to newest.
(To change the order, just move lines around and rebuild.)
Each line has tab-separated values: photo ID, date, filename, optional title.

The original photo is copied to the non-public folder `images/`. For each photo,
a number of sizes are generated (unless you've opted not to) and put in
`public/images/<id>/`.

One page per photo. Each photo page gets the relative URL `/photo/<id>/`.
Each page has "prev" and "next" links, if applicable.

`/photo/` is an archive page with thumbnails of every photo.

The most recent photo page is copied to `/index.html`.

RSS and CSS files are also generated.

Starting with only `1600pr.sh` and adding two photos (foo01.jpg and foo02.jpg),
we get the following:

```
.
├── _1600pr.dat
├── 1600pr.sh
├── images
│   ├── foo01.jpg
│   └── foo02.jpg
└── public
    ├── images
    │   ├── 1
    │   │   ├── 1280_foo01.jpg
    │   │   ├── 1600_foo01.jpg
    │   │   ├── 1920_foo01.jpg
    │   │   ├── 800_foo01.jpg
    │   │   └── thumb_foo01.jpg
    │   └── 2
    │       ├── 1280_foo02.jpg
    │       ├── 1600_foo02.jpg
    │       ├── 1920_foo02.jpg
    │       ├── 800_foo02.jpg
    │       └── thumb_foo02.jpg
    ├── index.html
    ├── index.xml
    ├── photo
    │   ├── 1
    │   │   └── index.html
    │   ├── 2
    │   │   └── index.html
    │   └── index.html
    └── style.css
```

Customize
---------
A bunch of things can be set with variables at the top of the script. Otherwise
just hack it to your heart's content. This is a quick hack for my own personal
use: it's deliberately minimalist and I'm not looking to add major features,
but perhaps it can be of use to someone else too.

To change title/url/email/sizes/etc. without modifying the script you can use
environment variables. Just set them somewhere, perhaps in a wrapper script, like so:

```
#!/bin/sh
export _1600PR_SITE_TITLE="example.com"
export _1600PR_SITE_URL="https://example.com/"
export _1600PR_EMAIL="foo@example.com"
exec ./1600pr.sh "$@"
```
