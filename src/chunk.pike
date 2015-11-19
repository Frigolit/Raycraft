class MCChunk {
	Stdio.File fd;
	int sector_offset;
	int sector_size;

	string data_hash;
	string data;

	int data_length;
	int compression_type;

	int(0..1) modified;
	int(0..1) loaded;

	mapping(int:System.Memory) sections;

	NBT_Tag nbt;

	int xpos;
	int zpos;

	string cache_path;

	array heightmap;

	mixed _sprintf(mixed ... args) {
		return sprintf("MCChunk(%d)", compression_type);
	}

	void create(Stdio.File f, int offset, int size) {
		fd = f->dup();

		fd->seek(offset << 12);
		sscanf(fd->read(5), "%4c%c", data_length, compression_type);
		data = fd->read(data_length);
		data_hash = Crypto.SHA256.hash(data);

		cache_path = combine_path(getenv()->HOME, ".raycraft/cache/chunks/" + sprintf("%02X/%02X/%s", data_hash[0], data_hash[1], String.string2hex(data_hash[2..])));

		if (Stdio.is_file(cache_path)) {
			cache_load();
		}
		else load();

		fd->close();
	}

	void load() {
		if (loaded) return;

		string x = Gz.inflate(0)->inflate(data);

		nbt = nbt_parse(x);
		loaded = 1;

		object level = nbt->get_child("Level");
		xpos = level->get_child("xPos")->value;
		zpos = level->get_child("zPos")->value;

		heightmap = level->get_child("HeightMap")->values / 16;

		sections = ([ ]);
		foreach (level->get_child("Sections")->children, object o) {
			System.Memory m = System.Memory(16 * 16 * 16);
			m->pwrite(0, (string)o->get_child("Blocks")->values);

			int y = o->get_child("Y")->value;
			sections[y] = m;
		}

		//cache_save();
	}

	void cache_load() {
		mapping m = Standards.JSON.decode(Stdio.read_file(cache_path));
		xpos = m->x;
		zpos = m->z;
		heightmap = m->heightmap;
	}

	void cache_save() {
		mapping m = ([
			"x": xpos,
			"z": zpos,
			"heightmap": heightmap,
		]);

		if (!Stdio.is_dir(dirname(cache_path))) {
			Stdio.mkdirhier(dirname(cache_path));
		}

		Stdio.write_file(cache_path, Standards.JSON.encode(m));
	}

	int get_block(int x, int y, int z) {
		int s = (y >> 4);
		y &= 15;

		if (!sections[s]) return 0;

		return sections[s][y*16*16 + z*16 + x];
	}
}
