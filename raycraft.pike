#!/usr/bin/env pike

#include "src/anvil.pike"
#include "src/chunk.pike"
#include "src/nbt.pike"
#include "src/world.pike"

#define BLOCKSIZE 32

// Some standard built-in block colors
mapping colors = ([
	1:  CColor(0.3, 0.3, 0.3),
	2:  CColor(0.2, 0.7, 0.2),
	3:  CColor(0.5, 0.2, 0.0),
	4:  CColor(0.4, 0.4, 0.4),
	8:  CColor(0.1, 0.3, 0.75),
	9:  CColor(0.1, 0.3, 0.75),
	17: CColor(0.7, 0.6, 0.25),
	18: CColor(0.0, 0.4, 0.0),
	155: CColor(0.9, 0.9, 0.9),
	156: CColor(0.9, 0.9, 0.9),
]);

mapping textures = ([ ]);

CColor black = CColor(0.0, 0.0, 0.0);

SDL.Surface screen;
MCWorld world;

bool antialias = false;

mapping chunk_cache = ([ ]);

int main(int argc, array argv) {
	antialias = Getopt.find_option(argv, "a", "antialias");

	int width = (int)Getopt.find_option(argv, "w", "width", UNDEFINED, "640");
	int height = (int)Getopt.find_option(argv, "h", "height", UNDEFINED, "360");

	float cam_init_x = (float)Getopt.find_option(argv, "x", "", UNDEFINED, "0.0");
	float cam_init_y = (float)Getopt.find_option(argv, "y", "", UNDEFINED, "100.0");
	float cam_init_z = (float)Getopt.find_option(argv, "z", "", UNDEFINED, "0.0");
	float cam_init_yaw = (float)Getopt.find_option(argv, "", "yaw", UNDEFINED, "0.0");
	float cam_init_pitch = (float)Getopt.find_option(argv, "", "pitch", UNDEFINED, "0.0");
	float cam_init_fov = (float)Getopt.find_option(argv, "f", "fov", UNDEFINED, "75.0");

	argv = Getopt.get_args(argv);
	argc = sizeof(argv);

	if (argc < 2) {
		werror("Usage: %s [options] <world path>\n", basename(argv[0]));
		werror("\n");

		werror("-a|--antialias    Enable anti-aliasing.\n");
		werror("-w|--width=N      Sets the width of the render.\n");
		werror("-h|--height=N     Sets the height of the render.\n");
		werror("-x N              Sets the X coordinate for the camera.\n");
		werror("-y N              Sets the Y coordinate for the camera (default: 100.0).\n");
		werror("-z N              Sets the Z coordinate for the camera.\n");
		werror("--yaw=N           Sets the yaw rotation of the camera.\n");
		werror("--pitch=N         Sets the pitch rotation of the camera.\n");
		werror("-f|--fov=N        Sets the FOV of the camera (default: 75.0).\n");
		werror("\n");

		werror("If an \"export\" folder exists, the rendered frames will be saved to it.\n");
		return 1;
	}

	for (int i = 1; i < 256; i++) {
		if (!colors[i]) {
			colors[i] = CColor(1.0, 0.0, 1.0);
		}
	}

	// Load world
	world = MCWorld(argv[1]);

	// Load colors
	load_colors();

	// Initialize SDL
	SDL.init(SDL.INIT_VIDEO);
	SDL.set_caption("Raycraft", "");
	screen = SDL.set_video_mode(width, height, 32, SDL.HWSURFACE | SDL.DOUBLEBUF | SDL.HWACCEL | SDL.RLEACCEL);

	// Initialize camera
	CCamera cam = CCamera(cam_init_x, cam_init_y, cam_init_z, cam_init_yaw, cam_init_pitch);
	cam->fov = cam_init_fov;

	Thread.Mutex mtx = Thread.Mutex();

	int frame = 0;

	void update() {
		Image.Image img = Image.Image(width, height, 0, 0, 0);

		// Move camera
		//cam->position->y += 1.0;
		//cam->yaw += 4.0;

		cam->start_render_async(
			width,
			height,
			BLOCKSIZE,
			lambda(Image.Image tile, int x, int y, int status, int tiles_total, int tiles_finished) {
				img->paste(tile, x * BLOCKSIZE, y * BLOCKSIZE);

				object k = mtx->lock(1);
				SDL.Surface()->set_image(img, SDL.HWSURFACE)->display_format()->blit(screen);
				destruct(k);

				if (tiles_total == tiles_finished) {
					if (Stdio.is_dir("export")) {
						Stdio.write_file("export/frame" + sprintf("%05d", ++frame) + ".png", Image.PNG.encode(img));
					}
					//SDL.Surface()->set_image(img, SDL.HWSURFACE)->display_format()->blit(screen, UNDEFINED, SDL.Rect(width, 0, width, height));
					//update();
				}
			});
	};

	update();

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

// Load average colors for blocks.lst and blocks.png
void load_colors() {
	Image.Image img = Image.PNG.decode(Stdio.read_file("data/blocks.png"));

	array a = Stdio.read_file("data/blocks.lst") / "\n";
	foreach (a, string b) {
		if (glob("*,*,*", b)) {
			array c = array_sscanf(b, "%d,%d,%d");

			int x = c[1];
			int y = c[2];

			Image.Image tile = img->copy(x * 16, y * 16, x * 16 + 15, y * 16 + 15);
			array d = tile->average();

			colors[c[0]] = CColor(d[0] / 255.0, d[1] / 255.0, d[2] / 255.0);
			textures[c[0]] = tile;
		}
	}

	textures[2] = textures[2] * ({ 32, 180, 32 });
	textures[18] = textures[18] * ({ 16, 128, 16 });
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

	Image.Image render(int width, int height) {
		Image.Image img = Image.Image(width, height, 0, 0, 0);
		float fv = fov  * 0.0174532925;
		float spx = 0.2 / (float)width;
		float spy = 0.2 / (float)height;

		for (int y = 0; y < height; y++){
			write("\rRendering... %.1f%%", ((float)(y + 1.0) / (float)height) * 100.0);

			for (int x = 0; x < width; x++) {
				float ry = ((float)y / (float)height) - 0.5;
				float rx = ((float)x / (float)width) - 0.5;

				float fx = rx * fv;
				float fy = ry * fv;

				if (antialias) {
					CColor c1 = raytrace(rx, ry, (rx - 0.5 - spx) * fv, (ry - 0.5) * fv) || black;
					CColor c2 = raytrace(rx, ry, (rx - 0.5 + spx) * fv, (ry - 0.5) * fv) || black;
					CColor c3 = raytrace(rx, ry, (rx - 0.5) * fv, (ry - 0.5 - spy) * fv) || black;
					CColor c4 = raytrace(rx, ry, (rx - 0.5) * fv, (ry - 0.5 + spy) * fv) || black;

					float r = (c1->r + c2->r + c3->r + c4->r) / 4.0;
					float g = (c1->g + c2->g + c3->g + c4->g) / 4.0;
					float b = (c1->b + c2->b + c3->b + c4->b) / 4.0;

					img->setpixel(x, y, (int)(r * 255), (int)(g * 255), (int)(b * 255));
				}
				else {
					CColor c = raytrace(rx, ry, fx, fy);
					if (!c) c = CColor(0.0, 0.0, 0.0);

					img->setpixel(x, y, (int)(c->r * 255), (int)(c->g * 255), (int)(c->b * 255));
				}
			}
		}

		write("\rRendering... 100.0%\n");
		return img;
	}

	void start_render_async(int width, int height, int blocksize, function cb) {
		Thread.Farm pool = Thread.Farm();
		pool->set_max_num_threads(4);

		Thread.Mutex mtx = Thread.Mutex();

		int tiles_x = (width / blocksize) + !!(width % blocksize);
		int tiles_y = (height / blocksize) + !!(height % blocksize);

		int tiles = tiles_x * tiles_y;
		int tiles_orig = tiles;

		void cb_tile(Image.Image img, int _x, int _y, int status) {
			object k = mtx->lock(1);
			if (status == 1) tiles--;
			cb(img, _x, _y, status, tiles_orig, tiles_orig - tiles);
			destruct(k);
		};

		array a = ({ });
		for (int y = 0; y < tiles_y; y++) {
			for (int x = 0; x < tiles_x; x++) {
				a += ({ ({ _render_tile, x, y, width, height, blocksize, cb_tile }) });
			}
		}

		Array.shuffle(a);
		foreach (a, array b) {
			pool->run_async(@b);
		}
	}

	private void _render_tile(int tilex, int tiley, int width, int height, int blocksize, function cb) {
		mixed err = catch {
			int tilew = tilex * blocksize + blocksize > width ? width % blocksize : blocksize;
			int tileh = tiley * blocksize + blocksize > height ? height % blocksize : blocksize;

			Image.Image img = Image.Image(tilew, tileh, 0, 0, 0);

			// Top-left corner
			img->line(0, 0, 5, 0, 255, 0, 0);
			img->line(0, 0, 0, 5, 255, 0, 0);

			// Top-right corner
			img->line(tilew - 1, 0, tilew - 6, 0, 255, 0, 0);
			img->line(tilew - 1, 0, tilew - 1, 5, 255, 0, 0);

			// Bottom-left corner
			img->line(0, tileh - 1, 5, tileh - 1, 255, 0, 0);
			img->line(0, tileh - 1, 0, tileh - 6, 255, 0, 0);

			// Bottom-right corner
			img->line(tilew - 1, tileh - 1, tilew - 6, tileh - 1, 255, 0, 0);
			img->line(tilew - 1, tileh - 1, tilew - 1, tileh - 6, 255, 0, 0);

			cb(img->clone(), tilex, tiley, 0);
			img = img->clear(0, 0, 0);

			float fv = fov  * 0.0174532925;
			int ix, y, x;

			float ry, rx, fx, fy;
			float r, g, b;
			CColor c;

			if (antialias) {
				// Anti-aliased, get colors from 10 points

				for (int iy = 0; iy < tileh; iy++) {
					y = iy + (tiley * blocksize);

					for (ix = 0; ix < tilew; ix++) {
						x = ix + (tilex * blocksize);

						array ca = ({ });

						for (float ify = -0.2; ify <= 0.2; ify += 0.05) {
							for (float ifx = -0.2; ifx <= 0.2; ifx += 0.05) {
								rx = ((x + ifx) / (float)width) - 0.5;
								fx = rx * fv;

								ry = ((y + ify) / (float)height) - 0.5;
								fy = ry * fv;

								ca += ({ raytrace(rx, ry, fx, fy) || black });
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
						rx = ((float)x / (float)width) - 0.5;

						fx = rx * fv;
						fy = ry * fv;

						c = raytrace(rx, ry, fx, fy) || black;

						img->setpixel(ix, iy, (int)(c->r * 255), (int)(c->g * 255), (int)(c->b * 255));
					}
				}
			}

			cb(img, tilex, tiley, 1);
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
		CColor kc;

		float fx, fy, fz;	// Absolute coordinates
		int ax, ay, az;	// Absolute block coordinates
		int bx, by, bz;	// Block coordinates within chunk (16x128x16)
		int cx, cy, cz;	// Chunk coordinates within world

		int b;

		float _yaw = yaw * 0.0174532925 + ryaw;
		float _pitch = pitch * 0.0174532925 - rpitch;

		Math.Matrix v_center = Math.Matrix(({ 0.5, 0.5, 0.5 }));

		Math.Matrix v_axis_top = Math.Matrix(({ 0.0, 1.0, 0.0 }));
		Math.Matrix v_axis_front = Math.Matrix(({ 1.0, 0.0, 0.0 }));
		Math.Matrix v_axis_side = Math.Matrix(({ 0.0, 0.0, 1.0 }));

		float u, v;

		float n = 0.0;
		while (n < 4096.0) {
			fx = position->x + cos(_yaw) * n;
			fy = position->y + sin(_pitch) * n;
			fz = position->z + sin(_yaw) * n;

			ax = (int)fx;
			ay = (int)fy;
			az = (int)fz;

			bx = ax & 15;
			by = ay & 127;
			bz = az & 15;

			cx = ax >> 4;
			cy = ay >> 7;
			cz = az >> 4;

			kc = UNDEFINED;
			if (!cy) {
				MCChunk chunk = chunk_cache[cx + "," + cz];
				if (!chunk) {
					chunk = world->get_chunk(cx, cz);
					chunk_cache[cx + "," + cz] = chunk;
				}

				if (chunk) {
					b = chunk->get_block(bx, by, bz);

					if (b) {
						kx = ax;
						ky = ay;
						kz = az;

						float bxf = fx % 1.0;
						float byf = fy % 1.0;
						float bzf = fz % 1.0;

						/*
						if (byf > 0.99 && ((bxf < 0.01 || bxf > 0.99) || (bzf < 0.01 || bzf > 0.99))) {
							return CColor(0.0, 0.0, 0.0);
						}
						*/

						if (textures[b]) {
							if (bxf <= 0.001 || bxf >= 0.999) {
								u = bzf;
								v = byf;
							}
							else if (byf <= 0.001 || byf >= 0.999) {
								u = bxf;
								v = bzf;
							}
							else {
								u = bxf;
								v = byf;
							}

							array tc = textures[b]->getpixel((int)(u * 16), (int)(v * 16));

							if (u <= 0.01 || u >= 0.99 || v <= 0.01 || v >= 0.99) {
								return CColor(tc[0] / 512.0, tc[1] / 512.0, tc[2] / 512.0);
							}
							else {
								return CColor(tc[0] / 255.0, tc[1] / 255.0, tc[2] / 255.0);
							}
						}
						else {
							return colors[b];
						}
					}
				}
			}

			// Calculate distance to block edges
			float nx = 1.0 - (abs(cos(_yaw)) * n) % 1.0;
			float ny = 1.0 - (abs(sin(_pitch)) * n) % 1.0;
			float nz = 1.0 - (abs(sin(_yaw)) * n) % 1.0;

			float nv = min(nx, ny, nz) + 0.001;

			n += nv;
		}
	}
}

class CColor {
	float r, g, b;

	void create(float _r, float _g, float _b) {
		r = _r;
		g = _g;
		b = _b;
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
