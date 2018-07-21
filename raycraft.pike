#!/usr/bin/env pike

#include "src/anvil.pike"
#include "src/chunk.pike"
#include "src/nbt.pike"
#include "src/world.pike"

#include "src/blockmodel.pike"

#define BLOCKSIZE 32

mapping models = ([ ]);
BlockModel default_model;

SDL.Surface screen;
MCWorld world;

bool antialias = false;

mapping chunk_cache = ([ ]);
ADT.History chunk_soft_cache = ADT.History(512);

string exec_path;
string world_path;

mapping bounds;

CColor bg_color = CColor(221.0/255.0, 237.0/255.0, 249.0/255.0);

int main(int argc, array argv) {
	exec_path = argv[0];

	antialias = Getopt.find_option(argv, "a", "antialias");

	int width = (int)Getopt.find_option(argv, "w", "width", UNDEFINED, "640");
	int height = (int)Getopt.find_option(argv, "h", "height", UNDEFINED, "360");

	float cam_init_x = (float)Getopt.find_option(argv, "x", "", UNDEFINED, "0.0");
	float cam_init_y = (float)Getopt.find_option(argv, "y", "", UNDEFINED, "100.0");
	float cam_init_z = (float)Getopt.find_option(argv, "z", "", UNDEFINED, "0.0");
	float cam_init_yaw = (float)Getopt.find_option(argv, "", "yaw", UNDEFINED, "0.0") + 90.0;
	float cam_init_pitch = (float)Getopt.find_option(argv, "", "pitch", UNDEFINED, "0.0") - 45.0;
	float cam_init_fov = (float)Getopt.find_option(argv, "f", "fov", UNDEFINED, "75.0");

	int enable_preview = (int)Getopt.find_option(argv, "p");
	string outfile = Getopt.find_option(argv, "o", "", UNDEFINED, "");
	int multiproc = (int)Getopt.find_option(argv, "m", "", UNDEFINED, "1");
	bool save_image_on_update = Getopt.find_option(argv, "u");

	int is_renderer = Getopt.find_option(argv, "", "renderer");

	if (multiproc < 1) {
		multiproc = 1;
	}

	argv = Getopt.get_args(argv);
	argc = sizeof(argv);

	set_weak_flag(chunk_cache, Pike.WEAK_VALUES);

	if (argc < 2) {
		werror("Usage: %s [options] <world path>\n", basename(argv[0]));
		werror("\n");

		werror("-p|--preview      Enable preview (SDL).\n");
		werror("-o FILENAME       Saves the image to the specified file (supports PNG (default), JPEG and GIF).\n");
		werror("-a|--antialias    Enable anti-aliasing.\n");
		werror("-w|--width=N      Sets the width of the render.\n");
		werror("-h|--height=N     Sets the height of the render.\n");
		werror("-x N              Sets the X coordinate for the camera.\n");
		werror("-y N              Sets the Y coordinate for the camera (default: 100.0).\n");
		werror("-z N              Sets the Z coordinate for the camera.\n");
		werror("--yaw=N           Sets the yaw rotation of the camera.\n");
		werror("--pitch=N         Sets the pitch rotation of the camera.\n");
		werror("-f|--fov=N        Sets the FOV of the camera (default: 75.0).\n");
		werror("-m N              Enables multi-processing with N worker processes.\n");
		werror("-u                When combined with -o, saves the framebuffer for every rendered tile.\n");

		return 1;
	}

	world_path = argv[1];

	// Load world
	world = MCWorld(argv[1]);
	bounds = world->get_bounds();

	// Load block data
	load_blocks();

	// Create fallback texture
	Image.Image texture_fallback = Image.Image(4, 4, 0, 0, 0);
	texture_fallback->setpixel(0, 0, 255, 255, 255);
	texture_fallback->setpixel(2, 0, 255, 255, 255);
	texture_fallback->setpixel(1, 1, 255, 255, 255);
	texture_fallback->setpixel(3, 1, 255, 255, 255);
	texture_fallback->setpixel(0, 2, 255, 255, 255);
	texture_fallback->setpixel(2, 2, 255, 255, 255);
	texture_fallback->setpixel(1, 3, 255, 255, 255);
	texture_fallback->setpixel(3, 3, 255, 255, 255);
	texture_fallback = texture_fallback->bitscale(16, 16);

	default_model = BlockModel();
	default_model->material = Material(texture_fallback, Image.Image(255, 255, 255, 4, 4));

	if (is_renderer) {
		void send(mapping m) {
			write(Standards.JSON.encode(m, Standards.JSON.ASCII_ONLY) + "\n");
		};

		void cmd(string d) {
			mapping m = Standards.JSON.decode(d);

			if (m->cmd == "render") {
				CCamera cam = CCamera(m->camera->x, m->camera->y, m->camera->z, m->camera->yaw, m->camera->pitch);
				cam->fov = m->camera->fov;

				Image.Image tile = cam->render_tile(m->x, m->y, m->w, m->h, m->blksize, m->antialias);
				gc();

				send(([
					"cmd": "render_result",
					"x": m->x,
					"y": m->y,
					"image": Image.PNG.encode(tile),
				]));
			}
		};

		send(([ "cmd": "init" ]));

		string buf = "";

		while (true) {
			string d = Stdio.stdin->read(1024, 1);
			if (!d || d == "") {
				exit(0);
			}

			for (int i = 0; i < sizeof(d); i++) {
				if (d[i] == '\n') {
					cmd(buf);
					buf = "";
				}
				else {
					buf += d[i..i];
				}
			}
		}
	}
	else {
		if (enable_preview) {
			// Initialize SDL
			SDL.init(SDL.INIT_VIDEO);
			SDL.set_caption("Raycraft", "");
			screen = SDL.set_video_mode(width, height, 32, SDL.HWSURFACE | SDL.DOUBLEBUF | SDL.HWACCEL | SDL.RLEACCEL);
		}

		// Initialize camera
		CCamera cam = CCamera(cam_init_x, cam_init_y, cam_init_z, cam_init_yaw, cam_init_pitch);
		cam->fov = cam_init_fov;

		Thread.Mutex mtx = Thread.Mutex();

		function render;

		if (multiproc > 1) {
			// Multi-processing renderer
			render = lambda(int width, int height, bool antialias, function cb_tile_start, function cb_tile_done) {
				Thread.Queue queue = Thread.Queue();

				int tiles_x = (width / BLOCKSIZE) + !!(width % BLOCKSIZE);
				int tiles_y = (height / BLOCKSIZE) + !!(height % BLOCKSIZE);

				int tiles = tiles_x * tiles_y;
				int tiles_done = 0;

				for (int y = 0; y < tiles_y; y++) {
					for (int x = 0; x < tiles_x; x++) {
						queue->write(({ cam, x, y, width, height, BLOCKSIZE, antialias }));
					}
				}

				Thread.Mutex _mtx = Thread.Mutex();
				object k = _mtx->lock();

				Thread.Mutex _updmtx = Thread.Mutex();

				// Local callbacks
				void _cb_tile_start(Worker worker, int x, int y) {
					cb_tile_start(x, y);
				};

				void _cb_tile_done(Worker worker, int x, int y, Image.Image tile) {
					object k_upd = _updmtx->lock(1);
					cb_tile_done(x, y, tile);

					tiles_done++;

					write("\r""Rendering... %.2f%%", ((float)tiles_done / (float)tiles) * 100.0);

					if (tiles_done == tiles) {
						write("\n");
						// Rendering completed
						destruct(k);
					}
				};

				// Start renderers
				write("Starting %d workers...\n", multiproc);
				array workers = ({ });

				for (int i = 0; i < multiproc; i++) {
					workers += ({ Worker(i, queue, _cb_tile_start, _cb_tile_done) });

					// This will kill the worker when reached
					queue->write(0);
				}

				// Lock on self - This will release when all tiles have finished rendering
				_mtx->lock(1);
			};
		}
		else {
			// Single process renderer
			render = lambda(int width, int height, bool antialias, function cb_tile_start, function cb_tile_done) {
				int tiles_x = (width / BLOCKSIZE) + !!(width % BLOCKSIZE);
				int tiles_y = (height / BLOCKSIZE) + !!(height % BLOCKSIZE);

				int tiles = tiles_x * tiles_y;

				array a = ({ });
				for (int y = 0; y < tiles_y; y++) {
					for (int x = 0; x < tiles_x; x++) {
						a += ({ ({ x, y, width, height, BLOCKSIZE, antialias }) });
					}
				}

				foreach (a, array b) {
					int x = b[0];
					int y = b[1];

					cb_tile_start(x, y);

					Image.Image tile = cam->render_tile(@b);
					gc();

					cb_tile_done(x, y, tile);
				}
			};
		}

		Thread.Thread(
			lambda() {
				Image.Image img = Image.Image(width, height, 0, 0, 0);

				if (enable_preview) {
					Image.Image img_preview = Image.Image(width / 8, height / 8, 0, 0, 0);

					// Render preview
					render(
						width / 8,
						height / 8,
						false,
						lambda(int x, int y) {
							img_preview->box(x * BLOCKSIZE, y * BLOCKSIZE, (x + 1) * BLOCKSIZE - 1, (y + 1) * BLOCKSIZE - 1, 255, 0, 0);
							img->paste(img_preview->scale(width, height), 0, 0);

							object k = mtx->lock(1);
							SDL.Surface()->set_image(img, SDL.HWSURFACE)->display_format()->blit(screen);
							destruct(k);
						},
						lambda(int x, int y, Image.Image tile) {
							img_preview->paste(tile, x * BLOCKSIZE, y * BLOCKSIZE);
							img->paste(img_preview->scale(width, height), 0, 0);

							object k = mtx->lock(1);
							SDL.Surface()->set_image(img, SDL.HWSURFACE)->display_format()->blit(screen);
							destruct(k);
						}
					);

					// Darken preview
					img->paste((img_preview * 0.5)->scale(width, height), 0, 0);

					object k = mtx->lock(1);
					SDL.Surface()->set_image(img, SDL.HWSURFACE)->display_format()->blit(screen);
					destruct(k);
				}

				// Start main render
				render(
					width,
					height,
					antialias,
					lambda(int x, int y) {
						// todo
					},
					lambda(int x, int y, Image.Image tile) {
						img->paste(tile, x * BLOCKSIZE, y * BLOCKSIZE);

						if (outfile != "" && save_image_on_update) {
							if (glob("*.jpg", lower_case(outfile))) {
								Stdio.write_file(outfile, Image.JPEG.encode(img, ([ "quality": 100 ])));
							}
							else if (glob("*.gif", lower_case(outfile))) {
								Stdio.write_file(outfile, Image.GIF.encode(img));
							}
							else {
								Stdio.write_file(outfile, Image.PNG.encode(img));
							}
						}

						if (enable_preview) {
							object k = mtx->lock(1);
							SDL.Surface()->set_image(img, SDL.HWSURFACE)->display_format()->blit(screen);
							destruct(k);
						}
					}
				);

				// Write to file (if specified)
				if (outfile != "") {
					if (glob("*.jpg", lower_case(outfile))) {
						Stdio.write_file(outfile, Image.JPEG.encode(img, ([ "quality": 100 ])));
					}
					else if (glob("*.gif", lower_case(outfile))) {
						Stdio.write_file(outfile, Image.GIF.encode(img));
					}
					else {
						Stdio.write_file(outfile, Image.PNG.encode(img));
					}
				}

				if (!enable_preview) {
					exit(0);
				}
			}
		);

		if (enable_preview) {
			SDL.Event e = SDL.Event();
			while (true) {
				while (e->get()) {
					if (e->type == SDL.QUIT) return 0;
				}

				object k = mtx->lock(1);
				SDL.flip();
				destruct(k);

				Pike.DefaultBackend(0.0);
				sleep(0.1);
			}

			return 0;
		}
		else {
			return -1;
		}
	}
}

// Load block data
void load_blocks() {
	array a = Stdio.read_file("data/blocks.lst") / "\n";
	foreach (a, string b) {
		if (glob("*,*", b)) {
			array c = b / ",";
			array d = c[0] / ":";

			string name = c[1];
			int id = (int)d[0];
			int var = (sizeof(d) >= 2 ? (int)d[1] : 0);

			string path = "data/blocks/" + name + ".json";

			if (Stdio.is_file(path)) {
				BlockModel m = BlockModel();
				m->set_data(Standards.JSON.decode(Stdio.read_file(path)));
				models[(id << 4) | var] = m;
			}
			else {
				werror("WARNING: Missing file %O for block %d:%d\n", path, id, var);
			}
		}
	}
}

string nicehrtime(int t) {
	if (t >= 1000000) return sprintf("%.1f s", t / 1000000.0);
	else if (t >= 1000) return sprintf("%.1f ms", t / 1000.0);
	else return sprintf("%d us", t);
}

class CCamera {
	CVector position;

	float yaw;
	float pitch;

	float fov;

	void create(float x, float y, float z, float yaw, float pitch) {
		position = CVector(x, y, z);
		this->yaw = yaw;
		this->pitch = pitch;
	}

	Image.Image render_tile(int tilex, int tiley, int width, int height, int blocksize, bool antialias) {
		mixed err = catch {
			int tilew = tilex * blocksize + blocksize > width ? width % blocksize : blocksize;
			int tileh = tiley * blocksize + blocksize > height ? height % blocksize : blocksize;

			Image.Image img = Image.Image(tilew, tileh, 0, 0, 0);

			float fv = fov * 0.0174532925;
			int ix, y, x;

			float ry, rx, fx, fy;
			float r, g, b;
			CColor c;

			if (antialias) {
				// Anti-aliased, get colors from multiple points

				for (int iy = 0; iy < tileh; iy++) {
					// Calculate screen Y-coordinate
					y = iy + (tiley * blocksize);

					for (ix = 0; ix < tilew; ix++) {
						// Calculate screen X-coordinate
						x = ix + (tilex * blocksize);

						array ca = ({ });

						for (float ify = -0.2; ify <= 0.2; ify += 0.1) {
							ry = ((y + ify) / (float)height) - 0.5;
							fy = ry * fv;

							for (float ifx = -0.2; ifx <= 0.2; ifx += 0.1) {
								rx = ((x + ifx) / (float)height) - 0.5;
								fx = rx * fv;

								ca += ({ raytrace(rx, ry, fx, fy) });
							}
						}

						float s = (float)sizeof(ca);

						r = Array.sum(ca->r) / s;
						g = Array.sum(ca->g) / s;
						b = Array.sum(ca->b) / s;

						img->setpixel(ix, iy, (int)(r * 255), (int)(g * 255), (int)(b * 255));
					}
				}
			}
			else {
				// Aliased, get color from 1 point

				for (int iy = 0; iy < tileh; iy++){
					y = iy + (tiley * blocksize);

					for (ix = 0; ix < tilew; ix++) {
						x = ix + (tilex * blocksize);

						ry = ((float)y / (float)height) - 0.5;
						rx = ((float)x / (float)height) - 0.5;

						fx = rx * fv;
						fy = ry * fv;

						c = raytrace(rx, ry, fx, fy);

						img->setpixel(ix, iy, (int)(c->r * 255), (int)(c->g * 255), (int)(c->b * 255));
					}
				}
			}

			return img;
		};

		if (err) {
			werror(describe_backtrace(err));
			exit(1);
		}
	}

	CColor raytrace(float x, float y, float ryaw, float rpitch) {
		int kx = 0;
		int ky = 0;
		int kz = 0;
		CColor kc = CColor(0.0, 0.0, 0.0, 0.0);

		int ax, ay, az;	// Absolute block coordinates
		int bx, by, bz;	// Block coordinates within chunk (16x128x16)
		int cx, cy, cz;	// Chunk coordinates within world

		mapping b;

		float _yaw = yaw * 0.0174532925 + ryaw;
		float _pitch = pitch * 0.0174532925 - rpitch;

		Math.Matrix v_center = Math.Matrix(({ 0.5, 0.5, 0.5 }));

		Math.Matrix v_axis_top = Math.Matrix(({ 0.0, 1.0, 0.0 }));
		Math.Matrix v_axis_front = Math.Matrix(({ 1.0, 0.0, 0.0 }));
		Math.Matrix v_axis_side = Math.Matrix(({ 0.0, 0.0, 1.0 }));

		float u, v;

		// Absolute coordinates - Starting point (TODO: Calculate along plane to apply camera sensor/film size)
		float fx = position->x;
		float fy = position->y;
		float fz = position->z;

		float tn = 0.0;

		float ang_x = cos(_yaw);
		float ang_y = sin(_pitch);
		float ang_z = sin(_yaw);

		int dir_x = sgn(cos(_yaw));
		int dir_y = sgn(sin(_pitch));
		int dir_z = sgn(sin(_yaw));

		int tm = time();

		BlockModel last_blk_type = UNDEFINED;

		while (true) {
			ax = (int)fx;
			ay = (int)fy;
			az = (int)fz;

			bx = ax & 15;
			by = ay & 127;
			bz = az & 15;

			cx = ax >> 4;
			cy = ay >> 7;
			cz = az >> 4;

			// 2 vertical chunks = 256 blocks world height
			if (cy == 0 || cy == 1) {
				MCChunk chunk = chunk_cache[cx + "," + cz];
				if (!chunk) {
					chunk = world->get_chunk(cx, cz);
					chunk_cache[cx + "," + cz] = chunk;
					chunk_soft_cache->push(chunk);
				}

				if (chunk) {
					b = chunk->get_block(bx, by | (cy << 7), bz);

					if (b) {
						kx = ax;
						ky = ay;
						kz = az;

						float bxf = fx % 1.0;
						float byf = fy % 1.0;
						float bzf = fz % 1.0;

						BlockModel model = models[(b->id << 4) | b->data] || models[b->id << 4] || default_model;

						if (model != last_blk_type || !model->join_blocks) {
							last_blk_type = model;

							array tc;
							string side = "any";

							if (bxf <= 0.001 || bxf >= 0.999) {
								u = bzf;
								v = 1.0 - byf;
								side = "front";
							}
							else if (byf <= 0.001 || byf >= 0.999) {
								u = bxf;
								v = bzf;
								side = "top";
							}
							else {
								u = bxf;
								v = 1.0 - byf;
								side = "left";
							}

							if (!model->materials[side] && !model->material) {
								tc = ({ (int)(u * 255.0), 0, (int)(v * 255.0), 1.0 });
							}
							else {
								tc = (model->materials[side] || model->material)->get(u, v);
							}

							if (side != "top") {
								tc[0] *= 0.8;
								tc[1] *= 0.8;
								tc[2] *= 0.8;
							}

							float alpha = tc[3] * (1.0 - kc->a);
							kc->r = linear(kc->r, tc[0], alpha);
							kc->g = linear(kc->g, tc[1], alpha);
							kc->b = linear(kc->b, tc[2], alpha);
							kc->a += alpha;

							if (kc->a >= 1.0) {
								break;
							}
						}
					}
					else {
						last_blk_type = UNDEFINED;
					}
				}
				else if (cx >= bounds->x_max && dir_x == 1) {
					return bg_color;
				}
				else if (cx < bounds->x_min && dir_x == -1) {
					return bg_color;
				}
				else if (cz >= bounds->z_max && dir_z == 1) {
					return bg_color;
				}
				else if (cz < bounds->z_min && dir_z == -1) {
					return bg_color;
				}
			}
			else if (cy > 0 && dir_y == 1) {
				return bg_color;
			}
			else if (cy < 0 && dir_y == -1) {
				return bg_color;
			}

			// Calculate step length
			float s_x = 1.0, s_y = 1.0, s_z = 1.0;

			if (ang_x < -0.00001) {
				s_x = abs((fx % 1.0) / ang_x);
			}
			else if (ang_x > 0.00001) {
				s_x = abs((1.0 - (fx % 1.0)) / ang_x);
			}

			if (ang_y < -0.00001) {
				s_y = abs((fy % 1.0) / ang_y);
			}
			else if (ang_y > 0.00001) {
				s_y = abs((1.0 - (fy % 1.0)) / ang_y);
			}

			if (ang_z < -0.00001) {
				s_z = abs((fz % 1.0) / ang_z);
			}
			else if (ang_z > 0.00001) {
				s_z = abs((1.0 - (fz % 1.0)) / ang_z);
			}

			float n = min(s_x, s_y, s_z);

			// Sanity checking
			if (n < 0.00001) {
				n = 0.00001;
			}

			// Step ray
			tn += n;

			fx += n * ang_x;
			fy += n * ang_y;
			fz += n * ang_z;
		}

		return CColor(
			linear(kc->r, 0.800, 1.0 - kc->a),
			linear(kc->g, 0.941, 1.0 - kc->a),
			linear(kc->b, 1.000, 1.0 - kc->a)
		);
	}
}

class CColor {
	float r, g, b, a;

	void create(float _r, float _g, float _b, float|void _a) {
		r = _r;
		g = _g;
		b = _b;
		a = undefinedp(_a) ? 1.0 : _a;
	}
}

class CVector {
	float x, y, z;

	void create(float _x, float _y, float _z) {
		x = _x;
		y = _y;
		z = _z;
	}
}

float linear(float v0, float v1, float t) {
	return (1 - t) * v0 + t * v1;
}

class Worker {
	int id;
	Thread.Queue queue;

	function cb_start;
	function cb_done;

	object proc;

	Stdio.File f_stdin = Stdio.File();
	Stdio.File f_stdout = Stdio.File();

	Stdio.File p_stdin;
	Stdio.File p_stdout;

	bool is_running = true;

	// Worker(i, queue, _cb_tile_start, _cb_tile_done)
	void create(int id, Thread.Queue queue, function cb_start, function cb_done) {
		this->id = id;
		this->queue = queue;
		this->cb_start = cb_start;
		this->cb_done = cb_done;

		p_stdin = f_stdin->pipe(Stdio.PROP_BUFFERED | Stdio.PROP_REVERSE);
		p_stdout = f_stdout->pipe(Stdio.PROP_BUFFERED);

		array args = ({ "pike", exec_path, "--renderer", world_path });
		mapping opts = ([
			"stdin": p_stdin,
			"stdout": p_stdout,
		]);

		proc = Process.create_process(args, opts);

		Thread.Thread(run);
	}

	void run() {
		string buf = "";

		while (is_running) {
			string d = f_stdout->read(1024, 1);
			for (int i = 0; i < sizeof(d); i++) {
				if (d[i] == '\n') {
					cmd(buf);
					buf = "";

					if (!is_running) {
						return;
					}
				}
				else {
					buf += d[i..i];
				}
			}
		}
	}

	private void cmd(string d) {
		mapping m = Standards.JSON.decode(d);

		if (m->cmd == "init") {
			next_tile();
		}
		else if (m->cmd == "render_result") {
			cb_done(this, m->x, m->y, Image.PNG.decode(m->image));
			next_tile();
		}
	}

	private void next_tile() {
		array a = queue->read();
		if (!a) {
			proc->kill(15);
			is_running = false;
			return;
		}

		CCamera cam = a[0];
		int x = a[1];
		int y = a[2];
		int w = a[3];
		int h = a[4];
		int blksize = a[5];
		int antialias = a[6];

		cb_start(this, a[1], a[2]);

		send(([
			"cmd": "render",
			"camera": ([
				"x": cam->position->x,
				"y": cam->position->y,
				"z": cam->position->z,
				"yaw": cam->yaw,
				"pitch": cam->pitch,
				"fov": cam->fov,
			]),
			"x": x,
			"y": y,
			"w": w,
			"h": h,
			"blksize": blksize,
			"antialias": antialias,
		]));
	}

	private void send(mapping m) {
		f_stdin->write(Standards.JSON.encode(m, Standards.JSON.ASCII_ONLY) + "\n");
	}
}
