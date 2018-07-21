class BlockModel {
	array(BlockModelElement) elements = ({ });
	mapping materials = ([ ]);

	Material material;
	bool join_blocks = true;

	void set_data(mapping m) {
		if (!undefinedp(m->join_blocks)) {
			join_blocks = m->join_blocks;
		}

		if (m->texture) {
			material = build_material_from_png(m->texture, m->colour_overlay);
		}

		if (m->textures) {
			foreach (m->textures; string side; mapping s) {
				Material mat = build_material_from_png(s->filename, s->colour_overlay);

				if (side == "sides") {
					materials["front"] = mat;
					materials["back"] = mat;
					materials["left"] = mat;
					materials["right"] = mat;
				}
				else {
					materials[side] = mat;
				}
			}
		}
	}
}

class BlockModelElement {
	
}

class Material {
	Image.Image image;
	Image.Image alpha;

	int width, height;

	void create(Image.Image _image, Image.Image _alpha) {
		image = _image;
		alpha = _alpha;

		width = image->xsize();
		height = image->ysize();
	}

	array(float) get(float u, float v) {
		int x = (int)(u * width);
		int y = (int)(v * height);

		array c = image->getpixel(x, y);
		array a = alpha->getpixel(x, y);

		return ({
			c[0] / 255.0,
			c[1] / 255.0,
			c[2] / 255.0,
			a[0] / 255.0
		});
	}
}

Material build_material_from_png(string filename, array|void colour_overlay) {
	mapping png = Image.PNG._decode(Stdio.read_file(filename));

	Image.Image image = png->image;
	Image.Image alpha = png->alpha;

	int w = image->xsize();
	int h = image->ysize();

	if (h > w) {
		image = image->copy(0, 0, w - 1, w - 1);
		alpha = alpha->copy(0, 0, w - 1, w - 1);
		h = w;
	}

	if (colour_overlay) {
		image *= colour_overlay;
	}

	if (!alpha) {
		alpha = Image.Image(255, 255, 255, w, h);
	}

	return Material(image, alpha);
}
