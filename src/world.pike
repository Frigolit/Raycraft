class MCWorld {
	mapping(string:MCAnvilFile) region_cache = ([ ]);
	private string base_path;

	NBT_Tag_Compound level;
	mapping(string:NBT_Tag_Compound) players = ([ ]);

	mixed _sprintf(mixed ... args) {
		return sprintf("MCWorld(%O)", base_path);
	}

	void create(string path) {
		set_weak_flag(region_cache, Pike.WEAK_VALUES);
		base_path = path;

		level = nbt_parse(Gz.File(combine_path(base_path, "level.dat")));

		if (Stdio.is_dir(combine_path(base_path, "players"))) {
			foreach (get_dir(combine_path(base_path, "players")), string a) {
				if (glob("*.dat", a)) {
					string p = combine_path(base_path, "players/" + a);

					players[(a / ".")[0..<1] * "."] = nbt_parse(Gz.File(p));
				}
			}
		}
	}

	array(MCChunk) get_all_chunks() {
		array r = ({ });
		foreach (get_all_regions(), object a) {
			r += a->get_all_chunks();
		}
		return r;
	}

	//! Gets a chunk from block coordinates (the chunk a specific block is in)
	MCChunk|void get_chunk_from_block(int block_x, int block_z) {
		return get_chunk(block_x >> 4, block_z >> 4);
	}

	//! Gets a chunk from chunk coordinates
	MCChunk|void get_chunk(int chunk_x, int chunk_z) {
		MCAnvilFile a = get_region(chunk_x >> 5, chunk_z >> 5);
		if (!a) return UNDEFINED;
		return a->get_chunk(chunk_x, chunk_z);
	}

	//! Gets a region file (anvil)
	MCAnvilFile|void get_region(int region_x, int region_z) {
		MCAnvilFile r = region_cache[region_x + "." + region_z];
		if (r) return r;
		else {
			string p = combine_path(base_path, "region/r." + region_x + "." + region_z + ".mca");

			if (!Stdio.is_file(p)) return UNDEFINED;
			return r = region_cache[region_x + "." + region_z] = MCAnvilFile(Stdio.File(p, "rw"), region_x, region_z);
		}
	}

	array(MCAnvilFile) get_all_regions() {
		array r = ({ });
		array a = get_dir(combine_path(base_path, "region"));
		foreach (a, string b) {
			if (glob("r.**.*.mca", b)) {
				int x, z;
				sscanf(b, "r.%d.%d.mca", x, z);
				
				r += ({ get_region(x, z) });
			}
		}
		return r;
	}
}
