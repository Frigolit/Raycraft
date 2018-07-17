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

	mapping(int:System.Memory) section_blocks;
	mapping(int:System.Memory) section_add;
	mapping(int:System.Memory) section_data;
	mapping(int:System.Memory) section_light;
	mapping(int:System.Memory) section_skylight;

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

		System.Memory m;
		section_blocks = ([ ]);
		section_add = ([ ]);
		section_data = ([ ]);
		section_light = ([ ]);
		section_skylight = ([ ]);

		foreach (level->get_child("Sections")->children, object o) {
			int y = o->get_child("Y")->value;

			section_blocks[y] = m = System.Memory(4096);
			m->pwrite(0, (string)o->get_child("Blocks")->values);

			if (o->get_child("Add")) {
				section_add[y] = m = System.Memory(2048);
				m->pwrite(0, (string)o->get_child("Add")->values);
			}

			if (o->get_child("Data")) {
				section_data[y] = m = System.Memory(2048);
				m->pwrite(0, (string)o->get_child("Data")->values);
			}

			if (o->get_child("BlockLight")) {
				section_light[y] = m = System.Memory(2048);
				m->pwrite(0, (string)o->get_child("BlockLight")->values);
			}

			if (o->get_child("SkyLight")) {
				section_skylight[y] = m = System.Memory(2048);
				m->pwrite(0, (string)o->get_child("SkyLight")->values);
			}
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

	mapping get_block(int x, int y, int z) {
		int s = (y >> 4);
		y &= 15;

		if (!section_blocks[s]) {
			return UNDEFINED;
		}

		int n = y*16*16 + z*16 + x;
		int id = section_blocks[s][n] | (section_add[s] ? ((section_add[s][n / 2] >> ((n % 2) << 2)) & 0x0F) : 0);

		if (!id) {
			return UNDEFINED;
		}

		return ([
			"id": id,
			"data": ((section_data[s][n / 2] >> ((n % 2) * 4)) & 0x0F) || 0,
			"light": section_light[s] ? (section_light[s][n / 2] >> ((n % 2) << 2)) & 0x0F : UNDEFINED,
			"skylight": section_skylight[s] ? (section_skylight[s][n / 2] >> ((n % 2) << 2)) & 0x0F : UNDEFINED,
		]);
	}
}
