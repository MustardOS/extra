# Community Shaders

Pickles (games) and Wasabi (video and music) both offer a shader catalogue, read from `data/shaders.json`. You can
list your own shader in it by hosting the `.frag` file yourself and adding an entry that links to it.

The `shader/` folder and the `MustardOS` entries in the catalogue are the shaders MustardOS ships with. They are looked
after by the MustardOS crew, so please do not add files to that folder or change those entries.

## How it works

1. Pickles or Wasabi fetches `data/shaders.json` from the `main` branch of this repository.
2. The catalogue is grouped by `author`, then listed by `name`.
3. Selecting a shader downloads the file from your `url`, checks it against `sha256`, and saves it on the device as
   `<author>/<file name>.frag` inside the player's own shader folder:
   - Pickles: `/run/muos/storage/pickles/shader/`
   - Wasabi: `/run/muos/storage/wasabi/shader/`
4. When an installed file no longer matches the `sha256` in the catalogue, the shader shows as an update.

The same file is offered in both players.

## Hosting your shader

Put your `.frag` file in your own public repository, for example on GitHub, and link to the raw file. On GitHub that
is the `raw.githubusercontent.com` link, not the `github.com/.../blob/...` page:

```
https://raw.githubusercontent.com/YourName/your-shaders/refs/heads/main/my-shader.frag
```

Any `https://` link that serves the file directly will work.

Every change to the file changes its SHA-256, and devices refuse a file that does not match the catalogue. If you link
to a branch such as `main`, the shader stops installing as soon as you push a change, until a pull request here updates
the hash. To avoid that, link to a tag or commit instead, and send a pull request with the new link, `sha256` and
`version` when you are ready to release a change:

```
https://raw.githubusercontent.com/YourName/your-shaders/v2/my-shader.frag
```

## Catalogue entry

```json
{
  "name": "My Shader",
  "author": "YourName",
  "url": "https://raw.githubusercontent.com/YourName/your-shaders/v1/my-shader.frag",
  "version": "1",
  "sha256": "<sha256 of the file>"
}
```

| Field     | Rules                                                                                                        |
|-----------|--------------------------------------------------------------------------------------------------------------|
| `name`    | Shown in the catalogue. Up to 63 characters, no leading or trailing spaces.                                  |
| `author`  | Your name or handle. Up to 63 characters. It also becomes the folder the shader is saved into on the device. |
| `url`     | A direct `https://` link to the raw `.frag` file.                                                            |
| `version` | A string, for example `"1"`. Raise it whenever the shader changes.                                           |
| `sha256`  | The 64 character SHA-256 of the exact file at `url`.                                                         |

The file name in `url` (without `.frag`) becomes the shader name on the device. Keep it to letters, numbers, `-` and
`_`. Two of your entries must not share a file name.

The list is kept in alphabetical order by `name`.

**Important:** one broken entry stops the whole catalogue loading in both Pickles and Wasabi on every device. A missing
field, an `http://` link or a malformed hash all count. Please check your entry before opening a pull request.

## Writing a shader

Shaders are GLSL ES 1.00 fragment shaders (OpenGL ES 2.0). Start the file with this header:

```glsl
// Name: My Shader
// Author: YourName
// Version: 1
```

Pickles and Wasabi add the following before your code, so do not declare any of it again:

```glsl
precision highp float;              // mediump on devices without highp
uniform sampler2D u_tex;            // the game or video image
uniform vec2 u_resolution;          // output size in pixels
uniform vec2 u_native_resolution;   // the size the game or video renders at
uniform vec2 u_source_resolution;
uniform vec2 u_texture_resolution;
uniform vec2 u_source_uv_extent;
uniform float u_time;               // counts frames, not seconds
uniform int u_frame;                // frame counter
varying vec2 v_uv;                  // texture coordinate
```

The file must contain `void main()` and write to `gl_FragColor`. It must be no larger than 128 KiB.

### Adjustable settings

Up to 16 settings can be adjusted on the device from the shader adjust menu in either player. Declare each one with a
`#pragma parameter` line and a matching `uniform float`:

```glsl
#pragma parameter strength "Effect Strength" 0.50 0.00 1.00 0.05

uniform float strength;
```

The values are the default, minimum, maximum and step size.

### Testing on a device

Copy your `.frag` file into `/run/muos/storage/pickles/shader/` or `/run/muos/storage/wasabi/shader/` on the device,
then pick it from the shader list in that player. Since the catalogue offers every shader to both players, try it in
Pickles on more than one system and in Wasabi with a video, at more than one scale, before submitting.

## Making a pull request

1. Fork this repository and create a branch, for example `shader/my-shader`.
2. Get the SHA-256 of the exact file your `url` serves:

   ```sh
   curl -sL "<raw url>" | sha256sum
   ```

3. Add your entry to `data/shaders.json` in alphabetical order by `name`. This file is the only one your pull request
   should change.
4. Check the catalogue still loads:

   ```sh
   jq -e 'all(.[]; (.name | length) > 0 and (.author | length) > 0 and (.version | type) == "string"
       and (.url | startswith("https://")) and (.sha256 | test("^[0-9a-fA-F]{64}$")))' data/shaders.json
   ```

   This prints `true` when every entry is usable.

5. Open the pull request with a link to your repository, a short description of the shader and a screenshot or two
   from a device. Mention if the shader only suits games or only suits video.

To update a shader later, send another pull request that changes your entry's `url` (if it points at a tag or commit),
`sha256` and `version`.
