class BlockModel {
	array(BlockModelElement) elements = ({ });
	mapping textures = ([ ]);

	Image.Image texture;	// Temporary hack for debugging

	void set_data(mapping m) {
		texture = Image.ANY.decode(Stdio.read_file(m->texture));
	}
}

class BlockModelElement {
	
}
