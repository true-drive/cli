# True Drive CLI

True Drive stores files as noise videos, so that any platform that hosts video can double as file storage. This is its command-line tool: it encodes files to video and decodes them back, using the [True Drive Core](https://github.com/true-drive/core) library.

> [!WARNING]
> Videos are **not encrypted**. Anyone with the video and this tool can recover the file, so encrypt anything sensitive before encoding it.

## Requirements

- `gcc`, [CMake](https://cmake.org/) 3.21 or newer, and `git` to build ([MSYS2](https://www.msys2.org/) is one way to get them on Windows)
- [FFmpeg](https://ffmpeg.org/) 5.1 or newer on your `PATH` at run time

## Build

The core library is a git submodule in `core/`, so fetch it first:

```sh
git submodule update --init
cmake -B build
cmake --build build
```

This builds the library and produces `build/truedrive`, or `build/truedrive.exe` on Windows. To build against a different checkout of the library, add `-DTRUEDRIVE_CORE_DIR=<path>` to the first `cmake` command.

### Using a container

This opens a shell in an Alpine container that has the compiler, CMake, and FFmpeg installed, with the repository mounted at `/app`:

```sh
docker build -f .devcontainer/Containerfile.dev -t truedrive-cli-dev .devcontainer
docker run -it --rm -v "$PWD":/app truedrive-cli-dev
```

If you use Podman, replace `docker` with `podman`. In Git Bash on Windows, put `MSYS_NO_PATHCONV=1` before `docker run`.

### Using VS Code

The repository includes a dev container with the same tools, plus `gdb`, `git`, and the C/C++ extension.

1. Install the [Dev Containers](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers) extension.
2. If you use Podman, set `dev.containers.dockerPath` to `podman` in your VS Code user settings.
3. Run **Dev Containers: Reopen in Container** from the Command Palette.

Then use the VS Code terminal to run the build commands above and the commands below.

## Usage

```sh
truedrive <encode|decode> -i <input file> -o <output path>
```

The examples below use the Linux binary. On Windows, run `.\build\truedrive.exe` instead.

### Encode a file

```sh
mkdir out
./build/truedrive encode -i input.txt -o out/video
```

This creates `out/video.mkv`. Leave the extension off the `-o` path, since it is added for you. An existing video is never replaced, so encoding fails if `out/video.mkv` already exists.

### Decode a video

```sh
./build/truedrive decode -i out/video.mkv -o out/restored.txt
```

The video only stores the file's contents, not its name, so give `-o` the full file name you want, including the extension. An existing file with that name is replaced.

### Intermediate files

Each run creates a `true_drive_encode_<timestamp>` or `true_drive_decode_<timestamp>` folder next to the output, containing the video's frames. These folders are kept after the run and can be deleted by hand. Encoding a 2 MiB file leaves about 2.6 MB behind.

### Exit status

The command exits with `0` on success and `1` on failure, with the reason printed to standard error.

## Tests

```sh
ctest --test-dir build --output-on-failure
```

The tests need FFmpeg and a POSIX shell. To also check for memory errors, use a toolchain that includes the address and undefined-behavior sanitizers:

```sh
cmake -B build/sanitize -DTRUEDRIVE_SANITIZE=ON
cmake --build build/sanitize
ctest --test-dir build/sanitize --output-on-failure
```

## Known limitations

- The folder that `-o` points into must already exist.
- Input files must be smaller than 64 MiB.
- Only `.mkv` videos can be decoded.
- On Windows, paths can't contain `"` or `%`.
- There is no error correction, so decoding needs every pixel to be intact. Platforms such as YouTube re-compress uploads, which makes decoding fail.
- Videos are stored as PNG images inside Matroska, which many media players and upload sites don't support.
- Videos made by earlier versions, which ended in red pixels, can't be decoded.

## License

[Apache License 2.0](LICENSE)
