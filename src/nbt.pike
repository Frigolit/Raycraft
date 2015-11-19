NBT_Tag nbt_parse_tag(Stdio.File|string f, int tag, string name, int|void depth) {
	if (stringp(f)) f = Stdio.FakeFile(f);

	if (tag == 0) {
		// End
		return NBT_Tag_End(name);
	}
	else if (tag == 1) {
		// Byte
		int v;
		sscanf(f->read(1), "%+1c", v);
		return NBT_Tag_Byte(name, v);
	}
	else if (tag == 2) {
		// Short
		int v;
		sscanf(f->read(2), "%+2c", v);
		return NBT_Tag_Short(name, v);
	}
	else if (tag == 3) {
		// Int
		int v;
		sscanf(f->read(4), "%+4c", v);
		return NBT_Tag_Int(name, v);
	}
	else if (tag == 4) {
		// Long
		int v;
		sscanf(f->read(8), "%+8c", v);
		return NBT_Tag_Long(name, v);
	}
	else if (tag == 5) {
		// Float (32-bit)
		float v;
		sscanf(f->read(4), "%4F", v);
		return NBT_Tag_Float(name, v);
	}
	else if (tag == 6) {
		// Double (64-bit)
		float v;
		sscanf(f->read(8), "%8F", v);
		return NBT_Tag_Double(name, v);
	}
	else if (tag == 7) {
		// Byte array
		int size;
		sscanf(f->read(4), "%4c", size);
		return NBT_Tag_ByteArray(name, (array)f->read(size));
	}
	else if (tag == 8) {
		// String
		int size;
		sscanf(f->read(2), "%2c", size);
		return NBT_Tag_String(name, f->read(size));
	}
	else if (tag == 9) {
		// List
		int list_tag_id;
		int list_size;

		sscanf(f->read(5), "%c%4c", list_tag_id, list_size);

		array(NBT_Tag) r = ({ });
		for (int i = 0; i < list_size; i++) {
			r += ({ nbt_parse_tag(f, list_tag_id, "", depth + 1) });
		}

		return NBT_Tag_List(name, list_tag_id, r);
	}
	else if (tag == 10) {
		// Compound
		array a = ({ });
		while (true) {
			NBT_Tag t = nbt_parse(f, depth + 1);
			if (!t->tag_id) break;
			a += ({ t });
		}

		return NBT_Tag_Compound(name, a);
	}
	else if (tag == 11) {
		// Int array

		int size;
		sscanf(f->read(4), "%4c", size);

		string x = f->read(size * 4);
		array v = Array.flatten(array_sscanf(x, "%{%4c%}"));

		return NBT_Tag_IntArray(name, v);
	}
	else {
		throw(({ "Unknown tag id " + tag + "\n", backtrace() }));
	}
}

NBT_Tag nbt_parse(Stdio.File|string f, int|void depth) {
	if (stringp(f)) f = Stdio.FakeFile(f);

	int tag = f->read(1)[0];
	if (!tag) return NBT_Tag_End;

	int name_len;
	sscanf(f->read(2), "%2c", name_len);
	string name = f->read(name_len);

	return nbt_parse_tag(f, tag, name, depth);
}

// ============================================================================
// NBT tag classes
// ============================================================================

class NBT_Tag {
	constant tag_id = 255;
	string tag_name;

	mixed _sprintf(mixed ... args) {
		return sprintf("NBT_Tag(%d, %O)", tag_id, tag_name);
	}

	void create(string name) {
		tag_name = name;
	}

	string encode() {
		return sprintf("%c%2H", tag_id, tag_name) + encode_payload();
	}

	string encode_payload() { throw(({ "encode_payload() unimplemented in tag " + tag_id + "\n", backtrace() })); }
}

class NBT_Tag_End {
	inherit NBT_Tag;

	constant tag_id = 0;

	mixed _sprintf(mixed ... args) {
		return sprintf("NBT_Tag_End(%d, %O)", tag_id, tag_name);
	}

	string encode_payload() { return ""; }
}

class NBT_Tag_Byte {
	inherit NBT_Tag;

	constant tag_id = 1;
	int(0..255) value;

	mixed _sprintf(mixed ... args) {
		return sprintf("NBT_Tag_Byte(%d, %O, %d)", tag_id, tag_name, value);
	}

	void create(string name, int(0..255) v) {
		::create(name);
		value = v;
	}

	string encode_payload() {
		return sprintf("%c", value);
	}
}

class NBT_Tag_Short {
	inherit NBT_Tag;

	constant tag_id = 2;
	int(0..65535) value;

	mixed _sprintf(mixed ... args) {
		return sprintf("NBT_Tag_Short(%d, %O, %d)", tag_id, tag_name, value);
	}

	void create(string name, int(0..65535) v) {
		::create(name);
		value = v;
	}

	string encode_payload() {
		return sprintf("%2c", value);
	}
}

class NBT_Tag_Int {
	inherit NBT_Tag;

	constant tag_id = 3;
	int(0..4294967295) value;

	mixed _sprintf(mixed ... args) {
		return sprintf("NBT_Tag_Int(%d, %O, %d)", tag_id, tag_name, value);
	}

	void create(string name, int(0..4294967295) v) {
		::create(name);
		value = v;
	}

	string encode_payload() {
		return sprintf("%4c", value);
	}
}

class NBT_Tag_Long {
	inherit NBT_Tag;

	constant tag_id = 4;
	int(0..18446744073709551615) value;

	mixed _sprintf(mixed ... args) {
		return sprintf("NBT_Tag_Long(%d, %O, %d)", tag_id, tag_name, value);
	}

	void create(string name, int(0..18446744073709551615) v) {
		::create(name);
		value = v;
	}

	string encode_payload() {
		return sprintf("%8c", value);
	}
}

class NBT_Tag_Float {
	inherit NBT_Tag;

	constant tag_id = 5;
	float value;

	mixed _sprintf(mixed ... args) {
		return sprintf("NBT_Tag_Float(%d, %O, %f)", tag_id, tag_name, value);
	}

	void create(string name, float v) {
		::create(name);
		value = v;
	}

	string encode_payload() {
		return sprintf("%4F", value);
	}
}

class NBT_Tag_Double {
	inherit NBT_Tag;

	constant tag_id = 6;
	float value;

	mixed _sprintf(mixed ... args) {
		return sprintf("NBT_Tag_Float(%d, %O, %f)", tag_id, tag_name, value);
	}

	void create(string name, float v) {
		::create(name);
		value = v;
	}

	string encode_payload() {
		return sprintf("%8F", value);
	}
}

class NBT_Tag_ByteArray {
	inherit NBT_Tag;

	constant tag_id = 7;
	array values;

	mixed _sprintf(mixed ... args) {
		return sprintf("NBT_Tag_ByteArray(%d, %O, %d)", tag_id, tag_name, sizeof(values));
	}

	void create(string name, array(int(0..255)) _values) {
		::create(name);
		values = _values;
	}

	string encode_payload() {
		return sprintf("%4c", sizeof(values)) + (string)values;
	}
}

class NBT_Tag_String {
	inherit NBT_Tag;

	constant tag_id = 8;
	string value;

	mixed _sprintf(mixed ... args) {
		return sprintf("NBT_Tag_String(%d, %O, %O)", tag_id, tag_name, value);
	}

	void create(string name, string v) {
		::create(name);
		value = v;
	}

	string encode_payload() {
		return sprintf("%2H", value);
	}
}

class NBT_Tag_List {
	inherit NBT_Tag;

	constant tag_id = 9;
	array children;
	int list_tag_id;

	mixed _sprintf(mixed ... args) {
		return sprintf("NBT_Tag_List(%d, %O, %d)", tag_id, tag_name, sizeof(children));
	}

	void create(string name, int _tagid, array(NBT_Tag) _children) {
		::create(name);
		list_tag_id = _tagid;
		children = _children;
	}

	string encode_payload() {
		string r = sprintf("%c%4c", list_tag_id, sizeof(children));

		foreach (children, NBT_Tag t) {
			r += t->encode_payload();
		}

		return r;
	}
}

class NBT_Tag_Compound {
	inherit NBT_Tag;

	constant tag_id = 10;
	array children;

	mixed _sprintf(mixed ... args) {
		return sprintf("NBT_Tag_Compound(%d, %O, %d)", tag_id, tag_name, sizeof(children));
	}

	void create(string name, array(NBT_Tag) _children) {
		::create(name);
		children = _children;
	}

	NBT_Tag|void get_child(string name) {
		foreach (children, NBT_Tag t) {
			if (t->tag_name == name) return t;
		}
	}

	string encode_payload() {
		string r = "";

		foreach (children, NBT_Tag t) {
			r += t->encode();
		}

		return r + "\0";
	}
}

class NBT_Tag_IntArray {
	inherit NBT_Tag;

	constant tag_id = 11;
	array values;

	mixed _sprintf(mixed ... args) {
		return sprintf("NBT_Tag_IntArray(%d, %O, %d)", tag_id, tag_name, sizeof(values));
	}

	void create(string name, array(int(0..4294967295)) _values) {
		::create(name);
		values = _values;
	}

	string encode_payload() {
		return sprintf("%4c%{%4c%}", sizeof(values), values);
	}
}
