LUALATEX = $(RUN) lualatex -interaction=nonstopmode -halt-on-error
SEEDS   ?= 1 2 3 4 5 6
# RUN=tools/in-docker builds inside the florilegium-tex image (see tools/Dockerfile)
RUN     ?=
LUA      = $(wildcard *.lua)
HOSTS    = florilegium-luatex.def florilegium-xetex.def
GS      ?= gs
SEED    ?= 7
CHECK_SEEDS ?= 1

all: florilegium.pdf florilegium-grow.pdf showcase.pdf

florilegium.pdf florilegium-grow.pdf showcase.pdf specimen.pdf: $(HOSTS)

check:
	$(RUN) texlua tools/contractcheck.lua
	$(RUN) texlua tools/replaycheck.lua
	$(RUN) python3 tools/determinism_oracle.py
	$(RUN) texlua tools/geometrycheck.lua
	$(RUN) python3 tools/geometry_oracle.py
	$(RUN) texlua tools/scenecheck.lua
	$(RUN) python3 tools/scene_oracle.py
	$(RUN) texlua tools/plannercheck.lua
	$(RUN) python3 tools/planner_oracle.py
	$(RUN) texlua tools/botanicalcheck.lua --legacy-layout
	$(RUN) python3 tools/botanical_oracle.py
	$(RUN) texlua tools/periodiccheck.lua
	$(RUN) python3 tools/periodic_oracle.py
	$(RUN) texlua tools/celticcheck.lua
	$(RUN) python3 tools/celtic_oracle.py
	$(RUN) texlua tools/islamiccheck.lua
	$(RUN) python3 tools/islamic_oracle.py
	$(RUN) texlua tools/freeformcheck.lua
	$(RUN) python3 tools/freeform_oracle.py
	$(RUN) texlua tools/substitutioncheck.lua
	$(RUN) python3 tools/substitution_oracle.py
	$(RUN) texlua tools/penrosecheck.lua
	$(RUN) python3 tools/penrose_oracle.py
	$(RUN) texlua tools/spectrecheck.lua
	$(RUN) python3 tools/spectre_oracle.py
	$(RUN) texlua tools/integrationcheck.lua
	$(RUN) python3 tools/integration_oracle.py
	$(RUN) texlua tools/beenkercheck.lua
	$(RUN) python3 tools/beenker_oracle.py
	$(RUN) texlua tools/hatcheck.lua
	$(RUN) python3 tools/hat_oracle.py
	$(RUN) texlua tools/tracerycheck.lua
	$(RUN) python3 tools/tracery_oracle.py
	$(RUN) texlua tools/eschercheck.lua
	$(RUN) python3 tools/escher_oracle.py
	$(RUN) texlua tools/mosaiccheck.lua
	$(RUN) python3 tools/mosaic_oracle.py
	$(RUN) texlua tools/strokecheck.lua
	$(RUN) python3 tools/stroke_oracle.py
	$(RUN) texlua tools/mazecheck.lua
	$(RUN) python3 tools/maze_oracle.py
	$(RUN) texlua tools/micrographycheck.lua
	$(RUN) python3 tools/micrography_oracle.py
	$(RUN) texlua tools/check-deco-integration.lua
	$(RUN) texlua tools/decocheck.lua
	$(RUN) python3 tools/deco_oracle.py
	$(RUN) texlua tools/layoutcheck.lua
	$(RUN) texlua tools/spacecheck.lua
	$(RUN) texlua tools/initialcheck.lua
	$(RUN) texlua tools/backendcheck.lua
	$(RUN) python3 tools/layoutsmoke.py
	$(RUN) python3 tools/bookcheck.py
	$(RUN) texlua tools/animcheck.lua $(CHECK_SEEDS)

botanical-engine-check:
	$(RUN) python3 tools/botanical_enginecheck.py

engine-check:
	$(RUN) python3 tools/enginecheck.py

offset-check:
	$(RUN) python3 tools/offsetcheck.py

folio-preview:
	$(RUN) python3 tools/foliopreview.py

xe:
	$(RUN) python3 tools/build.py folio-demo.tex --engine xe --output-dir build/xe

source-package:
	$(RUN) python3 tools/package.py

export-check:
	$(RUN) python3 tools/exportcheck.py

visual-check:
	$(RUN) python3 tools/visualcheck.py

book-preview: book-demo.tex florilegium.sty grow.lua $(LUA) tools/bookpreview.py
	$(RUN) python3 tools/bookpreview.py

layout-preview: layout-demo.tex florilegium.sty grow.lua $(LUA) tools/layoutpreview.py
	$(RUN) python3 tools/layoutpreview.py

# authored composition (authored.lua), one pass, about a second a page
florilegium.pdf: florilegium.tex florilegium.sty authored.lua grow.lua $(LUA) text-methods.tex text-sharing.tex
	$(LUALATEX) florilegium.tex

# grown composition (grow.lua), one pass: the end of the text is measured with \pagetotal
florilegium-grow.pdf: florilegium-grow.tex florilegium.sty grow.lua $(LUA) text-methods.tex text-growth.tex text-sharing.tex
	$(LUALATEX) florilegium-grow.tex

# initials, flowers at the headings, visitors and the seasons; two passes, because
# the option aging reads the page count of the first one
showcase.pdf: showcase.tex florilegium.sty grow.lua $(LUA)
	$(LUALATEX) showcase.tex
	$(LUALATEX) showcase.tex

# one of every primitive, drawn with \florilegiumdraw
specimen.pdf: specimen.tex florilegium.sty $(LUA)
	$(LUALATEX) specimen.tex

# one page for one seed:  make seed-7  ->  build/seed-7.pdf
seed-%: gallery.tex florilegium.sty grow.lua $(LUA)
	mkdir -p build
	$(LUALATEX) -jobname=build/seed-$* "\def\florilegiumseed{$*}\input{gallery.tex}"

# contact sheets: seeds (+ gif), one seed in six inks, one seed through the seasons
# (needs python3 + Pillow + pdftoppm)
gallery: gallery.tex florilegium.sty grow.lua $(LUA) tools/gallery.py
	python3 tools/gallery.py --seeds $(SEEDS) --run "$(RUN)"
	python3 tools/gallery.py --seed 6 --inks 2456C4 5B2A1F 2F6B4F 8E1B3A 4B3B8F 1D6E7A --run "$(RUN)"
	python3 tools/gallery.py --seed 6 --ages 0 0.33 0.67 1 --run "$(RUN)"

# the growth of one seed:  make grow-7  ->  build/grow-7.gif and .mp4 (MP4 needs ffmpeg);
# EXPLAIN=1 also marks the free disc each branch grows to  ->  build/grow-7-explain.*
grow-%: animation.tex florilegium.sty grow.lua $(LUA) tools/animate.py
	python3 tools/animate.py --seed $* --run "$(RUN)" $(if $(EXPLAIN),--explain)

# the README's animations (seed 6: all four visitors)
animation:
	$(MAKE) grow-6 RUN="$(RUN)"
	$(MAKE) grow-6 RUN="$(RUN)" EXPLAIN=1
	cp build/grow-6.gif gallery/growth.gif
	cp build/grow-6-explain.gif gallery/growth-explain.gif

# the PostScript port, run by Ghostscript:  make postscript [SEED=7]
#   -> build/postscript-7.pdf and gallery/preview-postscript.png (pdftoppm, Pillow)
postscript: postscript/florilegium.ps
	mkdir -p build gallery
	$(GS) -q -dSAFER -dBATCH -dNOPAUSE -dALLOWPSTRANSPARENCY -dSeed=$(SEED) \
	  -sDEVICE=pdfwrite -o build/postscript-$(SEED).pdf postscript/florilegium.ps
	pdftoppm -png -r 45 build/postscript-$(SEED).pdf build/postscript
	python3 -c "from PIL import Image; import glob; \
	  ims = [Image.open(f).convert('RGB') for f in sorted(glob.glob('build/postscript-[0-9].png'))]; w, h = ims[0].size; \
	  s = Image.new('RGB', (len(ims) * (w + 8) + 8, h + 16), (235, 235, 240)); \
	  [s.paste(im, (8 + i * (w + 8), 8)) for i, im in enumerate(ims)]; s.save('gallery/preview-postscript.png')"

preview: florilegium.pdf florilegium-grow.pdf showcase.pdf
	mkdir -p gallery
	pdftoppm -png -r 60 -f 1 -l 1 -singlefile florilegium.pdf gallery/preview-authored
	pdftoppm -png -r 60 -f 1 -l 1 -singlefile florilegium-grow.pdf gallery/preview-grown
	pdftoppm -png -r 45 showcase.pdf build/showcase
	python3 -c "from PIL import Image; import glob; \
	  ims = [Image.open(f).convert('RGB') for f in sorted(glob.glob('build/showcase-*.png'))]; w, h = ims[0].size; \
	  s = Image.new('RGB', (len(ims) * (w + 8) + 8, h + 16), (235, 235, 240)); \
	  [s.paste(im, (8 + i * (w + 8), 8)) for i, im in enumerate(ims)]; s.save('gallery/preview-showcase.png')"

clean:
	rm -rf build *.aux *.log *.out *.synctex.gz

.PHONY: all check botanical-engine-check engine-check offset-check folio-preview xe source-package export-check visual-check book-preview layout-preview gallery animation preview postscript clean

