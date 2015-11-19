class MCAnvilFile {
	private Stdio.File fd;
	private int region_x;
	private int region_z;

	private mapping(string:MCChunk) chunk_cache = ([ ]);

	private Thread.Mutex mtx = Thread.Mutex();

	mixed _sprintf(mixed ... args) {
		return sprintf("MCAnvilFile(%d, %d)", region_x, region_z);
	}

	void create(Stdio.File file, int x, int z) {
		fd = file;
		region_x = x;
		region_z = z;
	}

	MCChunk|void get_chunk(int x, int z) {
		if (chunk_cache[x + "." + z]) {
			return chunk_cache[x + "." + z];
		}

		x = x % 32;
		z = z % 32;

		int o = 4 * (x + z * 32);

		object k = mtx->lock(1);
		fd->seek(o);

		string d = fd->read(4);
		if (d == "\0\0\0\0") return UNDEFINED;

		int offset;
		int size;

		sscanf(d, "%3c%c", offset, size);

		return chunk_cache[x + "." + z] = MCChunk(fd, offset, size);
	}

	array(MCChunk)|void get_all_chunks() {
		array r = ({ });
		for (int z = 0; z < 32; z++) {
			for (int x = 0; x < 32; x++) {
				MCChunk c = get_chunk(x, z);
				if (c) r += ({ c });
			}
		}
		return r;
	}
}
