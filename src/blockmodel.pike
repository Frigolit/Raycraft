class BlockModel {
	array(BlockModelElement) elements = ({ });
	mapping textures = ([ ]);

	Image.Image texture;	// Temporary hack for debugging

	void set_data(mapping m) {
		texture = Image.ANY.decode(Stdio.read_file(m->texture));

		if (m->colour_overlay) {
			texture = texture * m->colour_overlay;
		}
	}
}

class BlockModelElement {
	
}
