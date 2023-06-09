all: street-light.tex
	@mkdir -p build/
	tectonic -X compile \
		--synctex \
		--keep-logs \
		--keep-intermediates \
		--outdir build/ \
		street-light.tex

clean:
	rm -rf build/
